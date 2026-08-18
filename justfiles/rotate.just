# RAUC signing-key rotation.
#
# Replaces the key the devices trust with a fresh per-project key, without a
# window in which a device can no longer verify an update. The full flow:
#
#   just rotate-keygen [name]                # new key, gitignored, never committed
#   just rotate-build [name]                 # transition + end-state bundles
#   just rotate-provision-ssh root@<hitl>    # once, if key auth is not set up
#   just rotate-run root@<hitl> [name]       # PROVE it on the HITL board first
#   just rotate-verify root@<hitl> [name] --empirical build/rotation/transition.raucb build/rotation/new-signed.raucb
#   just rotate-run root@<prod> [name]       # only then the prod board
#
# Why the order matters is written up in docs/rauc-key-rotation.md.
#
# `name` selects a dir under local/keys, which is gitignored -- the key is never
# committed, but it must live inside the project tree because that tree is what
# kas-container mounts, and kiosk-zero-w.yaml reads the fleet key from there to
# sign every ordinary build. Generating a key anywhere else leaves the build
# unable to find one. justfile_directory() keeps this absolute, so the recipes
# work from any cwd.
#
# The key NAME comes from `fleet-key` in the root Justfile. Completing a rotation
# means updating that and kiosk-zero-w.yaml -- see "Rotating to a new key" in
# docs/rauc-key-rotation.md.

keys-root := justfile_directory() / "local/keys"

# Generate a fresh signing key + self-signed cert. Never overwrites an existing
# pair -- rotation always makes a NEW one.
[group('rotate')]
[doc("Generate a new RAUC signing key (gitignored, never committed)")]
rotate-keygen name=fleet-key:
    tools/rauc-keygen.sh "{{keys-root}}/{{name}}" "WiseKiosk Signing Key {{name}}"

# Install this host's SSH pubkey on a device so the OTA recipes' key auth works
# without relying on the debug-tweaks empty-root-password path.
[group('rotate')]
[doc("Install this host's SSH pubkey on a device")]
rotate-provision-ssh host=kiosk-host:
    tools/rauc-provision-ssh.sh "{{host}}"

# Build the transition (old-signed) and end-state (new-signed) bundles from the
# named key. Incremental on a warm build tree.
#
# `name` is the NEW key, so it must be named explicitly: the default is the key
# the fleet already trusts, and rotating a key to itself is refused rather than
# quietly producing two identically-signed bundles and a meaningless
# "transition". OLD_KEYDIR is passed from fleet-key so the old signer is not a
# second literal that can drift.
[group('rotate')]
[doc("Build the transition and end-state bundles for a rotation")]
rotate-build name=fleet-key:
    OLD_KEYDIR="{{keys-root}}/{{fleet-key}}" tools/rauc-rotate-build.sh "{{keys-root}}/{{name}}" {{config}}

# Rotate the signing key on ONE device over SSH. Pass --one-slot to stop after
# the first slot. Always name the host explicitly -- there is no safe default.
[group('rotate')]
[doc("Rotate the signing key on one device (transition then end-state)")]
rotate-run host name=fleet-key *flags:
    tools/rauc-rotate.sh "{{host}}" "{{keys-root}}/{{name}}" {{flags}}

# Check a device trusts the new key. Add: --empirical <old.raucb> <new.raucb>
# to also prove old-signed bundles are rejected and new-signed accepted.
[group('rotate')]
[doc("Verify a device trusts the new key (--empirical for the bundle test)")]
rotate-verify host name=fleet-key *flags:
    tools/rauc-rotate-verify.sh "{{host}}" "{{keys-root}}/{{name}}/signing.cert.pem" {{flags}}
