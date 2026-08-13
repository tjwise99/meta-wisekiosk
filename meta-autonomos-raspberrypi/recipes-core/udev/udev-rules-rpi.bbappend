# 99-com.rules is GPIO/i2c/spi/PWM/serial-symlink plumbing for Raspberry Pi
# add-on hardware. This kiosk has none: /dev/i2c* and /dev/spi* do not exist on
# the running device, and nothing uses GPIO or PWM.
#
# It is not merely inert. Six of its rules run PROGRAM="/bin/sh -c ...", forking
# a shell plus cmp, chgrp -R and chmod -R during udev coldplug -- on a single
# 1GHz ARM11 core that is 100% busy, in the window before brcmfmac binds and
# wlan0 appears. wlan0 is the gate the whole boot waits on.
#
# can.rules is left in place; it installs no PROGRAM rules.
do_install:append() {
    rm -f ${D}${sysconfdir}/udev/rules.d/99-com.rules
}
