# Service changes on the kiosk — the justification register

Every unit disabled, masked or modified on the **live Yocto device**, with the reason it was changed
and the evidence that it helped. A change with no entry here is not authorised; an entry with no
evidence is not a justification, and says so in its own row.

The Raspbian-era service trim on the SL16G card is a separate system and is owned by
`STATUS.md` (kiosk-reference) §"Session trim" and the Raspbian card notes (kiosk-reference `raspbian-card.md`). It is not
restated here — but it is the worked example of the bar below, and it met it.

## The bar

Two different questions get confused here, and they have different bars.

**May it be removed?** — **If the kiosk does not need it and we are booting it, it is waste, and that
is sufficient grounds** (owner, 2026-08-12). No measurement is required to authorise the removal.
What *is* required:

- **The dependency check.** `systemctl show -p RequiredBy,WantedBy <unit>`, read **before** the
  change, and a statement of what happens to anything listed. This is the one whose omission broke
  the Bluetooth change below, and it is a single command.
- **The revert command**, written out, that works over SSH.

**How much did it buy?** — that is a performance claim, and it needs:

- **The mechanism.** A sentence saying *why* this unit costs boot time, memory or image bytes on
  *this* device.
- **The measurement.** Before/after on **one** endpoint fixed in advance, **n ≥ 3** per arm, same
  device, same physical conditions. Two arms that differ in more than the change are not a
  measurement.

The overnight session's error was not removing things. It was removing things without **the
dependency check**, and then attaching a number to it that **the measurement** does not support — see
[`experiment-log.md`](experiment-log.md) §"The mask comparison was not an experiment". Worse, the
per-unit CPU accounting since taken shows **five of the eleven masked units never started at all**,
so the number it claimed cannot have come from them; that evidence is in
[`image-trim-recommendations.md`](image-trim-recommendations.md).

> **Why the measurement half of the bar is this strict.** One 1 GHz ARM11 core and an SD card. Both
> the cost of a unit and the benefit of removing it are small enough to sit inside the run-to-run
> spread, so an uncontrolled comparison will reliably produce a number of the right order and the
> wrong sign.

## Current state — nothing is masked by us

As of **2026-08-12**, after the revert described below, the Yocto device carries **no service masks
applied by this project**. The four masks present ship in the image.

| Unit | Masked by | Evidence |
|---|---|---|
| `dbus-1.service` | the image | mask symlink mtime `2018-03-09 07:34:56`, the build epoch |
| `keymap.service` | the image | same |
| `modutils.service` | the image | same |
| `networking.service` | the image | same |

The build epoch is the reproducible-build timestamp on every image-supplied file — for example
`/usr/lib/systemd/system/kiosk.service`. Any file whose mtime is **not** that epoch was changed after
flashing, which is how a change made without a record is still attributable. This is the check to run
first on any device whose history is unclear.

## Reverted 2026-08-12 — eleven masks, applied without justification

Applied 2026-08-12 `03:37–03:39` by a profiling subagent that terminated without reporting. They were
reconstructed after the fact by diffing the device against the build epoch, not from a record.

**Reverted 2026-08-12 08:32** on owner instruction, and the revert was confirmed across a reboot:
`systemctl list-unit-files --state=masked` returns only the four image masks.

```bash
# What the revert was (already applied; kept for the record):
systemctl unmask avahi-daemon.service avahi-daemon.socket bluetooth.service hciuart.service \
  neard.service ofono.service rpcbind.service rpcbind.socket zram.service \
  busybox-syslog.service busybox-klogd.service
```

Several of them are the right call and none were shown to be at the time. They are listed below with
the dependency check that was missing, and with what each actually costs — measured after the revert,
which is the number that was never taken. Anything re-applied gets its own row.

The **measured CPU** column is `CPUUsageNSec` read off the device at 220 s uptime on the reverted,
image-default configuration — that is, what each unit actually costs when nothing is masked.

