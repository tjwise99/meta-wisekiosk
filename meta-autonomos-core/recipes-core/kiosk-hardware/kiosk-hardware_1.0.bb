SUMMARY = "Kiosk hardware trim: keep unused subsystems out of the boot, and reboot on panic"
DESCRIPTION = "Drop-in configuration only -- no binaries, no services. Deliberately a \
separate recipe rather than a systemd_%.bbappend: touching the systemd recipe re-hashes \
systemd -> gtk+3/at-spi2-core -> webkitgtk3, which is a multi-hour WebKit rebuild for three \
config files. The same reasoning is why kiosk-journal exists."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://kiosk-blacklist.conf file://watchdog.conf file://60-kiosk-panic.conf"
# scarthgap unpacks file:// SRC_URI straight into WORKDIR.
S = "${WORKDIR}"

do_install() {
    # Camera, ISP, codec, audio and GPIO. Measured 2026-08-12: these load ahead
    # of brcmfmac in udev's queue, and wlan0 is the gate the whole boot waits on.
    install -d ${D}${sysconfdir}/modprobe.d
    install -m 0644 ${WORKDIR}/kiosk-blacklist.conf ${D}${sysconfdir}/modprobe.d/

    install -d ${D}${sysconfdir}/systemd/system.conf.d
    install -m 0644 ${WORKDIR}/watchdog.conf ${D}${sysconfdir}/systemd/system.conf.d/

    install -d ${D}${sysconfdir}/sysctl.d
    install -m 0644 ${WORKDIR}/60-kiosk-panic.conf ${D}${sysconfdir}/sysctl.d/

    # zram ships BOTH mechanisms for one job: zram_0.2.bb inherits update-rc.d
    # (/etc/init.d/zram, picked up by systemd-sysv-generator) and systemd
    # (zram-swap.service + dev-zram0.swap). The systemd path wins the race and
    # claims /dev/zram0; the SysV script then fails every boot with
    # "write error: Device or resource busy", burning 162ms to do it. Swap is
    # genuinely provided -- /dev/zram0, 208.8MB -- so masking costs no swap.
    # Masked rather than deleted from the package: removing the init script
    # would leave update-rc.d's postinst referring to a file that is not there.
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/zram.service

    # systemd-resolved answers zero queries here -- resolvectl reports Total
    # Transactions 0 on a normal boot. It costs ~729ms starting at 19.96s, before
    # the gate, to write one file. Masking it with a static /etc/resolv.conf
    # (kiosk-static-resolv.bbclass) measured -1.03s at basic.target, n=3, ranges
    # not overlapping. DNS still resolves; timesyncd is the only consumer.
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/systemd-resolved.service

    # udev evaluates every rule file against all 345 device uevents. This board
    # has no sound card (/sys/class/sound empty), no V4L (/sys/class/video4linux
    # absent), no DRM card, and only the aggregate 'mice' input node -- yet the
    # image still ships rules for cameras, joysticks, tape, MTD, CD-ROM,
    # InfiniBand, FIDO and btrfs. Masking these took the effective rule set from
    # 616 lines to 350 and udevd's CPU from 5091ms to 4513ms, measured n=3.
    #
    # A /dev/null symlink in /etc/udev/rules.d shadows the /usr/lib file of the
    # same name -- udev(7). Nothing under /usr/lib is modified, so this does not
    # re-hash systemd.
    #
    # NOT masked, deliberately: 71-seat, 73-seat-late and 70-uaccess (logind
    # seat/ACL handling that Xorg may want), 60-drm (display), 60-persistent-
    # storage and the net rules (SD card and lifeline).
    install -d ${D}${sysconfdir}/udev/rules.d
    for r in ${KIOSK_UDEV_RULES_MASKED}; do
        ln -sf /dev/null ${D}${sysconfdir}/udev/rules.d/$r.rules
    done
}

KIOSK_UDEV_RULES_MASKED = "\
    78-sound-card 60-persistent-alsa 60-persistent-v4l 70-camera \
    60-persistent-input 60-evdev 60-input-id 70-mouse 70-touchpad 70-joystick \
    90-libinput-fuzz-override 80-libinput-device-groups \
    60-persistent-storage-tape 60-persistent-storage-mtd 75-probe_mtd \
    60-cdrom_id 60-infiniband 60-fido-id 90-iocost 60-sensor 64-btrfs 75-casync \
"

FILES:${PN} = " \
    ${sysconfdir}/modprobe.d/kiosk-blacklist.conf \
    ${sysconfdir}/systemd/system.conf.d/watchdog.conf \
    ${sysconfdir}/sysctl.d/60-kiosk-panic.conf \
    ${sysconfdir}/systemd/system/zram.service \
    ${sysconfdir}/systemd/system/systemd-resolved.service \
    ${sysconfdir}/udev/rules.d \
"
