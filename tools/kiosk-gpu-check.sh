#!/usr/bin/env bash
# Is WebKit compositing on the GPU, or repainting every frame on the CPU?
#
#   tools/kiosk-gpu-check.sh root@<host>
#
# The regression guard for the vc4 switch. The image can build mesa, ship
# xf86-video-modesetting and still land WebKit back in software rendering --
# a black kiosk looks identical either way, and so does a smooth-enough page on
# a cold morning. This turns that into an exit code.
#
# WHAT IT READS, AND WHY NOT THE OBVIOUS THING.
#
# The authoritative answer is the "Renderer" row of `webkit://gpu`, which reads
# `DMABuf (Supported buffers: Hardware, Shared Memory)` -- and is ABSENT
# altogether when no mode is available. That row cannot be read from here.
# WebKit computes it in AcceleratedBackingStoreDMABuf::rendererBufferMode()
# from EGL extension queries, never logs it on any WEBKIT_DEBUG channel, and
# exposes it only as pixels rendered by a browser (WebKitProtocolHandler.cpp,
# handleGPU). There is no headless read of it. A script claiming to have read
# it would be asserting something it never saw.
#
# So this reads the GPU path's FOOTPRINT in the web process instead, which is
# decidable over SSH from /proc alone:
#
#   an fd on /dev/dri/*       the DMABuf backing store holds the render node
#                             open. On the Broadcom-userland image it is absent,
#                             because the EGL fails the extension gate and no
#                             accelerated backing store is created at all
#   *_dri.so in maps          which mesa gallium driver is mapped. Both vc4 and
#                             v3d are BUILT (meta-raspberrypi's mesa_%.bbappend
#                             adds `gallium vc4 v3d kmsro`); which one a
#                             BCM2835 actually loads is not asserted here and is
#                             something the investigation's run records from its
#                             drv= output. Either
#                             satisfies the check. swrast_dri.so is mesa's
#                             software rasteriser, which opens a render node too
#                             and would otherwise pass while doing exactly the
#                             CPU work this switch exists to remove
#
# This is a PROXY for the buffer mode, not the mode. It cannot tell Hardware
# from Shared Memory -- both open a render node. What it can tell, which is the
# regression worth catching, is a hardware GPU path from software wearing its
# clothes.
#
# KNOWN LIMIT, open until a board runs: when one process maps a hardware driver
# and another maps only swrast, this passes on the hardware match. No board has
# yet printed a drv= line, so whether that combination can even arise is
# unobserved -- and so is which process holds the fd, which is why the check
# accepts any member of the family rather than naming WebKitWebProcess. Both
# questions are recorded in
# docs/issue_investigation/gpu_compositing/README.md and settled by that run's
# output, not by argument.
#
# CMA is printed beside it because full KMS on a 512 MB board is the other half
# of the risk: the framebuffer comes out of the CMA pool, and a pool that is
# large enough to boot and too small under load fails hours later as an
# allocation error, not as a blank screen at boot.
#
# `--capture` DRIVES the page the default mode cannot read: it points KIOSK_URL
# at webkit://gpu, restarts the kiosk, screenshots, then puts KIOSK_URL back and
# restarts again. It produces a PNG for a person to read the Renderer row off.
# It does NOT read that row and never reports a verdict from it -- the exit code
# in that mode means "the capture came back", not "compositing is on".
#
#   tools/kiosk-gpu-check.sh root@<host>                   read-only, exit-coded
#   tools/kiosk-gpu-check.sh root@<host> --capture [out.png]  mutating, for eyes
#
# --capture RESTARTS THE KIOSK TWICE and edits /data/config/kiosk.conf. It backs
# the whole file up on the device first and restores by moving that backup
# BACK -- never by rewriting the URL line from a value carried through a shell
# quote, which is one odd character away from corrupting the only configuration
# file a wall-mounted panel has. The revert is trapped, so an interrupt or a
# failed capture still runs it. The one case it cannot cover is the device dying
# mid-run: that leaves the panel on webkit://gpu, and the fix is to move
# /data/config/kiosk.conf.gpucheck-bak back over kiosk.conf by hand.
#
# Without a reachable kiosk, what still runs: argument handling, the mode split,
# and the SSH failure modes. Everything else is a read of the device's own /proc.
set -uo pipefail

