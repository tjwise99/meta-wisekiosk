# bootdelay=0 -- U-Boot's 2-second pause before it boots.
#
# This is the "2s splash" and it is invisible to every measurement this project
# has taken: /proc/uptime and the journal both start at kernel entry, so the
# whole boot profile is blind to it. Confirmed on the device with
# `fw_printenv bootdelay` (owner, 2026-08-12).
#
# rpi_0_w_defconfig does not set CONFIG_BOOTDELAY, so U-Boot's Kconfig default
# of 2 applies -- verified in the generated .config, line 391: CONFIG_BOOTDELAY=2.
#
# WHY THIS ONLY WORKS ON A REFLASH: no uboot.env is built or deployed. The env
# is created on the device at first boot by boot.cmd.in --
#   if test ! -e mmc 0:1 uboot.env; then saveenv; fi
# -- so a fresh card takes the COMPILED-IN default and saves that out. On a card
# that already has a saved env, the saved value wins and this changes nothing.
#
# Deliberately not done with fw_setenv, per docs/image-migration.md: the env
# shares its 0x4000 block with BOOT_ORDER and the RAUC slot counters, and a
# write interrupted at the wrong moment drops U-Boot to a built-in default with
# no RAUC boot logic -- an unbootable card. Baking it costs nothing and cannot
# be interrupted.
#
# Injected into the defconfig rather than shipped as a .patch so it survives
# upstream edits to that file; delete-then-append keeps it idempotent across
# rebuilds, since ${S} is not cleaned between them.
do_configure:prepend:raspberrypi0-wifi() {
    sed -i '/^CONFIG_BOOTDELAY=/d' ${S}/configs/${UBOOT_MACHINE}
    echo 'CONFIG_BOOTDELAY=0' >> ${S}/configs/${UBOOT_MACHINE}
}
