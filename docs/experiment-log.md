# Experiment log — the Yocto device

What was tried on the Yocto card, and what actually held. An experiment that failed, that was
invalid, or that was abandoned is recorded here with the reason, so the next session does not pay
for it twice — condensed to keep only findings that still teach something once the standing root
cause (below) explained most of what came before it.

Scope is the Yocto device, 2026-08-11 onward. The Raspbian-era campaign is already logged in
the Raspbian card notes (kiosk-reference `raspbian-card.md`).

Three outcomes are distinguished throughout, because they are worth different amounts:

| | Meaning |
|---|---|
| **KILLED** | the hypothesis was tested and is dead. The most valuable outcome here |
| **INVALID** | the test did not measure what it claimed. Worse than no result, because it was believed |
| **ABANDONED** | not run, or run and never read. Costs nothing but tells you nothing |

---

## Boot-time optimisation, 2026-08-12

A profiling subagent ran an overnight campaign of small boot-time changes; most were reverted the
next morning (reverts in [`service-changes.md`](service-changes.md)). What survived from it:

### The camera stack was queued in front of the WiFi driver — the largest win found

Reading the journal between `mmc1: new high speed SDIO card` (4.0 s) and `brcmfmac: F1 signature
read` (27.3 s) showed udev loading `vc_sm_cma`, `mc`, `snd_bcm2835`, `videodev`,
`bcm2835_mmal_vchiq`, `bcm2835_isp`, `bcm2835_v4l2` and `bcm2835_codec`, registering fourteen
`/dev/video*` nodes, and only then reaching `brcmfmac`. All four leaf modules had `lsmod` usage
count 0.

Blacklisting the four leaves, n=3: **`wlan0` 3.33 s earlier** (non-overlapping ranges), `surf` exec
2.13 s earlier, for only **0.73 s** of CPU work removed — four times the gain for a fifth of the CPU,
which is what identifies it as a **serialisation** problem rather than a load problem. Stacked with
the Bluetooth removal below: `load_finished` **49.80 s → 46.57 s**.

### Bluetooth removal — killed the assumption that CPU removal buys boot time

Three-unit mask (`bthelper@.service` + `bluetooth` + `hciuart`), n=3: removed **2.43 s of CPU work**
and moved `wlan0` by **0.00 s**. `surf` exec came 1.00 s earlier, `load_finished` 0.53 s — inside the
run-to-run spread. The freed CPU became **idle** (8.4 % → 13.3 %), not speed, because the boot is
gated on `wlan0` appearing and Bluetooth runs after that gate. Removing CPU work on a CPU-saturated
boot does not convert 1:1 into wall clock when the work removed isn't on the critical path.

The kernel modules still load and probe despite the package being removed at build level
(`hci_uart_bcm`, `hci0: BCM43430A1`, four failed firmware-patch lookups for `BCM43430A1.hcd`, at
~22.5–23.1 s) — not costed, may be worth a further blacklist, recorded so the removal isn't assumed
complete.

### Parallelising `wpa_supplicant` made the boot worse — KILLED by direct experiment

A `DefaultDependencies=no` drop-in let `wpa_supplicant` start as soon as `wlan0` existed rather than
waiting on `sysinit.target`/`basic.target`. Network-online moved 5.55 s earlier, exactly as intended
— and `surf` exec moved **8.74 s later**, net **3.2 s worse**, reproducible to the hundredth of a
second across three boots (40.24 / 40.28 / 40.34 s). Releasing `kiosk.service` 6.8 s earlier put it
on a core still finishing dbus, journal flush, RAUC mark-good and the tail of udev, and it took
15.5 s longer to start once released. **Releasing work earlier without removing any of it converts a
wait into a queue** — the opposite of the intended effect. Reverted; the device was confirmed back at
baseline (`brcmfmac` 21.94 s, `wlan0` 24.92 s, network online 28.53 s, `surf` exec 31.56 s).

### Journal cap sizing — the fix was in the free space, not the cap

