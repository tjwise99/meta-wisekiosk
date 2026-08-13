# AutonomOS RAUC Update Bundle
# Generates a signed RAUC bundle containing the rootfs image
#
# Build with: bitbake update-bundle
# Output: tmp-<machine>/deploy/images/<machine>/update-bundle-<machine>.raucb
#
# To use custom signing keys, set in local.conf or kas yaml:
#   AUTONOMOS_RAUC_KEY_DIR = "/path/to/keys"
#   AUTONOMOS_RAUC_KEY_FILE = "signing.key.pem"
#   AUTONOMOS_RAUC_CERT_FILE = "signing.cert.pem"

# Required since the bundle gained a SRC_URI (the RAUC slot-post-install hook):
# insane.bbclass fails do_populate_lic for any recipe that fetches files without
# LIC_FILES_CHKSUM, and returns early only for CLOSED. This recipe produces an
# internal artefact, so CLOSED is the accurate declaration rather than a silencer.
LICENSE = "CLOSED"

inherit bundle autonomos-rauc

RAUC_BUNDLE_COMPATIBLE = "${AUTONOMOS_RAUC_COMPATIBLE}"
RAUC_BUNDLE_VERSION = "${DISTRO_VERSION}"
RAUC_BUNDLE_DESCRIPTION = "AutonomOS Update Bundle"
RAUC_BUNDLE_FORMAT = "verity"

RAUC_BUNDLE_SLOTS = "rootfs"
RAUC_SLOT_rootfs = "autonomos-devel"
RAUC_SLOT_rootfs[fstype] = "ext4"

# Signing keys - use project-configured keys or default development keys
RAUC_KEY_FILE = "${@d.getVar('AUTONOMOS_RAUC_KEY_DIR') + '/' + d.getVar('AUTONOMOS_RAUC_KEY_FILE') if d.getVar('AUTONOMOS_RAUC_KEY_DIR') else d.getVar('THISDIR') + '/../../files/rauc-example-keys/' + d.getVar('AUTONOMOS_RAUC_KEY_FILE')}"
RAUC_CERT_FILE = "${@d.getVar('AUTONOMOS_RAUC_KEY_DIR') + '/' + d.getVar('AUTONOMOS_RAUC_CERT_FILE') if d.getVar('AUTONOMOS_RAUC_KEY_DIR') else d.getVar('THISDIR') + '/../../files/rauc-example-keys/' + d.getVar('AUTONOMOS_RAUC_CERT_FILE')}"
RAUC_KEYRING_FILE = "${@d.getVar('AUTONOMOS_RAUC_KEY_DIR') + '/' + d.getVar('AUTONOMOS_RAUC_KEYRING_FILE') if d.getVar('AUTONOMOS_RAUC_KEY_DIR') else d.getVar('THISDIR') + '/../../files/rauc-example-keys/' + d.getVar('AUTONOMOS_RAUC_KEYRING_FILE')}"

# Generate casync bundle with chunk store for delta updates
RAUC_CASYNC_BUNDLE = "1"
