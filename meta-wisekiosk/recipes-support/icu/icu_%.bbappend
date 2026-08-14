# libicudata is 30 786 792 bytes on the device -- the second-largest file in the
# image, and ICU ships locale data for every language on earth for a kiosk that
# renders one.
#
# This uses ICU's own supported filter mechanism rather than deleting anything:
# icu_74-2.bb already carries PACKAGECONFIG[make-icudata] and a do_make_icudata
# task that rebuilds the data archive with ICU_DATA_FILTER_FILE=${WORKDIR}/filter.json.
# The task is a no-op unless make-icudata is in PACKAGECONFIG, so both halves are
# needed.
#
# The filter restricts LOCALES only, and keeps every feature category -- break
# iteration, collation, charset mappings. Dropping feature categories is where
# text rendering breaks, and text is the entire product here.
#
# WebKit build-depends on ICU, so this is a webkitgtk3-class rebuild. It is
# deliberately batched with the enchant removal and NOTHING else: mixing the
# gstreamer removal in would make a regression unattributable, and gstreamer is
# a hard DEPENDS rather than a PACKAGECONFIG so it is a different kind of change.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:class-target = " file://filter.json"
PACKAGECONFIG:append:class-target = " make-icudata"