Raising `SystemMaxUse` to 150 MB stopped early-boot journal entries being dropped, but cost ~0.5 s of
boot, because the flush at ~25 s scales with *current* journal size. Vacuuming to 32 MB and capping
at 32 MB dropped entries again on the very next boot (usage sat at 31 MB against the cap — no free
space to flush into). The fix needed slack between usage and the cap: `SystemMaxUse=64M` + vacuum to
~20 MB → flush time 1.12–1.20 s (from 1.91–2.02 s) with early boot fully captured.

### The mask comparison was not an experiment — INVALID

Eleven units were masked and the per-boot journal read afterwards as though it were an experiment:

| | before masks (n=17) | after masks (n=4) |
|---|---|---|
| `Network is Online` | ~36.7–38.5 s | 34.22 / 34.53 / 35.18 / 35.46 |
| `uptime_at_exec` (surf) | ~41–43 s | 38.14 / 39.13 / 39.94 / 40.11 |

It reads as ~2–3 s. It is not a result: the two arms are **not the same device configuration** — the
17 "before" boots span RAUC install work, a slot change and a rollback; the masks are not the only
difference, and may not be the largest one. **n=17 against an unbalanced n=4**, not randomised, with
the "after" arm being simply the four most recent boots — the arm most likely to share whatever else
was true at the end of the session. The honest reading is that masking eleven units on a 1 GHz core
plausibly saves a small amount of time, and the size of it is unknown.

### Instrumentation defects, recorded because they recurred

Several early checks reported success while measuring nothing, which is why the rest of this log
insists on seeding the failing case before trusting a check:

- **`dd` reported a transfer "survived" that moved 0 bytes.** Busybox `dd` has no `conv=fsync`; the
  first run of a durable-write test printed a usage error, wrote nothing, and the harness recorded
  success. A test that transfers zero bytes always survives; only the re-run without the bad flag
  meant anything.
- **`prove-watchdog.sh` compared `boot_id` with a bare `!=`.** A racing `ssh` returned an empty
  string, which compares unequal to anything, so the check would have printed PROVEN even if the
  device never came back. Fixed to fail closed on an empty read and require `uptime` to decrease.
- **A tmpfiles `L` line with five dashes instead of four** parsed the extra dash as `Age` and created
  a symlink pointing at the literal string `"- /data/log/journal"` — broken link, journald silently
  volatile, config that read as entirely correct.
- **A launcher rewrite lost its execute bit** (`0644` against the shipped `0755`) and never ran —
  `xinit` execs it directly, so with `Restart=always` the next boot would have been a black screen
  retrying every 10 s. Its premise (a network wait) had also already been deleted by the change it
  depended on. Caught only by testing on the device, not by review. (Worth keeping: busybox `nc`
  exits 1 against an open port as well as a closed one, so a readiness check built on `nc` can never
  succeed.)
- **An `After=` drop-in on `systemd-journal-flush.service` created an ordering cycle**; systemd broke
  it by deleting the tmpfiles-setup job, and the kiosk didn't start. Fixed with a separate unit — a
  new unit cannot cycle with the graph it's ordered against.
- **`journalctl -b -N` doesn't work on this image.** Every boot shares the same pre-timesync
  first-entry timestamp, so the offset lookup is degenerate. Address a boot by its ID from
  `journalctl --list-boots` instead.
- **Journal wall-clock timestamps are not comparable across a boot.** There is no RTC and no
  `fake-hwclock`; every boot starts in the past and only NTP moves the clock forward, so early
  entries can be stamped *before* the boot started. Use `-o short-monotonic` or `/proc/uptime`.

---

## Delivery: the chunk-and-pause workaround, and where it broke

> **Superseded — dead end.** The "sustained SDIO traffic wedges the board" model below was overturned
> by the CPU-frequency root cause (§"ROOT CAUSE + FIX"). Kept for the ruling-out experiments and the
> `panic=10` / watchdog recovery evidence, not the mechanism.

The board wedges on sustained SDIO traffic in either direction. Three tests killed the alternative
explanations: a 133 MB `scp` at full rate with WiFi power save on froze 11 s in, having moved 0
bytes; a 16 MB chunk rate-limited to 1 MB/s froze on the first chunk (ruling out link saturation);
and 334 MB written to `/data` with `sync`, negligible network, survived while a plain 133 MB write to
`/dev/null` — zero disk writes — hung (ruling out the SD card and the disk as the dependency).
Transmit hangs it too: of three runs sending 133 MB from the device, 2 of 3 hung. The shape that
worked was chunk-and-pause — 32 × 4 MB at full rate with a 4 s gap between chunks, moving 133 MB with
zero hangs — until it didn't:

