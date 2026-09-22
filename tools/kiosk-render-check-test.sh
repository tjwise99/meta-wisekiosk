#!/usr/bin/env bash
# Self-test for tools/kiosk-render-check.sh's verdict.
#
#   tools/kiosk-render-check-test.sh
#
# kiosk-render-check.sh is a GATE, and the only one that can see a frozen render
# at all. Its claim is that identical frames FAIL and differing frames PASS, and
# that a capture which did not happen does neither. A gate nothing re-runs is
# unproven, which is why guard.sh ships beside guard-test.sh and
# kiosk-gpu-check.sh beside kiosk-gpu-check-test.sh.
#
# It reaches the SHIPPED function, not a copy: the tool is sourced with
# KIOSK_RENDER_CHECK_LIB=1, which defines `render_verdict` and returns before any
# argument handling or device access. A test that re-implemented the hash compare
# would prove the re-implementation and leave the tool unguarded.
#
# The verdict is a pure text -> exit code mapping, so every case is a probe
# string and an expected code. No device, no network, milliseconds.
#
# BOTH DIRECTIONS, deliberately. Proving it fires on identical hashes says
# nothing about whether it fires on everything -- a verdict hard-wired to return
# 1 would pass the frozen fixtures and every could-not-tell fixture that precedes
# them. The differing-hashes cases are what stop that.
#
# TO WATCH THIS FAIL -- do it before trusting a green run:
#   * invert the `[ "$h1" = "$h2" ]` test and re-run: 8 cases flip, every frozen
#     and every advancing one.
#   * neuter any ONE of trap (a)'s three guards -- `rc_bad=0`, `short=0`,
#     `empty=0` -- and re-run. Each takes a different fixture red, because each
#     is pinned by an input the other two let through. Measured: rc_bad -> 2 red,
#     short -> 3 red, empty -> 1 red.
#   * replace the emitter's `import -window root` with a read of /dev/fb0 and
#     re-run: 2 red. That is trap (b).
# Revert afterwards. Each of these was run against a scratch copy of the tool,
# not asserted from reading it -- and the first version of this list was WRONG:
# it named two fixtures for the rc guard that the byte guard already covered, so
# deleting the rc guard left the suite green. The fixture that closes it is
# "non-zero rc with a plausible frame".
#
# Exit codes are asserted, never messages: the code is the contract `just
# render-check` would hand its caller. The consequence is worth knowing rather
# than discovering -- the could-not-tell branches all return 2, so neutering one
# of their diagnostics leaves this suite green.
set -uo pipefail

HERE=$(dirname "$0")
KIOSK_RENDER_CHECK_LIB=1 . "$HERE/kiosk-render-check.sh"

pass=0
fail=0

# check <name> <expected-rc> <probe-text>
check() {
    local name=$1 want=$2 probe=$3 got
    render_verdict "$probe" > /dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL  $name: expected rc=$want, got rc=$got" >&2
    fi
}

CAP='cap import=1
cap identify=1
crop 520x140+240+30'

A=5d41402abc4b2a76b9719d911017c592
B=7d793037a0760186574b0282f2f435e7
NOTBLANK='blank min=0 max=255 mean=4.2'

# --- FROZEN: the failure this tool exists for -----------------------------
check "identical hashes are FROZEN" 1 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=0 at=10:43:14 bytes=1840 md5=$A
$NOTBLANK"

# Identical pixels do not require identical file sizes in principle, and the
# verdict must key on the HASH, not on bytes= agreeing. Pinned so a future
# "compare the sizes too" shortcut is a deliberate change.
check "identical hashes, differing byte counts, still FROZEN" 1 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=0 at=10:43:14 bytes=1841 md5=$A
$NOTBLANK"

# No identify on the device: the blank line is absent entirely, and its absence
# must not block the verdict. A `[ "$mn" = "$mx" ]` written without the -n guards
# compares two empty strings, finds them equal, and turns every board without
# identify into a permanent rc2.
check "FROZEN with no blank line at all" 1 "cap import=1
cap identify=0
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=0 at=10:43:14 bytes=1840 md5=$A"

# --- advancing: the legal input the gate must NOT reject ------------------
check "differing hashes are advancing" 0 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=0 at=10:43:14 bytes=1852 md5=$B
$NOTBLANK"

check "advancing with no blank line at all" 0 "cap import=1
cap identify=0
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=0 at=10:43:14 bytes=1852 md5=$B"

