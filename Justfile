# AutonomOS Build and Deployment Commands
#
# This Justfile provides convenience commands for building AutonomOS images,
# managing RAUC OTA updates, and deploying to devices.
#
# Quick start:
#   just build              # Build the image
#   just flash /dev/sdX     # Flash to SD card
#   just rauc-status <ip>   # Check device RAUC status

set dotenv-load := true

# Default machine target
machine := env('MACHINE', 'raspberrypi5')

# Kas configuration
config := env('KAS_CONFIG', 'reference.yaml')

# Image name for flash recipe
image-name := "autonomos-devel"

# === RAUC Configuration ===

# Directory for RAUC bundles
rauc-bundle-dir := "build/bundles"

# Development signing keys (override RAUC_CERT, RAUC_KEY, RAUC_KEYRING for production)
rauc-cert := env('RAUC_CERT', 'meta-autonomos-core/files/rauc-example-keys/development.cert.pem')
rauc-key := env('RAUC_KEY', 'meta-autonomos-core/files/rauc-example-keys/development.key.pem')
rauc-keyring := env('RAUC_KEYRING', 'meta-autonomos-core/files/rauc-example-keys/development.cert.pem')

# Import shared recipes
import 'justfiles/ota.just'
import 'justfiles/deploy.just'
import 'justfiles/device.just'

default: help

# Print this help message
help:
    @just --list

# === Build ===

# Build the AutonomOS image using kas-container
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

# Write per-site config to a device's /data. The image carries none of it.
[group('provision')]
[doc("Provision a reachable device's /data from secrets.yaml")]
provision-device host="root@192.168.1.6":
    tools/provision.sh device {{host}}

# Before first boot: the wifi credentials are what let you reach the device, so
# the first write cannot come over the network.
[group('provision')]
[doc("Provision a mounted /data partition on a fresh card")]
provision-card mountpoint:
    tools/provision.sh card {{mountpoint}}