| Unit | Plausible mechanism | Dependency check | Measured CPU | Verdict |
|---|---|---|---|---|
| `neard.service` | NFC daemon; the Pi Zero W has no NFC hardware | `RequiredBy=[]` `WantedBy=[]` | **inactive, 0 ms** | Remove from the **image**. Masking it saves no boot time — it never starts |
| `ofono.service` | telephony/modem stack; no modem present | `RequiredBy=[]` `WantedBy=[]` | **inactive, 0 ms** | Same — image bytes only |
| `rpcbind.service` + `.socket` | ONC RPC portmapper for NFS; no NFS mounts. Also removes a listening socket | `RequiredBy=[]` `WantedBy=[]` | **inactive, 0 ms** | Same, plus a security argument |
| `avahi-daemon.service` + `.socket` | mDNS responder; the kiosk reaches its backend by IP, and nothing discovers it by name | `RequiredBy=[]` `WantedBy=[]` | **inactive, 0 ms** | Same. Confirm nothing on the LAN resolves the kiosk by `.local` first |
| `bluetooth.service` | BlueZ; **this device has no reason to have Bluetooth at all** (owner, 2026-08-12) | `RequiredBy=[bthelper@hci0.service]` | **active, 485 ms** | **Right call, wrong change.** See below |
| `hciuart.service` | attaches the BT controller over UART; same argument | `RequiredBy=[bthelper@hci0.service]` | **244 ms** | **Right call, wrong change.** See below |
| `busybox-syslog.service` | duplicate log path — journald is the log this project reads, and syslog writes the same records to the SD card again | `RequiredBy=[]` `WantedBy=[]` | **active, 230 ms** | **Remove.** Real cost, real duplication. Confirm nothing reads `/var/log/messages` |
| `busybox-klogd.service` | feeds kernel messages to syslog; moot if syslog goes | `RequiredBy=[]` `WantedBy=[]` | **inactive, 0 ms** | Remove with the row above; no boot-time win of its own |
| `zram.service` | compressed swap in RAM | `RequiredBy=[]` `WantedBy=[]` | **failed, 162 ms** | **Do not mask. Investigate.** See below |

> **Correction, 2026-08-12 evening — four of these five measurements are superseded.** The `Measured
> CPU` column above was read at 220 s uptime on one specific boot, that morning. On the image running
> this evening, `ofono`, `avahi-daemon`, `rpcbind` and `busybox-klogd` are `active` with non-zero CPU
> (`ofono` 468 ms, `avahi-daemon` 190 ms, `rpcbind` 95 ms, `busybox-klogd` 93 ms), and masking the set
> together with `busybox-syslog` and the failing `zram` measurably moved `surf` exec **−1.92 s**. Only
> `neard` remains confirmed `inactive, 0 ms`. **Why the other four started is not established** —
> nothing in this session identified what changed between the two readings. Full numbers and the
> combined-mask caveat are owned by
> [`image-trim-recommendations.md`](image-trim-recommendations.md) §"The waste set does cost boot
> time"; this changes the **Verdict** column above from "no boot-time win" to "measured boot-time win,
> not yet isolated per unit" for those four rows. It does not change the removal decision — §"The bar"
> above already establishes that "not needed" is sufficient grounds on its own.

### Bluetooth should go — but it is a three-unit change, not a two-unit one

**The device has no reason to have Bluetooth at all** (owner, 2026-08-12). Nothing pairs, nothing
scans, and the kiosk's only link is WiFi. So the intent behind masking `bluetooth` and `hciuart` was
correct. The change as made was not.

Both are `RequiredBy=bthelper@hci0.service`, and **that instance really is started on every boot** —
verified on the device 2026-08-12:

```
systemctl is-active bthelper@hci0.service   -> active
InactiveExitTimestampMonotonic              -> 34.48 s
/etc/udev/rules.d/90-pi-bluetooth.rules     -> the rule that instantiates it
```

It is a `static` template, so it is not enabled and does not show up in an `is-enabled` sweep — udev
instantiates it when the controller appears, at 34.5 s, inside the busiest part of boot. Masking the
two units it `Requires` does not skip it; it makes it **fail on every boot**, permanently, while the
udev rule goes on firing.

**The correct removal masks the template as well**, so nothing is left to instantiate:

