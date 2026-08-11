# systemd requires ExecStart to be an absolute path; a bare "wpa_supplicant"
# makes the unit fail to load, and the symptom is a board with no network and
# therefore no way in. Rewrite it at install time rather than forking the unit,
# so upstream edits to the file still flow through.
do_install:append() {
    sed -i 's|^ExecStart=wpa_supplicant|ExecStart=${sbindir}/wpa_supplicant|' \
        ${D}${sysconfdir}/systemd/system/wpa_supplicant.service
}
