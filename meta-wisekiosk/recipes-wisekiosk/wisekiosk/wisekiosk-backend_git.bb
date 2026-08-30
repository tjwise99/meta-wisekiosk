SUMMARY = "WiseKiosk backend: serves the frontend bundle and the API on :8080"
DESCRIPTION = "One origin for the page, its configuration and the API. The bundle is served from \
disk at request time rather than embedded, which is what lets /srv/kiosk/config.json be a symlink \
into /data and be picked up without a rebuild. The port and the two flags are the app's, not this \
layer's."

require wisekiosk-src.inc

# scarthgap unpacks file:// SRC_URI straight into WORKDIR; go.bbclass redirects
# only the git entry, so this lands beside the checkout.
SRC_URI += "file://wisekiosk.service"

GO_IMPORT = "github.com/tjwise99/WiseKiosk"

LIC_FILES_CHKSUM = "file://src/${GO_IMPORT}/LICENSE;md5=4af5bdd6287d36bddd2161cdad4e1eb5"

# The go module is the backend/ subtree, one level below the import path the
# checkout lands at.
GO_WORKDIR = "${GO_IMPORT}/backend"
GO_INSTALL = "${GO_IMPORT}/backend/cmd"

inherit go-mod

# Any fetch at compile time fails the task.
export GOPROXY = "off"

CGO_ENABLED = "0"

# poky's arm defaults assume cgo, and Go refuses both without it: goarch.bbclass
# sets GO_DYNLINK:arm ?= "1" (shared Go runtime) and go.bbclass appends
# -buildmode=pie. The :arm suffix is required -- an override-suffixed value wins
# over the bare name.
GO_DYNLINK:arm = ""
GOBUILDFLAGS:remove = "-buildmode=pie"

inherit systemd

SYSTEMD_SERVICE:${PN} = "wisekiosk.service"
SYSTEMD_AUTO_ENABLE = "enable"

# `go install ./cmd` names the binary after its directory.
do_install:append() {
    mv ${D}${bindir}/cmd ${D}${bindir}/wisekiosk

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/wisekiosk.service ${D}${systemd_system_unitdir}/wisekiosk.service
}

FILES:${PN} += "${systemd_system_unitdir}/wisekiosk.service"

# TLS anchors for the app's upstream calls.
RDEPENDS:${PN} += "ca-certificates"

# The account the service runs as, uid and gid both pinned at 10001: /data is
# slot-shared, so the numeric ids are what survive an A/B update. The group is
# created explicitly because useradd otherwise assigns a gid of its own.
inherit useradd

USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-g 10001 kiosk"
USERADD_PARAM:${PN} = "-u 10001 -g kiosk -d /srv/kiosk -s /bin/false -r kiosk"
