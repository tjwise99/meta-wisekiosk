# Experiment log — the Yocto device

Everything attempted on the Yocto card, including — especially — what did not work. An experiment
that failed, that was invalid, or that was abandoned is recorded here with the reason, so the next
session does not pay for it twice.

Scope is the Yocto device, 2026-08-11 onward. The Raspbian-era campaign is already logged in
the Raspbian card notes (kiosk-reference `raspbian-card.md`) and the Raspbian card notes (kiosk-reference `raspbian-card.md`).

Three outcomes are distinguished throughout, because they are worth different amounts:

| | Meaning |
|---|---|
| **KILLED** | the hypothesis was tested and is dead. The most valuable outcome here |
| **INVALID** | the test did not measure what it claimed. Worse than no result, because it was believed |
| **ABANDONED** | not run, or run and never read. Costs nothing but tells you nothing |

---

## The boot-optimisation campaign, 2026-08-12 overnight

Run by a profiling subagent that terminated without reporting. Its changes were reconstructed after
the fact by diffing the device against the image build epoch. Everything in this section was reverted
on 2026-08-12 morning; the reverts are in [`service-changes.md`](service-changes.md).

### The mask comparison was not an experiment — INVALID

Eleven units were masked and the per-boot journal was read afterwards as though it were an
experiment log:

| | before masks (n=17) | after masks (n=4) |
|---|---|---|
| `Network is Online` | ~36.7–38.5 s | 34.22 / 34.53 / 35.18 / 35.46 |
| `uptime_at_exec` (surf) | ~41–43 s | 38.14 / 39.13 / 39.94 / 40.11 |

It reads as ~2–3 s. It is not a result:

- The two arms are **not the same device configuration**. The 17 "before" boots span the RAUC install
  work, a slot change, a rollback to slot A and back, and the journal fixes. The masks are not the
  only difference; they are not even the largest one.
- **n=17 against n=4**, unbalanced and not randomised, with the "after" arm being simply *the most
  recent four boots* — the arm most likely to share whatever else was true at the end of the session.
- The endpoint drifted. `uptime_at_exec` is measured from a clock that
  the Raspbian card notes (kiosk-reference `raspbian-card.md`) on this image.

The honest reading is that masking eleven units on a 1 GHz core plausibly saves a small amount of
time, and the size of it is unknown. The handoff said as much — "directional, not a result" — which
is correct, and which also means it is not a justification for keeping the change.

### `early-start.conf` — ABANDONED

A drop-in to remove `After=/Wants=network-online.target` from `kiosk.service`, so Xorg could start
while WiFi was still associating. Created, then deleted, in the same session. **Never tested, no
measurement, no record of why it was withdrawn.** The empty
`/etc/systemd/system/kiosk.service.d/` directory it left behind was still on the device the next
morning, and `systemd` was still holding a reference to the deleted file because `daemon-reload` was
never run.

This is the half of the design that carried the claimed 7–11 s benefit.

### The launcher backend-wait — ABANDONED, and it would have taken the kiosk down

`/usr/bin/kiosk-launch` was rewritten to poll the backend with `wget` before exec'ing `surf`,
bounded at 60 s. Written at 03:51, into a boot that started at 03:46, so it never ran: `SURFMS
backend_` appears **zero times in all 22 retained boots**.

Two defects, neither recorded by the session that made it:

1. **The file lost its execute bit** — `0644`, where the image ships `0755`. `kiosk.service` runs
   `ExecStart=/usr/bin/xinit /usr/bin/kiosk-launch …` and `xinit` execs that path directly. Verified
   on the device 2026-08-12 by copying the file, `chmod 644`, and running it: `Permission denied`.
   With `Restart=always` and `RestartSec=10`, the next boot would have been a black screen retrying
   every ten seconds.
2. **Its premise had been deleted.** The script's own comment says *"kiosk.service no longer waits
   for network-online.target"*. With `early-start.conf` gone, it still does — so the wait loop would
   have run after the network was already up and saved nothing.

**Worth keeping from it:** busybox `nc` exits 1 against an open port as well as a closed one, so a
readiness check built on `nc` can never succeed. That is why the script used `wget`. The file is
preserved at `kiosk-launch.backend-wait.sh` (kiosk-reference).

### The boot profile is n=1 against three different finish lines — INVALID as a comparison

| Measurement | Endpoint | Value |
|---|---|---|
| 2026-08-11, n=3 | complete display (weather icons rendered) | 57.08 s |
| 2026-08-12, n=1 | `load_finished` | 50.82 s |
| 2026-08-12, n=8 | SSH reachable | 53–56 s |

An earlier draft of the handoff treated these as one number and implied a ~53 s total. They are three
different events. The handoff was corrected before it was committed, and the correction stands: **no
improvement can be claimed, because nobody measured the same endpoint twice.**

The per-window breakdown — kernel 7.6 s, local filesystems 11.8 s, `wlan0` appearing at 31.5 s, and
so on — is **n=1**. It is a sketch of where to look, not a measurement.

### Boot `-12` — ABANDONED

One boot (03:21:05) recorded no `uptime_at_exec` at all and a `Network is Online` of 42.03 s against
a ~37 s norm. Noticed, written down, never investigated. It is the only anomalous boot in the set and
therefore the most informative one.

---

## Delivery and the network hang, 2026-08-11/12

### Single-stream transfer hangs the board — KILLED three hypotheses

| Attempt | Conditions | Outcome |
|---|---|---|
| 133 MB `scp`, full rate, power save on | froze 11 s in, **0 bytes** transferred |
| 16 MB chunk, rate-limited to **1 MB/s**, power save off | froze on the *first* chunk |
| **Test B**: 133 MB into `cat > /dev/null`, zero disk writes | **HUNG** |
| **Test A**: `dd` 334 MB to `/data` + `sync`, negligible network | **survived** |

Dead as a result: **WiFi power save** (disabled and verified `off`, still hung), **link saturation**
(1 MB/s hung on the first chunk), and **the SD card** (Test A wrote 334 MB and survived).

Working delivery shape: 32 × 4 MB chunks at full rate with a 4 s pause between, each md5-verified.
133 MB moved with zero hangs.

### The first Test A was invalid and reported SURVIVED — INVALID

busybox `dd` has no `conv=fsync`. The first run printed a usage error, wrote nothing, and the harness
recorded **survived**. A test that transfers zero bytes always survives. It was re-run without the
flag, and only the re-run means anything.

This is the failure mode named in the Raspbian card notes (kiosk-reference `raspbian-card.md`): *if "it passed" would look identical
when the thing failed, nothing was measured.*

### Out-of-band diagnosis — ABANDONED, both options rejected on design

The board dies writing nothing to the journal, which lives on `/data` on the SD card. Two channels
were considered and neither was built:

- **netconsole** — ships over the same wireless interface that is wedging. It cannot report its own
  failure.
- **ramoops** — needs a `/boot` change, which is the one class of change that can require physical
  access to undo. Refused on that basis.

Still open. A USB-serial adapter is the obvious third option and the bench does not have one.

### `VOLATILE_LOG_DIR` for the persistent journal — KILLED on cost

Setting it re-hashes systemd → gtk+3 → webkitgtk3 and triggers a multi-hour WebKit rebuild, *and* it
puts the journal on the rootfs slot that every OTA replaces — so the log would be destroyed by the
update whose failure it exists to explain. Replaced by a tmpfiles symlink to `/data`.

---

## Instrumentation that lied

Four separate cases where the *reader* was broken and the device was blamed.

### The tmpfiles symlink had five dashes — INVALID

The `L` line type takes four fields of `-`. With five, systemd parsed the extra dash as `Age` and
created a symlink whose target was the literal string `"- /data/log/journal"`. Broken link, journald
silently volatile, configuration looking entirely correct. Caught only by reading the symlink back
off the device rather than re-reading the config that wrote it.

### The journal-flush drop-in created an ordering cycle — and took the kiosk down

Adding `After=systemd-tmpfiles-setup.service` to `systemd-journal-flush.service` produced a cycle.
systemd broke it by **deleting the tmpfiles-setup job**, so `/var/volatile/log` was never created,
`/var/log` dangled, and the kiosk did not start. Replaced with a separate `kiosk-journal-flush.service`
— a new unit cannot cycle with the graph it is being ordered against.

### `prove-watchdog.sh` would have printed PROVEN either way — INVALID

It compared `boot_id` before and after with a bare `!=`. The post-recovery `ssh` raced the boot and
returned an **empty string**, which compares unequal to anything — so the check would have reported
PROVEN had the device never come back at all. The verdict happened to be right. The logic was not.
It now fails closed on an empty read and additionally requires `uptime` to have decreased.

### `journalctl -b -N` does not work on this image

Every boot shares the same pre-timesync first-entry timestamp, so systemd's offset lookup is
degenerate and `-b -1` returns "No journal boot entry found". **Address a boot by its ID**, from
`journalctl --list-boots`, and note the ID is printed there without dashes.

---

## This session, 2026-08-12 morning

### The board hung on a trivial SSH session — the "sustained receive" model does not cover it

