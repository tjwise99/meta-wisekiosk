#!/bin/bash
# Verify a device's trusted RAUC keyring, and optionally prove it empirically by
# feeding it signed bundles.
#
# The cheap check is deductive: the keyring is a single self-signed cert, and RAUC
# trusts exactly the certs in it, so "keyring == new cert" already means old-signed
# bundles are rejected. --empirical additionally exercises the real code path: an
# old-signed bundle must be REJECTED and a new-signed bundle ACCEPTED. It costs two
# bundle transfers, so it is meant for the HITL board, not every prod rotation.
#
# Usage: rauc-rotate-verify.sh <host> <new-cert> [--empirical <old-signed.raucb> <new-signed.raucb>]
set -euo pipefail

HOST=${1:?usage: rauc-rotate-verify.sh <host> <new-cert> [--empirical old.raucb new.raucb]}
NEW_CERT=${2:?need <new-cert> path}
shift 2

SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
SCP="scp -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

fp() { openssl x509 -in "$1" -noout -fingerprint -sha256 | sed 's/.*=//'; }
NEW_FP=$(fp "$NEW_CERT")
DEV_FP=$($SSH "$HOST" 'openssl x509 -in /etc/rauc/keyring.pem -noout -fingerprint -sha256' | sed 's/.*=//')
NCERTS=$($SSH "$HOST" 'grep -c "BEGIN CERTIFICATE" /etc/rauc/keyring.pem')

echo "device keyring fp : $DEV_FP"
echo "new cert fp       : $NEW_FP"
echo "certs in keyring  : $NCERTS"

rc=0
[ "$DEV_FP" = "$NEW_FP" ] || { echo "FAIL: device does not trust the new cert"; rc=1; }
[ "$NCERTS" = "1" ] || echo "NOTE: keyring holds $NCERTS certs (not a single-cert keyring)"

if [ "${1:-}" = "--empirical" ]; then
    OLD_B=${2:?--empirical needs <old-signed.raucb> <new-signed.raucb>}
    NEW_B=${3:?--empirical needs <old-signed.raucb> <new-signed.raucb>}
    test -f "$OLD_B" || { echo "no bundle at $OLD_B" >&2; exit 2; }
    test -f "$NEW_B" || { echo "no bundle at $NEW_B" >&2; exit 2; }

    # RTC-less board: pin the clock from the host so cert validity is never the
    # reason a signature check passes or fails.
    $SSH "$HOST" "date -u -s '$(date -u '+%Y-%m-%d %H:%M:%S')'" >/dev/null

    echo "== empirical negative: an OLD-signed bundle must be REJECTED"
    $SCP "$OLD_B" "$HOST:/data/verify.raucb" >/dev/null
    if OUT=$($SSH "$HOST" 'rauc info /data/verify.raucb' 2>&1); then
        echo "FAIL: device ACCEPTED an old-signed bundle -- the old key is still trusted"; rc=1
    elif [ "$(printf '%s' "$OUT" | grep -ciE 'signature|verif|not trusted|unknown ca|certificate')" -gt 0 ]; then
        echo "  ok: old-signed bundle rejected for a signature/trust reason"
    else
        echo "FAIL: old-signed bundle failed, but NOT for a signature reason -- inconclusive:"; echo "$OUT" | sed 's/^/    /'; rc=1
    fi

    echo "== empirical positive: a NEW-signed bundle must be ACCEPTED"
    $SCP "$NEW_B" "$HOST:/data/verify.raucb" >/dev/null
    if $SSH "$HOST" 'rauc info /data/verify.raucb' >/dev/null 2>&1; then
        echo "  ok: new-signed bundle accepted"
    else
        echo "FAIL: device REJECTED the new-signed bundle"; rc=1
    fi
    $SSH "$HOST" 'rm -f /data/verify.raucb'
fi

if [ $rc -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit $rc
