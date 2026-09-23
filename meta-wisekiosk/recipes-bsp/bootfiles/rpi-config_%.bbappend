# HDMI settings carried over from the Raspbian kiosk. hdmi_force_hotplug brings
# the display up when the panel is off or slow to respond at boot -- the normal
# case for a kiosk behind glass whose TV is switched on after the Pi.
# hdmi_group=1 hdmi_mode=16 is CEA 1080p60, the panel's mode.
#
# These are FIRMWARE settings and are inert under full KMS, which takes the mode
# off the firmware. This image builds firmware KMS -- kiosk-zero-w.yaml's
# `graphics` block sets VC4DTBO = "vc4-fkms-v3d" -- so they are the live
# mechanism, and nothing on the kernel command line asserts the mode in their
# place. The kiosk's own 1280x720 is set on top of this by xrandr in
# kiosk-launch. Removing these keys reaches no deployed board in any case:
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
