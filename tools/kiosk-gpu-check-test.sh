#!/usr/bin/env bash
# Self-test for tools/kiosk-gpu-check.sh's verdict.
#
#   tools/kiosk-gpu-check-test.sh
#
# kiosk-gpu-check.sh is a GATE -- its whole claim is that a future change which
# re-disables the GPU makes it FAIL. A gate nothing re-runs is unproven, which is
# why guard.sh ships beside guard-test.sh and the CVE tools beside
# cve-tools-test.py. This is that file, and `just guards` runs it.
#
# It reaches the SHIPPED function, not a copy: the tool is sourced with
# KIOSK_GPU_CHECK_LIB=1, which defines `gpu_verdict` and returns before any
# argument handling or device access. A test that re-implemented the three greps
# would prove the re-implementation and leave the tool unguarded.
#
# The verdict is a pure text -> exit code mapping, so every case here is a probe
# string and an expected code. No device, no network, milliseconds.
#
# Both directions are asserted deliberately. Proving the gate fires on bad input
# says nothing about whether it fires on everything: `drifd=10 drv=vc4_dri.so` is
# a LEGAL input that must still pass, and it is here because `drifd=[1-9]` came
# close to being written `drifd=1`.
#
# TO WATCH THIS FAIL -- do it before trusting a green run. Add `swrast` to the
# allowlist in kiosk-gpu-check.sh's `hw=` grep and re-run: `swrast-only` and
# `kms-swrast-only` go red, because the defect the gate exists for is exactly
# the one that allowlist catches. Revert afterwards.
#
# Exit codes are asserted, never messages: the code is the contract `just
# gpu-check` hands its caller, and wording is not. The consequence is worth
# knowing rather than discovering: the two failing branches both return 1, so
# neutering one of their diagnostics leaves this suite green. Message-level
# diagnosis is NOT covered here, deliberately.
set -uo pipefail

HERE=$(dirname "$0")
KIOSK_GPU_CHECK_LIB=1 . "$HERE/kiosk-gpu-check.sh"

pass=0
fail=0

# check <name> <expected-rc> <probe-text>
check() {
    local name=$1 want=$2 probe=$3 got
    gpu_verdict "$probe" > /dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL  $name: expected rc=$want, got rc=$got" >&2
    fi
}

MEM='mem CmaTotal:         131072 kB
mem CmaFree:           98304 kB
drm card0 present'

# --- the pass cases -------------------------------------------------------
check "vc4 hardware" 0 "proc surf pid=311 drifd=0 drv=none
proc WebKitWebProces pid=340 drifd=2 drv=v3d_dri.so vc4_dri.so
$MEM"

# `/proc/<pid>/comm` truncates at 15 characters, so the renderer is spelled
# WebKitWebProces on the device. The verdict keys on the drifd/drv fields rather
# than the name, and this case exists so that stays true.
check "vc4, renderer only" 0 "proc WebKitWebProces pid=340 drifd=1 drv=vc4_dri.so
$MEM"

# The legal input the gate must NOT reject. drifd=[1-9] matches the leading 1 of
# 10; a fixture with a single-digit count only would never have caught a
# `drifd=[1-9]$`-shaped tightening.
check "ten dri fds still pass" 0 "proc WebKitWebProces pid=340 drifd=10 drv=vc4_dri.so
$MEM"

# --- the failures the gate exists for -------------------------------------
check "swrast-only fails" 1 "proc WebKitWebProces pid=340 drifd=1 drv=swrast_dri.so
$MEM"

# The spelled-differently-but-equivalent variant. Caught by the allowlist
# without being named anywhere in the tool.
check "kms-swrast-only fails" 1 "proc WebKitWebProces pid=340 drifd=1 drv=kms_swrast_dri.so
$MEM"

check "no dri fd fails" 1 "proc surf pid=311 drifd=0 drv=none
proc WebKitWebProces pid=340 drifd=0 drv=none
mem CmaTotal:          65536 kB
mem CmaFree:           61440 kB
drm card0 absent"

# --- could-not-tell, which must never read as a pass ----------------------
check "no browser process is rc2" 2 "$MEM"
check "empty probe is rc2" 2 ""

# rc1 means the subject is broken; rc2 means the read did not happen. These four
# all used to land on rc1 or 0, which sends someone hunting a GPU regression the
# evidence never claimed -- or worse, passes. Each is a read that failed.
#
# grep -o absent is the `pgrep -c` class: busybox HAS -o (findutils/grep.c's
# OPTSTR_GREP, outside every IF_FEATURE_ guard), so this fixture encodes what
# happens if that ever stops being true, rather than a defect believed present.
check "grep -o missing is rc2, not software" 2 "cap grep_o=0
proc WebKitWebProces pid=340 drifd=1 drv=none
$MEM"

check "unreadable fd dir is rc2, not no-GPU" 2 "cap grep_o=1
proc WebKitWebProces pid=340 drifd=? drv=vc4_dri.so
$MEM"

