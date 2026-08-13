SUMMARY = "Kiosk session: bare Xorg, no window manager, surf under systemd"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://kiosk.service file://kiosk-launch"
# scarthgap unpacks file:// SRC_URI straight into WORKDIR; the
# UNPACKDIR/sources layout is a later-release convention.
S = "${WORKDIR}"

inherit systemd

RDEPENDS:${PN} = "surf xinit xserver-xorg xserver-xorg-module-exa"

SYSTEMD_SERVICE:${PN} = "kiosk.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/kiosk-launch ${D}${bindir}/kiosk-launch

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/kiosk.service ${D}${systemd_system_unitdir}/kiosk.service

    # No /etc/kiosk.conf is generated. KIOSK_URL is site configuration and the
    # image must not carry it; kiosk.service reads /data/config/kiosk.conf,
    # written by provisioning.
}

FILES:${PN} += "${systemd_system_unitdir}/kiosk.service"
