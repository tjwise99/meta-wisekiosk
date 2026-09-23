#!/bin/sh
# Test B sampler: is there a ~1/s X stall with NO in-page probe at all?
#
# Runs ON THE BOARD. Samples the X server's CPU counters at ~100 ms using only shell
# builtins -- `read` from /proc/<pid>/stat forks nothing. An awk-per-sample loop would
# fork 1200 processes on a 1 GHz single-core board and manufacture the very bursts it
# is meant to detect.
#
# utime+stime are in USER_HZ jiffies (100 Hz here => 1 jiffy = 10 ms), so a 250 ms
# burst of X at ~100% shows as ~25 jiffies inside one 100 ms sample window.
#
# Output: one line per sample, "<uptime_seconds> <jiffies_since_boot>". The timestamp is
# read from /proc/uptime (10 ms resolution) rather than assumed from the loop index --
# `sleep 0.1` plus loop overhead makes the true interval longer than nominal, and a rate
# computed from an assumed interval would be wrong by exactly that drift.
set -u
SECS=${1:-120}

XPID=$(pidof Xorg 2>/dev/null || pidof X 2>/dev/null)
[ -n "$XPID" ] || { echo "NO_X_PID"; exit 1; }
echo "XPID=$XPID"
echo "CLK_TCK=$(getconf CLK_TCK 2>/dev/null || echo unknown)"
echo "SURF_SCRIPT_BYTES=$(wc -c < /home/root/.surf/script.js)"

n=$((SECS * 10))
i=0
while [ "$i" -lt "$n" ]; do
  # 16 fields: pid..stime. No subshell, no fork.
  read -r a b c d e f g h j k l m o ut st rest < "/proc/$XPID/stat"
  read -r upt idle < /proc/uptime
  printf '%s %s\n' "$upt" "$((ut + st))"
  i=$((i + 1))
  sleep 0.1
done