check "unreadable maps is rc2, not software" 2 "cap grep_o=1
proc WebKitWebProces pid=340 drifd=1 drv=?
$MEM"

# The capability line present and healthy must not disturb any verdict.
check "cap grep_o=1 still passes a good board" 0 "cap grep_o=1
proc WebKitWebProces pid=340 drifd=2 drv=vc4_dri.so
$MEM"

# --- the fd and the driver must be the SAME process -----------------------
# The `.*` in the hw grep is what holds the open fd and the hardware driver on
# one line, i.e. in one process. Widen `drifd=[1-9]` to `drifd=[0-9]` there and
# every other case in this file still passes, so nothing else pins it.
#
# What that permits is concrete: surf holds the render node while running
# swrast, the web process maps vc4 but holds no node, and the tool reports "GPU
# path present" with neither process on the hardware path. It is also the exact
# shape of the open process-identity question in
# docs/issue_investigation/gpu_compositing/README.md, so this fixture pins
# today's answer -- whichever way the investigation's run settles it, the change
# is deliberate.
check "fd and driver in DIFFERENT processes fails" 1 "proc surf pid=311 drifd=1 drv=swrast_dri.so
proc WebKitWebProces pid=340 drifd=0 drv=vc4_dri.so
$MEM"

# --- the documented mixed rule --------------------------------------------
# Recorded as a fixture so the rule is visible rather than implied. Whether it
# SHOULD pass is an open question in
# docs/issue_investigation/gpu_compositing/README.md, waiting on a real board to
# show what it prints; this asserts today's shipped behaviour so a change to it is
# deliberate rather than accidental.
check "mixed vc4+swrast passes (see the investigation)" 0 "proc surf pid=311 drifd=1 drv=swrast_dri.so
proc WebKitWebProces pid=340 drifd=2 drv=v3d_dri.so
$MEM"

# --- the emitter and the verdict must keep one vocabulary -----------------
# The remote probe WRITES the sentinels and gpu_verdict READS them: two sides of
# a contract in one file, with nothing else holding them together. Renaming one
# side alone -- `dri="?"` to `dri="unknown"` in the emitter -- leaves every
# fixture above green, because they supply probe text directly and so cannot see
# the emitter at all. After that rename an unreadable /proc/<pid>/fd stops
# matching, falls through, and is reported as rc1 "NO GPU path": the board
# blamed for the tool's own blindness, which is the precise failure the
# could-not-tell split was built to prevent.
#
# The heredoc is single-quoted and must stay that way -- the remote body needs
# `$d` and `${d#/proc/}` expanded ON THE DEVICE -- so the two sides cannot share
# a shell constant. Asserting each sentinel appears on both sides is what is
# left, and it fires on a rename of either side.
#
# Known limit, written down rather than discovered: a presence check cannot tell
# code from comment, so a sentinel surviving only in a comment would satisfy it.
# Closing that needs parsing. It also fails CLOSED if either region goes empty --
# rename the function or the heredoc delimiter and it reports out-of-sync rather
# than quietly stopping to have an opinion.
# Paired because the two sides spell the same sentinel differently: the emitter
# ASSIGNS it (`dri="?"`) and the verdict MATCHES it (`drifd=?`, sometimes with
# the `?` escaped for -E). Each pair is emitter-literal, then verdict-regex.
TOOL="$HERE/kiosk-gpu-check.sh"
emitter=$(sed -n '/^PROBE=/,/^REMOTE$/p' "$TOOL")
verdict=$(sed -n '/^gpu_verdict()/,/^}$/p' "$TOOL")
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
sentinel_pair "unreadable-fd"   'dri="?"'       'drifd=[?\\]'
sentinel_pair "unreadable-maps" 'drv="?"'       'drv=[?\\]'
sentinel_pair "grep-o-capability" 'cap grep_o=' 'cap grep_o='

# --- the tool's own argument handling, which is not in gpu_verdict --------
# Run as a subprocess: these are exit paths of the script, not of the function.
"$HERE/kiosk-gpu-check.sh" > /dev/null 2>&1
rc=$?
if [ $rc -eq 2 ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); echo "FAIL  no argument: expected rc=2, got rc=$rc" >&2; fi

# Set-but-empty, the case `just gpu-check ""` produces. It shared rc=1 with the
# GPU-regression verdict until this fixture existed.
"$HERE/kiosk-gpu-check.sh" "" > /dev/null 2>&1
rc=$?
if [ $rc -eq 2 ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); echo "FAIL  empty host: expected rc=2, got rc=$rc" >&2; fi

"$HERE/kiosk-gpu-check.sh" root@example --bogus > /dev/null 2>&1
rc=$?
if [ $rc -eq 2 ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); echo "FAIL  bad flag: expected rc=2, got rc=$rc" >&2; fi

echo "kiosk-gpu-check: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
