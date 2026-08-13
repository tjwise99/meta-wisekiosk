SUMMARY = "Kiosk soak sampler: one key=value line into /data every 5 minutes"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://kiosk-soak.sh file://kiosk-soak.service file://kiosk-soak.timer"
# scarthgap unpacks file:// SRC_URI straight into WORKDIR; the
# UNPACKDIR/sources layout is a later-release convention.
S = "${WORKDIR}"

inherit systemd

# busybox supplies every tool the sampler calls; vcgencmd comes from the
# firmware package that is already in the image.
RDEPENDS:${PN} = "busybox"

# Only the timer carries an [Install] section. Enabling the oneshot service
# alongside it would fail, and the timer is what pulls the service in.
SYSTEMD_SERVICE:${PN} = "kiosk-soak.timer"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/kiosk-soak.sh ${D}${bindir}/kiosk-soak.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/kiosk-soak.service ${D}${systemd_system_unitdir}/kiosk-soak.service
    install -m 0644 ${WORKDIR}/kiosk-soak.timer ${D}${systemd_system_unitdir}/kiosk-soak.timer
}

FILES:${PN} += "${systemd_system_unitdir}/kiosk-soak.service ${systemd_system_unitdir}/kiosk-soak.timer"
