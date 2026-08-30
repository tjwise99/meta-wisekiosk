SUMMARY = "WiseKiosk backend: serves the frontend bundle and the API on :8080"
DESCRIPTION = "One origin for the page, its configuration and the API. The bundle is served from \
disk at request time rather than embedded, which is what lets /srv/kiosk/config.json be a symlink \
into /data and be picked up without a rebuild. The port and the two flags are the app's, not this \
layer's."

require wisekiosk-src.inc

# scarthgap unpacks file:// SRC_URI straight into WORKDIR; the UNPACKDIR/sources
# layout is a later-release convention. go.bbclass's do_unpack redirects only
# the git entry, so this lands beside the checkout rather than inside it.
SRC_URI += "file://wisekiosk.service"

GO_IMPORT = "github.com/tjwise99/WiseKiosk"

LIC_FILES_CHKSUM = "file://src/${GO_IMPORT}/LICENSE;md5=4af5bdd6287d36bddd2161cdad4e1eb5"

# The go module is the backend/ subtree of the repository, so the tree go runs
# in is one level below the import path the whole checkout lands at.
GO_WORKDIR = "${GO_IMPORT}/backend"
GO_INSTALL = "${GO_IMPORT}/backend/cmd"

# go-mod, not go-vendor. The reachable graph is stdlib-only -- a cross-build
# with an empty module cache and the proxy off produces the binary with zero
# fetches, so the compile is already offline and there is nothing to vendor.
# `go mod vendor` would be worse than redundant: Go vendors `tool` directives,
# and backend/go.mod carries `tool oapi-codegen` behind ~17 indirect modules,
# so go-vendor would mean pinning and shipping the source of a code generator
# that never reaches the binary.
inherit go-mod

# The proof, not the intention: any fetch at compile time fails the task rather
# than silently reaching the network.
export GOPROXY = "off"

# A static binary. The device has no reason to carry a dynamic link to libc for
# a server whose imports are all stdlib.
CGO_ENABLED = "0"

# Two of poky's arm defaults assume cgo, and Go refuses both without it.
#
# goarch.bbclass sets GO_DYNLINK:arm ?= "1", which links against the shared Go
# runtime: "-linkshared requires external (cgo) linking, but cgo is not
# enabled". go.bbclass appends -buildmode=pie for every non-mips target to
# satisfy the textrel QA check, and refuses the same way -- internal-linking
# PIE does not exist for linux/arm.
#
# So the two are consequences of CGO_ENABLED = "0" rather than choices made
# here. Dropping pie needs no INSANE_SKIP to go with it: textrel reads
# DT_TEXTREL out of the dynamic section, and a static binary has none.
#
# The GO_DYNLINK assignment carries the :arm suffix because that is the one it
# countermands -- a plain GO_DYNLINK = "" parses fine and does nothing, since
# an override-suffixed value wins over the bare name whenever `arm` is in
# OVERRIDES.
GO_DYNLINK:arm = ""
GOBUILDFLAGS:remove = "-buildmode=pie"

inherit systemd

SYSTEMD_SERVICE:${PN} = "wisekiosk.service"
SYSTEMD_AUTO_ENABLE = "enable"

# `go install ./cmd` names the binary after its directory. The unit, the
# container and the app's own docs all say wisekiosk.
do_install:append() {
    mv ${D}${bindir}/cmd ${D}${bindir}/wisekiosk

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/wisekiosk.service ${D}${systemd_system_unitdir}/wisekiosk.service
}

FILES:${PN} += "${systemd_system_unitdir}/wisekiosk.service"

# The app reaches upstreams over TLS and the image ships no anchors otherwise.
RDEPENDS:${PN} += "ca-certificates"

# The account the service runs as. BOTH ids are pinned, and pinned NOW, before
# any file on /data is owned by them.
#
# /data is slot-shared: an A/B update replaces the rootfs and leaves it
# standing. So the numeric ids are what survive the update, not the names --
# a renumber on a later build orphans every /data file the app wrote, on a
# wall-mounted unit, with no remote undo. useradd assigns a gid on its own
# where none is given, which is exactly that failure with nobody having chosen
# it, so the group is created explicitly at the same number.
#
# 10001 and the name are the app's own, from its container image, not a choice
# invented here.
inherit useradd

USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-g 10001 kiosk"
USERADD_PARAM:${PN} = "-u 10001 -g kiosk -d /srv/kiosk -s /bin/false -r kiosk"
