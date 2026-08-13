# Drop four sub-packagegroups for hardware and services this kiosk does not have.
#
# Measured on the device 2026-08-12, n=3 per arm: masking ofono, avahi-daemon,
# rpcbind, busybox syslog/klogd and the failing zram init script together moved
# surf exec 34.42s -> 32.50s, ranges non-overlapping. avahi carries most of it
# despite being only 190ms of CPU, because it starts at 22.57s -- inside the
# window where brcmfmac downloads firmware and registers the netdev.
#
# This is deliberately NOT `DISTRO_FEATURES:remove = "3g nfc nfs zeroconf"`,
# which is the obvious route and has two problems:
#
#   1. zeroconf gates a systemd meson flag, INVERTED from the intuition:
#        bb.utils.contains('DISTRO_FEATURES','zeroconf','-Ddefault-mdns=no -Ddefault-llmnr=no','',d)
#      Removing zeroconf therefore RE-ENABLES systemd-resolved's own mDNS and
#      LLMNR responders -- trading avahi for a daemon that starts 2.6s earlier
#      and costs ~4x the CPU. The win would have partly cancelled itself.
#   2. It re-hashes systemd:do_configure. systemd reaches webkitgtk3 via
#      dbus -> at-spi2-core (PROVIDES atk) -> webkitgtk3, and bitbake's hash
#      equivalence cannot rule the cascade out until systemd has actually
#      rebuilt. `bitbake -S printdiff` reports a lower bound, not a guarantee.
#
# Editing RDEPENDS here re-hashes exactly one task, packagegroup-base:do_package,
# which nothing depends on. Verified with `bitbake -S printdiff core-image-base`.
#
# ofono is collateral from a feature kept on purpose: packagegroup-base.bb adds
# packagegroup-base-3g whenever usbhost is in MACHINE_FEATURES, and usbhost stays
# so a USB keyboard remains the recovery path when the network is gone.
# Two packages, not one. nfs and zeroconf are named directly in
# RDEPENDS:packagegroup-base, but 3g and nfc arrive through ADD_3G/ADD_NFC --
# set by a python anonymous function from DISTRO_FEATURES, and consumed by
# RDEPENDS:packagegroup-base-EXTENDED (packagegroup-base.bb:92-93).
#
# Removing all four from packagegroup-base alone was built and checked against
# the assembled rootfs: nfs and zeroconf went, ofono and neard stayed. The
# package manifest caught it; the recipe edit looked correct and was not. Same
# shape as the bluetooth trap in kiosk-zero-w.yaml -- the feature returns by a
# second path, so removing it from the obvious one silently does nothing.
RDEPENDS:packagegroup-base:remove = "\
    packagegroup-base-nfs \
    packagegroup-base-zeroconf \
"

RDEPENDS:packagegroup-base-extended:remove = "\
    packagegroup-base-3g \
    packagegroup-base-nfc \
"
