#!/usr/bin/env bash
# Take one boot profile end to end: enable, reboot, wait, pull, analyze, disable.
#
#   tools/kiosk-bootprofile.sh root@<host> [outdir] [wait-seconds]
#
# The six-step cycle below (enable, reboot, wait, collect, disable, analyze)
# needs a reachable kiosk end to end. What runs without one: argument
# handling, outdir creation, the ssh failure modes against an unreachable or
# nonexistent host, and the analyzer's parsing, invoked directly against a
# sample file.
#
# The sampler is image content that ships disabled -- it costs ~240ms of the
# boot it measures, so it is not something to leave on. What it is, what it
# cannot see, and how to read its output are at
# meta-wisekiosk/recipes-core/kiosk-bootprof/README.md; this script is only the
# capture cycle, which is otherwise six commands that have to be issued in order
# and one file that has to be named exactly right.
#
# The off switch is `systemctl disable`, never `rm` -- the README above says
# why. The wait is not politeness either: nothing exists to fetch before the
# sampler's window closes, and an SSH session opened during it skews the
# measurement by the cost quantified in that README. One connection, after.
#
# The default outdir is local/: the journal this pulls carries the hostname,
# addresses and the SSID, and local/ is the gitignored home this repository
# already reserves for exactly that -- the repository is public and just runs
# recipes with cwd at its root.
set -uo pipefail

HOST=${1:?usage: kiosk-bootprofile.sh <ssh-target> [outdir] [wait-seconds]}
OUTDIR=${2:-local}
WAIT=${3:-180}

# The analyzer is repo content, so resolve it against this script rather than
# against cwd. The [outdir] parameter is the tell that this is run from
# elsewhere, and the analyze step is the last one -- a path failure there has
# already spent a reboot of the thing under test.
REPO=$(cd "$(dirname "$0")/.." && pwd)

ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
# "$@" is this function's own arguments, forwarded to form the remote command --
# client-side expansion is the point, and there is no remote value to quote.
# shellcheck disable=SC2029
ssh_dev() { ssh "${ssh_opts[@]}" "$HOST" "$@"; }

mkdir -p "$OUTDIR"

# /data survives a reboot by design, so every earlier profile is still sitting
# there and `ls -t` will hand one back whether or not the reboot happened. The
# boot id taken here is what makes a stale sample distinguishable from a fresh
# one; without it, passing and failing are byte-identical.
BOOT_BEFORE=$(ssh_dev 'cat /proc/sys/kernel/random/boot_id' | tr -d '\r\n')
[ -n "$BOOT_BEFORE" ] || { echo "could not read the device's boot id -- refusing to run blind" >&2; exit 1; }

echo "== arming the sampler and rebooting (boot id now $BOOT_BEFORE)"
ssh_dev 'systemctl enable kiosk-bootprofile' || { echo "could not enable the unit" >&2; exit 1; }
ssh_dev 'systemctl reboot' > /dev/null 2>&1 || true

echo "== waiting ${WAIT}s without touching the device"
sleep "$WAIT"

echo "== collecting"
SAMPLE_REMOTE=""
BOOT_NOW=""
for _ in 1 2 3 4 5 6; do
    BOOT_NOW=$(ssh_dev 'cat /proc/sys/kernel/random/boot_id' | tr -d '\r\n')
    if [ -z "$BOOT_NOW" ] || [ "$BOOT_NOW" = "$BOOT_BEFORE" ]; then
        echo "   the device is still on boot $BOOT_BEFORE -- waiting 20s"
        sleep 20
        continue
    fi
    # Only the expected unmatched-glob message is filtered. A blanket
    # 2>/dev/null here would hide an unmounted /data exactly as well as it hides
    # a sample that has not been written yet.
    NEWEST=$(ssh_dev 'ls -t /data/boot-cpu-io.*.txt' 2>&1 \
        | grep -v 'No such file or directory' | head -n1 | tr -d '\r')
    # The sampler names its file after the boot it measured (kiosk-bootprof.c
    # writes "<out_path>.<boot-id>.txt"), so the NAME carries the proof and is
    # stronger than an mtime. Anything else is a leftover from an earlier boot.
    if [ "$NEWEST" = "/data/boot-cpu-io.$BOOT_NOW.txt" ]; then
        SAMPLE_REMOTE=$NEWEST
        break
    fi
    [ -n "$NEWEST" ] && echo "   device answered: $NEWEST -- not the sample for boot $BOOT_NOW"
    echo "   no sample for this boot yet; the sampler writes once at uptime 150 -- waiting 20s"
    sleep 20
done
[ -n "$SAMPLE_REMOTE" ] || {
    echo "no /data/boot-cpu-io.$BOOT_NOW.txt appeared -- a sample from an earlier boot is not a profile of this one" >&2
    exit 1
}

STEM=$(basename "$SAMPLE_REMOTE" .txt)
BOOT_ID=${STEM#boot-cpu-io.}

scp "${ssh_opts[@]}" "$HOST:$SAMPLE_REMOTE" "$OUTDIR/$STEM.txt" > /dev/null \
    || { echo "could not fetch $SAMPLE_REMOTE" >&2; exit 1; }

# The analyzer derives every window edge from a journal it finds by NAME:
# <same-stem>.journal.txt beside the samples. Get the name wrong and it falls
# back to hardcoded defaults, which are wrong the moment anything moves -- and
# it says so only in one word of its own output. Naming it here is why this is a
# script and not a paragraph.
#
# `journalctl -b` wants the boot ID with the dashes stripped. `-b -1` does not
# work on this image at all: every boot shares a pre-timesync first-entry
# timestamp, so "the previous boot" is not identifiable that way.
JOURNAL_ID=${BOOT_ID//-/}
ssh_dev "journalctl -b $JOURNAL_ID -o short-monotonic" > "$OUTDIR/$STEM.journal.txt" \
    || { echo "could not read the journal for boot $JOURNAL_ID" >&2; exit 1; }
[ -s "$OUTDIR/$STEM.journal.txt" ] || { echo "journal for boot $JOURNAL_ID is empty" >&2; exit 1; }

echo "== disarming"
ssh_dev 'systemctl disable kiosk-bootprofile' || echo "WARNING: the unit is still enabled" >&2

echo "== analyzing"
python3 "$REPO/meta-wisekiosk/recipes-core/kiosk-bootprof/files/analyze-boot-cpu-io.py" "$OUTDIR/$STEM.txt"