# ---------------------------------------------------------------- the verdict
#
# Everything that can regress lives in this one function, and it is a pure
# text -> exit code mapping: it reads the probe text and touches no device. That
# is what lets tools/kiosk-gpu-check-test.sh exercise the SHIPPED logic rather
# than a copy of it -- the test sources this file with KIOSK_GPU_CHECK_LIB=1 and
# calls this function directly. Keep it pure; a device read in here would make
# the guard untestable again.
#
#   0  a web process holds a DRM node open with a vc4/v3d driver mapped
#   1  the subject is broken: no DRM node, or software mesa only
#   2  could not tell: no browser process, transport failure, misinvocation
gpu_verdict() {
    local probe=$1 procs gpu hw

    # An empty process list is not a pass. It means the browser is not running,
    # or the walk matched nothing -- neither of which is evidence about the GPU,
    # and both of which would otherwise fall through to the same "no dri fd"
    # verdict as a genuine software-rendering regression.
    #
    # grep -c, never -q: under `set -o pipefail` a -q exits on the first match,
    # the producer dies of SIGPIPE at 141, and the condition reads FALSE exactly
    # when the pattern matched.
    procs=$(printf '%s\n' "$probe" | grep -c '^proc ')
    if [ "$procs" -eq 0 ]; then
        echo "no surf or WebKit process on the device -- nothing to measure, not a pass" >&2
        return 2
    fi

    # The could-not-tell cases, taken BEFORE any verdict. Each is a read that
    # did not happen, and a read that did not happen must never be scored as the
    # subject being broken: rc1 sends someone hunting a GPU regression that the
    # evidence never claimed.
    if [ "$(printf '%s\n' "$probe" | grep -c '^cap grep_o=0')" -ne 0 ]; then
        echo "cannot tell: the device's grep has no -o, so no driver name could be" >&2
        echo "extracted from any process's maps. Every drv= field is meaningless," >&2
        echo "and a good vc4 board would read as software mesa." >&2
        return 2
    fi
    if [ "$(printf '%s\n' "$probe" | grep -c '^proc .* drifd=?')" -ne 0 ]; then
        echo "cannot tell: a process's fd directory could not be read (drifd=? above)." >&2
        echo "An unreadable /proc/<pid>/fd and a process holding no DRM fd are" >&2
        echo "different answers; this is the first, and it is not a verdict." >&2
        return 2
    fi

    gpu=$(printf '%s\n' "$probe" | grep -cE '^proc .* drifd=[1-9]')
    if [ "$gpu" -eq 0 ]; then
        echo "NO GPU path: no web process holds /dev/dri open. WebKit is compositing in" >&2
        echo "software, or not compositing at all. See" >&2
        echo "docs/issue_investigation/gpu_compositing/README.md." >&2
        return 1
    fi

    # An open render node is necessary and not sufficient: mesa's software
    # rasteriser opens one too. A swrast-only image boots, renders, and holds the
    # fd -- it looks exactly like the pass below while doing on the CPU the whole
    # thing this switch exists to move off it.
    #
    # This is an ALLOWLIST of the board's hardware drivers, not a denylist of
    # swrast: a driver nobody anticipated fails closed rather than passing by
    # default, and `kms_swrast_dri.so` -- the other name the software path wears
    # -- is caught without being named.
    hw=$(printf '%s\n' "$probe" | grep -cE '^proc .* drifd=[1-9].*(vc4|v3d)_dri\.so')
    if [ "$hw" -eq 0 ]; then
        # One more could-not-tell before calling it software: if the candidate's
        # maps were unreadable, "no vc4/v3d mapped" is an absence of evidence,
        # not evidence of absence.
        if [ "$(printf '%s\n' "$probe" | grep -cE '^proc .* drifd=[1-9] drv=\?')" -ne 0 ]; then
            echo "cannot tell: the process holding /dev/dri has unreadable maps (drv=?)," >&2
            echo "so which driver it mapped is unknown. Not a software verdict." >&2
            return 2
        fi
        echo "SOFTWARE mesa: a web process holds /dev/dri open, but no vc4/v3d driver" >&2
        echo "is mapped -- the drv= field above says which. mesa fell back to its" >&2
        echo "software rasteriser, so compositing is still on the CPU." >&2
        return 1
    fi

    echo "GPU path present: a web process holds /dev/dri open with a vc4/v3d driver"
    echo "mapped. Confirm the mode itself by reading webkit://gpu's Renderer row --"
    echo "this cannot distinguish Hardware from Shared Memory."
    return 0
}

# Sourced as a library by the self-test: define the verdict and stop, before any
# argument handling or device access. `return` succeeds only when sourced, so an
# ordinary run falls through to exit.
if [ "${KIOSK_GPU_CHECK_LIB:-0}" = "1" ]; then
    # shellcheck disable=SC2317  # the `||` arm runs when this file is executed, not sourced
    return 0 2>/dev/null || exit 0
