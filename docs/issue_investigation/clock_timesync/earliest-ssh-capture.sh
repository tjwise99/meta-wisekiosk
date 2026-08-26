#!/bin/bash
# Reboot the bench board and capture the clock + `rauc info` at the EARLIEST
# moment sshd answers -- the exact point at which `just kiosk-install` reaches a
# freshly rebooted board, and the point at which a cold clock fails an install
# with "certificate is not yet valid" (#31).
#
# Measured identically for both runs; the only variable is the image on the board.
set -uo pipefail
# The bench board's address is scrubbed for this public repo; supply it, e.g.
# KIOSK_HOST=root@$(just find ...). As run, this line was a literal root@<addr>.
HOST=${KIOSK_HOST:?set KIOSK_HOST=root@<bench-board>}
OUT=${1:?usage: earliest-ssh-capture.sh <outfile>}
SSHO=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3)

BEFORE=$(ssh "${SSHO[@]}" "$HOST" 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null)
echo "pre-reboot boot_id=$BEFORE" > "$OUT"
ssh "${SSHO[@]}" "$HOST" 'systemctl reboot' >/dev/null 2>&1 || true
T0=$(date +%s)
while :; do
    NOW=$(ssh "${SSHO[@]}" "$HOST" 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null || true)
    if [ -n "$NOW" ] && [ "$NOW" != "$BEFORE" ]; then break; fi
    if [ $(( $(date +%s) - T0 )) -gt 300 ]; then echo "BOARD DID NOT RETURN IN 300s" >> "$OUT"; exit 1; fi
    sleep 1
done
echo "post-reboot boot_id=$NOW  (host waited $(( $(date +%s) - T0 ))s for sshd)" >> "$OUT"
# One round trip: everything below is measured at the same instant.
ssh "${SSHO[@]}" "$HOST" 'bash -s' >> "$OUT" 2>&1 <<'REMOTE'
echo "uptime_s_at_first_ssh=$(awk '{print $1}' /proc/uptime)"
echo "date=$(date '+%Y-%m-%dT%H:%M:%S%z')"
echo "epoch=$(date +%s)"
echo "ntpsync=$(timedatectl show -p NTPSynchronized | cut -d= -f2)"
echo "buildinfo=$(grep '^meta-wisekiosk' /etc/buildinfo)"
echo "slot=$(rauc status | grep 'Booted from')"
echo "timesyncd=$(systemctl is-active systemd-timesyncd)"
echo "bind_target=$(findmnt -no SOURCE,TARGET /var/lib/systemd/timesync 2>/dev/null || echo 'not a mountpoint')"
echo "--- rauc info /data/update.raucb ---"
rauc info /data/update.raucb 2>&1
echo "rauc_info_rc=$?"
echo "uptime_s_after_rauc_info=$(awk '{print $1}' /proc/uptime)"
REMOTE
echo "CAPTURE_DONE" >> "$OUT"