```bash
systemctl mask bthelper@.service bluetooth.service hciuart.service
# revert:
systemctl unmask bthelper@.service bluetooth.service hciuart.service
```

Masking the template covers every instance, so the udev rule resolves to a masked unit and the chain
ends cleanly with no failed unit. `hciuart` is the one that actually attaches the controller over
UART, so with it gone the hardware is never brought up — which is the closest thing to a real "no
Bluetooth" switch that is reachable over SSH. The `dtoverlay=disable-bt` route is a `/boot` change
and is therefore refused on this project regardless of merit.

This is where the overnight omission was a defect rather than a gap: the dependency check is one
command, it is the cheapest half of §"The bar", and its answer changes the change.

**Status: SHIPPED 2026-08-12.** Removed at the image level (`MACHINE_FEATURES`/`DISTRO_FEATURES`)
and delivered by OTA, not masked at runtime. It went through the bar properly — mechanism
stated, dependants checked, and now a measurement, since
[`boot-profile-yocto.md`](boot-profile-yocto.md) shows boot is CPU-bound and removing work is the
lever that actually moves it.

### `zram` is failing, and masking it hid that

With the masks reverted, `systemctl is-active zram.service` returns **`failed`** on this image, with a
root cause now in hand:

```
/etc/init.d/zram: line 42: echo: write error: Device or resource busy
```

There are **two** mechanisms for the same job in this image, and only one works: the SysV
`zram.service` fails as above, while `zram-swap.service` succeeds and provides 209 MB of swap. So the
unit was contributing nothing before it was masked, and masking it removed a *symptom* while leaving
the duplication in place.

That matters in the opposite direction to the rest of the list: this board has 437 MB of RAM and runs
WebKit, and the Raspbian card was observed swapping (77 MB swapped at 9h36m uptime,
`STATUS.md` (kiosk-reference) §"Session trim"). Compressed swap is plausibly something this device
**wants**. Masking a broken unit that should be working is how a capability is lost silently.

**Open:** why does `zram.service` fail on this image? Not investigated.

## Kept — changes with a mechanism and a demonstration

These are on slot B and were **not** reverted. They are robustness and recovery work, not boot
optimisation, and each was demonstrated in both directions.

| Change | Mechanism | Evidence | Revert |
|---|---|---|---|
| `/etc/rauc/system.conf` keyring repointed to `keyring.pem` | `system.conf` named a CA file absent from the image, so every bundle verification failed | `failed to load CA file … rc=1` before; `Verified inline signature… rc=0` after | `cp -a /etc/rauc/system.conf.bak-2026-08-12 /etc/rauc/system.conf && systemctl restart rauc` |
| `/etc/systemd/system.conf.d/watchdog.conf`, `RuntimeWatchdogSec=14` | `RuntimeWatchdogUSec=0` and no `panic=` in cmdline, so a wedged kernel hung forever | fired and recovered the board unattended in 113 s; fired again unattended in ~98 s on 2026-08-12 08:35 | `rm /etc/systemd/system.conf.d/watchdog.conf && systemctl daemon-reexec` |
| **+ `RebootWatchdogSec=30s`, `ShutdownWatchdogSec=30s`** (2026-08-12) | systemd closes `/dev/watchdog0` during shutdown and re-arms it under these. The default reboot window is **10 minutes**, so a hang on the way down left a 10-minute hole | **stated, not verified** — has not been made to fire | restore the single-directive version of the same file |
| **`/etc/sysctl.d/60-kiosk-panic.conf`** — `kernel.panic=10`, `kernel.panic_on_oops=1` (2026-08-12) | a panic otherwise sits forever; `panic_on_oops` turns a corrupt-but-limping kernel into a reboot rather than a zombie | live values read back `10` and `1`. **Does not cover an early panic** — `systemd-sysctl` runs at ~11.7 s, and the observed panic was at 4.0 s | `rm /etc/sysctl.d/60-kiosk-panic.conf` (takes effect at next boot) |
| `kiosk-journal-flush.service` + `/usr/lib/tmpfiles.d/99-kiosk-journal.conf` | journald was volatile, so the boot that failed left no evidence | `journalctl -b <id>` reads prior boots across reboots; ~41 MB on `/data` | `systemctl disable --now kiosk-journal-flush && rm /etc/systemd/system/kiosk-journal-flush.service` |

