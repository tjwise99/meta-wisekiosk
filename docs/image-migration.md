# Migrating device changes into the image

**A runtime change that is not in the build tree dies at the next OTA or reflash.** Slot B is
replaced wholesale by every update, so anything living only in `/etc` or `/usr/bin` on the running
device is temporary by construction — it survives reboots and then vanishes without warning at the
one moment when the device is least observed.

This document owns the delta between **the image as built** and **the device as running**, and where
each item has to land. It is the other half of
[`image-trim-recommendations.md`](image-trim-recommendations.md): that one says what the next image
should stop containing, this one says what it must start containing. **They are one change set to
the build tree, not two workstreams** — anything that ships a new image has to do both at once or
the second one loses.

## How to enumerate the delta — build-epoch diff

Every file the image installs carries the reproducible-build timestamp `2018-03-09 07:34:56`.
Anything with a different mtime was changed after flashing. That makes the delta mechanically
discoverable even when nobody wrote it down — which is how the undocumented overnight changes were
recovered.

```bash
touch -d "2018-03-10 00:00:00" /tmp/epoch-ref
find /etc /usr/bin /usr/sbin /usr/lib/systemd /usr/lib/tmpfiles.d /lib/udev/rules.d \
     -newer /tmp/epoch-ref -type f
find /etc/systemd -newer /tmp/epoch-ref -type l
rm -f /tmp/epoch-ref
```

Do **not** put `2>/dev/null` on it. busybox `find` accepts `-newer FILE` but not `-newermt`, and with
stderr suppressed the unsupported form returns an empty list that reads exactly like a clean device.

## Already migrated — verified baked into slot B

The four fixes that `STATUS.md` (kiosk-reference) warned were "RUNTIME ONLY and will vanish" are now
in the image. Confirmed 2026-08-12 by their build-epoch mtimes, not by reading the recipes:

| Fix | Evidence on device |
|---|---|
| timezone | `/etc/localtime → /usr/share/zoneinfo/America/New_York`, epoch mtime; `date` reports EDT |
| `wpa_supplicant` robustness | `/etc/systemd/system/wpa_supplicant.service.d/robust.conf`, epoch mtime — the `wlan0` ordering plus `Restart=on-failure` |
| RAUC keyring path | `/etc/rauc/system.conf` epoch mtime, `path=/etc/rauc/keyring.pem` |
| soak sampler | `/usr/bin/kiosk-soak.sh` epoch mtime, `kiosk-soak.timer` enabled |

That warning in `STATUS.md` is therefore retired for these four. It is not retired in general — see
the table below.

## ~~Not migrated~~ — RESOLVED 2026-08-12, all of it now ships

This section listed the runtime-only delta. **Everything in it is now in the image and delivered by
OTA**; the table is kept only because its "Priority" column records why each mattered.

| Device path | What it was | Now |
|---|---|---|
| `/etc/systemd/system.conf.d/watchdog.conf` | `RuntimeWatchdogSec=14` — appeared nowhere in the tree | `kiosk-hardware` recipe, plus `RebootWatchdogSec`/`ShutdownWatchdogSec` |
| `/etc/systemd/journald.conf.d/50-kiosk-size.conf` | journald sizing | `kiosk-journal` `persistent.conf`, settled at 64M cap / ~20MB working set |
| `kiosk-journal-flush.service`, `99-kiosk-journal.conf` | journal flush + symlink | `kiosk-journal` recipe |
| `kiosk-bootprofile.service`, the boot sampler | boot-profiling diagnostic | **`kiosk-bootprof` recipe** — installed, *not* enabled |
| `/usr/bin/kiosk-launch` | reverted to the image copy | nothing to migrate; md5 matched the image |
| `machine-id`, `ssh_host_*`, `ld.so.cache` | first-boot generated | nothing — these are supposed to differ |

## Migrated into the build tree, 2026-08-12 — verified in a built image

