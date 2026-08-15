# A touchscreen calibrator on a device with no touchscreen: MACHINE_FEATURES
# drops "touchscreen", but this arrives through packagegroup-core-x11-utils'
# RDEPENDS, which features do not gate.
#
# Bytes only. It is not a service and does not run at boot, so nothing here
# should move the clock.
RDEPENDS:${PN}-utils:remove = "xinput-calibrator"

# rxvt-unicode IS in the image (manifest: rxvt-unicode 9.31-r0) and it arrives
# through this packagegroup, but not from any RDEPENDS in this file: the chain is
# packagegroup-core-x11 -> ${PN}-utils -> xserver-nodm-init -> xinit, and xinit's
# own RDEPENDS names it. It installs as /usr/bin/rxvt{,c,d} through update-
# alternatives, which is why a grep for "urxvt" comes back empty on a running
# image that carries it. A removal has to target xinit's RDEPENDS; a remove line
# here matches nothing.