### ⛔ The chunk-and-pause workaround did NOT reproduce — OTA blocked at 64/130 MB

**2026-08-12 afternoon.** The first OTA of a trimmed image reached **64 MB of 130 MB** and stopped
converging: each attempt landed one chunk, the board hung, and the unsynced append was lost on
reboot, so the file rolled back. Net progress across the last four runs was zero.

| Run | chunks landed | transfer failures |
|---|---|---|
| 1 | 14 | 2 |
| 2 | 0 | 1 |
| 3 | 2 | 1 |
| 4 | 0 | 3 |
| 5 | 1 | 1 |

The same 32 × 4 MB / 4 s shape that had moved 133 MB with zero hangs overnight, and gentler variants
(6 s, 8 s pauses), hung repeatedly once the destination passed ~60 MB. **`sync` per chunk made it
strictly worse** — unsynced, the first run moved 14 chunks in a row; with a `sync` added after each
append (for durable resume), it hung on the *first* transfer of every subsequent run, so forcing 4 MB
of synchronous SD writes per chunk provoked the failure. **Unsynced appends are lost on a hang, so a
"verified" chunk can silently disappear**: a read-back md5 check passed for two chunks because it
read them out of page cache, then the board hung and the file rolled back past them — resume must
re-read the destination's real size after every failure rather than trust its own record of what it
sent.

Nothing was damaged (`BOOT_ORDER=B A`, both slots `good`, kiosk active, no FAT errors); every hang
self-recovered, which is `panic=10` and the watchdog earning their place. The attempt was stopped
deliberately rather than ground against the risk of unclean shutdowns corrupting the FAT partition
that holds `uboot.env`. This investigation predates, and is superseded by, the CPU-frequency root
cause below.

---

## Kernel panic at 4.0 s in `mmc_rescan` — a separate, still-real hazard

**2026-08-12.** A routine `systemctl reboot` did not come back; the board sat dead for >5.5 minutes
until an owner power-cycle. Transcribed from the console, the only copy — nothing reaches the journal
this early in boot:

```
3.940  mmcblk0: mmc0:5048 DDINC 28.9 GiB
4.001  8<--- cut here ---
4.010  Unable to handle kernel paging request at virtual address c0f9076c when execute
4.025  [c0f9076c] *pgd=00e0040e(bad)
4.035  Internal error: Oops: 8000000d [#1] ARM
4.055  CPU: 0 PID: 54 Comm: kworker/0:2   Not tainted 6.6.63 #1
4.077  Workqueue: events_freezable mmc_rescan
4.088  PC is at softirq_vec+0x18/0x28     LR is at complete+0x48/0x74
4.462  Kernel panic - not syncing: Fatal exception in interrupt
```

It dies at the exact moment the SDIO bus enumerates — on a healthy boot the next line after
`mmcblk0: … 28.9 GiB` at 3.94 s is `mmc1: new high speed SDIO card` at 4.002 s. The panic lands in
that gap, in the `mmc_rescan` workqueue, branched to an unmapped address (`Code: bad PC value`) — a
corrupted function pointer, in interrupt context. Observed **once in roughly 30 boots**.

No userspace mechanism can reach it: the hardware watchdog only arms at 5.2 s and `sysctl`'s
`kernel.panic` only applies from ~11.7 s, both after this panic already fires. The only mechanism
that reaches a 4.0 s panic is the kernel command line, which lives in `/boot` — putting the project's
own "never modify `/boot`" rule in tension with its own purpose, since here the *absence* of a
parameter was what caused a physical-recovery event. Resolved in both places: `CMDLINE:append = "
panic=10"` in the build tree for future images (see [`image-migration.md`](image-migration.md)), and
— on the owner's explicit instruction, with the unit on a bench — appended to the card already in
the device.

