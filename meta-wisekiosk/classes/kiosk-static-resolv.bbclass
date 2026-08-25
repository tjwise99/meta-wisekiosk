# Point /etc/resolv.conf at /data, and mask systemd-resolved (kiosk-hardware).
#
# systemd-resolved answers ZERO queries on this device -- `resolvectl statistics`
# reports Total Transactions 0 on a normal boot. Its entire job here is writing
# one file, for ~729ms of CPU starting at 19.96s, before the gate. Masking it
# measured -1.03s at basic.target, n=3, ranges not overlapping.
#
# The nameserver ITSELF is site configuration and is NOT baked. An earlier
# version of this class wrote KIOSK_NAMESERVER into the image, which is the same
# mistake as baking the SSID: one image per site. It is now a symlink into
# /data/config, written by provisioning.
#
# A dangling symlink on an unprovisioned device means DNS fails. That is correct
# and deliberate -- timesyncd is the only consumer, the kiosk reaches its backend
# by IP, and a device with no /data/config has no network anyway.
#
# Why a postprocess and not a recipe: /etc/resolv.conf is already shipped as a
# symlink by a package, so a second package installing that path is a do_rootfs
# conflict.
#
# On precedence, previously called a contest not worth rushing:
# /usr/lib/tmpfiles.d/systemd-resolve.conf carries
#     L! /etc/resolv.conf - - - - ../run/systemd/resolve/stub-resolv.conf
# `L` creates only when the path does not exist -- it is not `L+` and does not
# replace one. Confirmed on hardware across three reboots.

kiosk_set_static_resolv() {
    rm -f ${IMAGE_ROOTFS}${sysconfdir}/resolv.conf
    ln -s /data/config/resolv.conf ${IMAGE_ROOTFS}${sysconfdir}/resolv.conf
}

# Bare name: a ';' glued to it hides this body from the task hash (guard 9).
ROOTFS_POSTPROCESS_COMMAND += "kiosk_set_static_resolv"
