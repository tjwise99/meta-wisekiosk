# Carry the device's machine-id into each freshly written slot. See
# files/kiosk-slot-hook.sh for why this cannot be done at boot: journald reads
# /etc/machine-id at ~8.2s, before /data is mounted, so the value must already
# be in the slot's rootfs.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://kiosk-slot-hook.sh"

# Required by the SRC_URI above: insane.bbclass fails do_populate_lic for any
# recipe that fetches files without LIC_FILES_CHKSUM, and returns early only for
# CLOSED. The bundle is an internal artefact, so CLOSED is the accurate
# declaration rather than a silencer. It lives here, with the SRC_URI that
# provokes the check, instead of in upstream's update-bundle.bb.
LICENSE = "CLOSED"

RAUC_BUNDLE_HOOKS[file] = "kiosk-slot-hook.sh"
RAUC_SLOT_rootfs[hooks] = "post-install"
