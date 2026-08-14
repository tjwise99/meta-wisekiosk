# Pi kiosk inventory

> **Two cards exist. This file covers both, and every section says which.**
>
> **Card B — Yocto (AutonomOS 0.1, kernel 6.6.63), 28.9 GB, A/B slots, RAUC — IS IN THE DEVICE.**
> **Card A — Raspbian/Chromium on the SL16G — is the rollback artifact, on a shelf.**
>
> The Card B material below was written 2026-08-12 from repo sources. Everything under
> §"Identity and hardware" onward is the **original Card A inventory, captured 2026-08-05 over
> SSH** — observed, not remembered. It is kept verbatim because it is still accurate about the card
> you would swap back in, and that card is the recovery plan. Live state is in
> `STATUS.md` (kiosk-reference).

## Two cards. Read this before anything below.

Two SD cards have carried this board's OS. **They are not the same machine**, and every section below
is split accordingly. Mixing a fact from one into a description of the other is the failure mode this
rewrite exists to close — the previous version of this file described only the first card and never
said so, which reads as "the machine" rather than "one of two states it has been in."

| | Card A — Raspbian (`SL16G`) | Card B — Yocto (`AutonomOS`) |
|---|---|---|
| Status as of this writing | **shelved — the rollback artifact** | **in the device, running** |
| Where | on the shelf, untouched | in the Pi, on the bench (not yet wall-mounted) |
| To make it live | physical card swap + power cycle | already live |
| First became live | 2019 (predates this repo) | 2026-08-11 ~23:40 |

```bash
# ROLLBACK to Card A (physical, always valid): power off, swap the SL16G card in, power on.
```

**Which one is actually in the device right now can change** — that is exactly the fact this file
must never assert on its own authority. `STATUS.md`'s top section is the single source of truth for
current state; treat everything below as "true of that card when it is the one inserted," not as "true
of the device today."

## Identity and hardware — the board itself, unchanged by which card is in it

| | |
|---|---|
| Model | Raspberry Pi **Zero W Rev 1.1** (BCM2835, revision `9000c1`) |
| Serial | `0000000024caf304` |
| MAC | `<PI_MAC>` (`B8:27:EB` = Raspberry Pi Foundation OUI) — same board, same address regardless of card (`STATUS.md:276`) |
| User-facing address | `192.168.1.6` on `wlan0` (DHCP), both cards |

```
Architecture:   armv6l          <- not armhf/ARMv7; this is the whole problem
CPU(s):         1
Model name:     ARMv6-compatible processor rev 7 (v6l)
CPU max MHz:    1000
```

One core, ARMv6, no NEON, no ARMv7 code will run — this is the fact that shapes every later decision
in this repo (Chromium's ARMv6 ceiling, WebKit's `scarthgap` branch choice, JIT disabled). It does not
change between cards.

| Memory | |
|---|---|
| Total RAM | 512MB, split **448MB ARM / 64MB GPU** |

**Confirmed on Card B, 2026-08-12:** `vcgencmd get_mem arm` → `448M`, `get_mem gpu` → `64M`.
Every `gpu_mem*` line in Card B's `/boot/config.txt` is commented out, so this is the firmware
default for a 512 MB board, not a configured split — and it therefore matches Card A by coincidence
of the default rather than by carried configuration.

## Storage and partition layout

### Card B — Yocto, in the device now

**28.9 GB, A/B layout** (`STATUS.md:281`):

| Partition | Contents |
|---|---|
| `p1` | boot (firmware, kernel images for both slots, `uboot.env`) |
| `p2` | `rootfs-a` (slot A) |
| `p3` | `rootfs-b` (slot B) |
| `p4` | `/data` — persistent, survives every A/B update. **479 MB** (`STATUS.md:256`) |

Image: `core-image-base-raspberrypi0-wifi` (`STATUS.md:339`). Each rootfs slot is replaced wholesale
by an OTA update; `/data` is the only partition an update does not touch, which is why the journal,
soak log and RAUC status all live there (`docs/image-migration.md` and `docs/service-changes.md`
cover *what* lives there; this file is only the partition fact).

**Measured on the device, 2026-08-12** (`fdisk -l /dev/mmcblk0`, `blkid`, `df -h`):

| Partition | Size | Type | Mount | Used |
|---|---|---|---|---|
| `p1` | 260 MB | `vfat` (W95 FAT32 LBA, boot flag) | `/boot` | 30.2 MB |
| `p2` | 2 GB | `ext4` | rootfs slot A | — |
| `p3` | 2 GB | `ext4` | rootfs slot B | — |
| `p4` | 512 MB | `ext4` | `/data` | 262.7 MB of 479 MB |

