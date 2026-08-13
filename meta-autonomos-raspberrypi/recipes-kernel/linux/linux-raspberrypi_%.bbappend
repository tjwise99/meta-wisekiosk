FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://k3s-netfilter.cfg"

# Two brcmfmac SDIO scatter-gather fixes, neither present in 6.6.63.
#
# 857282b819cb (mainline v6.13) sizes the sg table 35 -> 64. Backported to
# stable as 07c020c6d14d, first released in v6.6.66 -- two point releases past
# our pin, and rpi-6.6.y is frozen at 6.6.78 so a branch bump would deliver it.
#
# 52e8726d6782 (mainline v6.14) adds the `if (!sgl)` bounds check that turns
# running off the end of the table into -ENOMEM instead of a NULL deref. It was
# NEVER backported to 6.6.y or 6.12.y, so NO kernel bump delivers it. That is
# why these are carried as patches rather than chased with a version bump.
#
# Both verified to apply with zero fuzz and zero offset against this exact
# source. They are hygiene for a real unguarded defect and are explicitly NOT
# the fix for the crash diagnosed 2026-08-13 -- that was CPU instability at the
# top OPP, addressed by the kiosk-cpufreq recipe. Different fault class: these
# fault near address 0 with a resolvable PC.
SRC_URI += " \
    file://brcmfmac-857282b819cb.patch \
    file://brcmfmac-52e8726d6782.patch \
"