All of the following are in `~/meta-wisekiosk` and **verified by inspecting the assembled rootfs and
the deployed `cmdline.txt`**, not by reading the recipes. The tree is committed and pushed on
`zero-w-port`; an earlier restriction on touching GitHub for that repo was scoped to one session
(owner, 2026-08-12) and does not stand.

| Change | Where it landed | Verified |
|---|---|---|
| `panic=10` | `CMDLINE:append` | deployed `cmdline.txt` md5 `0ef67fa722f47036d60e31bfb50d75f2` — **byte-identical to the hand-edit on the device** |
| drop `console=serial0,115200` | `CMDLINE_SERIAL = "console=tty1"` | same file |
| camera/audio/GPIO module blacklist | **new recipe** `kiosk-hardware` → `/etc/modprobe.d/kiosk-blacklist.conf` | present, 16 directives |
| watchdog trio | `kiosk-hardware` → `/etc/systemd/system.conf.d/watchdog.conf` | all three directives present |
| `kernel.panic` / `panic_on_oops` | `kiosk-hardware` → `/etc/sysctl.d/60-kiosk-panic.conf` | present |
| journald sizing | `kiosk-journal` `persistent.conf` | `SystemMaxUse=64M`, `SystemMaxFileSize=8M` |
| `99-com.rules` removed | **new** `udev-rules-rpi.bbappend` | gone; `can.rules` correctly retained |
| `serial-getty` | `SERIAL_CONSOLES = ""` | **0** `serial-getty*` files in the rootfs |
| Bluetooth, audio, touchscreen, serial features | `MACHINE_FEATURES:remove`, `DISTRO_FEATURES:remove` | `bluez5`, `pi-bluetooth`, all 7 alsa packages, touchscreen packages and `90-pi-bluetooth.rules` all gone |

**Lifeline check, run every time:** `brcmfmac43430-sdio.*` firmware is still present (11 files). The
BCM43430 is a combo part and removing Bluetooth removes the BT patch, *not* the WiFi firmware —
but that must be confirmed on every feature change, not assumed.

### Three traps this hit

- **`MACHINE_FEATURES:remove = "bluetooth"` alone does nothing useful.** `packagegroup-base.bb:28`
  pulls `packagegroup-base-bluetooth` from **`DISTRO_FEATURES`**, not `COMBINED_FEATURES`. A build
  with only the machine-side removal completed cleanly and still shipped `bluez5`, `pi-bluetooth` and
  the BT firmware. Both removes are needed. `alsa` and `touchscreen` are *not* like this — they key on
  `MACHINE_FEATURES`/`COMBINED_FEATURES`, so the machine-side removal is enough, which is why
  `DISTRO_FEATURES` is deliberately left alone for those (touching it risks re-hashing gstreamer into
  webkitgtk3).
- **`PACKAGE_EXCLUDE` on `systemd-serialgetty` fails the build.** `packagegroup-core-boot` RDEPENDS on
  it, so opkg reports "conflicting requests". `SERIAL_CONSOLES = ""` is the right lever: the recipe
  wraps its whole `do_install` in `if [ ! -z "${SERIAL_CONSOLES}" ]` and sets `ALLOW_EMPTY`, giving a
  present-but-empty package that satisfies the dependency.
- **`MACHINE_EXTRA_RRECOMMENDS` bypasses features entirely.** `raspberrypi0-wifi.conf:11` pulls
  `bluez-firmware-rpidistro-bcm43430a1-hcd` directly, so it survived the feature removal.

## Migrated into the build tree, 2026-08-13 — the OPP-cap fix and its neighbours

Four changes landed after the 2026-08-12 batch, on `zero-w-port` commits `651d2fe` (the OPP cap, the
brcmfmac patches, ramoops) and `72af889` (`bootdelay=0`). Unlike the table above, these are
**verified on the reflashed running card (2026-08-13 ~21:20)** — the first boot after the reflash —
not against a build-host rootfs. `bootdelay=0` updates its existing row in §"Proven on the device,
now owed to the image"; the other three are new.

