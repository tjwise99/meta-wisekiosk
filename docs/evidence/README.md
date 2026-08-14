# Evidence — raspberrypi0-wifi wifi-crash / panic investigation

This directory used to hold ~1900 lines of deep read-only research into the Pi Zero W wifi crash.
Most of it investigated a root-cause theory that a later fix obviated. This page keeps only the
conclusions that document something **shipped** or a hazard that is **still live**. The full research
trail is not reproduced here — see the `kiosk-reference` repo's history if it is ever needed again.

The crash itself was fixed by capping `scaling_max_freq` at 900 MHz (`kiosk-cpufreq`), not by
anything below. See `STATUS.md` and `experiment-log.md` §"ROOT CAUSE + FIX" for that story.

## brcmfmac SDIO rx-path — two patches shipped as hygiene, not as the crash fix

Investigated whether the wifi crash was a known brcmfmac bug in kernel 6.6.63. Two small upstream
fixes touching the SDIO scatter-gather path were found missing from the pinned tree and both apply
cleanly:

- `857282b819cb` (backported as `07c020c6d14d`) — grows the rx scatterlist from 35 to 64 entries.
- `52e8726d6782` — adds an `if (!sgl)` bounds guard at the point the list is walked. Never
  backported to any 6.6.y or 6.12.y stable branch.

**Neither matches the observed crash signature** — the captured oops is a prefetch abort with an
unresolved PC/LR (a wild branch), not the NULL-pointer deref these two fixes address. So they are
**not** the crash fix. They shipped anyway as defensive hygiene: without them, an unbounded rx-glom
subframe count can walk a fixed 35-entry scatterlist off the end, which is a real, reachable
overrun independent of whether it explains the observed panic.

Raw evidence: `oops-brcmf-sdio-dataworker-2026-08-13.txt`.

## ramoops / pstore — feasibility question is closed; it now ships

Investigated whether ramoops/pstore could capture a hard-lockup panic across a reboot. Findings:

- The **dmesg zone** would be empty for this failure shape — it only fills on a panic/oops path,
  and a watchdog-driven hard lockup never reaches one.
- The **console zone** is the actual win: it writes the kernel log tail synchronously as each line
  is printed, with no dependence on panic. That is real evidence the current setup loses today,
  since journald never gets to flush it. It needs no kernel rebuild — only an explicit
  `console-size=` and a `ramoops.dtbo` overlay entry plus one `config.txt` line, since the overlay
  ships with the console zone disabled by default.
- `pstore/ftrace` would also work with interrupts disabled, but needs a kernel rebuild and carries
  real per-function-call overhead on a 1 GHz single core — not pursued.
- On this SoC a plain `reboot` and a watchdog reset are the same hardware event, so a passing
  reboot test is a passing watchdog-reset test for whether the region survives.

**Ramoops now ships** (`STATUS.md`: "ramoops is live and now permanent" — `ramoops.dtbo` plus one
additive `dtoverlay=` line in `config.txt`). The feasibility question is closed.

Raw evidence: `oops-2-slub-debug-armed-2026-08-13.txt`.

## The `mmc_rescan` panic — still live

The board can panic at 4.0 s in `mmc_rescan` on boot. Bounded to a ~60 s self-recovery by
`panic=10` in `cmdline.txt` (the one documented `/boot` exception, owner-approved 2026-08-12), not
fixed. This is a separate, still-open hazard from both the SDIO-throughput wedge (retired
2026-08-13) and the brcmfmac rx-glom overrun above. See `STATUS.md` for current status.

## What used to be here, and was deleted

Deep read-only research premised on the crash needing a **kernel version bump** in
`linux-raspberrypi` (6.6.63 → 6.6.78 / 6.6.151 / 6.12.x) to reach the brcmfmac fixes above:
`kernel-bump-viability.md` and `kernel-delta-research.md`. That mechanism was obviated by the
`kiosk-cpufreq` `scaling_max_freq` cap, which fixed the actual crash a different way. The research
was sound at the time it was done; it is a dead end now, and this directory no longer carries it.

The full `brcmfmac-bug-research.md` and `ramoops-feasibility-research.md` were condensed into the
two sections above and then deleted — the section-level detail (source citations, line numbers,
config dumps) lived only in those files and is not preserved elsewhere.
