# HDMI settings carried over from the Raspbian kiosk. hdmi_force_hotplug brings
# the display up when the panel is off or slow to respond at boot -- the normal
# case for a kiosk behind glass whose TV is switched on after the Pi.
# hdmi_group=1 hdmi_mode=16 is CEA 1080p60, the panel's mode.
#
# These are FIRMWARE settings and take effect only on the legacy (non-KMS)
# display path, so under the vc4 KMS driver this image builds they are inert.
# `video=HDMI-A-1:1920x1080@60D` on the kernel command line is what asserts the
# mode and forces the connector there; it is set in kiosk-zero-w.yaml's
# `graphics` block. Removing these keys reaches no deployed board in any case:
# config.txt lives on the shared FAT partition, which RAUC never touches.
do_deploy:append() {
    CONFIG=${DEPLOYDIR}/${BOOTFILES_DIR_NAME}/config.txt
    cat >> $CONFIG <<'RPICFG'

# --- kiosk display: carried from the Raspbian configuration ---
hdmi_force_hotplug=1
hdmi_group=1
hdmi_mode=16
RPICFG
}