| Change | Where it landed | Verified on the device |
|---|---|---|
| **CPU top-OPP cap (900 MHz)** | new recipe `kiosk-cpufreq` (`meta-autonomos-core/recipes-core/kiosk-cpufreq/`) → `kiosk-cpufreq-cap.service`, `SYSTEMD_AUTO_ENABLE = "enable"`; added by `kiosk-zero-w.yaml` `IMAGE_INSTALL:append = " kiosk-cpufreq"` | service enabled + active; `scaling_max_freq=900000`; `cpufreq capped at 900000 kHz` in dmesg; **held under a 120 MiB unthrottled receive, 3/3, `cur_freq` pinned at 900000** |
| **brcmfmac SDIO sg-table fixes** | new `linux-raspberrypi_%.bbappend` → two backport `.patch` files (`857282b819cb`, v6.13; `52e8726d6782`, v6.14) | in the shipped kernel; wifi associates and holds. **Not** the crash fix — hygiene for a separate unguarded NULL-deref |
| **ramoops / pstore** | `kiosk-zero-w.yaml` `RPI_KERNEL_DEVICETREE_OVERLAYS:append` + `RPI_EXTRA_CONFIG` (`dtoverlay=ramoops,total-size=0x40000,…`) | 4 `ramoops` lines in dmesg; `/sys/fs/pstore` mounts. **Reflash-only — see below** |
| **`iproute2-tc`** | `kiosk-zero-w.yaml` `IMAGE_INSTALL:append = " iproute2-tc"` (commit `22b00c7`, after it first went into a file this target never parses) | `/usr/sbin/tc` present. Ingress policing was never tested and is probably unneeded now the OPP cap fixes the real defect |

> **The CPU cap is the shipped form of the real stability fix, and it retires the "sustained SDIO
> traffic wedges the board" rule.** The board was corrupting memory at its top OPP (1000 MHz) under
> load — SDIO throughput only drove `ondemand` there. Capping `scaling_max_freq` at 900000 fixed it,
> and throughput went *up*. Full evidence in [`experiment-log.md`](experiment-log.md)
> §"ROOT CAUSE + FIX". The brcmfmac patches are unrelated to that crash.

> **ramoops cannot arrive by OTA.** The `dtoverlay=ramoops` line and `overlays/ramoops.dtbo` live on
> the shared FAT partition (`config.txt` + `overlays/`), and `RAUC_BUNDLE_SLOTS = "rootfs"` never
> touches it — so the overlay only reaches a **reflashed** card, exactly like `bootdelay=0` and
> `panic=10`. The field unit got it by the 2026-08-13 reflash. There is no `.dtbo`/`.dts` source in
> the layer; the recipe references the kernel's existing ramoops overlay by name.

## Traced but not acted on — the systemd → WebKit chain, and a feature-flag inversion

### The `systemd → webkit` chain runs through `dbus`, not through `gtk+3`/`at-spi2-core` directly

The chain asserted in `kiosk-hardware_1.0.bb` and the kas config is `systemd → gtk+3/at-spi2-core →
webkitgtk3`. Traced, 2026-08-12 evening, the load-bearing hop is **`dbus`**, which is not mentioned:

```
webkitgtk3    DEPENDS  atk                              (webkitgtk_2.44.4.bb:36)
   atk        PROVIDED BY at-spi2-core                  (at-spi2-core_2.50.1.bb:25)
at-spi2-core  DEPENDS  dbus                             (at-spi2-core_2.50.1.bb:16)
   dbus       PACKAGECONFIG[systemd] third field = systemd   (dbus_1.14.10.bb:37)
              enabled by DISTRO_FEATURES systemd        (autonomos.conf:16)
```

`at-spi2-core`'s own `inherit systemd` adds only `systemd-systemctl-native`, a native helper — it is
**not** the link. `gtk+3` reaches systemd the same way (it also DEPENDS on `atk`), so it is a parallel
branch, not the path.

