SUMMARY = "Cap CPU frequency below the Pi Zero W's unstable top OPP"
DESCRIPTION = "This board corrupts memory under sustained SDIO + network load at \
1000 MHz. Measured 2026-08-13: 2/2 deaths pinned at 1000 MHz and ~8 with the \
stock uncapped ondemand governor, against 8/8 survivals at every OPP below it. \
Capping scaling_max_freq at 900 MHz costs 10% of peak CPU and makes the kiosk \
stable. Shipped as a unit rather than as config.txt over_voltage because \
config.txt lives on the shared FAT partition and can never be delivered by OTA."
LICENSE = "CLOSED"

SRC_URI = "file://kiosk-cpufreq-cap.service"

inherit systemd
SYSTEMD_SERVICE:${PN} = "kiosk-cpufreq-cap.service"
SYSTEMD_AUTO_ENABLE = "enable"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/kiosk-cpufreq-cap.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "${systemd_system_unitdir}/kiosk-cpufreq-cap.service"
