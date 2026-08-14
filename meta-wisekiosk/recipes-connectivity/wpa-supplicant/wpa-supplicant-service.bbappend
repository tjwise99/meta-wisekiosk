# files/wpa_supplicant.service SHADOWS the copy that ships beside upstream's
# wpa-supplicant-service.bb. A FILESEXTRAPATHS:prepend entry is searched ahead
# of a recipe's own side directories, so the base recipe's unqualified
# SRC_URI = "file://wpa_supplicant.service" resolves to this layer's file. That
# is what points the unit at /data/config/wpa_supplicant.conf instead of the
# baked /etc copy -- the network lifeline, so it is also checked on the built
# image rather than trusted from the tree.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://robust.conf"

# systemd requires ExecStart to be an absolute path; a bare "wpa_supplicant"
# makes the unit fail to load, and the symptom is a board with no network and
# therefore no way in. The shadowed unit carries the relative form verbatim, so
# this rewrite is what puts an absolute path into the installed file.
do_install:append() {
    sed -i 's|^ExecStart=wpa_supplicant|ExecStart=${sbindir}/wpa_supplicant|' \
        ${D}${sysconfdir}/systemd/system/wpa_supplicant.service

    install -d ${D}${sysconfdir}/systemd/system/wpa_supplicant.service.d
    install -m 0644 ${WORKDIR}/robust.conf \
        ${D}${sysconfdir}/systemd/system/wpa_supplicant.service.d/robust.conf
}

FILES:${PN} += "${sysconfdir}/systemd/system/wpa_supplicant.service.d"
