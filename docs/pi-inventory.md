# Pi kiosk inventory

Inventory for the Yocto (AutonomOS 0.1, kernel 6.6.63) build running on this Raspberry Pi Zero W
kiosk. Written 2026-08-12 from repo sources and confirmed against the device. Live state — which
build is actually running, open hazards — is `STATUS.md` (kiosk-reference), not here.

**Rollback artifact:** the SL16G Raspbian card is the documented, physical rollback — power off, swap
it in, power on. Its full inventory lives in `raspbian-card.md` (kiosk-reference repo), not here.

## Identity and hardware

| | |
|---|---|
| Model | Raspberry Pi **Zero W Rev 1.1** (BCM2835, revision `9000c1`) |
| Serial | `<PI_SERIAL>` |
| MAC | `<PI_MAC>` (`B8:27:EB` = Raspberry Pi Foundation OUI) (`STATUS.md:276`) |
| User-facing address | `<KIOSK_IP>` on `wlan0` (DHCP) |

```
Architecture:   armv6l          <- not armhf/ARMv7; this is the whole problem
CPU(s):         1
Model name:     ARMv6-compatible processor rev 7 (v6l)
CPU max MHz:    1000
```

One core, ARMv6, no NEON, no ARMv7 code will run — this is the fact that shapes every later decision
in this repo (Chromium's ARMv6 ceiling, WebKit's `scarthgap` branch choice, JIT disabled).

| Memory | |
|---|---|
| Total RAM | 512MB, split **448MB ARM / 64MB GPU** |

**Confirmed 2026-08-12:** `vcgencmd get_mem arm` → `448M`, `get_mem gpu` → `64M`. Every `gpu_mem*`
line in `/boot/config.txt` is commented out, so this is the firmware default for a 512 MB board, not
a configured split.

## Storage and partition layout

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

## Operating system

```
AutonomOS 0.1
Linux 6.6.63
```

(`STATUS.md`, kiosk-reference; and [`experiment-log.md`](experiment-log.md) §"Kernel panic at 4.0 s in `mmc_rescan` — a separate, still-real hazard"). Built from the `scarthgap` (LTS) Yocto release —
`meta-raspberrypi`, `meta-openembedded`, `meta-rauc`, `meta-rauc-community` and `meta-lts-mixins` are
all pinned to it via `includes/base.yaml` in the build tree (`docs/yocto-ota-plan.md:414-433`).
Reference architecture copied from **`meta-autonomos`** (`github.com/jsmith212/meta-autonomos`,
read 2026-08-10) — that upstream targets Pi 5 and Pi Zero 2 W (ARMv7/v8), so its shape was copied,
its board support was not; this board's port is this project's own work.

Browser: `surf` 2.1 on **WebKitGTK 2.44.3**, `ENABLE_JIT=OFF`, confirmed genuine ARMv6 hard-float by
`readelf -A` (`Tag_CPU_arch: v6KZ`) — `docs/yocto-ota-plan.md:324-335`. The Raspbian card ran Chromium
instead; that path was ruled **out of scope for this image** (owner, 2026-08-10,
`docs/yocto-ota-plan.md`) because Chromium has no ARMv6 build past 72, and this card has nothing to
`mv` back to the way the Raspbian side-by-side install did. Ceiling/feature detail for this engine
belongs to [`browser-constraints.md`](browser-constraints.md), not here.

## Boot chain — the mechanism, not the timing

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
no RAUC logic at all (`docs/boot-profile-yocto.md:352-358`). `bootdelay=0` ships in the image (decided by the owner 2026-08-12; confirmed on the reflashed card,
`fw_printenv bootdelay=0`).

Recovery layered on top of this chain, in case a boot goes wrong: `panic=10` on the kernel command
line (deployed `cmdline.txt` md5 `0ef67fa722f47036d60e31bfb50d75f2`) turns an unrecoverable early
kernel panic into a 60-second unattended outage instead of a hang needing a person, and a hardware
watchdog (`RuntimeWatchdogSec=14`) covers a wedge anywhere else in the boot. Both are proven by firing
them, not merely inspected — see `STATUS.md`'s top section for the current state of each; this file
only records that the mechanism exists.

The Raspbian card had no A/B slots and no signed-bundle update path — a bad flash there needed a
physical reflash, which is exactly the property this A/B boot chain was built to remove.

## Package and firmware provenance

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

## Browser — what's installed, not the ceiling/feature analysis

Ceiling, feature gaps and build-target reasoning are [`browser-constraints.md`](browser-constraints.md)'s
job (see the note in §"Operating system" above about that document being behind). This section is only
what's on disk.

`surf` 2.1 linked against `libwebkit2gtk-4.1.so.0` / `libgtk-3.so.0`, shipped size 45 MB stripped
(`docs/yocto-ota-plan.md:326-334`). No side-by-side install — one browser, ships with the image.

## Network

`wlan0` only — the Zero W has no ethernet, so this is the one lifeline. WiFi chip is on SDIO
(`mmc1`), driven by `brcmfmac`. That bus's instability under sustained load is resolved — the root cause was
top-OPP memory corruption, fixed by the `kiosk-cpufreq` cap; the investigation is in
[`experiment-log.md`](experiment-log.md), not here. This file only records that the chip is on
`mmc1`, shared with no other device.

## Access

```bash
ssh root@<KIOSK_IP>
```

**root, no password** — the image ships `debug-tweaks` (`STATUS.md:277`). The host key differs from
the Raspbian card's; an existing `known_hosts` entry for this address will conflict and must be
replaced, not merged. Whether an empty root password is acceptable for a wall-mounted device is an
open hardening question tracked in `STATUS.md`, not decided here.

## Not owned here

- **Boot timing and blame analysis** — [`boot-profile-yocto.md`](boot-profile-yocto.md).
- **The Raspbian (SL16G) card's full inventory, package-archive investigation and boot-timing notes**
  — `raspbian-card.md` (kiosk-reference repo).
- **Every service masked, disabled or changed, and whether it was justified** —
  [`service-changes.md`](service-changes.md).
- **What was tried on the Yocto card and did not work** — [`experiment-log.md`](experiment-log.md).
- **What to cut from the Yocto image, ranked by cost** —
  [`image-trim-recommendations.md`](image-trim-recommendations.md).
- **Device changes not yet in the build tree** — [`image-migration.md`](image-migration.md).
- **Current device state, which card is actually live, open hazards** — `STATUS.md` (kiosk-reference).
  Always read that one first.