At `08:35:05` the journal of boot `cd9d80cc…` ends dead on
`Started OpenSSH Per-Connection Daemon (192.168.1.3:58376)`. That connection carried two commands,
`sleep 0.5` and `sleep --help`, and a few hundred bytes. Nothing follows it. The watchdog recovered
the board unattended at `08:36:43`, ~98 s later.

The hang signature is identical to the documented one — journal stops mid-air, no error, no panic, no
OOM. But the documented **trigger** is *continuous* network receive of 133 MB, and this was neither
continuous nor large. One event is not causation, and the board may simply hang on its own. Either
way, `STATUS.md` (kiosk-reference) §"THE HANG IS THE NETWORK PATH" describes a narrower trigger than
the evidence now supports.

**This also means every interactive session with this device is a coin flip**, and it is why the
collection harness for the boot profile tolerates a missing window and retries rather than recording
a failure.

### `PSI` and `systemd-analyze` are both unavailable — the easy instruments do not exist here

- `/proc/pressure/` does not exist; the kernel is built without `CONFIG_PSI`. There is no
  ready-made "how starved was the CPU" counter.
- `systemd-analyze` is not on the image, so `blame` and `critical-chain` are unavailable. The unit
  timeline has to come from the journal, and the journal's wall clock jumps.

Hence `boot-cpu-io-sample.sh` (kiosk-reference), which anchors every sample
on `/proc/uptime` and reads the raw counters directly.

### Bluetooth removal — KILLED the assumption that CPU removal buys boot time

Three-unit mask (`bthelper@.service` + `bluetooth` + `hciuart`), n=3 against baseline. Removed
**2.43 s of CPU work** with non-overlapping ranges — and moved `wlan0` by **0.00 s**. `surf` exec came
1.00 s earlier, `load_finished` 0.53 s, the latter inside the run-to-run spread.

The freed CPU became **idle**, not speed: idle went 8.4 % → 13.3 %. Dead as a result: the assumption,
written into the first draft of [`image-trim-recommendations.md`](image-trim-recommendations.md), that
on a CPU-saturated board removing CPU work converts roughly 1:1 into wall clock. It does not, because
the boot is gated on `wlan0` appearing and Bluetooth runs after that gate.

Also confirmed here: the three-unit form is correct. `bthelper@hci0` went `inactive` with no failed
unit, where the overnight two-unit form would have failed it on every boot.

### The camera stack was queued in front of the WiFi driver — the largest win found

Reading the journal between `mmc1: new high speed SDIO card` (4.0 s) and `brcmfmac: F1 signature
read` (27.3 s) showed udev loading `vc_sm_cma`, `mc`, `snd_bcm2835`, `videodev`,
`bcm2835_mmal_vchiq`, `bcm2835_isp`, `bcm2835_v4l2` and `bcm2835_codec`, registering fourteen
`/dev/video*` nodes, and only then reaching `brcmfmac`. All four leaf modules had `lsmod` usage
count 0.

Blacklisting the four leaves, n=3: **`wlan0` 3.33 s earlier** (non-overlapping), `surf` exec 2.13 s
earlier, for only **0.73 s** of CPU work removed. Four times the gain for a fifth of the CPU, which
is what identifies it as a **serialisation** problem rather than a load problem.

Stacked with the Bluetooth removal: `load_finished` **49.80 s → 46.57 s**, ranges non-overlapping.

Display verified unaffected by sampling the framebuffer — and the probe was seeded both ways first
(uniform buffer reads `BLANK`; a failed read reports `PROBE FAILED`, which it did when busybox `od`
turned out not to support `-A`/`-t`).

### ⛔ Kernel panic at 4.0 s in `mmc_rescan` — the hang has a name

**2026-08-12.** A routine `systemctl reboot` did not come back. The board sat dead for >5.5 minutes;
the owner read the console off the attached monitor. Transcribed from that photograph, which is the
only copy — nothing reached the journal, because this is 200 ms before journald exists:

```
3.940  mmcblk0: mmc0:5048 DDINC 28.9 GiB
4.001  8<--- cut here ---
4.010  Unable to handle kernel paging request at virtual address c0f9076c when execute
4.025  [c0f9076c] *pgd=00e0040e(bad)
4.035  Internal error: Oops: 8000000d [#1] ARM
4.055  CPU: 0 PID: 54 Comm: kworker/0:2   Not tainted 6.6.63 #1
4.068  Hardware name: BCM2835
4.077  Workqueue: events_freezable mmc_rescan
4.088  PC is at softirq_vec+0x18/0x28     LR is at complete+0x48/0x74
4.109  pc : [<c0f9076c>]  lr : [<c006305b>]  psr: 60000113
       r0 : ffffffea   r4 : c0f6caac
4.351  Process kworker/0:2 (pid: 54, stack limit = 0x6e7064bd)
       Code: bad PC value
4.462  Kernel panic - not syncing: Fatal exception in interrupt
```

**It dies at the moment the SDIO bus enumerates.** On a healthy boot the next line after
`mmcblk0: ... 28.9 GiB` at 3.94 s is `mmc1: new high speed SDIO card at address 0001` at 4.002 s.
The panic lands in that gap, in the `mmc_rescan` workqueue, having branched to an unmapped address
(`Code: bad PC value`) — a corrupted function pointer, in interrupt context, which is why it is a
panic rather than a survivable oops.

Observed **once in roughly 30 boots** across this session's measurement runs.

**This probably renames the "network hang".** `STATUS.md` (kiosk-reference) §"THE HANG IS THE NETWORK
PATH, NOT THE SD CARD" attributes the freezes to `brcmfmac`/SDIO under sustained receive, on `mmc1`.
This panic is the same controller with **no network traffic at all** — it happens before userspace
exists. Two symptoms, one subsystem. It also accounts for the 2026-08-12 08:35 freeze during a
trivial SSH session, which the receive-volume theory could not explain. The honest reframing is
**"the SDIO/mmc path is unstable"**, and the sustained-receive finding becomes one trigger rather
than the mechanism.

### Nothing in userspace can recover a 4-second panic — KILLED two proposed fixes

Both were proposed during this session and both are dead on the timing:

| Mechanism | Active from | Covers a 4.0 s panic? |
|---|---|---|
| hardware watchdog (`RuntimeWatchdogSec`) | 5.196 s, when systemd arms `/dev/watchdog0` | **no** |
| `kernel.panic` via `/etc/sysctl.d/` | ~11.7 s, when `systemd-sysctl` runs | **no** |
| `panic=10` on the kernel command line | from kernel entry | **yes** |

`RebootWatchdogSec` is also irrelevant here — it covers the shutdown window, and this panic is on the
way *up*. The only mechanism that reaches an early panic is the kernel command line, which lives in
`/boot`.

That puts the project's own rule in tension with its purpose: *"never modify `/boot`"* exists to
avoid a physical trip, and here the **absence** of a `/boot` parameter is what caused one. Resolved
in both places: `CMDLINE:append = " panic=10"` in the build tree for future images (see
[`image-migration.md`](image-migration.md)), and — on the owner's explicit instruction, with the unit
on a bench — ` panic=10` appended to `/boot/cmdline.txt` on the card in the device.

### `panic=10` PROVEN by making it fire — 60 s unattended recovery

The project has been burned before by fixes that were written up as though they existed, so this one
was tested rather than inspected. `echo c > /proc/sysrq-trigger`, twice, on a board whose
`rauc-mark-good` had already run so the test could not consume a boot attempt:

| | |
|---|---|
| Recovery | **60 s** from panic to SSH answering — 10 s timeout plus a normal ~50 s boot |
| It really rebooted | `boot_id` changed, `uptime` reset, and `kernel.sysrq` was back to its default **16**, so the `echo 1` the test needed did not survive |
| Nothing was damaged | counters `3/3`, both slots `good`, kiosk active, no ext4 errors |

**The first measurement of this was thrown away.** The poll loop started before the trigger returned
and reported "back after 1 s", which is impossible for a board that takes ~50 s to boot. Re-run with
the host clock as the reference and a poll that compares `boot_id` rather than mere reachability.
Quoting the first number would have claimed a one-second recovery.

**It does not fix the panic**, it bounds it: an indefinite hang needing a person becomes a 60-second
outage. The SDIO instability underneath is untouched and still the open question.

### Sustained TX hangs the board too — the hang is NOT receive-specific

`meta-wisekiosk` #5 lists RX-vs-TX as unverified. Run here, 133 MB `dd if=/dev/zero` from the device
to the workstation over SSH — the mirror of the documented Test B:

| Run | Duration | Rate | Result |
|---|---|---|---|
| 1 | 70 s | 1.90 MB/s | **survived** |
| 2 | 95 s | 1.40 MB/s | **HUNG** |
| 3 | 354 s | 0.38 MB/s | **HUNG** |

Both hangs recovered unattended; counters stayed `3/3` and the kiosk came back on its own.

**I nearly published the opposite conclusion.** Run 1 survived, and a single clean 133 MB transmit
against a documented receive that hung in 11 s having moved 0 bytes looked like a clean asymmetry —
strong enough that I wrote it up as "receive-specific" before repeating. Runs 2 and 3 killed it. The
rate argument that made run 1 look decisive (RX hung even when rate-limited to 1 MB/s, TX survived at
1.9 MB/s) was real and still wrong, because the effect is **probabilistic, not deterministic**.