Consequences:

- **Touching `dbus` is exactly as dangerous as touching `systemd`.** Nothing in the repo said so
  before this trace.
- **It is out of our control and correctly configured** — every hop is a genuine upstream dependency,
  and `systemd` in `DISTRO_FEATURES` is the distro's init choice. Nothing this repo does creates it.
- **"Remove `at-spi2-core`" is not available as a package removal.** It PROVIDES `atk`, which WebKit
  build-depends on. [`image-trim-recommendations.md`](image-trim-recommendations.md) §"`at-spi2-core`"
  floats this for a ~11.9 MB RSS win — only the runtime neutralisation that section also suggests
  (`NO_AT_BRIDGE=1` / `GTK_A11Y=none`) is on the table; the build-side removal is not.
- **The caution in `kiosk-hardware`'s own `DESCRIPTION` is more cautious than the evidence warrants.**
  `meta-autonomos-core/recipes-core/systemd/systemd_%.bbappend` already exists and appends to
  systemd's `do_install`, and every build touching it has been **~11 minutes with no WebKit rebuild**
  — `bitbake -S printdiff` for a `DISTRO_FEATURES:remove` confirms only `systemd:do_configure` and
  `packagegroup-base:do_package` as unusable, zero WebKit tasks. **That is a lower bound, not a
  guarantee**: `BB_SIGNATURE_HANDLER = "OEEquivHash"` means a dependent only rebuilds if the
  dependency's output actually differs, which is unknown until systemd has rebuilt.

### A feature-flag inversion: removing `zeroconf` turns systemd's own mDNS/LLMNR *on*

From the same `printdiff` run, systemd's `EXTRA_OEMESON` contains:

```
${@bb.utils.contains('DISTRO_FEATURES', 'zeroconf', '-Ddefault-mdns=no -Ddefault-llmnr=no', '', d)}
```

Inverted from the intuition: when `zeroconf` **is** set, systemd is built with mDNS and LLMNR
**disabled**, because `avahi` provides them instead. Removing `zeroconf` to drop `avahi-daemon` (as
[`image-trim-recommendations.md`](image-trim-recommendations.md) Tier 1 recommends) drops that flag
too and turns `systemd-resolved`'s own responders **on** — trading `avahi` (190 ms, starts 22.57 s)
for `resolved` (729 ms, starts 19.96 s, pre-gate). Done naively, the intended removal would partly
cancel itself and put multicast responders back on the network while appearing to remove them.

**Not yet resolved**: whether `avahi-daemon` can be dropped at the `MACHINE_FEATURES`/`RRECOMMENDS`
level, the way `alsa` and `touchscreen` are (see §"Three traps this hit" above), without touching
`DISTRO_FEATURES:zeroconf` at all — that would be the clean removal. Investigate before acting on the
Tier 1 zeroconf row.

### Build cost, and why it is small

**~11 minutes, zero webkit rebuilds**, across five builds. Task count fell 7495 → 7304.

The tree warns that changes cascade into a multi-hour WebKit rebuild. That is true only for changes
that alter **systemd's output** — `VOLATILE_LOG_DIR` is read by systemd's `do_install`, which is why
it cascades. This distro sets `BB_SIGNATURE_HANDLER = "OEEquivHash"` and `BB_HASHSERVE = "auto"`
(from `poky.conf`, required by `autonomos.conf`), so a rebuild producing identical output keeps its
unihash and downstream sstate still hits.

That is why every config file here went into a **separate recipe** rather than a
`systemd_%.bbappend`: adding a file to systemd's package changes its output, which is exactly the
case hash equivalence cannot absorb. Note also that `systemd-serialgetty` is its **own** recipe, so
`SERIAL_CONSOLES` is cheap despite the name.

> `sources/` is kas-managed and re-checked-out to a pinned SRCREV on every build, so edits to
> `meta-raspberrypi` are wiped. Overrides belong in `kiosk-zero-w.yaml` or a layer we own.

