#!/usr/bin/env bash
# Capture what the kiosk is actually showing, and read the capture correctly.
#
#   tools/kiosk-screenshot.sh root@<host> [out.png]
#
# The capture itself needs a reachable kiosk. What runs without one: argument
# handling, the overwrite guard, mkdir of the output directory, and the
# ssh/scp failure modes against an unreachable or nonexistent host.
#
# `import -window root` (imagemagick) is the capture path this image carries.
# There is no scrot and no fbgrab: fbgrab was dropped on a misdiagnosis and
# never restored -- see docs/issue_investigation/screenshot_capture_fbgrab/README.md
# before proposing either back.
#
# DISPLAY=:0 on the remote command: nothing puts DISPLAY into an SSH session on
# this image -- /etc/environment is empty, the pam_env DISPLAY line is commented
# out, and sshd has PermitUserEnvironment off. Without it `import` exits with
# "unable to open X server". Xorg is started by plain xinit with no -auth and
# there is no /home/pi and no .Xauthority, so :0 alone is also sufficient; the
# same reasoning is at
# meta-wisekiosk/recipes-core/kiosk-bootprof/files/measure-surf.sh.
#
# /data, not /tmp: /tmp is tmpfs and the staged file would not survive a reboot
# racing the capture. The remote file is removed once it is here.
#
# The default output goes under local/: a capture is a picture of the site's
# live kiosk page, and local/ is the gitignored home this repository already
# reserves for exactly that -- the repository is public and just runs recipes
# with cwd at its root.
#
# Reading it:
#
#   rgb min=0 max=255 mean~4    healthy -- black background, sparse light text.
#                               A mean near zero is NORMAL and is not evidence
#                               of a blank screen.
#   min == max                  every pixel identical: blank. This is the blank
#                               test, not the mean.
#
# A capture cannot tell you the render is LIVE. Every process-level check would
# look identical against a screen frozen for hours -- so the device's own clock
# is taken in the same SSH invocation as the capture, and the point of the
# exercise is comparing it against the clock the page renders. That is why this
# script refuses to overwrite an existing file: a stale PNG next to a fresh
# timestamp is the exact false pass it exists to prevent.
set -uo pipefail

HOST=${1:?usage: kiosk-screenshot.sh <ssh-target> [out.png]}
OUT=${2:-local/kiosk-$(date +%Y%m%d-%H%M%S).png}

ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)

mkdir -p "$(dirname "$OUT")" || { echo "cannot create $(dirname "$OUT")" >&2; exit 1; }

[ -e "$OUT" ] && { echo "$OUT exists -- refusing to overwrite a capture you may be about to read as fresh" >&2; exit 1; }

REMOTE=/data/kiosk-screenshot.$$.png

# Clock and capture in ONE invocation: two invocations put an unknown gap
# between the reference time and the pixels it is supposed to date.
#
# $REMOTE carries this run's local PID and must expand HERE, on the client, so
# the staged path is the one the scp below fetches. Deliberate, not an oversight.
# shellcheck disable=SC2029
DEVICE_TIME=$(ssh "${ssh_opts[@]}" "$HOST" "date '+%H:%M:%S'; DISPLAY=:0 import -window root $REMOTE") || {
    echo "capture failed on the device" >&2; exit 1; }

scp "${ssh_opts[@]}" "$HOST:$REMOTE" "$OUT" > /dev/null || { echo "could not fetch $REMOTE" >&2; exit 1; }
# Same client-side $REMOTE as the capture above: this must remove the exact path
# this run staged, not whatever a remote expansion would produce.
# shellcheck disable=SC2029
ssh "${ssh_opts[@]}" "$HOST" "rm -f $REMOTE" || true

[ -s "$OUT" ] || { echo "$OUT is empty -- the capture did not survive the copy" >&2; exit 1; }

echo "device clock at capture: $DEVICE_TIME"
echo "wrote $OUT"

# identify is optional on the workstation, so its absence must not read as a
# pass: say which check did not run.
if ! command -v identify > /dev/null; then
    echo "note: imagemagick not installed here -- min/max/mean NOT checked"
    exit 0
fi

# Normalised to 0-255 so the numbers are comparable with the signature above:
# %[min]/%[max]/%[mean] are reported in the build's quantum range, which is
# 65535 here, and a mean of 1000 next to a documented "mean~4" reads as a fault.
read -r MIN MAX MEAN <<< "$(identify -format '%[fx:minima*255] %[fx:maxima*255] %[fx:mean*255]' "$OUT")"
echo "min=$MIN max=$MAX mean=$MEAN"
if [ "$MIN" = "$MAX" ]; then
    echo "BLANK: every pixel identical -- the screen is not rendering"
    exit 1
fi
echo "not blank. Now read the rendered clock against the device clock above,"
echo "and the fetched data against its live source -- a frozen render passes"
echo "every other check there is."
