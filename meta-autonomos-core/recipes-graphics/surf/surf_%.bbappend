FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Kiosk instrumentation and WM-independent placement. Both are opt-in via the
# environment, so one binary serves every arm of a measurement:
#   SURF_MILESTONES=1        "SURFMS <name> <s-since-exec>" on stderr
#   SURF_OVERRIDE_REDIRECT=1 map the window bypassing the window manager
#   SURF_GEOMETRY=WxH        override the monitor size used for placement
#
# Ported from tools/surf-kiosk.patch in the kiosk-reference project, which
# targets surf 2.0. Four hunks needed rework for 2.1: RunInFullscreen changed
# from .val.b to .val.i, an Ephemeral branch appeared around web-context
# creation, and the loadchanged cases were rewritten.
SRC_URI += "file://0001-kiosk-milestones-and-override-redirect.patch"