**Proven by making it fire**, not just inspected: `echo c > /proc/sysrq-trigger`, twice, after
`rauc-mark-good` had already run so the test couldn't consume a boot attempt. Recovery was **60 s**
from panic to SSH answering (10 s timeout plus a normal ~50 s boot), confirmed by a changed
`boot_id`, and nothing was damaged (counters `3/3`, both slots `good`, no ext4 errors). It does not
fix the panic — it bounds an indefinite hang needing a person to a 60-second unattended outage. The
mechanism underneath this specific panic is still unknown.

---

## The dead ends: two days chasing an SDIO/firmware theory

For two days the working hypothesis was that the SDIO bus, the WiFi driver, or the WiFi firmware
itself was defective. All three variants of that theory are superseded by the CPU-frequency finding
below — kept here only because the negative results and the method lessons they produced are still
worth having.

**The SDIO/firmware "wedge" model.** Multiple lines of evidence pointed at the wireless path itself:
sustained receive and sustained transmit could each hang the board; a kernel oops resolved to a
corrupted jump inside `brcmf_sdio_dataworker`, the brcmfmac SDIO receive worker; dose-response
testing across burst size and average rate found apparent thresholds (~0.9 MB/s, then revised to a
burst-size effect) that looked like a receiver limit; under-voltage was ruled out (`get_throttled`
stayed `0` through every death) and plain CPU starvation was ruled out (the board still hung at 12 %
idle over plain HTTP, which has no crypto to blame); two different firmware builds, swapped at
runtime via `/sys/module/firmware_class/parameters/path`, crashed identically. Every one of these was
a real measurement of a real device death — they were measuring the effect of the true cause (CPU
frequency reaching its top OPP under sustained load) at one remove, since a higher receive rate drives
more CPU demand, which drives `ondemand` to 1000 MHz. See "ROOT CAUSE + FIX" below for the finding
that resolves all of them at once.

**The kernel-bump that proved unnecessary.** Slab debugging (`slub_debug=FZPU`) found no redzone or
poison violation, ruling out a simple buffer overrun. A parallel review of brcmfmac's upstream history
found two real, still-missing fixes — a scatterlist table-size bug and a null-guard in
`brcmf_sdiod_sglist_rw()` — but the table-size bug was measured on-device to be nowhere near triggered
at safe rates (mean glom depth 4.8 against a 35-entry table), and the null-guard fix has never been
backported to the 6.6.y stable series at all. Neither missing patch was the cause, so a kernel version
bump would not have fixed this regardless of whether it shipped either fix.

