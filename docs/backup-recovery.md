# Recovering this Pi if its card dies

**Status 2026-08-06 05:44: a full-card image exists and is verified.** Everything below is
measured on the device. Provisioning *new* kiosks is [`provisioning.md`](provisioning.md).

| | |
|---|---|
| Image | `~/kiosk-SL16G-2026-08-06.img.gz`, **4.9GB** (15,932,063,744 raw) |
| md5 | `93c80a8da2c85e27c95294f3881b6080` |
| Partition table | `~/kiosk-SL16G-2026-08-06.manifest.txt` |
| Taken | 02:57–05:44, 2026-08-06, 1.6 MB/s over SSH, nothing written to the Pi |
| Verified | **Yes**, `tools/verify-image.sh`: gzip stream, byte count, all 5 partitions vs manifest, `e2fsck -fn` on root, FAT signatures on `p1`/`p6` |
| Not done | Never restored onto a card. Verification proves the image is coherent, not that a restore was rehearsed |

The image is **524,288 bytes larger than the card**: `dd` read 15193 full 1MiB blocks plus a final
half-block, and `conv=sync` padded that short read to a full block. The padding is verified all-zero.
The card is 15,931,539,456 bytes = 15193.5 MiB — not a whole number of MiB, which is why the tail exists.

`e2fsck` reports 1,721,872 of 3,505,536 blocks used, matching `dumpe2fs` on the live device exactly.


## One copy, on this host

The image lives on the same WSL2 machine that serves the mirror. **This is a closed decision, weighed
and accepted** (owner, 2026-08-06): no other destination exists, and one copy beats none. A backup on
the machine it backs up is a real weakness — it is accepted, not overlooked, and it is not an open
question.

The Pi also **cannot push to this host**: it is NAT'd at `172.21.236.113/20`, so a push from the device
(`nc`, `rsync` daemon) fails at the network layer regardless of tooling. Transfers must be **pulled**
from this side over SSH.

## Why an image still matters

> **Superseded 2026-08-06:** this document previously asserted **"this machine cannot be rebuilt from
> scratch — the base Raspbian Stretch archive is offline"**, and concluded the image was the only
> recovery path. **Wrong as written.** The archive moved to `legacy.raspbian.org/raspbian`; the machine
> is repairable by repointing `sources.list`. See [`pi-inventory.md`](pi-inventory.md) §"Package
> archives and what can be installed".

The correction does not lower the priority:

- `legacy.raspbian.org` is a third party's frozen archive that can vanish.
- A rebuild reconstitutes *a* Stretch system, not **this** machine's accumulated state.
- Restore-from-image is minutes; rebuild-and-reconfigure is days.

| | Size |
|---|---|
| Config that actually matters (portable role + device identity) | **~3.5KB** |
| Image required to preserve it | **6.3GB used of a 15.9GB card** |

The card is an `SL16G` manufactured **08/2019**, running 24/7 since. Identity and full partition layout
are in [`pi-inventory.md`](pi-inventory.md) §"Storage" — including that `p1` is required to boot.

## The bottleneck is the ARM11 core, not the card and not the radio

| Measurement | Result | Samples |
|---|---|---|
| Raw card read (`iflag=direct`) | **22.7 MB/s** | 3 (22.7 / 22.7 / 22.6) |
| SSH pipe, `aes128-ctr` | **1.45 MB/s** | 1 × 64MB |
| SSH pipe, `chacha20-poly1305` | 1.37 MB/s | 1 × 64MB |
| SSH pipe, `aes128-gcm` | 1.19 MB/s | 1 × 64MB |
| WiFi link | 72.2 Mb/s, −36 dBm, 70/70 | — |

The card is 15× faster than the pipe and the radio is not the constraint. Three ciphers within 20% of
each other is the tell: swapping ciphers does not move it because the single 1GHz ARM11 core is
saturated. **1.45 MB/s is the ceiling.** Use `-c aes128-ctr`, best of the three by ~20%.

A separate 2026-08-05 run measured 22.9 MB/s (n=1) — distinct sample, not a correction.

## Never compress on the Pi

`gzip -1` on card data:

| Region | Ratio | gzip input rate |
|---|---|---|
| Real filesystem data | 1.71× | **0.89 MB/s** |
| Empty space | 229× | 4.40 MB/s |
| Mixed | 17.9× | 3.45 MB/s |

**On real data gzip is slower than the wire** — 0.89 MB/s against a 1.45 MB/s pipe — because it
competes for the same saturated core. Across a whole card the empty space roughly cancels this out
(~2h49m compressed vs ~3h03m raw), so Pi-side compression buys about **14 minutes and costs a failure
mode**: a corrupt gzip stream ruins everything after the corruption, where a raw image degrades
locally. With 943G free on the receiving end, storing 15GB is free. **Send raw, compress on arrival.**

