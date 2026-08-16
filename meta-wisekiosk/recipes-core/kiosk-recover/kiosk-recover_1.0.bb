SUMMARY = "Recovery script that reverses kiosk-hardware's boot trims -- placed on /data, not the rootfs"
DESCRIPTION = "kiosk-recover turns the locked-down kiosk back into an interactively-debuggable Linux \
box: it unmasks the DNS resolver, login/session and userdb units kiosk-hardware masks, deletes the \
masked udev rule symlinks, re-enables Bluetooth input, restores the /etc/resolv.conf symlink into \
/data, and reboots. It is NOT a boot un-bricker -- it runs on a slot that already reaches a shell. \
\
It runs only when a human runs it: no timer, no deadman, no auto-revert, because this recovery \
machinery is itself an untested change. It does not touch /boot, sshd, networkd or wpa_supplicant, \
and it deliberately leaves zram.service masked (issue #17: unmasking restores a unit that fails \
every boot and sizes swap at 90% of RAM). \
\
This recipe is the tree home and single source of truth for the script. It is DELIBERATELY installed \
into no image: the script is placed on /data by tools/provision.sh, because /data survives an A/B \
flip and a reflash and is present regardless of which image version booted -- a per-slot rootfs \
install is not. Because it ships no service and is in no IMAGE_INSTALL, ci-guards.sh guard 7 (auto- \
enabled service reachability) cannot see it; guard 8 checks the /data placement path instead."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://kiosk-recover"
S = "${WORKDIR}"

# No do_install and no IMAGE_INSTALL on purpose (see DESCRIPTION): delivery is
# tools/provision.sh -> /data/RECOVER.sh, not a rootfs package. This recipe
# exists so the script has a versioned home under the layer and is linted by
# ci-guards.sh guard 3 like every other shipped script.
do_install() {
    :
}