**The "chip stops signalling" theory was the sender starving itself.** `mmc1` interrupts falling
to the idle rate during a stall looked like proof the firmware had stopped delivering frames. It
wasn't: sampling the *sender's* TCP state (`ss -ti`) during the same window showed `unacked: 0` and
`lastsnd: 3552ms` — nothing was outstanding because the sender had nothing to send. The pacing loop
was a fork-per-chunk `dd` + `sleep 0.1`, run on a host at load average 28 under a WebKit build, which
measured independently at 29 KB/s against a requested 640 KB/s. **A receiver-only instrument cannot
see a sender-side stall** — every later arm sampled the sender too, and a device stall was only
counted when the sender was demonstrably pushing (`unacked > 0` and `lastsnd` small while the
device's byte counter stayed flat). A follow-up arm built to that rule, paced by a single
non-forking sender, did show a genuine device-side collapse (`cwnd` fell to 1, seven backed-off
retransmits, none acknowledged) — the device-side failure was real; this specific proof of it was not.

---

## The mechanism: a corrupted jump in the network-receive softirq

Captured via `ramoops`/`pstore`, after an owner-authorised `/boot` write reserved memory across the
reset (the same class of change as `panic=10`, taken deliberately and proven first on a triggered
test panic). Full oops text in
[`evidence/oops-brcmf-sdio-dataworker-2026-08-13.txt`](evidence/oops-brcmf-sdio-dataworker-2026-08-13.txt).

The fault is an *instruction fetch* abort: the CPU jumps to `PC = 0xc1137c58` and tries to execute
data. That address is **constant across four separate crashes**, under two different CPU governors,
while `LR` (the call site) differs each time — a random corruption gives a random target, so a
constant target from different call sites means a deterministic computed jump, not a scribbled heap.
The address resolves to roughly 1.09 MB past the end of the kernel image, in the region the early
allocator uses (percpu, early bootmem) — not a symbol, not module space, not the vector page.

Resolving the raw stack against `/proc/kallsyms` (the oops itself printed no backtrace — the frame
pointer was garbage) puts the crash in generic softirq code, not inside brcmfmac:
`net_rx_action → __napi_poll → process_backlog → __netif_receive_skb_one_core → deliver_skb`'s
indirect call to the registered protocol handler. **brcmfmac is the packet source, not the faulting
code** — the `Workqueue: brcmf_sdio_dataworker` line in the oops names where the packet came from,
not where the corruption is. This is generic Linux network-receive code, faulting on a jump-table
entry that an earlier, unrelated memory corruption had already clobbered.

This was originally written up as its own "ROOT CAUSE": a corrupted function pointer specifically
inside brcmfmac's SDIO receive path. That framing is overturned by the CPU-frequency finding below —
brcmfmac only happens to be the code running when the underlying corruption is dereferenced.

---

## ROOT CAUSE + FIX

**2026-08-13 evening.** The softirq jump above names *where* the fault lands; this names *why*: the
board corrupts memory at its top CPU OPP, not on the SDIO bus. Controlled dose-response, one
variable, against the 120 MB unthrottled transfer that had already killed the board ~10 times that
day:

| CPU frequency | result |
|---|---|
| **1000 MHz** pinned | **2/2 DIED** (~50 s) |
| `ondemand`, uncapped (700↔1000) | died ~8 times that day |
| 900 MHz pinned | 1/1 survived |
| 800 MHz pinned | 1/1 survived |
| 700 MHz pinned | 3/3 survived |
| **`ondemand` capped at 900 MHz** | **3/3 survived** |

**8 of 8 survive below 1000 MHz. 100 % death at 1000 MHz.** In the capped-`ondemand` runs the
frequency-transition counter kept climbing throughout, so transitions themselves are fine — it's the
top OPP specifically. Throughput held at ~1.9 MB/s across both frequencies, so this isn't "slower
CPU, therefore less load." Matches raspberrypi/linux **#2555** — open since 2018, six independent
users reporting `force_turbo=1` + `over_voltage=4` as the fix on the same silicon family.

**This kills every rate and burst model in this log, including the ~0.9 MB/s boundary above.** The
chain was always indirect: higher receive rate → more CPU → `ondemand` climbs to 1000 MHz → the SoC
corrupts memory → the jump documented above. Rate was a correlate of the trigger, never the trigger
itself — which is why the OTA at 0.35 MB/s always worked (never enough sustained CPU demand to reach
1000 MHz), why `slub_debug` and every SDIO error counter stayed clean, and why two different firmware
builds crashed identically: none of them were ever the variable.

**The fix:** `kiosk-cpufreq` caps `scaling_max_freq` at 900000. `over_voltage`/`force_turbo` were not
used instead because both live in `config.txt` on the shared FAT partition, which
`RAUC_BUNDLE_SLOTS = "rootfs"` never touches — a voltage fix could never arrive by OTA. The frequency
cap ships as a systemd unit in the rootfs and does. Cost: ~10 % of peak CPU. Throughput went *up*, not
down — ~3.6 MB/s against ~1.9 MB/s while the board was still crashing, because removing the crashes
removed the retries.

**Consequence for delivery design.** The chunk-and-pause shape is no longer needed to avoid the wedge
on the capped image — a plain unthrottled transfer is 3/3 survived. It keeps its other property,
resuming from the durable on-disk size after an interrupted transfer, which is unrelated to the OPP
fix and still worth having.

Full detail, the shipped unit, and the OTA that proved the fix from the built image rather than a
hand-edit are in `STATUS.md` (kiosk-reference).

---

## What the failures have in common

The entries above are, again and again, the same mistake wearing different clothes: **a check whose
broken state is indistinguishable from a passing state.** `dd` writing zero bytes and surviving. An
empty `boot_id` comparing unequal. A five-dash symlink that parses. A launcher that "would fire on
the next boot" and cannot execute. A receiver that cannot tell its own silence from the sender's.

The countermeasure is the same in every case and it is cheap: **seed the failing case and confirm the
check reports failure**, before trusting it to report success.