| Approach | On the wire | Time | Restore |
|---|---|---|---|
| **Full card `dd`, raw** | 15.9 GB | **~3h03m** | bit-exact, `dd` it back |
| Full card `dd \| gzip -1` on Pi | ~4.5 GB | ~2h49m | brittle stream |
| `rsync`/`tar` of root files | ~6.3 GB | ~1h18m | **rebuild required** |

The card is 14.9 GiB total. Wire figures are decimal GB; "~6.3 GB" and `dumpe2fs`'s "7.05GB used"
describe the same data under different accounting — see [`pi-inventory.md`](pi-inventory.md) §"Storage".

## `e2image` looked ideal and is a dead end

`e2image -ra` copies only used blocks — 7.05GB instead of 13.4GB — and `/sbin/e2image` 1.43.4 **is**
present. But piped to stdout the sparse holes emit as real zeros, so the full **14.36GB** crosses the
wire anyway. Compressing the pipe to elide them puts gzip back in the path at 0.89 MB/s. It only wins
writing to a sparse file, and the Pi has 6.2G free for a 7GB image. Recorded so nobody re-derives it.

`command -v e2image` reports MISSING because e2fsprogs lives in `/sbin`, off the PATH of a
non-interactive SSH shell. The binaries are there.

## Tooling on the device

Present: `rsync` 3.1.2, `tar`, `dd`, `gzip`, `xz`, e2fsprogs (`e2image` 1.43.4, `dumpe2fs`,
`resize2fs`). Absent: `partclone`, `fsarchiver`, `zerofree`, `pv`.

> **Superseded 2026-08-06:** this read "absent **and unobtainable**" and concluded "**nothing new can
> be installed on this device**". The second half is wrong — they are obtainable after repointing
> `sources.list`, **but read the `apt upgrade` warning there first**. In practice the backup was still
> built from what was present, because installing anything on a device mid-incident is a change.

`zerofree` stays unusable for shrinking regardless: it needs the root filesystem remounted read-only
on a live kiosk.

## Taking the image

Reading the card over SSH writes nothing to the Pi and is in the recoverable class — worst case you
abort. Pulling the card is the hands-on option and stays refused. The only cost is a crash-consistent
image wanting an `fsck` on restore, which for a static kiosk filesystem is a weak objection against
having no copy at all.

```bash
# from a host that is NOT the mirror server; ~3h, ~15GB, resumable only by restarting
ssh -i ~/.ssh/id_ed25519 -c aes128-ctr pi@192.168.1.6 \
  'sudo dd if=/dev/mmcblk0 bs=4M iflag=direct status=progress' \
  | gzip > kiosk-SL16G-$(date +%F).img.gz
```

`gzip` runs on **this** side, not the Pi. Verify with `gzip -t` and record size and `md5sum` next to
the image — an unverified backup of an irreplaceable system is a guess.

**Thermals are not a concern:** 46.5°C idle, `get_throttled=0x0`, never throttled since boot. Sustained
reads do not wear NAND (writes do), so a 3-hour read costs the card nothing. The kiosk is sluggish
while it runs — load hit 1.73 during a 256MB read. Run it overnight.

## Still open

- ~~**Verify the current image**~~ — **done 2026-08-06** by
  `verify-image.sh` (kiosk-reference): gzip stream, byte count, all five partitions against
  the manifest, `e2fsck -fn` on root, FAT signatures on `p1`/`p6`. md5 recorded in
  `STATUS.md` (kiosk-reference). It has still **never been restored onto a card** — coherent is not
  rehearsed.
- **`PiShrink`** or equivalent, so the image restores onto a smaller card. Untested, runs on the
  receiving side, costs the device nothing.
- ~~**`rsync` for the second copy onward.**~~ — **designed and tested 2026-08-06**, not scheduled:
  [`hardening-and-backup-plan.md`](hardening-and-backup-plan.md) §"Part 1" and
  `kiosk-backup.sh` (kiosk-reference). The prediction here held — excluding
  `/home/pi/.cache` (189,654 of 193,332 files) takes the job to 2,004 regular files / 371 MB. The
  caveat also held and is why the image stays: **a file-level copy is not bootable.**

## `[Yocto]` Recovering a boot that succeeds with no network

Everything above recovers a **dead card**. This section covers the failure the A/B slots do not:
a boot that completes normally and comes up **without a network**. Nothing automatic catches it —
the watchdog does not fire because nothing is wedged, and `rauc-mark-good` still runs at ~33 s, so
the boot counters never decrement and U-Boot never falls back. It is the one class where a config
change on a wall-mounted unit costs a physical trip.

Two mechanisms cover it, in order of cost:

