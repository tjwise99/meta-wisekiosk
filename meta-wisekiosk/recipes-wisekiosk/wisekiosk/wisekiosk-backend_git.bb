SUMMARY = "WiseKiosk backend: serves the frontend bundle and the API on :8080"
DESCRIPTION = "One origin for the page, its configuration and the API. The bundle is served from \
disk at request time rather than embedded, which is what lets /srv/kiosk/config.json be a symlink \
into /data and be picked up without a rebuild. The port and the two flags are the app's, not this \
layer's."

require wisekiosk-src.inc

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

# `go install ./cmd` names the binary after its directory. The unit, the
# container and the app's own docs all say wisekiosk.
do_install:append() {
    mv ${D}${bindir}/cmd ${D}${bindir}/wisekiosk
}

# The app reaches upstreams over TLS and the image ships no anchors otherwise.
RDEPENDS:${PN} += "ca-certificates"
