SUMMARY = "Persistent journal on /data, across A/B updates"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://99-kiosk-journal.conf file://persistent.conf file://kiosk-journal-flush.service"
# scarthgap unpacks file:// SRC_URI straight into WORKDIR; the
# UNPACKDIR/sources layout is a later-release convention.
S = "${WORKDIR}"

inherit systemd

# Deliberately does NOT set VOLATILE_LOG_DIR. That variable is read by
# systemd's do_install, so changing it re-hashes systemd, gtk+3, at-spi2-core
# and then webkitgtk3 -- a multi-hour WebKit rebuild for a symlink. It also puts
# the journal on the rootfs slot, which an A/B update replaces wholesale.
SYSTEMD_SERVICE:${PN} = "kiosk-journal-flush.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/99-kiosk-journal.conf ${D}${nonarch_libdir}/tmpfiles.d/

    install -d ${D}${sysconfdir}/systemd/journald.conf.d
    install -m 0644 ${WORKDIR}/persistent.conf ${D}${sysconfdir}/systemd/journald.conf.d/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/kiosk-journal-flush.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${nonarch_libdir}/tmpfiles.d ${sysconfdir}/systemd/journald.conf.d ${systemd_system_unitdir}/kiosk-journal-flush.service"