Disklabel is `dos`, identifier `0x076c4a2a`. The two rootfs slots are deliberately equal at 2 GB —
an update writes a whole slot, so they must be interchangeable. The booted slot reports 1.8 GB
usable with ~300 MB in use, which is the headroom the module trim is spending against.

### Card A — Raspbian (`SL16G`), the rollback artifact

Captured 2026-08-05 over SSH, while this card was still the running system. Unchanged since — it has
sat untouched on the shelf.

| | |
|---|---|
| Card | `SL16G`, serial `<CARD_SERIAL>`, manufactured **08/2019** |
| Capacity | **15,931,539,456 bytes** (15,192 MiB) |
| Root | `/dev/mmcblk0p7`, 14G, 49% used |
| Boot | `/dev/mmcblk0p6`, 68M (FAT32, mounts as `boot` in Windows) |

Installed via **NOOBS** — hence the unusual layout (`p6` boot, `p7` root rather than the usual
`p1`/`p2`) and the `os_config.json` on the boot partition. `p1` is not optional:

| Partition | Size | Contents |
|---|---|---|
| `mmcblk0p1` | 1.4G | FAT16, NOOBS bootloader/recovery — **needed to boot** |
| `mmcblk0p2` | — | extended container |
| `mmcblk0p5` | 32M | NOOBS settings |
| `mmcblk0p6` | 69M | `/boot`, 23M used |
| `mmcblk0p7` | 13.4G | root — 7.05GB used, 7.31GB free (`dumpe2fs`: 3,505,536 blocks × 4096, 1,783,664 free) |

> **Read the units before comparing these.** `df` reports **GiB** excluding reserved blocks — that is
> "14G, 49% used". `dumpe2fs` used-blocks × 4096 is **7.05 GB** decimal, and a file-level copy of the
> same data is quoted elsewhere as **~6.3 GB**. All three describe one filesystem; none corrects
> another. Unlabelled units are the defect.

Sequential read **2026-08-05: 22.9 MB/s** (`dd bs=1M count=100 iflag=direct`, n=1); a separate
**2026-08-06** run measured **22.7 MB/s** (n=3: 22.7 / 22.6 / 22.7) — see
[`backup-recovery.md`](backup-recovery.md). `dmesg` was clean on this card — no I/O errors, no bad
sectors — as of the date it was last live. It has not been re-checked since being shelved; it is a
wear candidate after 24/7 service since 2019, so re-verify before ever making it live again rather
than trusting this reading.

## Operating system

### Card B — Yocto, in the device now

```
AutonomOS 0.1
Linux 6.6.63
```

(`STATUS.md:267-268`, `docs/experiment-log.md:257`). Built from the `scarthgap` (LTS) Yocto release —
`meta-raspberrypi`, `meta-openembedded`, `meta-rauc`, `meta-rauc-community` and `meta-lts-mixins` are
all pinned to it via `includes/base.yaml` in the build tree (`docs/yocto-ota-plan.md:414-433`).
Reference architecture copied from **`meta-autonomos`** (`github.com/jsmith212/meta-autonomos`,
read 2026-08-10) — that upstream targets Pi 5 and Pi Zero 2 W (ARMv7/v8), so its shape was copied,
its board support was not; this board's port is this project's own work.

