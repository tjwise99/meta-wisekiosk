# RAUC signing-key rotation.
#
# Replaces the key the devices trust with a fresh per-project key, without a
# window in which a device can no longer verify an update. The full flow:
#
#   just rotate-keygen [name]                # new key, kept OUTSIDE the repo
#   just rotate-build [name]                 # transition + end-state bundles
#   just rotate-provision-ssh root@<hitl>    # once, if key auth is not set up
#   just rotate-run root@<hitl> [name]       # PROVE it on the HITL board first
#   just rotate-verify root@<hitl> [name] --empirical build/rotation/transition.raucb build/rotation/new-signed.raucb
#   just rotate-run root@<prod> [name]       # only then the prod board
#
# Why the order matters is written up in docs/rauc-key-rotation.md.
# The signing key never enters the repo; `name` selects a dir under
# ~/.config/wisekiosk/keys.

keys-root := env('HOME') / ".config/wisekiosk/keys"

# Generate a fresh signing key + self-signed cert. Never overwrites an existing
# pair -- rotation always makes a NEW one.
[group('rotate')]
[doc("Generate a new RAUC signing key (kept out of the repo)")]
rotate-keygen name="kiosk-2026":
    tools/rauc-keygen.sh "{{keys-root}}/{{name}}" "WiseKiosk Signing Key {{name}}"

# Install this host's SSH pubkey on a device so the OTA recipes' key auth works
# without relying on the debug-tweaks empty-root-password path.
[group('rotate')]
[doc("Install this host's SSH pubkey on a device")]
rotate-provision-ssh host=kiosk-host:
    tools/rauc-provision-ssh.sh "{{host}}"

# Build the transition (old-signed) and end-state (new-signed) bundles from the
# named key. Incremental on a warm build tree.
[group('rotate')]
[doc("Build the transition and end-state bundles for a rotation")]
rotate-build name="kiosk-2026":
    tools/rauc-rotate-build.sh "{{keys-root}}/{{name}}" {{config}}

# Rotate the signing key on ONE device over SSH. Pass --one-slot to stop after
# the first slot. Always name the host explicitly -- there is no safe default.
[group('rotate')]
[doc("Rotate the signing key on one device (transition then end-state)")]
rotate-run host name="kiosk-2026" *flags:
    tools/rauc-rotate.sh "{{host}}" "{{keys-root}}/{{name}}" {{flags}}

# Check a device trusts the new key. Add: --empirical <old.raucb> <new.raucb>
# to also prove old-signed bundles are rejected and new-signed accepted.
[group('rotate')]
[doc("Verify a device trusts the new key (--empirical for the bundle test)")]
rotate-verify host name="kiosk-2026" *flags:
    tools/rauc-rotate-verify.sh "{{host}}" "{{keys-root}}/{{name}}/signing.cert.pem" {{flags}}