**A USB keyboard on tty1.** `kiosk-zero-w.yaml` keeps `keyboard` and `usbhost` in
`MACHINE_FEATURES` for exactly this, and the panel is already the console (`console=tty1`). This is
the only way in when the network is gone.

**`/data/RECOVER.sh`**, which undoes every runtime change and reboots:

```sh
sh /data/RECOVER.sh
```

It unmasks the units masked for boot trimming, deletes the udev rule **symlinks**, removes the
Bluetooth modprobe drop-in, restores the `resolv.conf` symlink, and reboots. It lives on `/data`,
which survives both a reflash of a rootfs slot and an A/B update. Safe to run twice. It does not
touch `/boot`, `sshd`, `systemd-networkd` or `wpa_supplicant`.

> **Proven by running it, not by reading it — and that is what found its defect.** The first version
> deleted `/etc/udev/rules.d/*.rules` with a glob, which took `99-fuse.rules`, `can.rules` and
> `touchscreen.rules` with it: three real files the image ships, alongside the symlinks it meant to
> remove. They were restored byte-for-byte from the assembled rootfs and the script narrowed to
> `-type l`. An inspection pass called the original correct.

**Recovery machinery is itself an untested change.** This script deliberately does nothing
automatically — no timer, no deadman, no auto-revert. On a device whose revert is already a
one-liner, a harness that acts on its own adds a failure mode and removes none.

## `[Yocto]` The no-LAN boot recovers itself — `kiosk-netcheck`

The section above ends by arguing against automatic recovery machinery, and that argument still
holds for everything it covers. This is the one case it does not: **a revert you cannot reach is not
a one-liner.** `RECOVER.sh` assumes a person at a keyboard, which is exactly what an unreachable
board denies. So the automatic mechanism is justified here by the same reasoning that rejects it
elsewhere, not in spite of it.

`kiosk-netcheck.service` is ordered `Before=boot-complete.target`, which `rauc-mark-good.service`
already `Requires`. That hook is upstream systemd design, so nothing about `rauc-mark-good` is
patched or overridden. If the check exits non-zero, `boot-complete.target` is never reached,
`mark-good` never runs, U-Boot's boot counter is **not** reset, and three such boots drop the slot
from `BOOT_ORDER` — turning "boots fine, unreachable" into the A/B fallback that already works.

The check waits up to 120 s for an IPv4 default gateway on `wlan0` and one successful ping to it.
The gateway, not the internet: this must work on an isolated LAN.

**It only ever withholds.** It never marks a slot bad. Withholding is recoverable from the other
slot; marking bad is not. And it suppresses itself entirely — marks good despite having no LAN —
when the partner slot's boot status is not `good`, because a kiosk nobody can reach still beats a
card with no bootable slot, which is the one failure that costs a physical trip.

Overrides live in `/data/kiosk-netcheck.conf` (`TARGET`, `DEADLINE`, `IFACE`), which survives both an
OTA and a slot reflash. Setting `TARGET` to an unroutable address is how the failure path is tested
without taking the real network down — the lifeline stays up while the *check* fails.

### Proven by making it fire, in all three directions

Runtime install on slot A, 2026-08-13. Script-level first, then across real reboots:

| Case | Expected | Observed |
|---|---|---|
| Healthy LAN | pass | exit 0 in 93 ms; gateway answered at 28.4 s of boot |
| No LAN, partner slot `good` | withhold | exit 1; `boot-complete` **inactive**, `rauc-mark-good` refused with "Dependency failed", **`BOOT_A_LEFT` 3 → 2** |
| No LAN, partner slot **not** `good` | mark good anyway | exit 0, "WITHHOLDING SUPPRESSED" — exercised against a stubbed `rauc status` rather than by marking a live slot bad |
| Restore, reboot | counter recovers | `BOOT_A_LEFT` back to **3**, all units active, zero failed |

The kiosk stayed `active` with its full browser tree through the failing boot: the blast radius is
exactly one unit, because `rauc-mark-good` is the only thing on this image that requires
`boot-complete.target` and `kiosk.service` does not.

**Cost: `rauc-mark-good` moved 25.9 s → 30.1 s**, because it now waits for the LAN. That slightly
widens a hazard already recorded in `STATUS.md` (kiosk-reference): a watchdog fire landing *before*
`mark-good` runs, three times running, would exhaust the boot counter on its own.

> **The third row is the weakest evidence here, and deliberately so.** The escape hatch was proven
> against a stubbed `rauc status --output-format=shell`, not by marking slot B bad on the live
> board. That substitutes rauc's *output* while exercising the real script, real parser and real
> branch — but it does not prove RAUC reports a genuinely bad slot in the shape the parser expects.
> The second row covers that half: it parsed real output and correctly found slot B `good`. Together
> they cover the path; neither covers it alone.