The watchdog is the one to watch rather than trust: `STATUS.md` (kiosk-reference) §"Hardware
watchdog ARMED and PROVEN" records that it can also misfire under startup load, and three fires
before `rauc-mark-good` runs at ~33 s would exhaust the boot counter.

## Reverted 2026-08-12 — the launcher and the early-start drop-in

| Change | State | Why reverted |
|---|---|---|
| `/usr/bin/kiosk-launch` — bounded 60 s backend-readiness wait before exec'ing `surf` | **reverted** to the image version (`md5 5178acbe5a7b46b0754e5407da12c17a`, mode `0755`) | It had lost its execute bit, and `xinit` execs it directly. Verified on the device: a `0644` copy returns `Permission denied`. The next boot would have been a black screen on a 10 s restart loop |
| `/etc/systemd/system/kiosk.service.d/early-start.conf` — drop the `network-online.target` gate | **already deleted** by the previous session; the empty directory was removed and `daemon-reload` run | Never tested. It is the half that carried the claimed benefit |

The two were one design and only one half survived, which made the surviving half worse than useless:
the launcher's own comment states *"kiosk.service no longer waits for network-online.target"*, and
with the drop-in gone that premise was false. `kiosk.service` still carries
`After=/Wants=network-online.target`, so the wait loop would have run **after** the network was
already up and saved nothing.

The reverted launcher is preserved at
`kiosk-launch.backend-wait.sh` (kiosk-reference)
and on the device at `/data/kiosk-launch.backend-wait.reverted`. **It is worth reading before anyone
rewrites it**: it records that busybox `nc` exits 1 against an open port as well as a closed one, so a
readiness check built on `nc` can never succeed. That finding cost someone real time and is
independent of whether the change ships.

## Added 2026-08-12 — diagnostic, and scheduled for removal

| Change | Purpose | Revert |
|---|---|---|
| `kiosk-bootprofile.service` → `kiosk-bootprof.c` (kiosk-reference) (binary at `/usr/bin/kiosk-bootprof`) | samples `/proc/stat`, `/sys/block/mmcblk0/stat`, `/proc/loadavg` and module first-seen times twice a second from early boot. Costs 237 ms per boot | **now image content** (`kiosk-bootprof` recipe), shipped **disabled**: `systemctl disable kiosk-bootprofile`. Do not `rm` it |
| `/etc/systemd/journald.conf.d/50-kiosk-size.conf` — `SystemMaxUse=64M`, `SystemMaxFileSize=8M`, `SystemKeepFree=64M`, working set vacuumed to ~20 MB | the persistent journal had hit its default cap (10 % of the 479 MB `/data` = 47.9 MB) and was **dropping pre-flush early-boot entries** — journals began at 25.7 s instead of 0 | `rm /etc/systemd/journald.conf.d/50-kiosk-size.conf && systemctl restart systemd-journald` |

**This took three attempts and the middle one was worse than the original.** The flush at ~25 s scales
with *current* journal size and sits before the `wlan0` gate, so a 150 MB cap cost ~0.5 s of boot and
growing; capping at 32 MB with 31 MB in use recreated the dropping. The failure was never a small cap,
it was no free space. Loose cap, small working set: flush **1.12–1.20 s** against 1.91–2.02 s, with
early boot fully captured. Detail in [`boot-profile-yocto.md`](boot-profile-yocto.md).

It is instrumentation, not a kiosk component, and it perturbs what it measures — it is itself a
runnable process, so `nr_running` includes it. Both facts are handled in
[`boot-profile-yocto.md`](boot-profile-yocto.md).

**It now ships in the image** via the `kiosk-bootprof` recipe, installed but **not enabled** — an
earlier note here said to remove it once the boot work closed, which was wrong: the boot work is
ongoing and this is how it is done. Enable it, reboot, read, disable. Usage in
[`remote-debugging.md`](remote-debugging.md) §"Recipe 10 — Profile the boot: is the core busy,
blocked, or queued?".
