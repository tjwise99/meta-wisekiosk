#!/bin/sh
# Low-uptime clock witness (#31 verification harness -- not shipped in any image).
# Runs from clockproof.service at sysinit, long before systemd-timesyncd's
# ~56s network sync, and records what the clock and RAUC actually see there.
# Never returns non-zero: a failed witness must not fail a boot.
LOG=/data/clockproof.log
{
    echo "=== boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) ==="
    echo "uptime_s=$(awk '{print $1}' /proc/uptime 2>/dev/null)"
    echo "date=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)"
    echo "epoch=$(date +%s 2>/dev/null)"
    echo "buildinfo=$(grep '^meta-wisekiosk' /etc/buildinfo 2>/dev/null)"
    echo "slot=$(rauc status 2>/dev/null | grep 'Booted from')"
    echo "ntpsync=$(timedatectl show -p NTPSynchronized 2>/dev/null | cut -d= -f2)"
    echo "persist_clock_mtime=$(date -r /data/systemd-timesync/clock '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo NONE)"
    echo "rootfs_clock_mtime=$(date -r /var/lib/systemd/timesync/clock '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || echo NONE)"
    if [ -f /data/update.raucb ]; then
        echo "--- rauc info /data/update.raucb (uptime $(awk '{print $1}' /proc/uptime)s) ---"
        rauc info /data/update.raucb 2>&1
        echo "rauc_info_rc=$?"
    else
        echo "rauc_info_rc=SKIPPED_no_bundle"
    fi
    echo "uptime_end_s=$(awk '{print $1}' /proc/uptime 2>/dev/null)"
    echo
} >> "$LOG" 2>&1
sync
exit 0
