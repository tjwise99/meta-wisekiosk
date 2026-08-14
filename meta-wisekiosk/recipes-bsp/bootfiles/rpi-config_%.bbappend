# HDMI settings carried over from the Raspbian kiosk. Without hdmi_force_hotplug
# the display does not come up if the panel is off or slow to respond at boot --
# which is the normal case for a kiosk behind glass whose TV is switched on
# after the Pi. hdmi_group=1 hdmi_mode=16 is CEA 1080p60, the panel's mode.
#
# These are FIRMWARE settings and only take effect on the legacy (non-KMS)
# display path, which is why DISABLE_VC4GRAPHICS is set alongside them.
do_deploy:append() {
    CONFIG=${DEPLOYDIR}/${BOOTFILES_DIR_NAME}/config.txt
    cat >> $CONFIG <<'RPICFG'

# --- kiosk display: carried from the Raspbian configuration ---
hdmi_force_hotplug=1
hdmi_group=1
hdmi_mode=16
RPICFG
}
