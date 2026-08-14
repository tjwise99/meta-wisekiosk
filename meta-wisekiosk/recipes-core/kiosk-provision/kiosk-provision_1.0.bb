SUMMARY = "Apply per-site configuration from /data over the image defaults"
DESCRIPTION = "Every site value -- SSID, PSK hash, kiosk URL, hostname, nameserver -- is \
substituted into the rootfs at build time, so one image serves exactly one site. That blocks \
a shared fleet artifact and puts the site's wireless credentials inside every bundle. \
\
This applies /data/config over those values at boot. It is deliberately non-breaking: a value \
is overridden only if /data/config supplies it, so a device with no /data/config behaves \
exactly as before. Removing the baked values is a separate step and must not happen until \
provisioning is proven on hardware. \
\
machine-id is NOT handled here and cannot be: journald reads it at ~8.2s, before /data is \
mounted. It needs a RAUC post-install hook writing into the freshly-written slot."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://kiosk-provision file://kiosk-provision.service"
S = "${WORKDIR}"

inherit systemd
SYSTEMD_SERVICE:${PN} = "kiosk-provision.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/kiosk-provision ${D}${bindir}/
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/kiosk-provision.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${bindir}/kiosk-provision ${systemd_system_unitdir}/kiosk-provision.service"
