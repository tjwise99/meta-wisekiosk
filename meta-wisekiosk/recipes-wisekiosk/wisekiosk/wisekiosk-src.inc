# The app commit, pinned in exactly one place.
#
# wisekiosk-frontend and wisekiosk-backend are two halves of one repository and
# must be built from the same commit -- a bundle and a server that disagree
# about the boundary schema fail at runtime, not at build time. Both require
# this file, so there is one SRCREV to bump and no second copy to drift.
#
# Not recorded again in /etc/buildinfo: that stamp carries the meta-wisekiosk
# commit, and meta-wisekiosk commit -> this file -> app commit is a chain
# anyone can walk. A second copy of the app commit in the image would be a
# restated fact with somewhere to drift to. See docs/layers-and-kas.md.

HOMEPAGE = "https://github.com/tjwise99/WiseKiosk"
LICENSE = "MIT"

SRC_URI = "git://github.com/tjwise99/WiseKiosk.git;protocol=https;branch=main"
SRCREV = "33e710338d9b03afa9968194717ff0ddc4e3a72d"

# The app carries no release version; the commit is the version. `+git` is
# poky's own spelling for that (SRCPV has been empty since 4.3).
PV = "0.0+git"
