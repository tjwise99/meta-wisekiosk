#!/usr/bin/env bash
# One SSH connection, reused, for a debugging session made of small commands.
#
#   tools/kiosk-ssh.sh root@<host> 'uptime -p'
#   tools/kiosk-ssh.sh root@<host> 'bash -s' <<'EOF'   # a script, still one round trip
#   systemctl is-active kiosk
#   cut -d' ' -f1 /proc/loadavg
#   EOF
#   tools/kiosk-ssh.sh root@<host> --close             # drop the master early
#
# The key exchange is not free here: it runs on the same saturated 1GHz ARM11
# core the browser renders on, so per-command handshake cost is kiosk load, not
# just operator latency. Multiplexing pays that once. Nothing is installed on
# the device -- the master lives on this host -- so it cannot touch the lifeline.
#
# Batch anyway: one `bash -s` heredoc beats ten calls even over a warm master.
#
# Three things bite:
#
#   * The control socket path caps at ~108 characters, and a path over the cap
#     fails with `too long for Unix domain socket` on EVERY call including the
#     first, which reads as a connection failure rather than a path problem.
#     %C is a hash of (local host, remote host, port, user), so that half is
#     fixed-length no matter what the target is called. The whole path is
#     "$HOME/.ssh/kiosk-%C", so $HOME is the one variable component and the
#     only way back over the cap -- fine on any ordinary home directory, and
#     the thing to look at first if the cap is ever hit.
#
#   * Do not add LogLevel=ERROR to silence the post-quantum banner on cold
#     connect. The banner is expected noise from this EOL sshd; suppressing it
#     suppresses genuine connection errors with it -- the same mistake as
#     2>/dev/null on a probe, which turns a broken check into something
#     indistinguishable from a broken kiosk.
#
#   * A master orphaned by a device reboot is the expected stale case.
#     ServerAliveInterval/CountMax bound it at ~60s instead of hanging forever.
#     This path is reasoned, not measured. If commands stop answering after a
#     reboot, run --close before diagnosing anything else.
#
# A backgrounded SSH command often exits 1 even when the work succeeded, so
# verify by querying state afterwards, never by the exit code.
set -uo pipefail

HOST=${1:?usage: kiosk-ssh.sh <ssh-target> <command> | <ssh-target> --close}
shift

CONTROL="$HOME/.ssh/kiosk-%C"

ssh_opts=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10
    -o ControlMaster=auto
    -o ControlPath="$CONTROL"
    -o ControlPersist=30m
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=4
)

if [ "${1:-}" = "--close" ]; then
    # -O exit against no master is not an error worth failing on: the desired
    # state is "no master", and that is already true.
    ssh "${ssh_opts[@]}" -O exit "$HOST" 2>&1 | grep -v 'No such file or directory' || true
    exit 0
fi

[ "$#" -gt 0 ] || { echo "usage: kiosk-ssh.sh <ssh-target> <command>" >&2; exit 2; }

exec ssh "${ssh_opts[@]}" "$HOST" "$@"