Browser: `surf` 2.1 on **WebKitGTK 2.44.3**, `ENABLE_JIT=OFF`, confirmed genuine ARMv6 hard-float by
`readelf -A` (`Tag_CPU_arch: v6KZ`) — `docs/yocto-ota-plan.md:324-335`. This replaces Card A's Chromium
entirely; Chromium was ruled **out of scope for this image** (owner, 2026-08-10,
`docs/yocto-ota-plan.md`) because it has no ARMv6 build past 72 and a Yocto card has nothing to `mv`
back to. Ceiling/feature detail for this engine belongs to
[`browser-constraints.md`](browser-constraints.md), not here — as of this writing that document has
not yet been updated to describe it (flagged in the doc-audit, 2026-08-12; not this file's job to fix).

### Card A — Raspbian (`SL16G`), the rollback artifact

```
Raspbian GNU/Linux 9 (stretch)      released 2018-03-13
Linux 4.19.66+ #1253                Aug 2019
```

Browser: Chromium 72 side-by-side install, system package frozen at 60 — see §"Browser" below.

## Boot chain — the mechanism, not the timing

### Card B — Yocto: firmware → U-Boot → RAUC slot selection → kernel → systemd

```
SoC ROM/GPU firmware (bootcode.bin / start.elf, on p1)
  └─ U-Boot (rpi_0_w_defconfig, RPI_USE_U_BOOT="1")
       └─ reads BOOT_ORDER, BOOT_A_LEFT, BOOT_B_LEFT from the U-Boot environment,
          /boot/uboot.env (docs/boot-profile-yocto.md:353), and boots the selected slot
       └─ kernel 6.6.63, the selected slot's rootfs
            └─ systemd
                 └─ kiosk.service → /usr/bin/kiosk-launch (image copy, md5
                    5178acbe5a7b46b0754e5407da12c17a — STATUS.md:199-207) → surf,
                    bare Xorg, no window manager, no display-manager session chain
                    (Phase 2 of the OTA plan, passed — docs/yocto-ota-plan.md:309)
```

`rauc-mark-good` runs at ~33 s into boot and resets the per-slot boot-attempt counter — this is what
turns a successful boot into "this slot stays in `BOOT_ORDER`" (`docs/image-trim-recommendations.md:61`,
`STATUS.md:153-154`). A boot that dies before ~33 s (e.g. a kernel panic) burns an attempt without
this ever running; three in a row drops that slot from `BOOT_ORDER` (`STATUS.md:154-156`).

U-Boot's environment shares its 0x4000 block with the RAUC boot-order variables
(`docs/boot-profile-yocto.md:353`) — this is why `bootdelay` must ship in the image's initial
environment rather than be set with `fw_setenv` on the running board: a hang mid-write to that block
(this board takes unexplained hangs) drops U-Boot to its built-in default environment, which carries
no RAUC logic at all (`docs/boot-profile-yocto.md:352-358`). `bootdelay` is **currently 2** (confirmed
on the device, `docs/boot-profile-yocto.md:342-343`); a build with `bootdelay=0` is decided
(owner, 2026-08-12) but **not yet shipped** as of the most recent `STATUS.md` entry
(`STATUS.md:26`) — check `STATUS.md`'s top section for whether that has landed since.

Recovery layered on top of this chain, in case a boot goes wrong: `panic=10` on the kernel command
line (deployed `cmdline.txt` md5 `0ef67fa722f47036d60e31bfb50d75f2`) turns an unrecoverable early
kernel panic into a 60-second unattended outage instead of a hang needing a person, and a hardware
watchdog (`RuntimeWatchdogSec=14`) covers a wedge anywhere else in the boot. Both are proven by firing
them, not merely inspected — see `STATUS.md`'s top section for the current state of each; this file
only records that the mechanism exists.

### Card A — Raspbian: NOOBS bootloader → kernel → systemd → session chain

```
NOOBS bootloader (mmcblk0p1, FAT16 — needed to boot)
  └─ kernel 4.19.66+
       └─ systemd
            └─ lightdm (autologin pi)
                 └─ LXDE session
                      └─ ~/.config/lxsession/LXDE-pi/autostart
                           └─ @/home/pi/mmClient.sh → chromium-browser (side-by-side 72 build)
```

No A/B, no signed-bundle update path, no slot concept — a bad flash on this card needs a physical
reflash, which is exactly the property Card B's boot chain was built to remove.

## Package and firmware provenance

### Card B — Yocto

Build tree: **`~/meta-wisekiosk`** on the workstation (not on the device), branch **`zero-w-port`**.
It has a GitHub remote (`github.com/tjwise99/meta-wisekiosk`, public per
`docs/yocto-ota-plan.md:232`) and is committed and pushed. An earlier restriction on touching
GitHub for that repo was scoped to a single session (owner, 2026-08-12) and does not stand.
A clean checkout of `zero-w-port` reproduces the card in the device: the recipes the running image
depends on were committed 2026-08-12 evening, having until then lived only in the working tree
(`kiosk-journal`, `kiosk-soak`, the `raspberrypi0-wifi` RAUC files — `STATUS.md:247-249`). **Commit
before building anything new from this tree**, or the delta is at risk of being lost.

WiFi firmware: `brcmfmac43430-sdio.*`, **11 files** — this is the lifeline (no ethernet on this board)
and is re-checked as present on every build, since removing Bluetooth from the same combo BCM43430
part removes only the BT patch, not the WiFi firmware (`docs/image-migration.md:80`,
`STATUS.md:74-76`). Paired with a `wpa_supplicant.service.d/robust.conf` drop-in (ordering +
`Restart=on-failure`) that is now baked into the image, not runtime-only
(`docs/image-migration.md:41`).

Delivery mechanism: signed **RAUC** bundles (`.raucb`), signature verified against
`/etc/rauc/keyring.pem` (`/etc/rauc/system.conf`), built and installed via `just kiosk-ota` /
`kiosk-bundle` / `kiosk-send` / `kiosk-install` / `kiosk-reboot` / `kiosk-rollback` recipes in the
build tree, delivered over SSH by [`../tools/send-bundle-chunked.sh`](../tools/send-bundle-chunked.sh)
(`STATUS.md:48-51`) — the transfer *shape* that works is `experiment-log.md`'s territory, not this
file's; see that document before attempting a transfer.

### Card A — Raspbian

**This section owns the archive facts for this card.** The configured host is dead, so `apt update`
fails, `apt-get download` 404s, and a plain `apt install` of anything not cached fails. **The archive
itself moved.** Verified with `curl`, 2026-08-06:

| Endpoint | stretch `Release` | |
|---|---|---|
| `raspbian.raspberrypi.org/raspbian` | **404** | the host the device is configured to use |
| `raspbian.raspberrypi.com/raspbian` | 404 | |
| `mirrordirector.raspbian.org/raspbian` | 404 | |
| `archive.raspbian.org/raspbian` | 404 | |
| **`legacy.raspbian.org/raspbian`** | **200** | **the archive moved here** |
| `archive.raspberrypi.org/debian` | 200 | Raspberry Pi archive, holds Chromium |
| `archive.debian.org/debian` | 200 | Debian proper — caveat below |

`legacy.raspbian.org/raspbian` `dists/stretch/Release` reports `Origin: Raspbian`,
`Suite: oldoldstable`, `Codename: stretch`, `Architectures: armhf`,
`Components: main contrib non-free rpi firmware`, `Date: Sun, 23 Apr 2023 10:15:53 UTC`.

Real pool, not a stub: the exact package that 404'd on the device (`pool/main/p/pv/pv_1.6.0-1_armhf.deb`)
downloads from it — HTTP 200, **45,914 bytes**, valid `Debian binary package (format 2.0)`, and
`readelf -A` reports **`Tag_CPU_arch: v6`**, the genuine ARMv6 rebuild rather than an ARMv7 lookalike.

> **Corrected 2026-08-06.** Three documents stated **"this machine cannot be rebuilt"** because the
> base archive was gone. Wrong as written — the machine is **repairable** by repointing `sources.list`.

Two things that do **not** follow:

- **The backup priority does not drop.** `legacy.raspbian.org` is a third party's frozen archive that
  could vanish; a rebuild is not *this* machine's state. See [`backup-recovery.md`](backup-recovery.md).
- **`archive.debian.org` is not established as a substitute.** The concern that its armhf packages are
  ARMv7-built and would brick an ARMv6 board is **unverified** — the comparison package 404'd, so no
  architecture tag was read. Plausible, not proven. Do not upgrade it to a fact.

**Repointing is safe; upgrading afterwards is not.** Editing `sources.list` back undoes it. But **69
upgrades are pending** on a system untouched since 2019, including `libc`, `openssh`, `dhcpcd` and
`wpa_supplicant` — the SSH lifeline and the network stack. Install named packages deliberately; never
`apt upgrade` or `apt full-upgrade`.

**`apt-get install -s` lies here.** `apt-get install -s pv` reports a clean install;
`apt-get download pv` returns **404**. The index is cached locally while the archive it points at is
dead, so simulation reports success for packages that cannot be fetched.

## Browser — what's installed, not the ceiling/feature analysis

Ceiling, feature gaps and build-target reasoning are [`browser-constraints.md`](browser-constraints.md)'s
job (see the note in §"Operating system" above about that document being behind). This section is only
what's on disk.

### Card B — Yocto

`surf` 2.1 linked against `libwebkit2gtk-4.1.so.0` / `libgtk-3.so.0`, shipped size 45 MB stripped
(`docs/yocto-ota-plan.md:326-334`). No side-by-side install — one browser, ships with the image.

### Card A — Raspbian

Two are present; the kiosk runs the second.

| | System package | Side-by-side |
|---|---|---|
| Version | 60.0.3112.89 | **72.0.3626.121-0+rpt4** |
| Path | `/usr/lib/chromium-browser/` | `/opt/chromium-72/usr/lib/chromium-browser/` |
| Origin | Ubuntu 14.04 build, shipped with the image | extracted from `/var/cache/apt/archives` |
| Profile | `~/.config/chromium` (55MB) | `~/.config/chromium-72` |

72 was never installed via `dpkg` — a plain extraction, so the package database still records 60 and
rollback needs no package operation:
`mv /home/pi/mmClient.sh.chromium60 /home/pi/mmClient.sh && sudo reboot` (md5
`f3315ceacbb09bead1b6bab348f67dc4`).

## Network

`wlan0` only on both cards — the Zero W has no ethernet, so this is the one lifeline regardless of
which card is inserted. Same physical MAC on both. WiFi chip is on SDIO (`mmc1`), driven by
`brcmfmac`; that bus's behaviour under sustained load is under active investigation and belongs to
[`experiment-log.md`](experiment-log.md), not here — this file only records that the chip is on
`mmc1`, shared with no other device.

### Card A only

SSID `<SSID>`, WPA-PSK, config at `/etc/wpa_supplicant/wpa_supplicant.conf`. Latency to a LAN peer
~5–12ms, 0% loss.

## Access

### Card B — Yocto

```bash
ssh root@192.168.1.6
```

**root, no password** — the image ships `debug-tweaks` (`STATUS.md:277`). The host key differs from
Card A's; an existing `known_hosts` entry for this address will conflict and must be replaced, not
merged. Whether an empty root password is acceptable for a wall-mounted device is an open hardening
question tracked in `STATUS.md`, not decided here.

### Card A — Raspbian

```bash
ssh -i ~/.ssh/id_ed25519 pi@192.168.1.6
```

SSH was **not** enabled originally and the `pi` password was unknown. Both fixed 2026-08-05: SSH by
placing an empty file named `ssh` on the FAT boot partition; password by `sudo passwd pi` from a local
terminal (needs no prior credential — `pi` has passwordless sudo). This machine's `id_ed25519` public
key is in `~/.ssh/authorized_keys`. OpenSSH on the Pi is **7.4p1** — a modern client connects fine but
prints a post-quantum key-exchange warning, cosmetic.

## Not owned here

- **Boot timing and blame analysis** — Card A: the Raspbian card notes (kiosk-reference `raspbian-card.md`) (the systemd-unit
  contention analysis previously in this file belongs there and has been removed from here to avoid
  two owners for one fact; see that document's boot-related sections and its "For the successor"
  summary). Card B: [`boot-profile-yocto.md`](boot-profile-yocto.md).
- **Every service masked, disabled or changed, and whether it was justified** —
  [`service-changes.md`](service-changes.md).
- **What was tried on the Yocto card and did not work** — [`experiment-log.md`](experiment-log.md).
- **What to cut from the Yocto image, ranked by cost** —
  [`image-trim-recommendations.md`](image-trim-recommendations.md).
- **Device changes not yet in the build tree** — [`image-migration.md`](image-migration.md).
- **Current device state, which card is actually live, open hazards** — `STATUS.md` (kiosk-reference).
  Always read that one first.

---


---

# Card A — Raspbian on the SL16G (the rollback artifact)

Captured 2026-08-05 over SSH. Observed, not remembered — several things "remembered" about this box
turned out to be wrong. **This describes the shelved card, not the running device.**

## Identity and hardware

| | |
|---|---|
| Hostname | `<KIOSK_HOSTNAME>` |
| Model | Raspberry Pi **Zero W Rev 1.1** (BCM2835, revision `9000c1`) |
| Serial | `0000000024caf304` |
| Address | `192.168.1.6` on `wlan0` (DHCP) |
| MAC | `<PI_MAC>` (`B8:27:EB` = Raspberry Pi Foundation OUI) |
| User | `pi`, autologin via lightdm |

```
Architecture:   armv6l          <- not armhf/ARMv7; this is the whole problem
CPU(s):         1
Model name:     ARMv6-compatible processor rev 7 (v6l)
CPU max MHz:    1000
```

| Memory | |
|---|---|
| Total RAM | 512MB, split **448MB ARM / 64MB GPU** |
| Visible to OS | 432MB |
| Swap | 100MB file at `/var/swap` (`dphys-swapfile`) |
| Typical free | ~30–170MB depending on browser state |

Chromium alone sits around 150MB resident. Swap is on the SD card, so memory pressure and I/O pressure
are the same problem.

## Storage

| | |
|---|---|
| Card | `SL16G`, serial `<CARD_SERIAL>`, manufactured **08/2019** |
| Capacity | **15,931,539,456 bytes** (15,192 MiB) |
| Root | `/dev/mmcblk0p7`, 14G, 49% used |
| Boot | `/dev/mmcblk0p6`, 68M (FAT32, mounts as `boot` in Windows) |

Installed via **NOOBS** — hence the unusual layout (`p6` boot, `p7` root rather than the usual
`p1`/`p2`) and the `os_config.json` on the boot partition. `p1` is not optional:

| Partition | Size | Contents |
|---|---|---|
| `mmcblk0p1` | 1.4G | FAT16, NOOBS bootloader/recovery — **needed to boot** |
| `mmcblk0p2` | — | extended container |
| `mmcblk0p5` | 32M | NOOBS settings |
| `mmcblk0p6` | 69M | `/boot`, 23M used |
| `mmcblk0p7` | 13.4G | root — 7.05GB used, 7.31GB free (`dumpe2fs`: 3,505,536 blocks × 4096, 1,783,664 free) |

> **Read the units before comparing these.** `df` reports **GiB** excluding reserved blocks — that is
> "14G, 49% used". `dumpe2fs` used-blocks × 4096 is **7.05 GB** decimal, and a file-level copy of the
> same data is quoted elsewhere as **~6.3 GB**. All three describe one filesystem; none corrects
> another. Unlabelled units are the defect.

Sequential read **2026-08-05: 22.9 MB/s** (`dd bs=1M count=100 iflag=direct`, n=1); a separate
**2026-08-06** run measured **22.7 MB/s** (n=3: 22.7 / 22.6 / 22.7) — see
[`backup-recovery.md`](backup-recovery.md). Distinct samples, neither averaged into the other. Browser
startup is dominated by *random* I/O, so this understates the cost of a 55MB profile. A card running a
24/7 kiosk since 2019 is a wear candidate; nothing has failed, but suspect it first if boot times climb.

`dmesg` is clean — no I/O errors, no bad sectors.

> **Corrected 2026-08-06.** This previously said the card "survived an unclean shutdown with no ext4
> recovery". The boot log does show
> `EXT4-fs (mmcblk0p7): INFO: recovery required on readonly filesystem`
> followed by `recovery complete`. That is **routine journal replay after a power-cycle,
> not corruption** — both halves matter, since the line alone reads like a fault and the original
> sentence read like a clean bill of health.

## Operating system

```
Raspbian GNU/Linux 9 (stretch)      released 2018-03-13
Linux 4.19.66+ #1253                Aug 2019
```

## Package archives and what can be installed

**This section owns the archive facts for the repository.** The configured host is dead, so
`apt update` fails, `apt-get download` 404s, and a plain `apt install` of anything not cached fails
— which is what made the desktop and X server look unobtainable. **The archive itself moved.** Verified
with `curl`, 2026-08-06:

| Endpoint | stretch `Release` | |
|---|---|---|
| `raspbian.raspberrypi.org/raspbian` | **404** | the host the device is configured to use |
| `raspbian.raspberrypi.com/raspbian` | 404 | |
| `mirrordirector.raspbian.org/raspbian` | 404 | |
| `archive.raspbian.org/raspbian` | 404 | |
| **`legacy.raspbian.org/raspbian`** | **200** | **the archive moved here** |
| `archive.raspberrypi.org/debian` | 200 | Raspberry Pi archive, holds Chromium |
| `archive.debian.org/debian` | 200 | Debian proper — caveat below |

`legacy.raspbian.org/raspbian` `dists/stretch/Release` reports `Origin: Raspbian`,
`Suite: oldoldstable`, `Codename: stretch`, `Architectures: armhf`,
`Components: main contrib non-free rpi firmware`, `Date: Sun, 23 Apr 2023 10:15:53 UTC`.

Real pool, not a stub: the exact package that 404'd on the device (`pool/main/p/pv/pv_1.6.0-1_armhf.deb`)
downloads from it — HTTP 200, **45,914 bytes**, valid `Debian binary package (format 2.0)`, and
`readelf -A` reports **`Tag_CPU_arch: v6`**, the genuine ARMv6 rebuild rather than an ARMv7 lookalike.

> **Corrected 2026-08-06.** Three documents stated **"this machine cannot be rebuilt"** because the
> base archive was gone. Wrong as written — the machine is **repairable** by repointing `sources.list`.

Two things that do **not** follow:

- **The backup priority does not drop.** `legacy.raspbian.org` is a third party's frozen archive that
  could vanish; a rebuild is not *this* machine's state. See [`backup-recovery.md`](backup-recovery.md).
- **`archive.debian.org` is not established as a substitute.** The concern that its armhf packages are
  ARMv7-built and would brick an ARMv6 board is **unverified** — the comparison package 404'd, so no
  architecture tag was read. Plausible, not proven. Do not upgrade it to a fact.

**Repointing is safe; upgrading afterwards is not.** Editing `sources.list` back undoes it. But **69
upgrades are pending** on a system untouched since 2019, including `libc`, `openssh`, `dhcpcd` and
`wpa_supplicant` — the SSH lifeline and the network stack. Install named packages deliberately; never
`apt upgrade` or `apt full-upgrade`.

**`apt-get install -s` lies here.** `apt-get install -s pv` reports a clean install;
`apt-get download pv` returns **404**. The index is cached locally while the archive it points at is dead, so simulation
reports success for packages that cannot be fetched. Both halves verified on the device.

Upgrading the *browser* needs none of this — the debs are already cached. See
[`browser-constraints.md`](browser-constraints.md).

## Display and session

| | |
|---|---|
| Desktop | LXDE 9+rpi1 (`lxde-core`, `lxde-common 0.99.2-3`) |
| Display manager | lightdm 1.18.3, `autologin-user=pi` |
| WM | openbox (`libobrender32v5`, `libobt2v5` 3.6.1) |
| X config | no `/etc/X11/xorg.conf.d/` overrides |

HDMI is forced on so the display survives the TV being off at boot. `hdmi_force_hotplug=1` appears
twice in `/boot/config.txt` — harmless duplication.

```ini
hdmi_force_hotplug=1
hdmi_group=1        # CEA
hdmi_mode=16        # 1080p 60Hz
dtparam=audio=on
```

**Screen blanking is suppressed, but not where you would look.** `xscreensaver` is commented out of the
autostart and there is no `xset s off -dpms` anywhere, which reads as "unconfigured". It is handled on
the X server command line via lightdm: `/usr/lib/xorg/Xorg -s 0 -dpms -nocursor :0 -seat seat0 …` —
`-s 0` kills the screensaver timeout, `-dpms` power management, `-nocursor` the pointer. Confirmed by
reading the running process, not the config files. An earlier revision claimed blanking was
unconfigured; that was wrong.

## Kiosk launch chain

```
lightdm (autologin pi)
  └─ LXDE session
       └─ ~/.config/lxsession/LXDE-pi/autostart     (user file overrides /etc/xdg/...)
            ├─ @lxpanel --profile LXDE-pi
            │  #@pcmanfm --desktop --profile LXDE-pi
            │  #@xscreensaver -no-splash
            │  #@point-rpi
            └─ @/home/pi/mmClient.sh
```

`~/mmClient.sh` — **1,483 bytes**, md5 `f3315ceacbb09bead1b6bab348f67dc4`, byte-identical to
`mmClient.sh` (kiosk-reference). **Restore from `tools/`, never from a transcription in
a document** — an earlier full transcription here silently omitted the comment header while claiming
to be complete, which is why the file is summarised below rather than reproduced.

Structure: a `while true` loop around one `chromium-browser` invocation with `sleep 10` between
restarts, so a failed load recovers instead of leaving a black screen.

| Flag group | Why |
|---|---|
| `/opt/chromium-72/…` | side-by-side ARMv6 build; the system package stays at 60, so revert is a file move |
| `--user-data-dir=…/chromium-72` | separate profile — 72 would migrate the 60 profile to a format 60 cannot read, making the revert one-way |
| `--kiosk --start-maximized --app=<url>` | fullscreen, no chrome |
| `--remote-debugging-port=9222` | iterate over an SSH tunnel without rebooting; bound to `127.0.0.1` |
| `--disable-gpu` | **the startup fix** — see the Raspbian card notes (kiosk-reference `raspbian-card.md`) |
| `--disable-background-networking`, `--disable-component-update`, `--disable-sync`, `--disable-extensions`, `--disable-default-apps`, `--disable-breakpad`, `--disable-translate`, `--disable-client-side-phishing-detection`, `--disable-domain-reliability`, `--no-first-run`, `--no-default-browser-check`, `--password-store=basic` | one LAN page, and egress to 80/443 is firewalled, so these fetches cannot succeed anyway |

Revert is one line, no package operation:
`mv /home/pi/mmClient.sh.chromium60 /home/pi/mmClient.sh && sudo reboot`

It originally had **neither the loop nor the debug port** — a single `chromium-browser` line. No retry
loop meant one failed load stayed black until someone power-cycled it; no remote debugging meant every
failure looked identical from outside.

> **`openbox` is load-bearing, despite starting *after* chromium.** Verified 2026-08-06 with `xprop`:
> a WM is registered (`_NET_SUPPORTING_WM_CHECK`) and chromium's window holds
> `_NET_WM_STATE_FULLSCREEN`. A client cannot set that itself — `--kiosk` *requests* fullscreen by
> `_NET_WM_STATE` client message and the **window manager grants it**. With no WM the request goes
> unanswered. Its 14.3MB buys the fullscreen. Process start order is misleading here: chromium's
> window does not map until ~25s after exec, long after openbox is up.
>
> Running without a WM would mean hardcoding `--window-size`, pinning a geometry that depends on
> overscan settings living in `/boot/config.txt`. A lighter WM saves ~12MB, **zero** startup time, and
> costs a package install from a third-party frozen archive.

> **The panel runs at 1824x984, not 1920x1080.** `hdmi_mode=16` is 1080p; overscan trims it. The
> chromium window matches the root window exactly. That is **13% fewer pixels to composite**, which
> helps the software rasteriser — and changing it would mean editing `/boot`.

> **PM2 is not installed and never was.** No `pm2` binary, no `~/.pm2`. Only `/usr/bin/node`
> (**v8.11.1**) exists. The kiosk has always been a bare shell script.

## Browser

Two are present; the kiosk runs the second.

| | System package | Side-by-side |
|---|---|---|
| Version | 60.0.3112.89 | **72.0.3626.121-0+rpt4** |
| Path | `/usr/lib/chromium-browser/` | `/opt/chromium-72/usr/lib/chromium-browser/` |
| Origin | Ubuntu 14.04 build, shipped with the image | extracted from `/var/cache/apt/archives` |
| Profile | `~/.config/chromium` (55MB) | `~/.config/chromium-72` |

72 was never installed via `dpkg` — a plain extraction, so the package database still records 60 and
rollback needs no package operation.

The **Chromium 60 profile** has two extensions, unusual for a kiosk and worth knowing when debugging
blocked requests: `cjpalhdlnbpafiamejdnhcphjbkeiagm` (uBlock Origin) and
`aleakchihdccplidncghkekgioiakgal` (unidentified — check before trusting network behaviour). uBlock's
renderer measured **87MB RSS**, a fifth of the machine's memory, parsing filter lists at every start,
for a kiosk showing one LAN page. The 72 profile is fresh and has neither.

## Network

`wlan0` only (the Zero W has no ethernet). SSID `<SSID>`, WPA-PSK, config at
`/etc/wpa_supplicant/wpa_supplicant.conf`. Latency to a LAN peer ~5–12ms, 0% loss, jitter ~2ms idle and
~7ms busy — the jitter rise under load is a usable proxy for "the Pi is busy" when you have no other
telemetry. Wi-Fi has never been the bottleneck.

## Boot timing

Moved to the Raspbian card notes (kiosk-reference `raspbian-card.md`) §"Boot itself: systemd unit blame vs wall clock, and
the hardware floor" on 2026-08-12 — it is measurement, and that file owns "what was slow, and what
fixed it". Nothing was dropped in the move; it was verified atom-by-atom with `tools/doc-facts.py`.

For the **Yocto** card's boot timing, which is a different machine, see
[`boot-profile-yocto.md`](boot-profile-yocto.md).

## Access

SSH was **not** enabled originally and the `pi` password was unknown. Both fixed 2026-08-05: SSH by
placing an empty file named `ssh` on the FAT boot partition (readable from Windows); password by
`sudo passwd pi` from a local terminal, which needs no prior credential because `pi` has
passwordless sudo.
This machine's `id_ed25519` public key is in `~/.ssh/authorized_keys`.

```bash
ssh -i ~/.ssh/id_ed25519 pi@192.168.1.6
```

OpenSSH on the Pi is **7.4p1**. A modern client connects fine but prints a post-quantum key-exchange
warning — cosmetic, filter it out of scripted output.
