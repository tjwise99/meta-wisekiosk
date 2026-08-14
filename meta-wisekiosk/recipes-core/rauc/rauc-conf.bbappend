# meta-autonomos-raspberrypi's rauc-conf.bbappend prepends only its own
# files/${MACHINE} directory; raspberrypi0-wifi exists only in this layer.
FILESEXTRAPATHS:prepend := "${THISDIR}/files/${MACHINE}:"
