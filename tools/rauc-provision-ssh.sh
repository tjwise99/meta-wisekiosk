#!/bin/bash
# Install this host's SSH public key into a device's root authorized_keys so the
# OTA recipes (which use BatchMode=yes key auth) work without leaning on the
# debug-tweaks empty-root-password path. Idempotent.
#
# Usage: rauc-provision-ssh.sh root@<host>
#   SSH_PUBKEY overrides which public key is installed (default ~/.ssh/id_ed25519.pub)
set -euo pipefail

HOST=${1:?usage: rauc-provision-ssh.sh root@<host>}
PUB=${SSH_PUBKEY:-$HOME/.ssh/id_ed25519.pub}
test -f "$PUB" || { echo "no public key at $PUB (set SSH_PUBKEY)" >&2; exit 1; }
KEY=$(cat "$PUB")

# First contact may still ride the empty-password path; accept the host key once.
ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$HOST" "
    umask 077; mkdir -p /root/.ssh
    if grep -qxF '$KEY' /root/.ssh/authorized_keys 2>/dev/null; then
        echo 'key already present'
    else
        echo '$KEY' >> /root/.ssh/authorized_keys && echo 'key appended'
    fi"

echo "verifying key auth..."
ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 "$HOST" 'echo "key-auth OK: $(hostname)"'
