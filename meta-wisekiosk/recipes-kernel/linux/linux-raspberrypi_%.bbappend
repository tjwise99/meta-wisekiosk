FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# 52e8726d6782 (mainline v6.14) adds the `if (!sgl)` bounds check that turns
# running off the end of the brcmfmac SDIO scatterlist into -ENOMEM instead of a
# NULL deref. It was never backported to 6.6.y or 6.12.y, so no kernel bump
# delivers it -- that is why it is carried as a patch. Applies with zero fuzz and
# zero offset against 6.12.93.
#
# Hygiene for a real unguarded defect, explicitly NOT the fix for the crash
# diagnosed 2026-08-13 -- that was CPU instability at the top OPP, addressed by
# the kiosk-cpufreq recipe. Different fault class: this one faults near address 0
# with a resolvable PC.
SRC_URI += " file://brcmfmac-52e8726d6782.patch"
