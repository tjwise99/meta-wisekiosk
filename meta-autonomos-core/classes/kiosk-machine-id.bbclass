# Pin /etc/machine-id in the image.
#
# systemd ships /etc/machine-id EMPTY and populates it on the first boot of each
# rootfs slot. Under A/B that means every OTA mints a new identity, journald
# opens a fresh /var/log/journal/<machine-id> and abandons the previous one.
# Observed 2026-08-13: four namespaces totalling 136.6MB on a 479MB /data that
# also stages the ~130MB update bundle -- two more updates would have broken
# delivery outright. SystemMaxUse is enforced PER machine-id, so it never bounds
# the total across orphans.
#
# It also resets `journalctl --list-boots` on every update, so cross-boot
# comparison -- which every boot measurement in this project rests on -- does not
# survive an OTA.
#
# Why here and not somewhere more obvious:
#
#   * Not a /data bind mount (the shape data-machine-id.service uses). journald
#     starts at 8.2s and caches the machine-id immediately; /data is not mounted
#     and sysinit.target is nowhere near. A mount at sysinit is far too late to
#     change which journal directory this boot opens.
#   * Not a recipe shipping the file. The path is already owned by a package, so
#     a second one installing it is a do_rootfs conflict.
#   * Not a systemd bbappend. Touching systemd's do_install re-hashes
#     systemd -> gtk+3/at-spi2-core -> webkitgtk3, a multi-hour WebKit rebuild
#     for 33 bytes.
#
# SINGLE-DEVICE IMAGE. Every unit flashed from this image gets the SAME
# machine-id -- correct for this one kiosk, wrong for a fleet: systemd derives
# the networkd DUID from it, so two units on one LAN would collide. If a second
# unit is ever built from this image, this has to become per-device.

KIOSK_MACHINE_ID ??= ""

kiosk_set_machine_id() {
    if [ -z "${KIOSK_MACHINE_ID}" ]; then
        bbfatal "kiosk-machine-id inherited but KIOSK_MACHINE_ID is unset"
    fi
    echo "${KIOSK_MACHINE_ID}" > ${IMAGE_ROOTFS}${sysconfdir}/machine-id
    chmod 0644 ${IMAGE_ROOTFS}${sysconfdir}/machine-id
}

ROOTFS_POSTPROCESS_COMMAND += "kiosk_set_machine_id;"
