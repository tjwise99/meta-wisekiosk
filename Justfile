# Kiosk build and deployment commands
#
# Convenience commands for building the kiosk image, managing RAUC OTA updates,
# and deploying to the device.
#
# Quick start:
#   just build              # Build the image (kas fetches sources/ on first run)
#   just kiosk-ota          # Build a bundle and install it on the device
#   just flash /dev/sdX     # Flash to SD card
#   just rauc-status <ip>   # Check device RAUC status

set dotenv-load := true

# Default machine target
machine := env('MACHINE', 'raspberrypi0-wifi')

# Kas configuration
config := env('KAS_CONFIG', 'kiosk-zero-w.yaml')

# Image name for flash recipe
image-name := "core-image-base"

# The device every host-defaulting recipe talks to, in ssh target form. This is
# a hardware-in-the-loop unit and boards get swapped, so the address is the one
# thing here guaranteed to go stale -- it is defined once and overridden by the
# environment (`export KIOSK_HOST=root@<addr>`) rather than edited per recipe.
# `just find <cidr>` is how you learn the address of a board you just swapped in.
kiosk-host := env('KIOSK_HOST', 'root@192.168.1.6')

# === RAUC Configuration ===

# Directory for RAUC bundles
rauc-bundle-dir := "build/bundles"

# Development signing keys, used by the casync recipes in ota.just (override
# RAUC_CERT, RAUC_KEY, RAUC_KEYRING for production). They are upstream's own
# example keys and live in the meta-autonomos checkout, so these paths exist
# only after `kas-container checkout kiosk-zero-w.yaml` has populated sources/.
rauc-cert := env('RAUC_CERT', 'sources/meta-autonomos/meta-autonomos-core/files/rauc-example-keys/development.cert.pem')
rauc-key := env('RAUC_KEY', 'sources/meta-autonomos/meta-autonomos-core/files/rauc-example-keys/development.key.pem')
rauc-keyring := env('RAUC_KEYRING', 'sources/meta-autonomos/meta-autonomos-core/files/rauc-example-keys/development.cert.pem')

# Import shared recipes
import 'justfiles/ota.just'
import 'justfiles/deploy.just'
import 'justfiles/device.just'
import 'justfiles/rotate.just'

default: help

# Print this help message
help:
    @just --list

# === Build ===

# Build the kiosk image using kas-container
[group('build')]
build:
    kas-container build {{config}}

# Open a shell in the build environment
[group('build')]
shell:
    kas-container shell {{config}}

# === Clean ===

# Clean the build environment
[group('clean')]
clean:
    kas-container purge {{config}}

# Remove all build artifacts, sources, and start fresh
[group('clean')]
spotless: clean
    rm -rf build/
    rm -rf sources/

# === Repository guards ===

# Run the same checks CI runs. Fast, needs no build.
[group('guards')]
[doc("Run repository guards: secrets, template, shell syntax, YAML, gitleaks")]
guards:
    tools/ci-guards.sh

# Point git at .githooks so pre-commit runs the guards. Hooks are not carried by
# a clone, so this is per-checkout and has to be run once by hand.
[group('guards')]
[doc("Install the pre-commit hook for this checkout")]
install-hooks:
    git config core.hooksPath .githooks
    @echo "core.hooksPath -> .githooks (pre-commit runs tools/ci-guards.sh)"

# === Documentation checks ===

# Both checks run even when the first fails: two independent findings are worth
# more than the first one twice.
[group('check')]
[script('bash')]
[doc("Run every documentation check")]
verify:
    rc=0
    python3 tools/doc-links.py || rc=1
    python3 tools/doc-image.py check || rc=1
    if [ $rc -ne 0 ]; then echo; echo "verify FAILED"; fi
    exit $rc

# Cross-references in every tracked Markdown file: [text](path), #anchors, and
# section-name refs must resolve.
[group('check')]
[doc("Check that every tracked Markdown cross-reference resolves")]
links:
    python3 tools/doc-links.py

# What the prose says the image ships, against what it ships. Needs a populated
# build/ rootfs and is therefore local-only -- CI never builds, so wiring it
# into a required check would mean a permanently skipping gate.
[group('check')]
[doc("Check docs against what the built image ships (skips if unbuilt)")]
image:
    python3 tools/doc-image.py check

# Write per-site config to a device's /data. The image carries none of it.
[group('provision')]
[doc("Provision a reachable device's /data from secrets.yaml")]
provision-device host=kiosk-host:
    tools/provision.sh device {{host}}

# Before first boot: the wifi credentials are what let you reach the device, so
# the first write cannot come over the network.
[group('provision')]
[doc("Provision a mounted /data partition on a fresh card")]
provision-card mountpoint:
    tools/provision.sh card {{mountpoint}}
