#!/bin/bash
# Bench boot-loop clock soak collector (#31; opportunistically #18/#26).
# Runs once per boot from bootloop.service, ordered After=+Requires= rauc-mark-good.
#
# Safety model (see local/bootloop-2026-08-16/setup.md):
#   counter-safe : Requires=rauc-mark-good.service means this never even starts
#                  unless mark-good succeeded and reset BOOT_*_LEFT to 3, and the
#                  uptime>=90 gate puts reboot well after mark-good (~27s) + the
#                  NTP-sync window (~55s). Net RAUC counter stays 3/3.
#   fail-safe    : reboot is the LAST statement, reachable only after the explicit
#                  uptime>=90 gate AND count<N AND no STOP. Every other exit path
#                  returns WITHOUT rebooting, so a malfunction HALTS the loop.
#   bounded      : stops after N boots (count file on /data).
#   stoppable    : /data/bootloop/STOP halts at the next iteration (collect, then
#                  disable + no reboot).
#
# set -e is deliberately NOT used: the reboot is guarded by explicit conditions
# with validated values, which is stronger and more predictable than -e under
# busybox for a script that must fail toward "do not reboot".
set -u

DIR=/data/bootloop
N=40
DRYRUN="${BOOTLOOP_DRYRUN:-0}"

if [ "$DRYRUN" = "1" ]; then
    LOG="$DIR/dryrun.log"; COUNTF="$DIR/dryrun.count"
else
    LOG="$DIR/bootloop.log"; COUNTF="$DIR/count"
fi

log_ev() { echo "bootloop: $*"; }

# --- req 1: wait until NTPSynchronized=yes OR 120s cap, then ensure uptime>=90 ---
while :; do
    up=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
    sync=$(timedatectl show -p NTPSynchronized 2>/dev/null | cut -d= -f2)
    if [ "${sync:-no}" = "yes" ]; then break; fi
    if [ "${up:-0}" -ge 120 ] 2>/dev/null; then break; fi
    sleep 3
done
while :; do
    up=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
    if [ "${up:-0}" -ge 90 ] 2>/dev/null; then break; fi
    sleep 3
done

# --- collect one data line ---
count=$(cat "$COUNTF" 2>/dev/null || echo 0)
case "$count" in ''|*[!0-9]*) count=0 ;; esac
count=$((count + 1))
printf '%s\n' "$count" > "$COUNTF"
# BOUNDED + STOPPABLE persistence guard: if /data went read-only (e.g. an mmc
# I/O error remounted it RO -- the #18 failure), the count can't advance and a
# STOP file can't be created, so the loop would otherwise reboot forever. Read
# the count back; if it did not stick, HALT (no reboot) rather than loop open.
persisted=$(cat "$COUNTF" 2>/dev/null || echo NA)
if [ "$persisted" != "$count" ]; then
    log_ev "count did not persist ($persisted != $count); /data likely read-only -- halting, NOT rebooting"
    exit 1
fi

boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo NA)
ts=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo NA)

tsj=$(journalctl -b -o short-monotonic -u systemd-timesyncd 2>/dev/null || true)
ntp_contact=$(printf '%s\n' "$tsj" | awk -F'[][]' '/Contacted time server/{gsub(/ /,"",$2); print $2; exit}')
ntp_sync=$(printf '%s\n'    "$tsj" | awk -F'[][]' '/Initial clock synchronization/{gsub(/ /,"",$2); print $2; exit}')
[ -n "$ntp_contact" ] || ntp_contact=NA
[ -n "$ntp_sync" ]    || ntp_sync=NA
synchronized=$(timedatectl show -p NTPSynchronized 2>/dev/null | cut -d= -f2)
[ -n "${synchronized:-}" ] || synchronized=NA

# DNS resolve probe (diagnostic only; nslookup has its own bounded retries)
dnsout=$(nslookup google.com 2>&1 || true)
if printf '%s' "$dnsout" | grep -qi 'address'; then dns=ok; else dns=fail; fi

# RAUC boot-attempt counter (confirmation that mark-good kept it at 3/3)
fwenv=$(fw_printenv BOOT_ORDER BOOT_A_LEFT BOOT_B_LEFT 2>/dev/null || true)
border=$(printf '%s\n' "$fwenv" | awk -F= '/^BOOT_ORDER=/{print $2; exit}')
aleft=$(printf '%s\n'  "$fwenv" | awk -F= '/^BOOT_A_LEFT=/{print $2; exit}')
bleft=$(printf '%s\n'  "$fwenv" | awk -F= '/^BOOT_B_LEFT=/{print $2; exit}')
[ -n "$border" ] || border=NA
[ -n "$aleft" ]  || aleft=NA
[ -n "$bleft" ]  || bleft=NA

# #18 catch: pstore panic record + mmc errors
pstore_files=$(ls -A /sys/fs/pstore 2>/dev/null || true)
if [ -n "$pstore_files" ]; then
    pstore=PRESENT
    mkdir -p "$DIR/pstore-$count" 2>/dev/null || true
    cp -a /sys/fs/pstore/* "$DIR/pstore-$count/" 2>/dev/null || true
else
    pstore=empty
fi
mmclines=$(dmesg 2>/dev/null | grep -i mmc || true)
mmc_err=$(printf '%s\n' "$mmclines" | grep -icE 'error|timeout|fail' || true)
[ -n "$mmc_err" ] || mmc_err=0
if [ -n "$mmclines" ]; then
    { echo "=== boot $count $ts $boot_id ==="; printf '%s\n' "$mmclines"; } >> "$DIR/mmc.log" 2>/dev/null || true
fi

printf 'boot=%s ts=%s boot_id=%s ntp_contact_s=%s ntp_sync_s=%s synchronized=%s dns=%s BOOT_ORDER=%s A_LEFT=%s B_LEFT=%s pstore=%s mmc_err=%s\n' \
    "$count" "$ts" "$boot_id" "$ntp_contact" "$ntp_sync" "$synchronized" "$dns" "$border" "$aleft" "$bleft" "$pstore" "$mmc_err" \
    >> "$LOG"
sync

# --- reqs 3/4: bounded + stoppable => disable + NO reboot ---
stop=0; reason=
if [ -f "$DIR/STOP" ]; then stop=1; reason=STOP; fi
if [ "$count" -ge "$N" ] 2>/dev/null; then stop=1; reason="bound(N=$N)"; fi
if [ "$stop" = "1" ]; then
    log_ev "stopping ($reason) after boot $count; disabling unit, NOT rebooting"
    if [ "$DRYRUN" != "1" ]; then
        systemctl disable bootloop.service 2>/dev/null \
            || rm -f /etc/systemd/system/multi-user.target.wants/bootloop.service
        sync
    else
        log_ev "[dryrun] would disable + not reboot"
    fi
    exit 0
fi

# --- req 1/2 final guard: never reboot before 90s; reboot is the LAST statement ---
up=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
if [ "${up:-0}" -lt 90 ] 2>/dev/null; then
    log_ev "uptime guard $up<90 -- halting, NOT rebooting"
    exit 1
fi

log_ev "boot $count logged (sync=${ntp_sync}s), rebooting"
sync
if [ "$DRYRUN" = "1" ]; then log_ev "[dryrun] would reboot now"; exit 0; fi
/usr/sbin/reboot