## Proven on the device, now owed to the image

Measured n=3 per arm, then shipped in the image and delivered by OTA on 2026-08-12. These are the
changes the next image should carry, with the evidence in
[`boot-profile-yocto.md`](boot-profile-yocto.md).

| Change | Build-tree form | Worth |
|---|---|---|
| **`panic=10` on the kernel cmdline** | `CMDLINE:append = " panic=10"`, shipped in `kiosk-zero-w.yaml` | turns an unrecoverable early panic into a **60 s outage, proven** |
| **Drop `console=serial0,115200`** | `ENABLE_UART = "0"`, or drop `CMDLINE_SERIAL` — the kas config currently sets it deliberately, and that comment needs replacing | **−2.43 s wall for −0.43 s CPU**: synchronous `printk` to a 115200 UART blocks. The panel is the console; there is no adapter |
| **Camera / ISP / codec / audio / GPIO modules** | drop from the installed module set, or ship the `modprobe.d` file | part of `wlan0` −6.43 s |
| **`99-com.rules`** | drop the `rpi-config`/udev-rules package content that installs it | six `PROGRAM="/bin/sh -c …"` forks during coldplug, pre-gate |
| **`serial-getty@ttyS0`** | `SERIAL_CONSOLES` / `systemd-serialgetty` out of the image | a login prompt on a port with nothing attached, started at 25.4 s |
| **Camera/ISP/codec/audio modules out of the boot** | drop them from the installed module set, or ship `modprobe-kiosk-blacklist.conf` (kiosk-reference) as `/etc/modprobe.d/` content | **`wlan0` 3.33 s earlier** — the gate the whole boot waits on |
| **Bluetooth out** | drop `bluetooth` from `DISTRO_FEATURES`/`MACHINE_FEATURES` | −2.43 s CPU work |
| **`bootdelay=0`** (owner, 2026-08-12) | `u-boot_%.bbappend` `do_configure:prepend:raspberrypi0-wifi` deletes then appends `CONFIG_BOOTDELAY=0` in the defconfig (commit `72af889`) — **now `fw_printenv bootdelay=0` on the reflashed card** | 2 s of true power-on, invisible to every kernel-anchored measurement |
| **`RebootWatchdogSec=30s` / `ShutdownWatchdogSec=30s`** | same `systemd` bbappend as the runtime watchdog | closes a 10-minute default hole in the shutdown window |
| **`kernel.panic=10` / `panic_on_oops=1` sysctl** | a `sysctl.d` file in a recipe | covers oops-to-panic; redundant with the cmdline for panics |

**All of the above is now IN the shipped image and running** — delivered by OTA to slot A on
2026-08-12 and verified in the running system. `panic=10` in particular must never be dropped: it is
the only mechanism that recovers a 4-second panic, and its absence would only surface the next time
one happened.

**`kiosk-bootprof` and `measure-surf.sh` are in the image too**, via the `kiosk-bootprof` recipe —
installed but **not enabled**, because the profiler costs ~240 ms of the boot it measures. Usage is
[`remote-debugging.md`](remote-debugging.md) §"Recipe 10 — Profile the boot: is the core busy,
blocked, or queued?" and §"Recipe 11 — Time to complete display, not to `load_finished`". The C
source is compiled by the recipe with the target toolchain; the first version was hand-cross-compiled
inside the kas container, which was neither reproducible nor tracked.

Together the first two are **−3.23 s to `load_finished`** with non-overlapping ranges; with
`bootdelay` it is ~5.2 s.

**`bootdelay` must arrive by reflash, not `fw_setenv`.** The environment shares its 0x4000 block at
`/boot/uboot.env` with `BOOT_ORDER` and the RAUC slot counters; a hang mid-write — and this board
hangs unexplained — drops U-Boot to a built-in default with no RAUC boot logic, which is an
unbootable card and a physical trip.

### The watchdog is the urgent one

