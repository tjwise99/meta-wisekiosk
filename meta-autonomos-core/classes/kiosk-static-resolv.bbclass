# Replace the resolved-managed /etc/resolv.conf chain with a static file.
#
# systemd-resolved answers ZERO queries on this device: `resolvectl statistics`
# reports Total Transactions 0 on a normal boot. The kiosk fetches nothing
# client-side and reaches only its backend, by IP; the external APIs are fetched
# server-side and never resolve here. resolved's entire job is writing one file,
# for ~729ms of CPU starting at 19.96s -- before the gate.
#
# Measured on the shipped image, n=3, `Reached target Basic System`:
#     resolved active  22.61 / 22.02 / 21.96   mean 22.20
#     resolved masked  21.30 / 21.15 / 21.07   mean 21.17   -1.03s, ranges do not overlap
# DNS keeps working: nslookup resolves and NTPSynchronized=yes, with timesyncd
# the only consumer.
#
# Why a postprocess and not a recipe: /etc/resolv.conf is already shipped as a
# symlink by a package, so a second package installing that path is a do_rootfs
# conflict. Same lever as kiosk-machine-id, for the same reason.
#
# On the precedence question, which docs previously called a contest not worth
# rushing: /usr/lib/tmpfiles.d/systemd-resolve.conf carries
#     L! /etc/resolv.conf - - - - ../run/systemd/resolve/stub-resolv.conf
# `L` creates a symlink only when the path does not exist -- it is not `L+`, so
# it does not replace one. Confirmed on hardware rather than from the manual:
# a static file survived three reboots with systemd-tmpfiles-setup running to
# completion each time and never reclaiming it.
#
# KIOSK_NAMESERVER is a SITE value and belongs to the same class as WIFI_SSID --
# see the config-provisioning issue. It lives in secrets.yaml, not here.

KIOSK_NAMESERVER ??= ""

kiosk_set_static_resolv() {
    if [ -z "${KIOSK_NAMESERVER}" ]; then
        bbfatal "kiosk-static-resolv inherited but KIOSK_NAMESERVER is unset"
    fi
    rm -f ${IMAGE_ROOTFS}${sysconfdir}/resolv.conf
    for ns in ${KIOSK_NAMESERVER}; do
        echo "nameserver $ns" >> ${IMAGE_ROOTFS}${sysconfdir}/resolv.conf
    done
    chmod 0644 ${IMAGE_ROOTFS}${sysconfdir}/resolv.conf
}

ROOTFS_POSTPROCESS_COMMAND += "kiosk_set_static_resolv;"