# An `err` line is not by itself a failure -- import warns about visuals and
# colormaps on this board while producing a perfectly good PNG. The rc field is
# the authority, and this fixture keeps it that way.
check "advancing despite an import warning on stderr" 0 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
err import: geometry does not contain image
frame 2 rc=0 at=10:43:14 bytes=1852 md5=$B
$NOTBLANK"

# --- trap (a): a capture that did not happen is NEVER frozen --------------
# Each of these hashes identically across both frames, which is precisely how a
# failed capture impersonates a frozen screen.
check "failed capture is rc2, not FROZEN" 2 "$CAP
frame 1 rc=1 at=10:43:10 bytes=0 md5=none
frame 2 rc=0 at=10:43:14 bytes=1840 md5=$A"

check "both captures failed is rc2, not FROZEN" 2 "$CAP
frame 1 rc=1 at=10:43:10 bytes=0 md5=none
frame 2 rc=1 at=10:43:14 bytes=0 md5=none
err import: unable to open X server \`:0'"

# The rc guard's OWN fixture, and the reason it has one. The two cases above are
# caught by the byte guard whether or not the rc guard exists -- deleting the
# rc guard and re-running left this suite fully green, which is the defect that
# put this case here. Three guards are only three guards if each one is pinned
# by an input the other two let through.
#
# The shape is real, not contrived: import failing partway leaves a
# plausibly-sized partial PNG, and import failing with an earlier run's file
# still in place leaves a full one. Both hash stably across two frames, which is
# a FROZEN verdict on a board whose screen was never photographed.
check "non-zero rc with a plausible frame is rc2, not FROZEN" 2 "$CAP
frame 1 rc=1 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=1 at=10:43:14 bytes=1840 md5=$A
$NOTBLANK"

# Same, on one frame only and with the hashes differing: an advancing verdict is
# just as wrong when half the evidence was never collected.
check "one non-zero rc among differing hashes is rc2, not advancing" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=2 at=10:43:14 bytes=1852 md5=$B
$NOTBLANK"

# The exact constant, reached with rc=0 and a plausible byte count so the two
# guards ahead of it cannot be what catches this. Delete the EMPTY_MD5 branch
# and this case alone goes red.
check "md5 of empty input is rc2, not FROZEN" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$EMPTY_MD5
frame 2 rc=0 at=10:43:14 bytes=1840 md5=$EMPTY_MD5
$NOTBLANK"

# import exiting 0 having written nothing. The byte guard is the only thing
# between this and a FROZEN verdict.
check "short frame is rc2, not FROZEN" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=0 md5=$A
frame 2 rc=0 at=10:43:14 bytes=0 md5=$A
$NOTBLANK"

# One byte under the threshold, and one byte over. The pair is what pins the
# comparison as numeric-and-strict rather than, say, `bytes=0`.
check "one byte under MIN_BYTES is rc2" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=$((MIN_BYTES - 1)) md5=$A
frame 2 rc=0 at=10:43:14 bytes=1840 md5=$B
$NOTBLANK"

check "exactly MIN_BYTES is accepted" 0 "$CAP
frame 1 rc=0 at=10:43:10 bytes=$MIN_BYTES md5=$A
frame 2 rc=0 at=10:43:14 bytes=1840 md5=$B
$NOTBLANK"

# --- the other could-not-tells --------------------------------------------
check "no import on the device is rc2" 2 "cap import=0"
check "empty probe is rc2" 2 ""

check "one frame only is rc2" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
$NOTBLANK"

# Three frames is as broken a comparison as one: something emitted a line this
# verdict does not understand, and picking two of the three would be inventing
# an answer.
check "three frames is rc2" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=0 at=10:43:14 bytes=1840 md5=$A
frame 3 rc=0 at=10:43:18 bytes=1840 md5=$A
$NOTBLANK"

# A uniform region is could-not-tell, not FROZEN -- the hashes agree for a
# reason that says nothing about the browser. This is the mis-aimed-crop case,
# and scoring it rc1 is what would send someone to a working wall-mounted panel.
check "uniform region is rc2, not FROZEN" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=180 md5=$A
frame 2 rc=0 at=10:43:14 bytes=180 md5=$A
blank min=0 max=0 mean=0"

# All-white is just as uniform as all-black, and a `min=0 max=0` test would miss
# it. Written to fail a threshold-on-zero shortcut.
check "uniform white region is rc2 too" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=180 md5=$A
frame 2 rc=0 at=10:43:14 bytes=180 md5=$A
blank min=255 max=255 mean=255"

# Not blank by one value. The boundary the case above needs to be meaningful.
check "min differing from max by one is a real verdict" 1 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840 md5=$A
frame 2 rc=0 at=10:43:14 bytes=1840 md5=$A
blank min=0 max=1 mean=0.02"

# A frame line whose md5 field the verdict cannot read. Reported as out-of-step,
# never compared -- two empty strings are equal, and that is a FROZEN verdict
# over nothing at all.
check "missing md5 field is rc2" 2 "$CAP
frame 1 rc=0 at=10:43:10 bytes=1840
frame 2 rc=0 at=10:43:14 bytes=1840
$NOTBLANK"

# --- the emitter and the verdict must keep one vocabulary -----------------
# The remote probe WRITES these sentinels and render_verdict READS them: two
# sides of a contract in one file with nothing else holding them together.
# Renaming one side alone leaves every fixture above green, because they supply
# probe text directly and so cannot see the emitter at all. After such a rename
# a failed capture stops matching, falls through, and is reported as FROZEN --
# the board blamed for the tool's own blindness, which is the precise failure
# the could-not-tell split exists to prevent.
#
# The heredoc is single-quoted and must stay that way, so the two sides cannot
# share a shell constant. Asserting each sentinel appears on both sides is what
# is left, and it fires on a rename of either side.
#
# Known limit, written down rather than discovered: a presence check cannot tell
# code from comment, so a sentinel surviving only in a comment would satisfy it.
# It fails CLOSED if either region goes empty -- rename the function or the
# heredoc delimiter and it reports out-of-sync rather than quietly stopping to
# have an opinion.
TOOL="$HERE/kiosk-render-check.sh"
emitter=$(sed -n '/^PROBE=/,/^REMOTE$/p' "$TOOL")
verdict=$(sed -n '/^render_verdict()/,/^}$/p' "$TOOL")
sentinel_pair() {
    local name=$1 emit=$2 read=$3 e r
    e=$(printf '%s\n' "$emitter" | grep -cF "$emit")
    r=$(printf '%s\n' "$verdict" | grep -cE "$read")
    if [ "$e" -gt 0 ] && [ "$r" -gt 0 ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL  sentinel $name out of sync: emitter=$e verdict=$r" >&2
    fi
}
sentinel_pair "frame-line"  'echo "frame $n rc='  '\^frame '
sentinel_pair "import-cap"  'cap import=0'        'cap import=0'
sentinel_pair "blank-line"  'blank min='          '\^blank '
sentinel_pair "md5-field"   'md5=$m'              'md5='
sentinel_pair "bytes-field" 'bytes=$b'            'bytes='

# The capture path is trap (b). `import -window root` is the only surface the
# kiosk actually draws to; /dev/fb0 holds the console login buffer under fkms and
# would hand back a stable hash from a surface the browser never touches -- a
# FROZEN verdict that is true of the framebuffer and says nothing about the
# render. Asserted as a property of the shipped file, because the day someone
# "optimises" the capture is the day it silently starts lying.
if [ "$(printf '%s\n' "$emitter" | grep -cF 'import -window root')" -gt 0 ]; then
    pass=$((pass + 1))
else
    fail=$((fail + 1)); echo "FAIL  emitter no longer captures with import -window root" >&2; fi

if [ "$(printf '%s\n' "$emitter" | grep -cF '/dev/fb0')" -eq 0 ]; then
    pass=$((pass + 1))
else
    fail=$((fail + 1))
    echo "FAIL  the remote probe reads /dev/fb0 -- it is the console login buffer," >&2
    echo "      not the kiosk, and hashing it reports FROZEN on a painting board" >&2
fi

# --- the tool's own argument handling, which is not in render_verdict -----
# Run as a subprocess: these are exit paths of the script, not of the function.
# Each must be rc2 -- a misinvocation reported as rc1 sends someone to a ladder.
argcheck() {
    local name=$1; shift
    "$HERE/kiosk-render-check.sh" "$@" > /dev/null 2>&1
    local rc=$?
    if [ $rc -eq 2 ]; then pass=$((pass + 1)); else
        fail=$((fail + 1)); echo "FAIL  $name: expected rc=2, got rc=$rc" >&2; fi
}
argcheck "no argument"
# Set-but-empty, the case a `just render-check ""` produces.
argcheck "empty host" ""
argcheck "malformed crop" root@example.invalid "520x140"
argcheck "crop with negative offset" root@example.invalid "520x140+-4+30"
argcheck "crop with shell metacharacters" root@example.invalid '520x140+0+0; rm -rf /'

echo "kiosk-render-check: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
