# Yocto boot profile — where the time goes, and what kind of time it is

Measured on the device, 2026-08-12, **n=3 boots**, image-default service configuration (the eleven
masks applied overnight were reverted first, see [`service-changes.md`](service-changes.md)).

The point of this document is one distinction the previous profiling pass did not make: a boot window
can be long because the core is **doing work**, or because it is **waiting**. Those have opposite
fixes. Overlapping phases helps only in the second case, and on a single core it actively hurts in
the first.

A third case turned out to matter more than either, and is in §"The `wlan0` gate": a window can be
long because something is **queued behind unrelated work**. That is neither busy nor blocked in a way
the aggregate counters reveal, and it is where the largest measured win on this board came from.

## The finding

**Boot on this board is CPU-saturated, not I/O-blocked and not idle-waiting.**

Figures below are the **canonical baseline**: `kiosk-bootprof` at 2 Hz, whose own cost is 237 ms
(0.53 % of the boot's CPU work) and is recorded in every sample file. Earlier numbers in this
document's history came from a shell sampler costing 2295 ms and read ~2 points busier; see
§"The instrument".

| | boot 1 | boot 2 | boot 3 | mean |
|---|---|---|---|---|
| wall, boot → 60 s window | 52.0 s | 51.5 s | 52.0 s | 51.8 s |
| **CPU busy** | 85.2 % | 84.2 % | 86.8 % | **85.4 %** |
| **idle** | 10.18 % | 10.25 % | 8.44 % | **9.6 %** |
| iowait | 4.60 % | 5.54 % | 4.75 % | 5.0 % |
| total idle, seconds | 5.26 s | 5.25 s | 4.37 s | 4.96 s |
| CPU work in the boot | 44.3 s | 43.4 s | 45.1 s | 44.3 s |
| **run queue, excluding the sampler** | mean 5.52, max 19 | — | — | **~5.5 runnable** |

Milestones, same three boots:

| Milestone | mean |
|---|---|
| `wlan0` exists | **32.63 s** |
| network online | 36.30 s |
| `surf` exec | 40.00 s |
| `load_finished` | 49.80 s |

Per window, the same three boots (edges taken from each boot's own journal in `-o short-monotonic`):

| Window | wall | busy % | idle % | iowait % | |
|---|---|---|---|---|---|
| local filesystems | 11.5 s | 99.67 | **0.00** | 0.38 | before the gate |
| sysinit → basic | 5.2 s | 100.00 | **0.00** | 0.00 | before the gate |
| **waiting for `wlan0`** | 8.8 s | **100.00** | **0.00** | **0.00** | **the gate** |
| assoc + DHCP | 4.0 s | 84.77 | 13.97 | 1.25 | after |
| Xorg → `surf` exec | 4.3 s | 76.43 | 5.60 | 17.96 | after |
| `surf` → `load_finished` | 10.2 s | 81.10 | 3.94 | 14.93 | after |

**There is no idle time at all before `wlan0` appears.** Not "a little" — the idle counter advances by
exactly zero jiffies across the local-filesystems, sysinit and `wlan0` windows, on every boot
measured, with both instruments. Every scrap of idle and iowait in the boot lies *after* the gate.

That split is the single most useful thing in this document, and §"The `wlan0` gate" turns it into a
rule for ranking changes.

## What this rules out

The overnight handoff proposed starting Xorg in parallel with the network wait, on the reasoning that
"X needs no network — only the page fetch does", valued at **7–11 s**.

That is not available on this hardware, and the ceiling can be computed exactly.

On one core, reordering or overlapping work reclaims only time the core was **not executing**.
Overlapping two runnable tasks on a single core conserves total CPU time — it changes who waits, not
how much work there is. So:

```
reclaimable by any scheduling change  =  idle + iowait  =  7.65 / 8.10 / 6.84 s   (mean 7.53 s)
CPU work already in the boot          =  44.3 / 43.4 / 45.1 s   (mean 44.3 s)
```

**The entire scheduling budget for the whole boot is 7.53 s, against a claim of 7–11 s.** The claimed
range therefore spans and exceeds the total budget, and hitting even its lower bound would mean
reclaiming essentially 100 % of every idle and blocked moment anywhere in the boot — which no
scheduling change achieves, because that idle is scattered across windows with nothing pending in
them.

> An earlier version of this section put the ceiling at 6.56 s and said the claim exceeded it "by
> roughly a factor of two". That used the heavy shell sampler, which suppressed idle. The corrected
> ceiling is 7.53 s and the factor-of-two claim is withdrawn. The argument below is the one that
> actually decides it, and it is unaffected.

**The decisive point is that none of that 7.53 s is in the window the change targets.** `waiting for
wlan0` measures 0.00 % idle and 0.00 % iowait on every boot, with both instruments. There is
literally nothing there to overlap into — all the idle sits *after* the gate, in `assoc + DHCP`
(13.97 %), `Xorg → surf exec` (5.60 %) and `surf → load_finished` (3.94 %). Starting Xorg earlier
moves it into a window with zero slack, adding a competing process to a run queue already averaging
5.44 runnable tasks on one core.

This is the failure mode the owner named before any of it was measured: over-parallelising a
single-core box converts a wait into a queue and produces dead time. The data says the box is already
past that point at boot.

### Confirmed directly, 2026-08-12 evening — not just accounting

The argument above is derived from idle-time accounting; nothing had actually been reordered and
measured. It was: a `DefaultDependencies=no` drop-in on `wpa_supplicant`, so it starts
as soon as `wlan0` exists rather than waiting for `sysinit.target`/`basic.target` (see the correction
in §"The `wlan0` gate" below for why that wait exists).

| | before | after | Δ | overlap |
|---|---|---|---|---|
| network online | 28.51 s | 22.97 s | −5.55 s | no |
| `surf` exec | 31.54 s | 40.28 s | **+8.74 s** | no |

Network online moved 5.55 s earlier, exactly as the reorder intended. `surf` exec moved **8.74 s
later** — net **3.2 s worse**, reproducible to the hundredth of a second across three boots (40.24 /
40.28 / 40.34 s). `kiosk.service` was released 6.8 s earlier, into a machine still running dbus,
journal flush, RAUC mark-good, RF-kill and the tail of udev, and took 15.5 s longer to start once
released, because it was now competing with all of that for the one core.

This is the accounting argument's prediction, not a contradiction of it: releasing work earlier does
not create CPU, and on this board the released work landed in a queue rather than in slack. **The
idle-time ceiling above is now backed by a direct experiment, not only by arithmetic.** Both changes
were reverted; full arm table in [`experiment-log.md`](experiment-log.md) §"Parallelising
`wpa_supplicant` made the boot worse — KILLED by direct experiment".

## The `wlan0` gate — the largest measured win, and it is not a CPU problem

> **Correction, 2026-08-12 evening: `wlan0` is a proxy for total CPU work removed, not the cause of
> the win below.** A direct test moved `wlan0` far earlier without removing any CPU work — preloading
> `brcmfmac` via `/etc/modules-load.d/` moved `wlan0` from 24.82 s to 14.19 s, a **−10.63 s** shift —
> and `surf` exec moved by **−0.06 s**: nothing, well inside run-to-run spread. The reason:
> `wpa_supplicant.service` inherits the implicit `After=sysinit.target basic.target` and starts only
> once those targets are reached, 11.25 s after `wlan0` already existed on that boot:
>
> ```
> 14.10  Found device .../wlan0
> 22.14  Reached target System Initialization
> 23.07  Reached target Basic System
> 25.35  Starting Bring up wlan0 ... wpa_supplicant
> 28.51  Reached target Network is Online
> ```
>
> Association plus DHCP is only ~3.2 s of that 14.4 s wait. **Every trim in this section that moved
> `wlan0` earlier also removed CPU work**, and it is the CPU removed — not `wlan0`'s arrival — that
> moved `surf` exec: the two happened to move together every time because both track total CPU work,
> not because one causes the other. The measurements below (module blacklist, Bluetooth stack) still
> stand as boot-time wins, because they *did* remove CPU work. Read every "`wlan0` gate" reference
> below as shorthand for "reaching `sysinit.target`/`basic.target`", not as `wlan0` itself gating
> anything — and see the confirmation above in §"What this rules out" for what happens when `wlan0` is
> moved earlier by reordering instead.

`wlan0` does not exist until **32.63 s**, and every unit downstream waits on it. The chip is not slow
to appear:

```
 4.00 s  mmc1: new high speed SDIO card at address 0001     <- the WiFi chip is on the bus
27.33 s  brcmfmac: F1 signature read @0x18000000            <- the driver first touches it
28.26 s  Firmware: BCM43430/1 wl0: ... version 7.45.98
32.53 s  Found device /sys/subsystem/net/devices/wlan0
```

**23.3 seconds pass between the chip being visible on SDIO and `brcmfmac` binding to it.** Reading the
journal across that window shows what occupies the last six seconds of it:

```
21.28  rpi-gpiomem            24.02  snd_bcm2835          (audio)
21.58  vc_sm_cma              25.00  videodev             (V4L2)
22.07  mc: media interface    25.41  bcm2835_mmal_vchiq
22.36  vc_sm_cma probe        26.04  bcm2835_isp
22.84->23.34  vc_sm init      26.32  bcm2835_v4l2
                              26.57->27.34  /dev/video10..23,31   (14 nodes)
27.33  brcmfmac starts
```

udev is loading the Raspberry Pi **camera, ISP, codec and audio** stack, and `brcmfmac` is queued
behind it. All four leaf modules load with `lsmod` usage count **0** — nothing uses them. This kiosk
has no camera and no audio.

### Measured, n=3 per arm

Blacklisting `bcm2835_isp`, `bcm2835_codec`, `bcm2835_v4l2` and `snd_bcm2835`
(`modprobe-kiosk-blacklist.conf` (kiosk-reference)):

| | baseline | blacklisted | Δ |
|---|---|---|---|
| **`wlan0` exists** | 32.6 / 32.7 / 32.6 → **32.63 s** | 29.2 / 29.5 / 29.2 → **29.30 s** | **−3.33 s**, ranges do not overlap |
| network online | 36.30 s | 33.90 s | −2.40 s |
| **`surf` exec** | 40.2 / 39.6 / 40.2 → **40.00 s** | 38.0 / 37.6 / 38.0 → **37.87 s** | **−2.13 s**, ranges do not overlap |
| `load_finished` | 49.80 s | 48.10 s | −1.70 s, **ranges overlap** — directional only |
| CPU work in boot | 44.27 s | 43.53 s | −0.73 s |

**CPU work fell by 0.73 s while `wlan0` moved 3.33 s earlier.** The gain is four times the CPU
removed, so this was never a CPU-quantity problem — it is **serialisation**. Work sitting ahead of
`brcmfmac` in udev's queue delays the gate that the whole boot waits on, whether or not it is
expensive.

That is the opposite of the Bluetooth result in [`service-changes.md`](service-changes.md), which
removed **2.43 s of CPU** and moved `wlan0` by **0.00 s** — because it sits *after* the gate, so the
freed CPU became idle rather than speed.

**The rule this yields, restated:** on this board, work removed *before* `wpa_supplicant` is allowed to
start — gated by `sysinit.target`/`basic.target`, not by `wlan0`'s own arrival — converts to boot
time; work removed *after* that point converts to idle. `wlan0`'s timestamp is not itself the gate: in
every measurement in this section it moved together with total CPU work, which is what actually
converts to boot time, and reordering `wlan0` earlier alone buys nothing (confirmed directly, see
above). Rank every trim by whether it removes CPU work ahead of `sysinit.target`/`basic.target`, not
by whether it happens to move `wlan0`.

### Stacked with the Bluetooth removal, n=3

Both changes applied together, against the same baseline:

| | baseline | + modules | + modules + Bluetooth |
|---|---|---|---|
| `wlan0` exists | 32.63 s | 29.30 s | **29.10 s** |
| network online | 36.30 s | 33.90 s | 33.50 s |
| `surf` exec | 40.00 s | 37.87 s | **36.73 s** |
| **`load_finished`** | 48.6 / 49.4 / 51.4 → **49.80 s** | 48.10 s | 45.8 / 46.0 / 47.9 → **46.57 s** |
| CPU work in boot | 44.27 s | 43.53 s | **41.47 s** |

**They stack, and the combined `load_finished` ranges do not overlap the baseline's** (45.8–47.9
against 48.6–51.4) — so unlike either change alone, the pair moves the endpoint that matters by a
margin larger than the run-to-run spread. **−3.23 s to `load_finished`, −2.80 s of CPU work.**

The split is exactly what the gate rule predicts: the modules buy the gate (`wlan0` −3.33 s, almost
all of it), Bluetooth buys CPU after the gate (−2.07 s further CPU work, `wlan0` unchanged), and the
two do not overlap because they act on different things.

### The module first-seen timeline — where the gate actually goes

Module loads mostly do not log, so the journal cannot answer "what is udev doing between 14.5 s and
28 s". `kiosk-bootprof` therefore also records the first time each module appears in `/proc/modules`
(capped at 1 Hz; `/proc/modules` is a seq_file over every loaded module and costs more than the three
counters). Image-default boot:

```
17.08  cfg80211, rfkill, uio, uio_pdrv_genirq
21.08  fixed
22.57  mc, raspberrypi_gpiomem, snd
24.07  snd_pcm, snd_timer, vc_sm_cma, videobuf2_common, ecc, ecdh_generic
25.08  brcmutil, snd_bcm2835, videodev
26.59  videobuf2_dma_contig, videobuf2_memops, videobuf2_v4l2, videobuf2_vmalloc
28.07  bcm2835_isp, bcm2835_v4l2, v4l2_mem2mem, brcmfmac
```

**`cfg80211` — the module `brcmfmac` depends on — is loaded at 17.1 s, eleven seconds before the
driver that needs it.** Nothing about the WiFi stack is slow; `brcmfmac` is simply late in udev's
queue on a core that is 100 % busy.

### A second pass at the blacklist bought nothing — negative result

Four more modules load in that window and were added to the blacklist: `vc_sm_cma` (which survived
the first pass with usage count 0), `raspberrypi_gpiomem`, `uio`, `uio_pdrv_genirq`. Measured n=3:

| | baseline | 8-module blacklist |
|---|---|---|
| `wlan0` | 32.3 / 32.4 / 32.2 → **32.30 s** | 28.9 / 28.9 / 28.8 → **28.87 s** |
| `surf` exec | 39.37 s | 37.33 s |
| `brcmfmac` loads | 28.07 s | 25.97 / 26.49 / 25.98 s |

**−3.43 s, against −3.33 s for the original four** — and the baseline had already moved 0.33 s from
the journald fix below. The four extra modules are worth roughly **0.1 s: nothing.** The camera and
audio stack was the entire effect. Keep them out of the image for size if convenient, but do not
claim boot time for them, and do not re-run this experiment expecting a different answer.

`drm`, `backlight` and `drm_panel_orientation_quirks` were deliberately **not** blacklisted: they load
at 9.6 s via `modprobe@drm.service`, far ahead of the gate, and logind's seat handling may want DRM.
Breaking X to save nothing is a bad trade.

### The journal flush was costing 0.8 s, and the first fix made it worse

The persistent-journal cap interacts with boot time, because the flush at ~25 s sits before the gate:

| journal size | flush cost | early boot captured? |
|---|---|---|
| 51–54 MB | 1.42–1.54 s | yes |
| 77–81 MB (`SystemMaxUse=150M`) | 1.91–2.02 s | yes |
| 31 MB at a **32 MB** cap | — | **no** |
| **19–21 MB, 64 MB cap** | **1.12–1.20 s** | yes |

Flush cost tracks **current size**, not entry count (~432 entries throughout). Raising the cap to
150 MB to stop early-boot entries being dropped therefore bought debuggability and cost ~0.5 s of
boot, growing. Capping at 32 MB with 31 MB already in use **recreated the original bug** — the
failure was never a small cap, it was *no free space*. The working configuration is a loose cap with
a small working set: `SystemMaxUse=64M`, `SystemMaxFileSize=8M`, vacuumed to ~20 MB.

### Verified not to break the display

The kiosk renders through the legacy `bcm2708_fb` framebuffer, configured on the kernel command line;
`vc_sm_cma` is used only by the camera and codec paths. After the blacklist: `kiosk` active, 3 surf
processes, X running, no new failed units, and a framebuffer sample reading
`rgb_min=0 rgb_max=255 rgb_mean=2.03 distinct=227` — pixels present, matching the baseline's
`mean=1.84 distinct=221`. The probe was seeded in both directions first: a uniform buffer reads
`BLANK`, and a failed read reports `PROBE FAILED` rather than blank.

## What it points to instead

Since boot is CPU-bound, the lever that works is **less work**, not more overlap — and that lever is
not capped at 4.5 s, because it reduces the 47 s of CPU work itself.

That is an argument *for* trimming services, which is what the overnight session did — for the wrong
reason, without checking dependants, and without a measurement. The route back is in
[`service-changes.md`](service-changes.md) §"The bar": mask the subset whose hardware is absent
(`neard`, `ofono`) or whose function is unused (`rpcbind`), re-measure n=3 against a fixed endpoint,
and keep only what shows up.

Remaining leads:

- **The `wlan0` gate is still 29.3 s after the module trim**, and the chip is on the bus at 4.0 s. The
  camera stack explained ~3.3 s of that; the remaining gap was open as "the single highest-value
  question" when this was written. **Finding 5 (2026-08-12 evening, see the correction above) resolves
  the shape of it, though not the full accounting**: `wpa_supplicant` does not start until
  `sysinit.target`/`basic.target` are reached, independent of `wlan0`'s own timestamp, so most of the
  remaining gap is time spent reaching those targets on a saturated core — not literally "ahead of
  `brcmfmac` in udev's queue" as originally framed here. **Pursuing it as a queue-ordering problem is a
  closed line**: a direct reorder (confirmed above) moved `wlan0` earlier without removing work and
  made `surf` exec 8.74 s worse. The lever that remains is removing CPU work ahead of
  `sysinit.target`/`basic.target`, the same "less work" conclusion §"What it points to instead" already
  reaches.
- **`zram.service` fails on every boot** — `/etc/init.d/zram: line 42: echo: write error: Device or
  resource busy`. A 437 MB board running WebKit plausibly wants compressed swap. Masking it, as the
  overnight session did, hid a broken feature rather than removing an unwanted one.

## Your own SSH session is an instrument, and it costs 3.34 s

**One connection per boot, opened no earlier than 90 s after reboot.** An `sshd` per-connection
daemon burned **3 340 ms of CPU** on a core with no idle, measured from `CPUUsageNSec` on the unit
itself. A connection opened at 32.2 s during a profiling run landed inside browser startup and
inflated `surf` exec on that boot.

The boundary is worth stating exactly, because it decides which figures from a contaminated run
survive: this board has **no network at all before ~30 s**, so nothing done from a workstation can
reach `mmc1`, `brcmfmac`, `wlan0` or `Reached target Network is Online`. Those are safe on any boot.
Everything from `SURFMS uptime_at_exec` onward is not.

90 s clears the latest milestone ever observed here (`surf` exec at 40.24 s, on a deliberately
misconfigured arm) with ~35 s of margin. Raise it to 120 s if complete display is the endpoint --
§"Endpoints" records one boot that took over 165 s to reach icon render despite a normal
`load_finished`.

The wait is **latency, not a measurement parameter**. It changes when the journal is read, never
what the journal says, so shortening it does not invalidate comparison against earlier arms.

## The instrument, and its limits

`kiosk-bootprof.c` (kiosk-reference), analysed by
`analyze-boot-cpu-io.py` (kiosk-reference). It samples `/proc/stat`,
`/sys/block/mmcblk0/stat` and `/proc/loadavg` twice a second from early boot into a preallocated
buffer, and writes once at the end — so measuring adds no SD writes to the window being measured.

It replaced a shell sampler (`boot-cpu-io-sample.sh` (kiosk-reference), kept
for reference) because the instrument was distorting the result:

| | shell, 1 Hz | C, 2 Hz |
|---|---|---|
| self CPU per boot | 2295 ms | **237 ms** |
| share of the boot's CPU work | 5.1 % | **0.53 %** |
| cost per sample | ~16 ms | **0.64 ms** |
| measured CPU busy | 87.4 % | **85.4 %** |
| measured headroom | 6.56 s | **7.53 s** |

Three properties beyond the cost, each of which fixes a way the shell version could mislead:

- **No cadence drift.** Samples land on an absolute `CLOCK_MONOTONIC` grid — the same clock as
  `journalctl -o short-monotonic`, so window edges align exactly. All boots report `late_samples=0`.
  The shell loop drifted 1.01–1.08 s per nominal second.
- **It reports its own cost** as `self_cpu_us=` in every output file, so the overhead is never
  inferred. An earlier draft of this document asserted the busy fraction was near-invariant to
  instrument cost; that was wrong by ~2 points, and this is the fix for that class of error.
- **It validates all three sources at startup and refuses to run** if one will not parse, rather than
  emitting zero-filled columns that read as real data.

Cross-compiled with the Yocto toolchain inside the `ghcr.io/siemens/kas/kas:5.4` image (the build is
containerised, so the cross `gcc` will not run on the host — its ELF interpreter points into
`/work`). Dynamic build is 9.75 KB; the command line is in the file header.

Stated plainly, because each of these bounds a claim above:

- **It does not cover the first ~8.6 s.** systemd cannot run a unit before it starts, so the kernel
  and early-systemd window is outside the data.
- **It counts itself.** The sampler is a runnable process, so `nr_running` includes it; every run
  queue figure above is `nr_running - 1`.
- **The instrument's cost changed the numbers materially, and an earlier draft of this document said
  it did not.** The first baseline used a sampler that looped over all 46 lines of `/proc/diskstats`
  per sample and burned **9.1 s of CPU**; it now reads the single-line `/sys/block/mmcblk0/stat` and
  burns 2.3 s. Rewriting it moved the headline figures:

  | | heavy sampler (9.1 s) | light sampler (2.3 s) |
  |---|---|---|
  | CPU busy | 91.2 % | **87.4 %** |
  | idle | 4.6 % | **8.4 %** |
  | scheduling headroom | 4.51 s | **6.56 s** |

  The claim that the busy fraction was "nearly invariant" to instrument cost was wrong — the headroom
  figure moved by ~45 %, and the headroom figure is what the argument rests on. **The numbers in this
  document are the light-sampler run.** What did *not* move is the finding: both baselines record
  0.00 % idle through the local-filesystems, sysinit and `wlan0` windows, and the conclusion holds
  under either, because 6.56 s is still below the 7–11 s that was claimed. Wall-clock times here
  still run ~1 s longer than an uninstrumented boot.
- **`io_ticks` is not populated by this kernel's mmc driver** — 0 at 3 minutes uptime, 4050 at 4.8 h.
  It is recorded but unusable over boot-length windows. `iowait %` and `rd_ms`/`wr_ms` are the
  I/O figures used here.
- **`/proc/pressure/` does not exist** (no `CONFIG_PSI`) and `systemd-analyze` is not on the image,
  so neither PSI nor `blame`/`critical-chain` was available.

**The sampler now ships in the image, installed but not enabled** (`kiosk-bootprof` recipe). Enable
it for a run, then disable it again — it costs ~240 ms of the boot it measures:

```bash
systemctl enable --now kiosk-bootprofile && systemctl reboot   # capture one boot
systemctl disable kiosk-bootprofile                            # put it back to sleep
```

Do **not** `rm` it — it is image content now, so a delete is undone by the next OTA and leaves the
device disagreeing with its own image in the meantime. Full workflow in
[`remote-debugging.md`](remote-debugging.md) §"Recipe 10 — Profile the boot: is the core busy,
blocked, or queued?".

## The first boot after an OTA is slower — do not baseline on it

`ldconfig`, `systemd-journal-catalog-update` and `systemd-machine-id-commit` are gated on
`ConditionNeedsUpdate=` and fire only on a boot immediately following a freshly written slot. Measured
2026-08-12 evening, one OTA'd slot's first boot against its second:

| | boot 1 (first after OTA) | boot 2 (steady) | Δ |
|---|---|---|---|
| `brcmfmac` | 24.21 s | 23.28 s | −0.93 s |
| `wlan0` | 28.54 s | 26.91 s | −1.63 s |

~770 ms of CPU removed by skipping those units moves `wlan0` by 1.63 s — more evidence for the
CPU-saturation finding above. **The mechanism is confirmed** (the units demonstrably skip on the
second boot); **the 1.63 s magnitude is n=1 and not established.** Any timing taken on a slot's first
post-OTA boot overstates steady state — measure the second boot or later. `ldconfig` itself burns
369 ms of CPU spread across 3.64 s of wall clock: timesliced, not slow.

## Endpoints — do not mix these

Three different finish lines have been quoted for this image, and an earlier handoff draft conflated
them. Anything compared against a number below must use the same row.

> **Every figure in this document is kernel-relative and excludes U-Boot.** `CLOCK_MONOTONIC` and
> `/proc/uptime` both start at kernel entry, so `bootdelay=2` — confirmed on the device with
> `fw_printenv bootdelay`, and by the owner, 2026-08-12 — is invisible to all of it. **Add ~2 s for
> true power-on to anything below.** Filed as `meta-wisekiosk` #4 bootdelay.
>
> **Decision: `bootdelay=0`** (owner, 2026-08-12). Keeping a short delay to preserve the U-Boot prompt
> was considered and rejected on the grounds that reaching that prompt needs a keyboard and a serial
> adapter attached to the unit — *"if I have to plug in a keyboard it's the same work as a reflash"*.
> A recovery avenue that costs a physical trip is not a recovery avenue on this device, so the delay
> buys nothing.
>
> **Land it in the build tree, not with `fw_setenv` on the live card.** The environment lives at
> `/boot/uboot.env`, in the same 0x4000 block as `BOOT_ORDER`, `BOOT_A_LEFT` and `BOOT_B_LEFT`, and
> `fw_setenv` rewrites that block with a new CRC. This board takes unexplained hangs — one on
> 2026-08-12 during a trivial SSH session — and a hang mid-write drops U-Boot to its built-in default
> environment, which carries no RAUC boot-order logic. That is an unbootable card and a physical trip.
> Building the image with `bootdelay=0` in the initial environment reaches the same state by reflash,
> with nobody writing that block on a running board.

| Endpoint | What it means | Value |
|---|---|---|
| SSH reachable | the lifeline is back | 53–56 s (n=8, 2026-08-12) |
| `SURFMS uptime_at_exec` | `surf` is exec'd | **39.67 s** (n=3) |
| `SURFMS load_finished` | WebKit finished the page load | 51.10 / 48.79 / 50.48 → **50.12 s** (n=3) |
| **complete display** | **weather icons rendered — the only one a viewer sees** | 53.42 / 54.89 / 52.65 → **53.65 s** (n=3) |

Complete display is now measured on this configuration, replacing the 2026-08-11 figure of 57.08 s
(which was a different configuration and is not a valid comparison). Tool:
`measure-surf-yocto.sh` (kiosk-reference) — the Raspbian
`measure-surf.sh` (kiosk-reference) does not run here (no `/home/pi`, no
`.Xauthority`, different busybox flags).

**The window between `load_finished` and complete display is large and noisy**: 3.53 s on the
baseline arm, 6.49 s on a blacklist boot. It is the page's own post-load fetching and rendering, which
depends on the backend, so it is not a property of the boot. **Do not treat a complete-display delta
smaller than ~2 s as a boot result** — the baseline's own spread is 2.24 s across three boots.

With the module blacklist: 52.56 / 52.13 s and **one boot that never reached icon render at all**
within ~165 s despite `load_finished` at 46.80 s. The kiosk was healthy on that boot — the page's
data fetch is downstream of the backend and untouched by a module blacklist — so it is recorded as
observed, not attributed. n=2 is too thin to claim the −1.3 s difference.