fi

# ------------------------------------------------------------------- the tool

# A misinvocation is "I could not tell", not "the board regressed" -- so exit 2,
# never 1. `${1:?}` would leave bash's own parameter-error status of 1, which is
# the code a caller reads as a GPU regression, and it fires on set-but-empty too
# (`just gpu-check ""`).
if [ "${1:-}" = "" ]; then
    echo "usage: kiosk-gpu-check.sh <ssh-target> [--capture [out.png]]" >&2
    exit 2
fi
HOST=$1
MODE=${2:-}
OUT=${3:-}

HERE=$(dirname "$0")

if [ -n "$MODE" ] && [ "$MODE" != "--capture" ]; then
    echo "unknown argument '$MODE' -- expected --capture" >&2
    exit 2
fi

if [ "$MODE" = "--capture" ]; then
    # The URL is site configuration and lives only on the device
    # (kiosk-session_1.0.bb: no /etc/kiosk.conf is generated), so the original
    # value exists nowhere else. It is read back here and restored from THAT,
    # never from a guess at what it should be -- putting a wrong URL on a
    # wall-mounted panel is the failure this mode could most easily cause.
    #
    # The restore moves a BACKUP OF THE WHOLE FILE back, rather than rewriting
    # the URL line from a value this script carried around. A URL interpolated
    # back through a shell quote is one odd character away from writing a broken
    # line to a wall-mounted panel's only configuration file; a file move cannot
    # misquote anything.
    # Armed BEFORE the swap, not after: a trap installed on the line following
    # the mutation leaves a window in which an interrupt strands the panel on
    # webkit://gpu. Restoring when there is no backup is a no-op, so arming it
    # early costs nothing.
    # The remote side says which of the two things it did. Without that marker a
    # run where no backup existed prints the same "restored" line as one that
    # really moved the file back -- the reassuring message would be the only
    # evidence, and it would be identical either way.
    # shellcheck disable=SC2317  # reached through the trap below, which shellcheck does not follow
    restore() {
        local out rc
        out=$("$HERE/kiosk-ssh.sh" "$HOST" 'sh -s' <<'RESTORE'
[ -f /data/config/kiosk.conf.gpucheck-bak ] || { echo "nothing-to-restore"; exit 0; }
mv /data/config/kiosk.conf.gpucheck-bak /data/config/kiosk.conf
systemctl restart kiosk
echo "restored"
RESTORE
        )
        rc=$?
        if [ "$rc" -eq 0 ]; then
            case "$out" in
                *restored*)          echo "kiosk.conf restored from its backup; kiosk restarted" ;;
                *nothing-to-restore*) echo "no backup on the device -- kiosk.conf was never swapped" ;;
                *)                   echo "restore reported neither outcome: $out" >&2 ;;
            esac
        else
            echo "RESTORE FAILED (rc=$rc): /data/config/kiosk.conf.gpucheck-bak is" >&2
            echo "still on $HOST. Move it back over kiosk.conf by hand -- until then" >&2
            echo "the panel is showing webkit://gpu, not the kiosk page." >&2
        fi
    }
    trap restore EXIT INT TERM

    "$HERE/kiosk-ssh.sh" "$HOST" 'sh -s' <<'PREP' || {
grep -q '^KIOSK_URL=' /data/config/kiosk.conf || exit 3
cp /data/config/kiosk.conf /data/config/kiosk.conf.gpucheck-bak
sed -i '/^KIOSK_URL=/d' /data/config/kiosk.conf
echo 'KIOSK_URL=webkit://gpu' >> /data/config/kiosk.conf
systemctl restart kiosk
PREP
        echo "could not stage the probe URL on $HOST (exit 3 means kiosk.conf has" >&2
        echo "no KIOSK_URL line at all, so there is nothing to put back)." >&2
        exit 2; }

    # surf has to reach first-paint before there is anything to photograph. The
    # milestone the launcher already emits is the honest signal; this polls for
    # the process rather than sleeping a guessed interval, and gives up rather
    # than capturing a screen that is still blank -- a blank PNG here reads
    # exactly like compositing being off.
    #
    # `pgrep -x … | wc -l`, NOT `pgrep -c`: busybox's pgrep accepts
    # "vlafxones:+P:+" (procps/pgrep.c:141) and has no -c at all. It would exit
    # 1 with a usage message, `|| true` would swallow it, and the count would
    # read empty -> 0 on every poll -- so the loop could never break and
    # --capture would report "surf did not come back up" on a perfectly healthy
    # board, every time. kiosk-soak.sh:98 uses the same `pgrep -x` shape.
    #
    # A poll that could not RUN is tracked apart from a poll that ran and found
    # no surf. Losing the transport mid-capture and the browser failing to come
    # back are different answers, and collapsing them onto rc1 reports a broken
    # kiosk when the truth is a dropped connection.
    up=0
    pollrc=0
    for _ in $(seq 1 30); do
        up=$("$HERE/kiosk-ssh.sh" "$HOST" 'pgrep -x surf | wc -l')
        pollrc=$?
        [ $pollrc -eq 0 ] && [ "${up:-0}" != "0" ] && break
        sleep 2
    done
    if [ $pollrc -ne 0 ]; then
        echo "cannot tell: lost contact with $HOST while waiting for surf (ssh exited" >&2
        echo "$pollrc). Whether the browser came back is unknown. kiosk.conf is put" >&2
        echo "back on the way out -- verify it by hand if that restore also failed." >&2
        exit 2
    fi
    if [ "${up:-0}" = "0" ]; then
        echo "surf did not come back up within 60s -- not capturing a screen that" >&2
        echo "has nothing on it yet. kiosk.conf is put back on the way out." >&2
        exit 1
    fi
    sleep 5

    "$HERE/kiosk-screenshot.sh" "$HOST" ${OUT:+"$OUT"} || { echo "capture failed" >&2; exit 1; }

    # No verdict, deliberately. The Renderer row is pixels in that PNG and this
    # never parsed it; an exit code here would be asserting something unread.
    echo
    echo "Read the 'Hardware Acceleration Information' table in the capture:"
    echo "  Renderer: DMABuf (Supported buffers: Hardware, Shared Memory)  -- GPU"
    echo "  Renderer row ABSENT                                           -- no mode at all"
    echo "This mode reports only that the capture came back, not what it shows."
    exit 0
