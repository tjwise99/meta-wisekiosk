#!/bin/bash
# Build the two RAUC bundles a signing-key rotation needs:
#   new-signed.raucb  - rootfs carrying the NEW keyring, signed with the NEW key.
#                       The end state; every slot ends up here.
#   transition.raucb  - the SAME rootfs (NEW keyring), signed with the OLD key,
#                       so a device still trusting the old key will accept it.
#
# A device verifies a bundle's signature against the keyring in its RUNNING slot,
# and trusts the next bundle against whatever keyring the last one baked in. So a
# device on the old key cannot accept a new-signed bundle directly; it accepts
# the old-signed transition bundle, boots the new keyring, and only then accepts
# new-signed bundles. rauc-rotate.sh drives that order.
#
# Both bundles bake the SAME (new) keyring, so the rootfs image is identical
# between the two builds and the second build only re-runs the signing step.
#
# Usage: rauc-rotate-build.sh <new-keydir> [kas-config]
#   new-keydir - dir holding signing.key.pem + signing.cert.pem (from rauc-keygen.sh)
set -euo pipefail

NEW_KEYDIR=${1:?usage: rauc-rotate-build.sh <new-keydir> [kas-config]}
KCONFIG=${2:-kiosk-zero-w.yaml}

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

OLD_KEY="sources/meta-autonomos/meta-autonomos-core/files/rauc-example-keys/development.key.pem"
OLD_CERT="sources/meta-autonomos/meta-autonomos-core/files/rauc-example-keys/development.cert.pem"

test -f "$NEW_KEYDIR/signing.key.pem"  || { echo "no signing.key.pem in $NEW_KEYDIR" >&2; exit 1; }
test -f "$NEW_KEYDIR/signing.cert.pem" || { echo "no signing.cert.pem in $NEW_KEYDIR" >&2; exit 1; }
test -f "$OLD_KEY"  || { echo "old dev key not found ($OLD_KEY) -- run kas checkout first" >&2; exit 1; }
test -f "$OLD_CERT" || { echo "old dev cert not found ($OLD_CERT)" >&2; exit 1; }

# kas-container only mounts the project tree, so a keydir under ~/.config is
# invisible to the build. Stage one inside build/ (gitignored, never a commit
# candidate) and reference it as ${TOPDIR}/... which resolves identically inside
# and outside the container regardless of the mount layout.
OUT="build/rotation"
STAGE="$OUT/keydir"
mkdir -p "$STAGE"
install -m600 "$NEW_KEYDIR/signing.key.pem"  "$STAGE/signing.key.pem"
install -m644 "$NEW_KEYDIR/signing.cert.pem" "$STAGE/signing.cert.pem"
install -m644 "$OLD_KEY"  "$STAGE/old.key.pem"
install -m644 "$OLD_CERT" "$STAGE/old.cert.pem"

HDR_VERSION=$(sed -n 's/^[[:space:]]*version:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$KCONFIG" | head -1)
: "${HDR_VERSION:=14}"

BUNDLE_LINK="build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/update-bundle-raspberrypi0-wifi.raucb"

# $1 out-file  $2 signing-key filename  $3 signing-cert filename. The keyring
# baked into the rootfs is always the NEW cert; only the signer differs.
gen_override() {
    cat > "$1" <<YAML
header:
  version: $HDR_VERSION
local_conf_header:
  rauc-rotation: |
    AUTONOMOS_RAUC_KEY_DIR = "\${TOPDIR}/rotation/keydir"
    AUTONOMOS_RAUC_KEY_FILE = "$2"
    AUTONOMOS_RAUC_CERT_FILE = "$3"
    AUTONOMOS_RAUC_KEYRING_FILE = "signing.cert.pem"
YAML
}

echo "== build A: end-state bundle (new keyring, NEW-signed)"
gen_override "$OUT/override-endstate.yaml" signing.key.pem signing.cert.pem
kas-container shell "$KCONFIG:$OUT/override-endstate.yaml" -c "bitbake update-bundle"
test -f "$BUNDLE_LINK" || { echo "build A produced no bundle at $BUNDLE_LINK" >&2; exit 1; }
cp -L "$BUNDLE_LINK" "$OUT/new-signed.raucb"

echo "== build B: transition bundle (new keyring, OLD-signed)"
gen_override "$OUT/override-transition.yaml" old.key.pem old.cert.pem
kas-container shell "$KCONFIG:$OUT/override-transition.yaml" -c "bitbake update-bundle"
test -f "$BUNDLE_LINK" || { echo "build B produced no bundle at $BUNDLE_LINK" >&2; exit 1; }
cp -L "$BUNDLE_LINK" "$OUT/transition.raucb"

# Verify the one property the on-device install gates cannot catch cheaply: the
# keyring BAKED into the rootfs (what the device trusts after installing either
# bundle) must be the NEW cert. If the kas override had silently failed to apply,
# the build would fall back to the dev keys and bake the OLD keyring -- caught
# here host-side, before a ~30-minute transfer/boot cycle discovers it. Signing
# correctness (transition=old, end-state=new) is verified by the `rauc info` gate
# inside kiosk-install at install time.
ROOTFS="build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/core-image-base-raspberrypi0-wifi.rootfs.ext4"
NEW_FP=$(openssl x509 -in "$STAGE/signing.cert.pem" -noout -fingerprint -sha256 | sed 's/.*=//')
if command -v debugfs >/dev/null 2>&1 && [ -f "$ROOTFS" ]; then
    BAKED_FP=$(debugfs -R "cat /etc/rauc/keyring.pem" "$ROOTFS" 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//')
    if [ "$BAKED_FP" = "$NEW_FP" ]; then
        echo "verified: rootfs keyring == new cert ($BAKED_FP)"
    else
        echo "FAIL: rootfs keyring is $BAKED_FP, expected new cert $NEW_FP" >&2
        echo "the key override did not apply -- do NOT deploy these bundles." >&2
        exit 1
    fi
else
    echo "note: debugfs unavailable or rootfs missing; skipping baked-keyring check"
    echo "      (the phase-1 fingerprint gate on-device still catches a wrong keyring)"
fi

echo
echo "built:"
echo "  $OUT/new-signed.raucb   (NEW-signed; the end state)"
echo "  $OUT/transition.raucb   (OLD-signed; install first on an old-key device)"
echo "next: just rotate-run root@<host> $(basename "$NEW_KEYDIR")"
