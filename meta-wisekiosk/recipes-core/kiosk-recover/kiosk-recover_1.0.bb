SUMMARY = "Recovery script that reverses kiosk-hardware's boot trims; placed on /data by provisioning"
DESCRIPTION = "kiosk-recover unmasks the resolver, login/session and userdb units, deletes the masked \
udev symlinks, re-enables Bluetooth, restores the /etc/resolv.conf symlink, and reboots -- turning \
the locked-down kiosk back into a debuggable box. Not a boot un-bricker. Placed on /data by \
tools/provision.sh, not installed into any image (see do_install)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://kiosk-recover"
S = "${WORKDIR}"

# No do_install / no IMAGE_INSTALL on purpose: delivery is tools/provision.sh ->
# /data/RECOVER.sh (survives an A/B flip and reflash), not a rootfs package.
# Ships no service, so guard 7 can't police it; guard 8 checks the /data path.
# The recipe gives the script a versioned home and guard-3 lint.
do_install() {
    :
}