It is the only item with **no representation in the build tree at all**, and it is the mechanism that
recovered this board unattended twice on 2026-08-12 — once at 08:35 from a hang that nothing else
would have caught. An OTA today would silently remove the thing that makes an unattended hang
survivable, and the loss would only become visible the next time the board wedged.

It also needs the care noted in `STATUS.md` (kiosk-reference) §"Hardware watchdog ARMED and PROVEN":
it can misfire under startup load, and three fires before `rauc-mark-good` runs at ~33 s would
exhaust the boot counter. Migrating it is not the same as leaving it unexamined.

## The build tree is committed and reproducible

The recipes the running image depends on — `kiosk-journal`, `kiosk-soak`, the `raspberrypi0-wifi`
RAUC files, and the later `kiosk-cpufreq` / ramoops / `bootdelay=0` work — are all committed on
`main`. A clean checkout now reproduces the delivered image, so the A/B reproducibility claim holds.

## The combined change set for the next image

Ordered so that the risky and the reversible are not mixed:

1. **Commit the build tree as-is.** No behaviour change; it makes the current image reproducible.
2. **Add the watchdog drop-in and the journald size cap.** Both are additive, both are already proven
   on the device, neither touches the lifeline.
3. **Remove the Tier 1 items** from [`image-trim-recommendations.md`](image-trim-recommendations.md)
   — Bluetooth, audio, 3G, NFC, NFS, zeroconf, busybox syslog, imagemagick, the terminal emulator,
   keyboard/console, surplus tzdata and locales. All are `DISTRO_FEATURES` or `RDEPENDS` edits.
4. **Resolve `zram`** — two mechanisms, one broken. Decide which, delete the other.
5. **Measure**, n=3, against the baseline in [`boot-profile-yocto.md`](boot-profile-yocto.md), on the
   `load_finished` endpoint (50.1 s mean). Only then attach a number to any of it.
6. **Leave the module trim and anything `webkitgtk3`-adjacent for a separate build.** They are the
   biggest wins and the longest rebuilds, and mixing them into the batch above makes a regression
   impossible to attribute.

**Deliver the resulting bundle with [`../tools/send-bundle-chunked.sh`](../tools/send-bundle-chunked.sh),
or `just kiosk-ota`.** A single-stream 133 MB transfer reliably hangs this board.

> **Do not use the "32 × 4 MB at full rate with a 4 s gap" shape this section used to recommend.**
> It is recorded in `STATUS.md` (kiosk-reference) §"THE WORKAROUND WORKS" as having moved 133 MB
> with zero hangs, and on 2026-08-12 it **did not reproduce** — it hung repeatedly past 60 MB and made
> zero net progress across four runs. Following the old advice reproduces the exact hang this project
> spent a day bounding. What works separates the receive burst from the disk `sync` in time; see
> [`experiment-log.md`](experiment-log.md) §"The chunk-and-pause workaround did NOT reproduce".

## Verifying the assembled rootfs from the build host: absolute symlinks lie

Every claim in this document is checked against the assembled rootfs at
`build/tmp-*/work/*/core-image-base/*/rootfs` rather than against the recipes, because a recipe edit
that looks correct and does nothing is the failure mode here — see §"`3g` and `nfc` arrive by a
second path".

That check has its own trap. The rootfs is a directory on the **build host**, so an *absolute*
symlink inside it resolves against the host's filesystem, not the image's:

```
rootfs/usr/bin/import -> /usr/bin/import.im7      # absolute
```

`test -e "$ROOTFS/usr/bin/import"` follows that to the **host's** `/usr/bin/import.im7`, which does
not exist, and reports the file missing. It is present and works — `import -version` on the device
returns ImageMagick 7.1.1-47. This produced two false alarms on 2026-08-12, one of them a false
report that the only remaining screenshot path had been deleted.

Check the package manifest, or `ls` the path, or test the link itself with `-L`. Do not use `-e`.
[`../tools/doc-image.py`](../tools/doc-image.py) is unaffected: it records paths from directory
listings and never tests existence.
