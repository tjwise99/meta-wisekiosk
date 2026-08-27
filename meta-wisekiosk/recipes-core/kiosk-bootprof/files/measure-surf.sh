#!/bin/sh
# Complete-display time for the Yocto kiosk, monotonic form.
#
# "Complete display" is when the weather icons have rendered -- the only endpoint
# a viewer sees, and deliberately NOT loadEventEnd: the modules keep fetching and
# rendering after surf's load event.
#
# The Raspbian tools/measure-surf.sh does not run here: no /home/pi, no
# .Xauthority, no kiosk-prefetch/kiosk-rngd, and busybox head/od take different
# flags. The measurement itself is the same shape.
#
#   complete_display = uptime_at_exec + load_started + performance.now()
#
# All three are CLOCK_MONOTONIC-derived, which is what makes this trustworthy on
# a board whose wall clock steps mid-boot: fake-hwclock restores the shutdown
# time and timesyncd steps it forward once the network is up, so any epoch-based
# form can read ~30 s low. The page self-timestamps into its own title, so
# reading it late does not perturb the value.
#
# Nothing is polled during the startup window. On one saturated core, a poll loop
# forking xprop inflates the number it is reading.

READ_AT=${1:-115}
export DISPLAY=:0
ML=/var/log/surf-milestones.log

NOW=$(cut -d. -f1 /proc/uptime)
[ "$NOW" -lt "$READ_AT" ] && sleep $((READ_AT - NOW))

# xwininfo -tree, not -children: surf sets override-redirect, so the window is
# absent from the client list and is not a direct child of root either.
TITLE=''
for _ in 1 2 3 4 5; do
	for id in $(xwininfo -root -tree 2>/dev/null | awk '/^ +0x/ { print $1 }'); do
		t=$(xprop -id "$id" WM_NAME 2>/dev/null | sed 's/^WM_NAME(STRING) = "//; s/"$//')
		case "$t" in *'| T '*) TITLE="$t" ;; esac
	done
	[ -n "$TITLE" ] && break
	sleep 10
done

echo "boot_id:       $(cat /proc/sys/kernel/random/boot_id)"
echo "read_at_s:     $(cut -d. -f1 /proc/uptime)"

if [ -z "$TITLE" ]; then
	echo 'RESULT: TIMEOUT -- no instrumented title found'
	exit 1
fi

# Title is "<mirror bits> | T <navigationStart_ms> <performance.now_ms>"
PN=${TITLE##* }
NAV=${TITLE% *}; NAV=${NAV##* }

UPX=$(awk '/uptime_at_exec/{print $3; exit}' "$ML" 2>/dev/null)
LST=$(awk '/ load_started /{print $3; exit}' "$ML" 2>/dev/null)
LFN=$(awk '/ load_finished /{print $3; exit}' "$ML" 2>/dev/null)

echo "title:         $TITLE"
if [ -z "$UPX" ] || [ -z "$LST" ]; then
	echo "RESULT: INCOMPLETE -- milestones missing from $ML"
	exit 1
fi

awk -v u="$UPX" -v l="$LST" -v f="$LFN" -v pn="$PN" 'BEGIN {
	printf "uptime_at_exec_s:   %.2f\n", u
	printf "load_started_s:     %.2f  (offset from exec)\n", l
	if (f != "") printf "load_finished_s:    %.2f  (absolute: %.2f)\n", f, u + f
	printf "perf_now_s:         %.2f  (icon render, from navigationStart)\n", pn/1000
	printf "RESULT_complete_display_s: %.2f\n", u + l + pn/1000
}'
