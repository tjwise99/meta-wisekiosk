FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# The build-time substitution of WIFI_SSID / WIFI_PSK_HASH is GONE, deliberately.
# Baking them made one image serve exactly one site and shipped the site's
# wireless credentials inside every bundle. wpa_supplicant now reads
# /data/config/wpa_supplicant.conf, which is written by provisioning.
#
# The packaged /etc/wpa_supplicant.conf is left as the upstream placeholder with
# an empty ssid. Nothing reads it any more; it is not removed only because doing
# so would fight the base recipe's packaging for no benefit.
do_install:append() {
    :
}