**Corrected characterisation.** Three independent observations now:

| Observation | Traffic | Outcome |
|---|---|---|
| Test B, 133 MB inbound | sustained RX | hung in 11 s |
| rate-limited inbound, 1 MB/s | slow RX | hung on the first chunk |
| **this test, 133 MB outbound ×3** | **sustained TX** | **2 of 3 hung** |
| **panic at 4.0 s in `mmc_rescan`** | **none — no userspace yet** | **panic** |

So it is not the receive path, and it is not network volume. **Sustained SDIO activity in either
direction can wedge this board, and the same controller also panics at enumeration with no traffic at
all.** The one thing common to every case is `mmc1`/SDIO.

The chunk-and-pause workaround (32 × 4 MB with 4 s gaps) remains the only shape known to move a bundle
reliably, and its mechanism — breaking continuity — is consistent with this.

### ⛔ The chunk-and-pause workaround did NOT reproduce — OTA blocked at 64/130 MB

**2026-08-12 afternoon.** Attempted the first OTA of the trimmed image. The bundle reached **64 MB of
130 MB** and then stopped converging: each attempt lands one chunk, the board hangs, and the unsynced
append is lost on reboot, so the file rolls back. Net progress across the last four runs is **zero**.

| Run | chunks landed | transfer failures |
|---|---|---|
| 1 | **14** | 2 |
| 2 | 0 | 1 |
| 3 | 2 | 1 |
| 4 | 0 | 3 |
| 5 | 1 | 1 |

**This contradicts the documented workaround.** `STATUS.md` (kiosk-reference) §"THE WORKAROUND
WORKS" records 32 × 4 MB with 4 s pauses moving 133 MB with **zero hangs** on 2026-08-12 overnight.
The same shape today, and gentler variants (6 s and 8 s pauses), hang repeatedly once the destination
passes ~60 MB. Whatever made it work last night is not a property of the chunk shape alone.

**`sync` per chunk makes it strictly worse.** Unsynced, the first run moved 14 chunks in a row. With
a `sync` after each append — added to make resume durable — it hung on the *first* transfer of every
subsequent run. Forcing 4 MB of synchronous SD writes per chunk provokes the very subsystem that
panics in `mmc_rescan`.

**Unsynced appends are lost on a hang, so a "verified" chunk can silently disappear.** The read-back
md5 check passed for chunks 16 and 17 because it read them back out of *page cache*; the board then
hung and the file rolled back from 68 MB to 60 MB. Resume must re-read the destination's real size
after every failure — it must never trust its own record of what it sent.

**Nothing was damaged.** After all of it: `BOOT_ORDER=B A`, `BOOT_A_LEFT=3`, `BOOT_B_LEFT=3`, both
slots `good`, kiosk active with 3 surf processes, no FAT errors. Every hang self-recovered, which is
`panic=10` and the watchdog earning their place — this attempt would have needed a person at the
device on every one of ~8 hangs otherwise.

**Stopped deliberately rather than continued.** Each hang is an unclean shutdown on the FAT that
holds `uboot.env`, and `STATUS.md` (kiosk-reference) §"Open items" already flags repeated unclean
mounts as how that partition eventually corrupts — which is a physical-access recovery. Grinding a
non-converging loop against that risk is a bad trade.

**The delivery path is the blocker, not the image.** The image is built and verified; a flashable
`.wic.bz2` exists. Tier-1 OTA on this board is gated on understanding the SDIO instability, and this
attempt is evidence the chunk workaround is not a reliable substitute for that understanding.

### Three script defects worth remembering, all caught by verification rather than by review

1. **`stat -c%s` on a symlink returns 52** — the length of the target's name. The transfer computed
   one chunk instead of 32 and shipped 4 MB. Caught only by the end-to-end md5. Use `stat -Lc%s`.
2. **`dd bs=1 count=$OFF` is one syscall per byte.** Used to roll a partial file back to a chunk
   boundary, at 60 MB that is 60 million syscalls; it timed out and the following `mv` replaced a good
   file with a partial one. Offsets are chunk-aligned, so `bs=1M` is correct — and the `mv` must be
   guarded on the rolled-back copy being exactly the size requested.
3. **`local off=$1 mb=$((off / 1048576))` dies under `set -u`.** Arithmetic in a single `local` is
   expanded before the earlier assignment takes effect, so `off` is unbound. Split the statements.

### The recovery fired on a real fault, unattended — observed, not staged

During a 2-cycle collection run, boot `2a667247` ended mid-air at 11:30:11 on a routine SSH poll with
**no shutdown sequence** — the same signature as the 08:35 freeze and the 4 s panic. Its sample file
was never written, so the sampler died with the board.

The next boot, `be75887b`, appeared **without any reboot being issued**: the run was `collect-boots.sh 2`
and both of its reboots are accounted for by the two prior boots. So the board recovered on its own,
from a spontaneous fault, and the collection carried on.

**Which mechanism fired is not determinable** from these timestamps — `panic=10` predicts ~60 s and
the watchdog ~64 s, the clock jumps mid-boot, and the estimates disagree by ~20 s. Recorded as
"recovered unattended", not attributed.

### Blacklisting four more pre-gate modules — no measurable gain

`vc_sm_cma`, `raspberrypi_gpiomem`, `uio`, `uio_pdrv_genirq` all load between `cfg80211` (17.1 s) and
`brcmfmac` (28.1 s), so they looked like more of the same win. Measured n=3: `wlan0` at **28.87 s**
against **32.30 s** — but the original four-module blacklist already delivered −3.33 s, and the
baseline had shifted 0.33 s from the journald fix. **The extra four are worth ~0.1 s.**