fi

# One round trip through the shared multiplex master. The key exchange runs on
# the same core the browser renders on, so a probe made of eight ssh calls is
# itself load on the thing being measured.
#
# `sh`, not `bash`: this image is busybox userland and bash is not guaranteed.
# For the same reason the walk below is /proc directly -- busybox ps has no
# -eo, and pgrep alone would miss the renderer, which is a separate process and
# is the one that holds the GPU.
PROBE=$("$HERE/kiosk-ssh.sh" "$HOST" 'sh -s' <<'REMOTE'
# The probe states its own capability rather than assuming it. busybox 1.36.1
# carries -o unconditionally (findutils/grep.c, OPTSTR_GREP, outside every
# IF_FEATURE_ guard), so this is expected to be 1 -- but if it ever is not, the
# driver names come back empty and a GOOD vc4 board reads as software mesa. That
# is a false FAIL on a wall-mounted unit, so the verdict turns it into
# "could not tell" instead of guessing. `pgrep -c`, which busybox genuinely does
# NOT have, is exactly this class of assumption gone wrong.
if echo x_dri.so | grep -oE '[a-z0-9_]+_dri\.so' > /dev/null 2>&1; then
    echo "cap grep_o=1"
else
    echo "cap grep_o=0"
fi
for d in /proc/[0-9]*; do
    c=$(cat "$d/comm" 2>/dev/null) || continue
    case "$c" in
        WebKit*|webkit*|surf)
            pid=${d#/proc/}
            # `?`, not 0, when the fd directory cannot be read: a failed ls and a
            # process holding no DRM fd both produce an empty grep -c of 0, and
            # those are "could not tell" and "the subject is broken" -- different
            # answers that must not share a code.
            if fds=$(ls -l "$d/fd" 2>/dev/null); then
                dri=$(printf '%s\n' "$fds" | grep -c '/dev/dri/')
            else
                dri="?"
            fi
            if [ -r "$d/maps" ]; then
                drv=$(grep -oE '[a-z0-9_]+_dri\.so' "$d/maps" 2>/dev/null | sort -u | tr '\n' ' ')
                drv=${drv:-none}
            else
                drv="?"
            fi
            echo "proc $c pid=$pid drifd=$dri drv=$drv"
            ;;
    esac
done
grep -E '^Cma(Total|Free):' /proc/meminfo 2>/dev/null | sed 's/^/mem /'
[ -e /sys/class/drm/card0 ] && echo "drm card0 present" || echo "drm card0 absent"
REMOTE
)
rc=$?
[ $rc -eq 0 ] || { echo "cannot read $HOST: ssh exited $rc" >&2; exit 2; }

printf '%s\n' "$PROBE" | sed 's/^/  /'

gpu_verdict "$PROBE"
exit $?
