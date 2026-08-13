# Carry the device's machine-id into each freshly written slot. See
# files/kiosk-slot-hook.sh for why this cannot be done at boot: journald reads
# /etc/machine-id at ~8.2s, before /data is mounted, so the value must already
# be in the slot's rootfs.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://kiosk-slot-hook.sh"

RAUC_BUNDLE_HOOKS[file] = "kiosk-slot-hook.sh"
RAUC_SLOT_rootfs[hooks] = "post-install"