Recorded because it is the kind of experiment that looks obviously worth repeating: the mechanism
(work ahead of `brcmfmac` in udev's queue) is real, but the camera and audio stack was essentially
all of the mass. Do not re-run it expecting more.

### The journald cap fix recreated the bug it fixed — INVALID first attempt

Raising `SystemMaxUse` to 150 MB stopped early-boot entries being dropped, and cost ~0.5 s of boot,
because the flush at ~25 s scales with **current journal size** and sits before the `wlan0` gate.
The correction — vacuum to 32 MB and cap at 32 MB — put usage at 31 MB against a 32 MB cap and
**dropped early-boot entries again on the very next boot** (247 journal lines instead of ~690).

The original failure was never "the cap is too small", it was "there is no free space to flush into".
A loose cap with a small working set gives both: `SystemMaxUse=64M` + vacuum to ~20 MB → flush
1.12–1.20 s (from 1.91–2.02 s) with early boot fully captured.

### Journal wall-clock is unusable for boot timing — confirmed again

On the boot beginning `08:36:43`, `Reached target System Initialization` is stamped `08:34:25` —
before the boot started. This board has no RTC and no `fake-hwclock`; every boot starts in the past
and only NTP moves the clock forward, so early entries carry a timestamp from before `timesyncd` has
caught up. Use `-o short-monotonic`, or `/proc/uptime`.

---

## This session, 2026-08-12 evening

### Parallelising `wpa_supplicant` made the boot worse — KILLED by direct experiment

[`boot-profile-yocto.md`](boot-profile-yocto.md) §"What this rules out" derives a scheduling ceiling
from idle-time accounting alone and had never tried an actual reorder. This session did: a
`DefaultDependencies=no` drop-in on `wpa_supplicant`, so it starts as soon as `wlan0` exists rather
than waiting on `sysinit.target`/`basic.target`.

| | earlywifi (before) | earlywpa (after) | Δ | overlap |
|---|---|---|---|---|
| network online | 28.51 s | 22.97 s | −5.55 s | no |
| `surf` exec | 31.54 s | 40.28 s | **+8.74 s** | no |

Network online moved 5.55 s earlier, exactly as intended. `surf` exec moved **8.74 s later** — net
**3.2 s worse**, reproducible to the hundredth of a second across three boots (40.24 / 40.28 /
40.34 s). `kiosk.service` was released 6.8 s earlier (24.10 s vs 30.89 s), into a machine still
running dbus, journal flush, RAUC mark-good, RF-kill and the tail of udev, and took **15.5 s longer to
start** once released (16.2 s vs 0.65 s to `surf` exec) — because it was now competing with all of
that for the one core, against the heaviest CPU consumer in the boot (`kiosk.service` alone:
49 356 ms).

**Dead as a hypothesis: that releasing work earlier into this boot, without removing any of it, buys
time.** It does the opposite — it converts a wait into a queue, exactly the failure mode the owner
named before any of this was measured. Both changes were reverted and the device confirmed back at
the `udevrules` state (arm `confirm`, n=1): `brcmfmac` 21.94 s, `wlan0` 24.92 s, network online
28.53 s, `surf` exec 31.56 s — matching the pre-experiment `udevrules` numbers.

### Bluetooth kernel modules still load and probe, despite the package removal

[`service-changes.md`](service-changes.md) records Bluetooth as shipped-removed at the package level
(`MACHINE_FEATURES`/`DISTRO_FEATURES`). The kernel modules still load anyway. Observed at
22.5–23.1 s: `Bluetooth: Core ver 2.22`, `hci_uart_bcm serial0-0`, `Bluetooth: hci0: BCM43430A1`, then
four failed firmware-patch lookups for `BCM43430A1.hcd`. The `bluez` userspace is gone, but the
in-kernel Bluetooth stack and the UART attach driver are not — they load and probe, pre-`basic.target`,
find no firmware (removing Bluetooth also removed the BT patch — see the "Lifeline check" note in
[`image-migration.md`](image-migration.md) §"Migrated into the build tree, 2026-08-12 — verified in a
built image"), and fail cleanly.

**Not costed.** Whether this is worth a further kernel-module blacklist — the same mechanism as the
camera/audio trim in [`boot-profile-yocto.md`](boot-profile-yocto.md) — has not been measured. It may
sit inside the run-to-run noise, or it may be another case of work queued ahead of `brcmfmac`. Recorded
so the next session does not assume the Bluetooth removal is complete.

## Mapping the SDIO hang boundary, 2026-08-13

The delivery shape had never been tuned — 2 MB chunks with a 4 s receive pause and a 3 s sync pause
were the first parameters that worked, and were kept because they worked. That put ~7.3 min of pure
sleeping into a 20 min delivery, and it was never established which of chunk size, receive pause or
sync pause the board actually cares about.

**The rig was validated by seeding the defect first.** 24 MB as one continuous stream: **HUNG,
watchdog recovered, 0 bytes delivered, 57 s.** Without that, every "survived" below would be
consistent with a test that transfers nothing.

| shape | volume | elapsed | result |
|---|---|---|---|
| continuous (defect seed) | 24 MB | 57 s | **HUNG**, 0 B delivered |
| chunk 8 MB, rx 2 s, sync 2 s | 24 MB | 32 s | survived, complete |
| chunk 8 MB, rx 2 s, sync 2 s | 40 MB | 52 s | survived, complete |

**806 KB/s against the shipped shape's 104 KB/s — about 7.7× faster.** So the board does not need
2 MB chunks or a 4 s pause; both were far more conservative than the failure requires. What it needs
is *discontinuity*, which is consistent with everything already known: the trigger is continuous
receive, not rate and not volume.

> **This does not identify the mechanism**, and nothing here should be read as understanding it. It
> bounds the parameters, which is a different and weaker claim. A shape that survives 40 MB is not
> proven at 125 MB — the shape this project previously trusted survived to 60 MB before failing.

### Two test rigs reported "survived" while measuring nothing

Both were caught by checking the byte count rather than the verdict, and both are the same shape as
the `dd conv=fsync` failure recorded above.

- **`nc` listener on the device never started.** busybox `nc` here is built client-only —
  `Usage: nc [IPADDR PORT]`, no `-l`. The connection failed instantly, `elapsed=0s`, and the rig
  printed **survived**.
- **`nc -l -p 9999` on the workstation is invalid.** OpenBSD netcat rejects `-p` with `-l`, so the
  listener never bound. The device sat for 136 s receiving nothing, and the rig printed **survived**.

### The protocol question is ANSWERED: it is not SSH -- hypothesis dead

Tested 2026-08-13 once a non-SSH path existed. The backend container already serves static files on
port 8080, which crosses WSL2 because the kiosk itself uses it, so the device can pull a payload over
plain HTTP with no crypto in the data path. No port-forward or second host was needed after all.

Paired arms, same image, same 120 MB, both to `/dev/null` so disk is excluded, minutes apart:

| arm | run 1 | run 2 |
|---|---|---|
| HTTP (`wget`) | survived, 27 s | **HUNG** (stalled to a 300 s timeout) |
| SSH | **HUNG**, 48 s | **HUNG**, 51 s |

**Plain HTTP wedges the board too.** The hypothesis was that sshd decrypting at high throughput on a
1 GHz ARM11 starves something, which would have been a different defect with a different fix. One
HTTP hang kills it.

Two things this does establish:

- **The defect is protocol-independent**, which strengthens the existing "sustained receive" model
  rather than replacing it. Rate is not the discriminator either: the HTTP arm ran *faster*
  (4.6 MB/s against ~2.5) and still hung on the second attempt.
- **It is stochastic.** The same command survived once and hung once. That is why the 27 s survival
  looked decisive and was not.

> **This was very nearly written up as "the hang is SSH-specific".** The first HTTP arm survived, the
> paired SSH arm hung, and on that n=1 pair the conclusion looked clean enough to rewrite the
> project's model of the defect. It survived only because the arms were repeated before anything was
> published. On this board a single observation is worth nothing in *either* direction -- that rule
> already existed for boot timings and applies just as hard to failures.
>
> Two earlier arms in this same session were also worthless for the opposite reason and were nearly
> counted: 24 MB over HTTP (7 s) and 24 MB over SSH to `/dev/null` (9 s) both "survived" while
> finishing *inside* the 10-20 s window in which hangs occur. A test shorter than the failure window
> cannot observe the failure.

**Consequence for delivery design:** an HTTP pull updater needs chunk-and-pause exactly as much as
SSH does. `rauc-hawkbit-updater` streams continuously, so it is not made safe by not being SSH.

## The wedge, characterised 2026-08-13 — the documented model is wrong

First evidence ever obtained *from* the dying board. The journal lives on `/data` on the same card
and dies with it, which is why this failure has had no mechanism for two days. The witness is a
sampler that **`fsync`s every line**, so whatever it wrote up to ~0.5 s before death survives the
watchdog reset.

### What the board looks like as it dies

Every metric is healthy right up to the final sample, then nothing:

- **`rx_dropped` and `rx_errors` are 0** throughout. The driver reports no error at all.
- **`MemFree` is flat** (~212 MB). Not memory.
- **Timer interrupts keep incrementing normally** to the last line. The CPU is alive and servicing
  interrupts; death is instantaneous, not a decay.
- `mmc1` (SDIO, the WiFi chip) runs 2 700–4 700 interrupts/s; `mmc0` (the SD card) is idle by
  comparison — 4 per sample, which is the probe's own `sync`.

### Three hypotheses killed

| hypothesis | test | result |
|---|---|---|
| **Under-voltage / supply sag** | `get_throttled` sampled throughout; bit 16 is sticky-since-boot so even a brief sag registers | **`thr=0` on every sample, including the last.** Dead |
| **SSH-specific (sshd decryption starving the core)** | paired 120 MB arms, HTTP vs SSH, both to `/dev/null` | HTTP hangs too. Dead — recorded above |
| **CPU starvation** | same transfer with the kiosk stopped, and over HTTP which has no crypto | Hangs at **~12 % idle**. Dead |

The CPU ladder is worth keeping because it is monotonic and still does not predict the outcome:
SSH with the kiosk running 0 % idle → hung; SSH with it stopped ~2 % → hung; HTTP ~12 % → hung.

### KILLED: "it is *continuous* receive, not rate and not volume"

That sentence is this project's standing explanation and it is **wrong**.

A **continuous, uninterrupted 72 MB TCP stream survived 90 s** — no pauses anywhere — at ~0.83 MB/s,
fed as 64 KB writes. Continuity is not the trigger.

### KILLED: burst size — refuted by the delivery path we already run

> **The section below is superseded. Read this first.** It concluded that
> instantaneous burst size predicts the wedge. Two things refute it:
>
> 1. **The OTA uses 8 MB bursts and works every time** — 125 MB, zero hangs, in
>    production. If burst size were the hazard, 8 MB bursts would be lethal when
>    512 KB bursts died at 3 MB. This evidence was already in this repository
>    when the burst model was written, and was not checked against it.
> 2. **Capping the TCP receive window to 64 KB did not help: 3 of 3 kernel
>    deaths.** A 64 KB window bounds in-flight data to 64 KB by construction, so
>    if burst size were the variable this would have been the fix.
>
> Recomputed as **average sustained receive rate**, every arm including the OTA:
>
> | shape | avg MB/s | outcome |
> |---|---|---|
> | OTA, 8 MB bursts + 4 s pauses | **0.35** | works, repeatedly, in production |
> | 64 KB / 50 ms | 0.19–0.83 | survived |
> | 256 KB / 100 ms | 0.90 | died at 89 MB |
> | 512 KB / 100 ms | ~5 | died at 3 MB |
> | unthrottled | 2.6–4.8 | died 3 of 4 |
>
> That is monotonic and it explains the OTA. **The boundary is somewhere near
> 0.9 MB/s**, and the 64 KB vs 256 KB pair the burst model rested on is
> 0.83 vs 0.90 — a straddle of that boundary, not a burst-size effect.
>
> Note also that "rate" was dismissed earlier in this log on the strength of a
> single HTTP arm that survived at 4.6 MB/s — **the same arm that hung on its
> repeat.** Rate was never actually excluded; it was excluded on an outlier.

### Device-side fixes attempted, 2026-08-13

Sender-side throttling is not acceptable as the fix (owner, 2026-08-13): it only
holds while every future sender cooperates, and a fleet updater or someone's
`scp` will not. The board has to survive a hostile sender.

| lever | result |
|---|---|
| **TCP receive window** capped to 64 KB (`tcp_rmem`, `rmem_max`) | **3 of 3 kernel deaths.** Bounds in-flight burst, not average rate — on a 2 ms LAN a 64 KB window still permits many MB/s |
| **PHY bitrate cap** (`iw set bitrates legacy-2.4 11`) | **not supported** by brcmfmac: `Operation not supported (-95)` |
| **tc ingress policing** | the kernel modules are all present — `sch_ingress`, `act_police`, `sch_tbf`, `cls_u32` — but the **`tc` binary is not in the image**, and `iproute2` is not built. Needs `iproute2-tc` added, so it cannot be validated until an image carries it |

Ingress policing is the remaining candidate and the only one that is both
on-board and sender-agnostic: it drops inbound above a set rate regardless of
protocol or who is sending. A policer below the boundary — 4 Mbit/s ≈ 0.5 MB/s,
against an OTA that already runs at 0.35 — would also *speed up* delivery rather
than cost anything.

> **Untested.** Everything above about policing is reasoning, not measurement.
> The threshold it would be set from is itself n=1 per arm.

### Superseded: what was thought to predict it

| shape | average rate | delivered before death | outcome |
|---|---|---|---|
| 64 KB every 50 ms | 0.83 MB/s | 72 MB over 90 s | **survived** |
| 256 KB every 100 ms | 0.90 MB/s | 89 MB at 98 s | HUNG |
| 512 KB every 100 ms | — | **3 MB** | HUNG |
| unthrottled | 2.6–4.8 MB/s | 12–68 MB | HUNG |

The first two rows have nearly the same *average* rate and opposite outcomes, so the average is not
the variable. Burst size gives a clean dose-response: 64 KB survives, 256 KB dies late, 512 KB dies
almost immediately. The hazard rises with how much is delivered per burst.

**This reframes the workaround.** Chunk-and-pause does not work because of the pauses; it works
because it holds the *average* down while the bursts are separated enough for the chip to drain. A
sender that simply keeps its writes small is a different and simpler shape that also works.

> **n=1 per arm.** The 64 KB / 256 KB pair is the load-bearing comparison and deserves repeating
> before anything is designed around it. The failure is stochastic — the same unthrottled command
> survived once and hung twice — so single arms are weak evidence in both directions, which is
> exactly the trap that produced the "SSH-specific" claim above.

### There are TWO failure modes, and the watchdog has been hiding the difference

Found by widening `RuntimeWatchdogSec` from 14 s to 60 s — nobody had ever let the board sit long
enough to find out what it does on its own.

| trial (120 MB, unthrottled) | transfer | outcome |
|---|---|---|
| A | stalled to a 200 s cap | **STALL ONLY** — reachable immediately after, `boot_id` unchanged |
| 1 | 81 s | kernel death, reset |
| 2 | 121 s (hit the cap) | **STALL ONLY** — `boot_id` unchanged |
| 3 | 47 s | kernel death, reset |

**3 deaths and 2 stall-onlys in five trials.** In stall-only mode the board never dies: the transfer
stops moving, the system is severely degraded, and then it comes back by itself.

The consequence is that **the shipped 14 s watchdog turns a recoverable stall into a 113 s reboot.**
In stall-only mode the system is alive but too starved to pet the watchdog inside 14 s, and it does
pet it inside 60 s. For a kiosk, a stall the viewer may not notice is strictly better than a reboot
with a 43 s boot behind it.

> **Not a recommendation to change it yet, and n=5.** Widening the watchdog also lengthens recovery
> from the *genuine* deaths, which are the majority here (3 of 5). The trade is real and it is the
> owner's, not something to slip into an image.

> **An earlier draft of this section said the watchdog "has been causing the reboots, not rescuing
> them."** That was wrong and came from a single trial where the transfer stalled until the test's own
> timeout and the board was alive throughout — which is not recovery from a wedge, it is a run that
> never wedged. The trials above were run precisely to stop that inference from standing.

### Still not known

The mechanism. Nothing in the driver's own counters moves before death, so this is either inside the
BCM43430 firmware (7.45.98 TOB, from 2021) or in `brcmfmac`'s SDIO transfer path, and neither is
visible from userspace. `brcmfmac` on this build exposes only three module parameters
(`alternative_fw_path`, `debug`, `roamoff`), so there is little to tune from here.

## ⛔ RETRACTED SAME DAY: "the chip stops signalling" was my own sender starving

**Read this before the section below it, which stands only for the parts that survive.**

The load-bearing claim — that `mmc1` interrupts falling to the idle rate proves the BCM43430 stops
delivering — **is not supported**. There is a mundane alternative I failed to exclude: if the
*sender* stops transmitting, the chip has nothing to signal and the interrupt rate falls to idle for
exactly the same reason. The two are indistinguishable from the receiver, and the rig watched only
the receiver.

**What caught it.** Sampling `ss -ti` on the sender during a device-side dead window:

| field | value at rig t=156, mid-"stall" | meaning |
|---|---|---|
| `unacked` | **absent — zero** | nothing in flight; everything sent was acknowledged |
| `lastsnd` | **3552 ms** | the sender had not transmitted for 3.5 s |
| `retrans` | `0/2` — **2 in 24 MB**, unchanged across the stall | not loss; no RTO fired |
| `ssthresh` | 46, never moved | no congestion event |
| `rwnd_limited` / `sndbuf_limited` | absent | not blocked by either window |

A sender with nothing outstanding, no retransmits and no window limit has not been throttled by the
network. It simply produced no data.

**Why.** The pacing loop is `dd` + `sleep 0.1` — a fork per chunk, ten times a second — run on a host
sitting at **load average 28** under a WebKit build. Measured directly, with no device and no network
in the path at all, that loop delivered **29 KB/s against a nominal 640 KB/s**: 22× slower than
requested, in bursts separated by multi-second gaps. That is the entire "oscillating delivery"
pattern, and it is on this workstation.

### What survives, and what goes with it

**Survives — measured on the device, independent of the sender:**

- **The board really does die.** Three reboots today with a changed `boot_id`; sender starvation
  cannot reset a board.
- **Every `/sys/kernel/debug/mmc1/err_stats` counter is 0** after a boot that stalled: no command
  timeout, no CRC, no data timeout, no unexpected IRQ.
- **`sysrq w` finds no blocked task**, twice, and the `brcmf_wq` worker is parked in `schedule()`.
- **No kernel oops or panic message has ever been captured** before a death.
- The two rig defects and their fixes, below, are unaffected — and this retraction is a third
  instance of the same class.

**Retracted:**

- "The firmware stops delivering frames." Unproven. The IRQ-drop evidence has a sender-side
  explanation that was never excluded.
- **Every rate threshold measured today** — the 375 KB/s onset, the ramp steps. Those numbers
  describe this workstation's scheduler, not the board.
- **The pre-existing "average rate boundary ≈ 0.9 MB/s" model is now also suspect**, because
  `doseresp.sh` paced with the same fork-per-chunk `dd` + `sleep` shape. That model had already
  replaced the retracted burst-size model; both now rest on arms that may have been sender-limited.
  The one arm not built that way is the unthrottled `cat file | ssh` — a single process, no
  per-chunk fork — and that arm did kill the board.

### The method fix, which is the actual lesson

**A receiver-only instrument cannot see a sender-side stall.** Every future arm must sample the
sender, and a device stall may only be recorded when the sender is demonstrably pushing:

> `unacked > 0` **and** `lastsnd` small, while the device's byte counter is flat.

Anything else is unattributable. Additionally: **do not pace with a fork-per-chunk loop**, and do not
run timing-sensitive network arms against a host under heavy build load — check `/proc/loadavg`
first and record it with the result.

This is the same failure the bottom of this document names nine times: *a check whose broken state is
indistinguishable from a passing state.* The rig was built carefully, seeded in both directions, and
proven to capture what it claimed — and it was still pointed at only one end of the wire.

## REFINED: the fault is in the softirq network receive path, not inside brcmfmac

Two follow-up experiments narrowed the root cause below. **Read this before the section under it** —
the workqueue name in the oops is the packet *source*, not the faulting code.

### 1. Slab debugging is clean — the skbs are not being overrun

`CONFIG_SLUB_DEBUG=y` is compiled in with `SLUB_DEBUG_ON` off, so debugging was enabled at boot with
no rebuild: `slub_debug=FZPU,skbuff_head_cache,kmalloc-cg-2k,kmalloc-2k` (redzone, poison, sanity,
user tracking). It applied — `kmalloc-2k` object size went **2048 → 6144**, `skbuff_head_cache`
184 → 288.

The crash reproduced **and slub reported nothing**: no redzone violation, no poison overwrite, no
`slab_err`. Over 66 s of heavy traffic there are many alloc/free cycles on those caches, so this is
meaningful evidence against a buffer overrun or use-after-free of the skb data.

### 2. The jump target is CONSTANT, and the call chain resolves

`PC = 0xc1137c58` in **both** crashes, while `LR` differed (`c49eb964`, then `c547bce4`). Random
corruption gives a random target; the same target from different call sites means a deterministic
computed jump.

The oops printed no backtrace — the frame pointer was garbage — but the raw stack dump carries
kernel text addresses. Resolved against `/proc/kallsyms` from the running kernel:

```
call_with_stack+0x18                 ARM softirq stack switch
handle_softirqs+0xc4
net_rx_action+0x298
__napi_poll.constprop.0+0x34
process_backlog+0x54
__netif_receive_skb_one_core+0x5c    <-- deliver_skb() -> pt_prev->func()
ip_rcv+0x0        ip_packet_type+0x0
```

`__netif_receive_skb_one_core+0x5c` is the `deliver_skb(skb, pt_prev, orig_dev)` indirect call, and
both `ip_packet_type` and its correct handler `ip_rcv` are on the stack. So the kernel calls a
protocol handler pointer and lands on garbage, **in generic NET_RX softirq code**. That also explains
"Fatal exception in interrupt" despite `brcmf_sdio_dataworker` being a workqueue: the softirq ran on
top of the worker after `netif_rx`.

**Where the target is:** `0xc1137c58` = `_end + 0x111660`, about 1.09 MB past the end of the kernel
image — not in any symbol, not module space (`bf……`), not the vector page. That is the region the
early allocator uses (percpu, early bootmem), which is deterministic across boots, matching the
constant PC.

### What this means

brcmfmac is the packet *source*, and the rate dependence is simply how much traffic is pushed through
the receive path. The faulting code is generic. The closest published neighbour is
**raspberrypi/linux #4466** — Pi Zero W, ARMv6, instruction-fetch abort with an unresolved PC in the
network receive path, never diagnosed.

**No published bug matches this signature.** A parallel review searched the brcm80211 git history,
raspberrypi/linux issues and the web; report preserved at
[`evidence/brcmfmac-bug-research.md`](evidence/brcmfmac-bug-research.md). It flags an honest gap:
`lore.kernel.org` and `git.kernel.org` both refuse automated fetches from this host, so the
linux-wireless archives and kernel bugzilla are **unsearched**.

### Two real brcmfmac defects found on the way, worth taking regardless

Verified in this tree, and **not** claimed to be this crash — their failure mode is a data abort near
address 0 with a resolvable PC, which is a different fault class:

| fix | what | status in 6.6.63 |
|---|---|---|
| `857282b819cb` | scatterlist `nents` 35 → 64 (rx glom can exceed the table) | **missing**; backported as `07c020c6d14d`, first in **v6.6.66** — two point releases away |
| `52e8726d6782` | the `if (!sgl)` guard in `brcmf_sdiod_sglist_rw()` | **missing, and never backported** to 6.6.y — a kernel bump will not deliver it |

Measured on the device: at a safe 0.4 MB/s the mean glom depth is **4.8 packets per frame**
(2 298 frames / 10 967 packets, `rxglomfail: 0`) — far below the 35-entry table, so that defect is
not being approached at safe rates. Counters live at
`/sys/kernel/debug/ieee80211/phy0/counters`.

### Also killed cheaply

**zram / zsmalloc**: loaded but **swap used = 0**, so it is inert. A Zero W memory-stress lead was
dismissed for the cost of one command.

## ⛔ ROOT CAUSE, 2026-08-13: `brcmf_sdio_dataworker` jumps to a corrupted address

**It was never a lockup.** Captured by ramoops after an owner-authorised `/boot` write. Full text in
[`evidence/oops-brcmf-sdio-dataworker-2026-08-13.txt`](evidence/oops-brcmf-sdio-dataworker-2026-08-13.txt).

```
Unable to handle kernel paging request at virtual address c1137c58 when execute
[c1137c58] *pgd=0100041e(bad)
Internal error: Oops: 8000000d [#1] ARM
CPU: 0 PID: 33 Comm: kworker/u3:0
Workqueue: brcmf_wq/mmc1:0001:1 brcmf_sdio_dataworker [brcmfmac]
PC is at 0xc1137c58     LR is at 0xc49eb964
r0/r5 = c23ea3c0   slab skbuff_head_cache, offset 0, size 184
r4    = c20b0800   slab kmalloc-cg-2k, offset 0, size 2048
Code: b62fce94 b62fce8c 00000000 b62fce6c (b62fce74)
Kernel panic - not syncing: Fatal exception in interrupt
```

**Reading it:** oops code `8000000d` is an *instruction fetch* abort — the CPU tried to execute at an
address with a bad page directory entry. Neither PC nor LR resolves to a symbol, and the bytes at PC
(`b62f...`) are userspace-range addresses, so it is executing **data**. The workqueue line names the
code exactly: **`brcmf_sdio_dataworker`, the brcmfmac SDIO receive worker**, with a live `sk_buff`
and a 2 KB skb data buffer in its registers.

That is **memory corruption in the brcmfmac SDIO receive path** — a clobbered function pointer or
return address — not a deadlock, not an interrupt storm, not firmware wedging. Fatal in interrupt
context, so it cannot be recovered and panics immediately.

### ⚠ This overturns three of my own conclusions from earlier today

1. **"The CPU stops servicing timers and softirqs."** Wrong mechanism, correct observation. There is
   no starvation period at all — the kernel dies instantaneously. The detectors printed nothing
   because there was never a lockup to detect.
2. **"The hardware watchdog resets it ~16 s after the kernel stops."** No. It is `panic=10` plus boot
   time. The watchdog reasoning was a plausible chain built on a real measurement and it was wrong.
3. **`LOCKUP_DETECTOR` / `WQ_WATCHDOG` were never going to fire.** The whole kernel-bisect exercise
   was aimed at a lockup that does not exist. It was not wasted — it produced the boot-failure
   bisect and the 3-minute kernel test loop — but the premise was mistaken.

### The structural lesson: a userspace witness cannot capture a panic

Every instrument built over two days — the fsync-per-line `/dev/kmsg` witness, the 2.5 Hz interrupt
tracer, the sysrq rig — was **incapable of catching this by construction.** After a panic no
userspace process is ever scheduled again, so a userspace reader of `/dev/kmsg` can only ever record
what happened *before* the fatal instant, no matter how aggressively it syncs.

Only an **in-kernel, synchronous** persistence path can capture a panic. That is precisely what
pstore/ramoops is. The two days of fsync engineering were careful, well-tested, verified in both
directions — and pointed at a target they could not physically reach.

### What made the capture work

- `CONFIG_PSTORE=y`, `CONFIG_PSTORE_RAM=y`, `CONFIG_PSTORE_CONSOLE=y` were **already in the shipped
  kernel**. No rebuild was needed.
- The stock upstream `ramoops-overlay.dts` ships in the kernel tree and targets the base DTB's
  `rmem` symbol, which `bcm2708-rpi-zero-w.dtb` exports — so memory is reserved properly through
  device tree, with **no `mem=` hacking**.
- Compiled standalone with `dtc` (no kernel rebuild), placed at `/boot/overlays/ramoops.dtbo`, with
  one additive line in `config.txt`. `cmdline.txt` was never touched.
- **Proven on a known event before being trusted on the unknown one**: a deliberate
  `echo c > /proc/sysrq-trigger` panic was captured first, confirming both that RAM survives a reset
  on this board and that the console zone carries userspace-written `/dev/kmsg` telemetry.

### The CPU stops servicing timers, and that is the observability ceiling

The diagnostic kernel was bisected on the device (~3 min per arm, no OTA — copy a `uImage` into the
inactive slot's rootfs `boot/` and `rauc status mark-active`):

| kernel | boots? |
|---|---|
| `DEBUG_KERNEL` + `LOCKUP_DETECTOR` + `SOFTLOCKUP_DETECTOR` + `WQ_WATCHDOG` + `DETECT_HUNG_TASK` | **no** — 3/3 attempts, never reaches journald |
| `DEBUG_KERNEL` + `WQ_WATCHDOG` + `DETECT_HUNG_TASK` | **yes**, first try, kiosk renders |

So **`LOCKUP_DETECTOR`/`SOFTLOCKUP_DETECTOR` is what breaks boot** on this kernel, and the detector
actually wanted — `WQ_WATCHDOG`, which catches a stalled `brcmf_wq` — ships fine without it.

**Then the killer arm was run with both surviving detectors armed well inside the window:**

- `wq_watchdog_thresh` lowered **30 s → 5 s**. The default could never fire: the hardware watchdog
  resets the board ~16 s after the kernel stops.
- `hung_task_timeout_secs` = 10 s.

**Nothing printed.** No `BUG: workqueue lockup`, no hung task, no oops — the fsync'd witness's last
line predates the death and there is nothing after it.

That is a positive result, not an absence of one. `wq_watchdog` fires from a **timer**, and
`hung_task` from a **kernel thread**. Neither ran inside 5 s and 10 s respectively. Combined with the
earlier finding that the kernel's watchdog worker stops re-petting the hardware, the conclusion is:

> **The CPU stops servicing timers and softirqs entirely.** It is not merely failing to run
> workqueues.

Two hypotheses remain and they are **indistinguishable from here**, because both produce exactly this
silence:

1. **A spin with interrupts disabled.** ARMv6 has no NMI, so no hard-lockup detector can exist.
2. **An interrupt storm starving softirqs.** Hardirqs keep being serviced, so timer *softirqs* never
   run. The 2.5 Hz trace showed `mmc1` climbing steadily to the last sample rather than exploding,
   but that sample is up to 0.4 s before the event, which is not close enough to exclude it.

### What is left, and why none of it is reachable today

Every remaining instrument needs something currently ruled out:

| instrument | blocker |
|---|---|
| **ramoops/pstore** — would carry the dying kernel's ring buffer across the reset | needs reserved memory, which means a `cmdline.txt` change: **a `/boot` write**. No pstore backend is configured and there is no ramoops module in `/lib/modules`. |
| **serial console** | physical access. And note it may not even help: a spin with interrupts off prints nothing to any console. |
| **JTAG** | physical access. |
| **ftrace** | `/sys/kernel/debug/tracing` exists and `FUNCTION_TRACER` is in the base config, but the ring buffer is RAM and dies with the reset unless backed by pstore — same blocker as above. |

**This is an owner decision, of exactly the class `panic=10` was**: a `/boot` write, justified by the
absence of the parameter being the thing preventing diagnosis. It should be taken deliberately, not
slipped in — and `panic=10` was done with the unit on a bench.

### Two incidental corrections worth keeping

- **`CONFIG_BRCMDBG` was already in the base config.** It was never part of the fragment's delta, so
  `brcmfmac` tracing has been available at runtime all along via
  `/sys/module/brcmfmac/parameters/debug` (currently `0`). No rebuild was ever needed for it.
- **`uname -v` is not a build discriminator on this project.** Yocto pins it through
  `SOURCE_DATE_EPOCH`, so every kernel reports `#1 Fri Dec 6 10:10:05 UTC 2024` regardless of when it
  was built. Confirming which kernel is running requires a config-derived artefact — here
  `/sys/module/workqueue/parameters/watchdog_thresh`, which exists only with `CONFIG_WQ_WATCHDOG`.

### KILLED: the firmware build. Two different blobs, both wedge

Owner approved a firmware swap on 2026-08-13. **It did not fix it**, and that is a useful negative.

| | shipped | candidate |
|---|---|---|
| version | `7.45.98 (TOB) (56df937 CY)` | `7.45.98.118 (7d96287 CY)` |
| date | Mon 2021-07-19 | Tue 2021-03-30 |
| FWID | `01-8e14b897` | `01-32059766` |
| size | 399 344 | 419 798 |
| features | `pno`, `wowlpf` | `btcxhybridhw`, `fbt`, `mfp`, `sae`, `tko` |

Note the candidate is a *numbered release* while the shipped one is a top-of-branch snapshot four
months newer — so this is a build swap, not an upgrade. Both are 7.45.98 lineage.

**Result: the board died on the candidate too.** `boot_id` changed, 79 s to death versus 52 s on the
shipped blob — within the spread of everything else measured. n=1 on the candidate. Every
`mmc1 err_stats` counter was **zero again** afterwards, now on a third independent boot.

So the specific firmware build is not the variable. Combined with the SDIO bus reporting no error on
any boot, that shifts suspicion off the blob and toward `brcmfmac` or the BCM2835 SDIO host
controller itself.

#### The method, which is reusable and is the reason this was safe

`alternative_fw_path` turned out to be the wrong lever — `request_firmware` resolves relative to the
firmware search paths, so an absolute path there does not do what it looks like it does. The right
one is **`/sys/module/firmware_class/parameters/path`**, which prepends a search directory:

- **Runtime-only.** A reboot clears it and the shipped `/lib/firmware` blob returns with no action
  from anyone. Verified: after the death the parameter read empty and the TOB firmware was back.
- **Only the `.bin` is overridden.** The board-specific NVRAM (`.txt`) and the CLM blob are left to
  fall back to `/lib/firmware`, which the loader does automatically for anything absent from the
  custom path. The CLM was byte-identical anyway (same md5), so there was no CLM mismatch to worry
  about.
- **The dead-man reboot is armed first**, before `wpa_supplicant` is stopped or the driver unloaded.
  Cycling `wlan0` is cycling the lifeline; the unconditional 600 s timer is the only thing that
  returns the board if the candidate never associates. It associated in ~2 s.

Script kept at `fwswap.sh` (kiosk-reference).

### The death has no precursor, and the kernel — not userspace — is what stops

**Root cause is still NOT identified.** This section records how far the evidence reaches and where
it stops, because the stopping point is itself the finding.

**The watchdog is software-extended, and that turns it into an instrument.** `bcm2835_wdt` maxes out
near 16 s, but the kernel watchdog core honours longer timeouts by having a **kernel worker** re-pet
the hardware. systemd reports the value the driver returned, and it tracked every request — 14 s →
`14s`, 60 s → `1min`, 300 s → `5min` — so the extension is real.

With `RuntimeWatchdogSec=300`, the board still reset **~24 s after last contact**. A 300 s timeout
cannot expire in 24 s. What can is the *hardware* timeout, and that only fires if the kernel worker
stopped re-petting. So:

> **The kernel stops executing deferred work. This is not userspace starvation.** Both userspace
> tracers and the kernel's own watchdog worker die at the same instant, and the hardware resets the
> board ~16 s later.

**And there is no run-up to it.** A 2.5 Hz trace fsync'd to `/data`, read back after the reset:

| final 8 s before the wedge | value |
|---|---|
| `mmc1` interrupts | climbing **steadily**, ~1 400–2 500/s, to the last sample — no storm, no collapse |
| receive rate | **2.07 MB/s** in the final sample — full speed, no degradation |
| CPU (`/proc/stat`) | 47% user, 42% system, **6.7% idle**, 3.6% softirq — busy, not storming |
| `rx_dropped` / `rx_errors` | 0 / 0 |
| kernel messages | **none, ever** — no oops, no panic, no warning |

Then both tracers stop mid-stride. The failure is **instantaneous at full throughput**, which also
means the survivable "stall" and the fatal "death" are two different events, not one escalating.

An abrupt total stop with healthy interrupts, no printed error and no scheduler progress is the
signature of the CPU stuck with interrupts disabled — a spin or deadlock in an atomic context. That
is consistent with the SDIO transfer path, but *consistent with* is not *demonstrated*, and nothing
reachable from userspace can take it further.

### ⚠ Correction: the diagnostic kernel IS needed, and I said it was not

Earlier today this log stated the `kiosk-lockup-diag.cfg` rebuild could be skipped because
`CONFIG_MAGIC_SYSRQ` and `CONFIG_DETECT_HUNG_TASK` already ship. **That was true for the stall and
false for the death**, and the distinction was not made.

`sysrq` requires a kernel that still schedules — it delivered the whole survivable-stall picture and
was worth it. The death schedules nothing, so `sysrq`, `hung_task` and every userspace probe are
structurally blind to it. Naming the stuck function needs `CONFIG_LOCKUP_DETECTOR` printing from
interrupt context, which is exactly what that config fragment adds and what this kernel lacks.

The observable ceiling from userspace has been reached. Remaining routes, in order:

1. **Diagnostic kernel** — `LOCKUP_DETECTOR`, `WQ_WATCHDOG`, `BRCMDBG`. The only route that can name
   the function. Note ARM without a PMU-backed NMI may not support *hard* lockup detection, in which
   case even this may not print; check before assuming.
2. **`iproute2-tc` ingress policing** — does not fix the defect, makes the board enforce its own
   receive ceiling instead of trusting senders.
3. **Firmware swap** — running build is `7.45.98 (TOB)`, **Jul 19 2021**, the Cypress
   `cyfmac43430-sdio.bin`. `alternative_fw_path` makes this runtime-only and self-reverting.

### Re-measured with the corrected instrument — the device-side failure is real after all

The retraction above stands: the evidence originally offered was worthless. But re-running with a
sender that cannot starve (`pace.py` — one process, no fork per chunk, **reports its own achieved
rate**) and a per-connection sender witness produces the measurement that was missing. Two arms,
both with `/proc/loadavg` recorded:

| arm | shape | outcome | sender at the moment the device went flat |
|---|---|---|---|
| **A1** | unthrottled `cat file \| ssh` | **kernel death in 52 s** at 1.6–2.0 MB/s, no stall first | pushing — device rx was 1.6 MB/s in the final sample |
| **P1** | paced 1 MB/s, 100 KB every 100 ms | device receive collapsed, then death | `unacked:70`, `cwnd:1`, `lastsnd:25584`, `retrans:1/7` |

**P1 is the arm that carries the weight.** Compare the two sender signatures:

| | the retracted starvation case | P1 |
|---|---|---|
| `unacked` | **0** — nothing in flight | **70** — sent and never acknowledged |
| `lastsnd` | 3552 ms — idle, nothing to send | 25584 ms — **blocked in RTO backoff** |
| `cwnd` | 48, healthy | **1 — fully collapsed** |
| `retrans` | 2 in 24 MB, unchanged | **7**, exponentially backed off |

A sender with 70 packets outstanding, `cwnd` at 1 and seven backed-off retransmits is not idle. It
retransmitted seven times across ~25 s — `0.2, 0.4, 0.8, 1.6, 3.2, 6.4, 12.8` sums to 25.4 s, which
matches `lastsnd` — and **the device acknowledged none of them**, while its own rig kept logging and
`rx_packets` kept advancing by ~83 packets over 9 s from background traffic.

So during the failure the device is **alive, associated, and still receiving broadcast/beacon
traffic, but not the TCP stream**. That is a device-side receive failure, and this time nothing about
the sender explains it.

> **n=1 for P1, and it is a hypothesis-supporting result, not an established mechanism.** The
> difference from the retracted claim is attribution, not certainty: the earlier evidence was
> compatible with a starved sender, this is not. The next step is repetition — and the arm to repeat
> is the paced one, because it is the one where the sender's state is unambiguous.

## SUPERSEDED — read the retraction above first: the chip stops signalling, and the bus is clean

First evidence that names *where* the fault is. Two reproductions with an on-device rig
(`/data/autopsy.sh`, source in this repo at `autopsy.sh` (kiosk-reference)) that samples
the byte counter **and the SDIO interrupt count** every second, fsyncing each line, and fires
`sysrq` when the byte counter flatlines.

**None of this needed a kernel rebuild.** `CONFIG_MAGIC_SYSRQ` and `CONFIG_DETECT_HUNG_TASK` are
already in the shipped kernel; `/proc/sys/kernel/sysrq` ships as `16` (sync only) and is writable to
`1` at runtime. The diagnostic kernel on the `config-provisioning` branch was not required to get
this far, and the multi-hour rebuild it implies can be spent on something else.

### What a stall looks like from inside

| signal | during a stall | reading |
|---|---|---|
| `mmc1` interrupts | **15/s — the idle rate**, down from ~1 600/s under load | the chip is not signalling the host |
| `rx_bytes` | +87/s (background noise only) | nothing is being delivered |
| TCP receive queue (`/proc/net/tcp`) | `00000000` — empty | not a host-side drain problem |
| `rx_dropped` / `rx_errors` | 0 / 0 | the driver sees no error at all |
| `iw dev wlan0 link` | associated, −57 dBm, 72.2 MBit/s, unchanged | the association is entirely healthy |
| `sysrq w` (blocked tasks) | **empty, twice** | nothing is in D state |
| `brcmf_wq` worker | `state:I`, parked in `worker_thread → schedule` | the driver's workqueue is idle, not stuck |
| busy workqueues | only `dbs_work_handler` (cpufreq governor) | nothing driver-related is running |
| `/sys/kernel/debug/mmc1/err_stats` | **every counter 0** after a stall on that boot | no command timeout, no CRC, no data timeout, no unexpected IRQ |

The host is not failing to keep up. It is never told there is anything to collect, and the SDIO
host controller records no error while that is true.

### It is not a crash — it self-clears

The stall persisted for the remaining ~200 s of a 243 s transfer, delivering 6.8 MB of 120 MB. The
moment the sender stopped, a 2 MB probe completed **at full speed (1.4 MB/s including SSH setup)**.

So the condition is a **load-induced degraded delivery mode with hysteresis**: entered under
sustained receive rate, held while the sender keeps pushing (its retransmits maintain the pressure),
and released when the pressure comes off. That is why two days of probing read it as a hang — from
outside, "degraded until the sender gives up" and "hung" are the same picture.

**Both failure modes were seen again**, consistent with the earlier 3-deaths/2-stalls in five:
trial 1 escalated to a kernel death and reset at ~128 MB; trial 2 stalled at 1.4 MB and survived,
because the watchdog was widened to 60 s for the test.

### What this kills, and what it leaves

Dead: deadlock, lock contention, a stuck driver workqueue, a blocked task, softlockup, host-side
drain failure, and SDIO bus error. Every one of them is refuted by a counter that stayed at zero or
a task state that was idle.

Left standing: the **BCM43430 firmware** stops delivering received frames under sustained load. That
is inside the blob and not directly observable from here, which is consistent with two days of the
driver's own counters reporting nothing wrong.

### Consequences for the fix

- **Ingress rate policing still looks right, for a reason that is now explicit.** It cannot reduce
  SDIO traffic directly — `tc` ingress runs at `netif_receive_skb`, *after* the driver has already
  pulled the frame off the bus. It works by dropping enough that a congestion-responsive sender
  backs off, holding the sustained rate below the trigger. Every realistic sender here (scp, RAUC
  over HTTP, hawkBit) is TCP and therefore responsive. A UDP flood would not be covered by this or
  by anything else at this layer, and that limit should be stated rather than discovered.
- **Firmware replacement is now a first-class candidate**, where before it was a shrug. The device
  loads the **Cypress** build (`brcmfmac43430-sdio.raspberrypi,model-zero-w.bin` →
  `../cypress/cyfmac43430-sdio.bin`). `brcmfmac` exposes `alternative_fw_path`, so a different build
  can be tried **without touching the installed one** — and because the parameter is runtime-only, a
  reboot restores the shipped firmware by itself. That is the rare fix that is both board-side and
  self-reverting.
- **The watchdog trade is sharper than it was.** Stall mode is now known to be survivable *and*
  self-clearing. The shipped 14 s watchdog converts it into a 113 s reboot. Still an owner decision,
  and still weighed against the genuine deaths being the majority.

### Two rig defects, both caught by the rules rather than by review

1. **v1's kmsg witness died silently, killed by the rig's own `sysrq t`.** The dump overran the
   kernel ring buffer, the fsync-per-line reader (~40 lines/s) fell behind, `cat /dev/kmsg` took
   `EPIPE` and exited — and an empty log then read as "the kernel printed nothing before death".
   journald logged `/dev/kmsg buffer overrun, some messages lost` at the same instant, which is what
   gave it away; journald, being a faster reader, had captured the dump the rig lost. v2 drops
   `sysrq t` and **samples the witness's own liveness into the metric log**, proven in both
   directions by killing it deliberately and watching the field flip.
2. **`sysrq l` is not registered on this UP kernel** — it printed the HELP text instead of a
   backtrace, and a less careful read would have recorded "the backtrace was empty". The available
   keys are in that HELP line: `w`, `t`, `p`, `q`, `z`, `m`.

## ROOT CAUSE + FIX

**2026-08-13 evening.** The softirq jump documented above (§"ROOT CAUSE, 2026-08-13") names *where*
the fault lands. This names *why*: the board corrupts memory at its top CPU OPP, not on the SDIO bus.
Controlled dose-response, one variable, against the 120 MB unthrottled killer arm that had already
killed the board ~10 times today:

| CPU frequency | result |
|---|---|
| **1000 MHz** pinned | **2/2 DIED** (~50 s) |
| `ondemand`, uncapped (700↔1000) | died ~8 times today |
| 900 MHz pinned | 1/1 survived |
| 800 MHz pinned | 1/1 survived |
| 700 MHz pinned | 3/3 survived |
| **`ondemand` capped at 900 MHz** | **3/3 survived** |

**8 of 8 survive below 1000 MHz. 100% death at 1000 MHz.** In the capped-`ondemand` runs the
transition counter kept climbing (249→270, 292→311, 333→354) — the governor was switching the whole
time, so frequency transitions are fine and the top OPP specifically is not. Throughput held at
~1.9 MB/s across both frequencies, so this is not "slower CPU, therefore less load".

Matches raspberrypi/linux **#2555** — open since 2018, six independent users reporting
`force_turbo=1` + `over_voltage=4` as the fix on the same silicon family.

### KILLED: every rate and burst model in this log, including the ~0.9 MB/s boundary above

The chain was always indirect: higher receive rate → more CPU → `ondemand` climbs to 1000 MHz → the
SoC corrupts memory → the jump into `deliver_skb`'s indirect call documented above. Rate was a
correlate of the trigger, never the trigger itself. That is why the OTA at 0.35 MB/s always worked —
never enough sustained CPU demand to reach 1000 MHz — and why sender-side throttling looked like it
was helping.

It also resolves loose ends the rate model could not:

- **The PC constant across crashes** (`0xc1137c58`, four crashes, two governors) — a hardware-level
  fault producing a repeatable bad value, not a random heap scribble.
- **Why `slub_debug` found nothing, why every SDIO error counter stayed zero, and why two different
  firmware builds crashed identically** — none of them were ever the variable.

### The fix, and why this one over the obvious one

`kiosk-cpufreq` caps `scaling_max_freq` at 900000. `over_voltage`/`force_turbo` were not taken instead
because both live in `config.txt` on the shared FAT partition, which `RAUC_BUNDLE_SLOTS = "rootfs"`
never touches — a voltage fix could never arrive by OTA. The frequency cap ships as a systemd unit in
the rootfs and does. Cost: ~10% of peak CPU. Throughput went *up*, not down — ~3.6 MB/s against
~1.9 MB/s while the board was still crashing, because removing the crashes removed the retries.

**Consequence for delivery design.** `send-bundle-chunked.sh`'s chunk-and-pause shape is no longer
needed to avoid the wedge on the capped image — a plain unthrottled transfer is 3/3 survived. It keeps
its other property, resuming from the durable on-disk size after an interrupted transfer, which is
unrelated to the OPP fix and still worth having.

Full detail, the shipped unit, and the OTA that proved the fix from the built image rather than a
hand-edit are in `STATUS.md` (kiosk-reference).

## What the failures have in common

Nine of the entries above are the same mistake wearing different clothes: **a check whose broken
state is indistinguishable from a passing state.** `dd` writing zero bytes and surviving. An empty
`boot_id` comparing unequal. A five-dash symlink that parses. A masked unit whose absence is
attributed to a change that also happened. A launcher that "would fire on the next boot" and cannot
execute.

The countermeasure is the same in every case and it is cheap: **seed the failing case and confirm the
check reports failure**, before trusting it to report success.
