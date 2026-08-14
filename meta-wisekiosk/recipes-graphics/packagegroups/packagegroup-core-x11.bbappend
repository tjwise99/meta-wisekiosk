# A touchscreen calibrator on a device with no touchscreen: MACHINE_FEATURES
# drops "touchscreen", but this arrives through packagegroup-core-x11-utils'
# RDEPENDS, which features do not gate.
#
# Bytes only. It is not a service and does not run at boot, so nothing here
# should move the clock.
RDEPENDS:${PN}-utils:remove = "xinput-calibrator"
