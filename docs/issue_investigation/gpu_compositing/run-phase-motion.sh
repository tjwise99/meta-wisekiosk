#!/usr/bin/env bash
# Deploy the MOVING-vs-STATIC probe (p12_motion.js) to the prod kiosk, restart onto
# a cleared cache, let it run, then read the KP2| payload back out of the X title.
#
#   run-phase-motion.sh root@<host> <probe.js> <seconds>
#
# The sibling run-phase.sh reads the probe4 family's KP| payload. This one reads the
# KP2| payload the motion probe emits -- a different, longer wire shape (one record
# per 20 s block), so it greps KP2| and reads a larger title window. The board is
# named on the command line; this repository is public and carries no device address.
#
# Recoverable over the wire: the only device state touched is ~/.surf/script.js and
# the WebKit cache, both restored by deploying a zero-byte script.js and restarting.
set -uo pipefail

HOST=${1:?usage: run-phase-motion.sh root@<host> <probe.js> <seconds>}
PROBE=${2:?usage: run-phase-motion.sh root@<host> <probe.js> <seconds>}
SECS=${3:?usage: run-phase-motion.sh root@<host> <probe.js> <seconds>}
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)

"$REPO/tools/kiosk-ssh.sh" "$HOST" 'cat > /home/root/.surf/script.js' < "$PROBE" || exit 1

"$REPO/tools/kiosk-ssh.sh" "$HOST" "sh -s" <<EOF
rm -rf /home/root/.surf/cache
systemctl restart kiosk
sleep $SECS
export DISPLAY=:0
for id in \$(xwininfo -root -children 2>/dev/null | grep '0x' | awk '{print \$1}'); do
  xprop -len 32000 -id \$id WM_NAME 2>/dev/null | grep -E 'KP[0-9]+\|'
done
echo "LOAD \$(cat /proc/loadavg)"
p=\$(pidof WebKitWebProcess | cut -d' ' -f1)
[ -n "\$p" ] && grep VmRSS /proc/\$p/status
EOF
