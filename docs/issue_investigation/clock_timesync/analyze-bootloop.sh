#!/bin/bash
# Summarize a bootloop.log corpus. Prints N, the ntp_sync_s distribution and
# the categorical failure counts. Reads the field-keyed lines collect.sh writes.
set -uo pipefail
LOG=${1:?usage: analyze-bootloop.sh <bootloop.log>}
awk '
/^boot=/ {
    n++
    for (i = 1; i <= NF; i++) { split($i, kv, "="); f[kv[1]] = kv[2] }
    if (f["ntp_sync_s"] != "NA") { s[++m] = f["ntp_sync_s"]+0; sum += f["ntp_sync_s"]+0 }
    else { na_sync++ }
    if (f["dns"]      != "ok")  dnsfail++
    if (f["synchronized"] != "yes") notsync++
    if (f["pstore"]   != "empty") pst++
    if (f["mmc_err"]+0 > 0) mmc++
    if (f["A_LEFT"]+0 < 3 || f["B_LEFT"]+0 < 3) ctr++
}
END {
    if (m > 0) {
        asort(s)
        mean = sum / m
        for (i = 1; i <= m; i++) { d = s[i] - mean; ss += d*d }
        sd = (m > 1) ? sqrt(ss / (m - 1)) : 0
        med = (m % 2) ? s[(m+1)/2] : (s[m/2] + s[m/2+1]) / 2
    }
    printf "N_boots            = %d\n", n
    printf "ntp_sync_s samples = %d (NA: %d)\n", m, na_sync+0
    if (m > 0) {
      printf "ntp_sync_s min     = %.6f\n", s[1]
      printf "ntp_sync_s max     = %.6f\n", s[m]
      printf "ntp_sync_s mean    = %.6f\n", mean
      printf "ntp_sync_s median  = %.6f\n", med
      printf "ntp_sync_s sd      = %.6f\n", sd
      printf "ntp_sync_s spread  = %.6f\n", s[m] - s[1]
    }
    printf "dns != ok          = %d / %d\n", dnsfail+0, n
    printf "synchronized != yes= %d / %d\n", notsync+0, n
    printf "pstore non-empty   = %d / %d\n", pst+0, n
    printf "mmc_err > 0        = %d / %d\n", mmc+0, n
    printf "RAUC counter < 3   = %d / %d\n", ctr+0, n
}' "$LOG"
