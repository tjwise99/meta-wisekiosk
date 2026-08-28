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

# The device every host-defaulting recipe talks to, in ssh target form. The
# address is site-specific and this repo is PUBLIC, so it is never committed:
# there is no in-tree default. Set it in the environment
# (`export KIOSK_HOST=root@<addr>`) or a local .env, and `just find <cidr>`
# learns the address of a board you just swapped in. A recipe run without it
# fails on an empty host rather than targeting a stale one.
kiosk-host := env('KIOSK_HOST', '')

# === RAUC Configuration ===

# Directory for RAUC bundles
rauc-bundle-dir := "build/bundles"

# The key the fleet trusts. Single source for the just side (the `flash` keyring
# guard, the rotation recipes' old-key default). kiosk-zero-w.yaml repeats the
# name because bitbake cannot read a just variable -- the ONE site this cannot
# cover; docs/rauc-key-rotation.md lists both under "Rotating to a new key".
fleet-key := "kiosk-2026"

# Consumed ONLY by `rauc-to-casync` in ota.just, which is disabled
# (RAUC_CASYNC_BUNDLE = "0"; chunker removed with #29). NOT the fleet signing
# path -- that is kiosk-zero-w.yaml's AUTONOMOS_RAUC_*, pointed at the fleet-key
# dir under local/keys. These name upstream's retired example keys, which no
# device trusts, and exist only after `kas-container checkout` populates
# sources/. Reviving casync means repointing RAUC_CERT/RAUC_KEY/RAUC_KEYRING at
# the fleet key: a dev-key-signed bundle installs nowhere.
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
    tools/write-build-rev.sh
    kas-container build {{config}}

# Open a shell in the build environment
[group('build')]
shell:
    tools/write-build-rev.sh
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
#
# Both run even when the first fails, matching `verify` and the pre-commit hook:
# two independent findings are worth more than the first one twice.
[group('guards')]
[script('bash')]
[doc("Run repository guards: secrets, template, shell syntax, YAML, gitleaks, IPs, service reachability, recovery wiring, trailing-; hooks, guard wiring, guard self-test, review-checklist taxonomy, device identity")]
guards:
    rc=0
    tools/ci-guards.sh || rc=1
    tools/scrub-identity.py --check || rc=1
    if [ $rc -ne 0 ]; then echo; echo "guards FAILED"; fi
    exit $rc

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

# === Image audit ===

[group('audit')]
[doc("Report the CVE findings from the last audit build (skips if unbuilt)")]
cve:
    python3 tools/cve-report.py check

[group('audit')]
[doc("Report the SBOM the last build emitted (skips if unbuilt)")]
sbom:
    python3 tools/sbom-report.py check

[group('audit')]
[doc("Second-source findings the CVE manifest does not carry (skips if unbuilt)")]
cve-scan:
    python3 tools/cve-scan.py check

[group('audit')]
[doc("Report what changed in the CVE picture since the previous audit build (skips if <2)")]
cve-delta:
    python3 tools/cve-delta.py check

[group('audit')]
[doc("Build with cve-check inherited: CVE manifest beside the image, snapshot in ~/.cache/wisekiosk")]
cve-build:
    tools/write-build-rev.sh
    kas-container build {{config}}:includes/cve-audit.yaml
    python3 tools/cve-delta.py snapshot

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
