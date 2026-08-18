#!/bin/bash
# Generate a per-project RAUC signing key + self-signed certificate under the
# gitignored local/keys/<name>: inside the working tree, because that tree is
# what kas-container mounts and the build must read the key, but never
# committed. The certificate becomes the device keyring (what RAUC trusts); the
# key signs update bundles. Rotating means generating a fresh pair here and
# driving it onto the devices with 'just rotate-run' -- never committing either.
#
# Usage: rauc-keygen.sh <outdir> [common-name]
#   outdir  - directory to create the pair in (refused if it already holds one)
#   common-name - certificate CN (default derived from the outdir basename)
set -euo pipefail

OUTDIR=${1:?usage: rauc-keygen.sh <outdir> [common-name]}
CN=${2:-"WiseKiosk Signing $(basename "$OUTDIR")"}

KEY="$OUTDIR/signing.key.pem"
CERT="$OUTDIR/signing.cert.pem"

# Never clobber an existing pair: overwriting a key that a fielded device already
# trusts strands that device. Rotation always writes a NEW directory.
if [ -e "$KEY" ] || [ -e "$CERT" ]; then
    echo "refusing to overwrite existing key material in $OUTDIR" >&2
    echo "  ($KEY / $CERT) -- rotate into a fresh directory instead" >&2
    exit 1
fi

mkdir -p "$OUTDIR"
chmod 700 "$OUTDIR"

# 4096-bit RSA, self-signed, 10-year validity -- matches the retired dev cert's
# shape so nothing downstream (rauc, the keyring recipe) sees a different family.
# These boards have no RTC and boot in the past; the rotation always sets the
# device clock from the host before installing, so notBefore=now is safe, but
# the 10-year window leaves ample margin either way.
openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "$KEY" -out "$CERT" \
    -days 3650 -sha256 \
    -subj "/CN=$CN/O=WiseKiosk/C=US" >/dev/null 2>&1

chmod 600 "$KEY"
chmod 644 "$CERT"

FP=$(openssl x509 -in "$CERT" -noout -fingerprint -sha256 | sed 's/.*=//')
echo "generated RAUC signing pair:"
echo "  key  : $KEY"
echo "  cert : $CERT"
echo "  CN   : $CN"
echo "  sha256 fingerprint: $FP"
