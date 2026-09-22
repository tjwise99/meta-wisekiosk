#!/usr/bin/env bash
# Deploy one probe variant to the prod kiosk, restart onto a cleared cache, let it
# run, then read the frame-time payload back out of the X window title.
#
#   run-phase.sh root@<host> <probe.js> <seconds>
#
# The board is named on the command line, never in this file: this repository is
# public and carries no device address. Resolve the role's address from the
# gitignored local/device-identity.md, or with `just find <cidr>`.
#
# Recoverable over the wire: the only device state touched is ~/.surf/script.js and
# the WebKit cache, both restored by deploying a zero-byte script.js and restarting.
set -uo pipefail

HOST=${1:?usage: run-phase.sh root@<host> <probe.js> <seconds>}
PROBE=${2:?usage: run-phase.sh root@<host> <probe.js> <seconds>}
SECS=${3:?usage: run-phase.sh root@<host> <probe.js> <seconds>}
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)

"$REPO/tools/kiosk-ssh.sh" "$HOST" 'cat > /home/root/.surf/script.js' < "$PROBE" || exit 1

"$REPO/tools/kiosk-ssh.sh" "$HOST" "sh -s" <<EOF
rm -rf /home/root/.surf/cache
systemctl restart kiosk
sleep $SECS
export DISPLAY=:0
for id in \$(xwininfo -root -children 2>/dev/null | grep '0x' | awk '{print \$1}'); do
  xprop -len 8000 -id \$id WM_NAME 2>/dev/null | grep 'KP|'
done
echo "LOAD \$(cat /proc/loadavg)"
p=\$(pidof WebKitWebProcess | cut -d' ' -f1)
[ -n "\$p" ] && grep VmRSS /proc/\$p/status
EOF
