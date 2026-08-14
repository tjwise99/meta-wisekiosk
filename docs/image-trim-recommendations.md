# What to remove from the Yocto image — ranked by measurement

Derived from the boot profile in [`boot-profile-yocto.md`](boot-profile-yocto.md) and from per-unit
CPU, per-process RSS and per-package size read off this device on 2026-08-12. Every row says which of
the three costs it buys back — **boot time**, **RAM**, or **image bytes** — because they are not the
same list and several items score on only one.

> **Everything here is a build-tree change, not a runtime one.** Masking a unit on the running device
> is a way to *test* a removal; it is not the removal, and it dies at the next OTA because slot B is
> replaced wholesale. The counterpart document
> [`image-migration.md`](image-migration.md) covers what the next image must **start** containing —
> including changes this project has already made and not yet migrated. **The two are one change set
> to the build tree**, and an image that ships the removals without the additions loses the watchdog.

## The ranking principle comes from the measurement

Boot on this board is **CPU-saturated**: 85.4 % busy, 9.6 % idle, and **0.00 % idle** across the
local-filesystems, sysinit and `wlan0` windows (n=3). The run queue averages 5.4 runnable tasks on
one core. Full method in [`boot-profile-yocto.md`](boot-profile-yocto.md).

Three consequences, and they set the whole shape of this document. The third was measured after the
first draft and overturns part of it:

1. **A service that never starts costs no boot time, however unnecessary it is.** Removing it is
   still right — it is image bytes and attack surface — but it will not move the clock, and claiming
   otherwise is how the overnight session produced a number it could not defend.
2. **Removing CPU work does not convert 1:1 into boot time.** Removing Bluetooth took **2.43 s** of
   CPU out of the boot and moved `wlan0` by **0.00 s**; the freed CPU became idle. The first draft of
   this document asserted the 1:1 conversion, and the measurement disagreed.
3. **What converts to boot time is removing work that sits *before* the `wlan0` gate.** `wlan0` does
   not exist until 32.6 s and everything waits on it. Blacklisting the camera/ISP/codec/audio modules
   removed only **0.73 s** of CPU but moved `wlan0` **3.33 s** earlier, because they were queued ahead
   of `brcmfmac` in udev. Four times the gain for a fifth of the CPU.

> **Sharpened 2026-08-12 evening — `wlan0` is a proxy, not the gate.** Every trim above that moved
> `wlan0` earlier also removed CPU work; it is the CPU removed that buys boot time, not `wlan0`'s own
> arrival — `wpa_supplicant` actually waits on `sysinit.target`/`basic.target`, not on `wlan0`. Full
> mechanism, and a direct experiment confirming it, in
> [`boot-profile-yocto.md`](boot-profile-yocto.md) §"The `wlan0` gate". The ranking rule below is
> unaffected — every candidate here is ranked by CPU work removed, which is what actually converts —
> but read "the `wlan0` gate" as shorthand for that, not as `wlan0` itself gating anything.

**So rank every candidate by which side of the 32.6 s gate it sits on**, not by how much CPU it burns.
Before the gate: buys boot time. After the gate: buys idle, RAM and image bytes, which are worth
having but are not TTL.

**Not needed + we boot it = waste, and that is sufficient grounds to remove it** (owner,
2026-08-12). The measurements below size the win; they are not a gate on the decision.

## The measured cost of everything that actually runs

Per-unit CPU since boot, read from systemd's own accounting (`CPUUsageNSec`), at 220 s uptime:

| Unit | CPU | Verdict |
|---|---|---|
| `kiosk.service` | 42 533 ms | the product. Stays |
| **`systemd-udevd`** | **6 851 ms** | **largest non-kiosk consumer** — rule processing over device events, not module scanning. See §"The real `udevd` lever" |
| `kiosk-bootprofile` | 2 295 ms | the **shell** sampler, since replaced by `kiosk-bootprof` at 237 ms. Ships disabled; not in a normal boot |
| `systemd-journald` | 1 757 ms | keep — it is the only evidence channel this device has |
| `dbus` | 1 159 ms | required by GTK/WebKit |
| **`systemd-udev-trigger`** | **1 027 ms** | same root cause as `udevd` |
| `systemd-logind` | 813 ms | no interactive logins on a kiosk. Candidate |
| `systemd-timesyncd` | 740 ms | keep — the clock jump is already a measurement hazard |
| `systemd-resolved` | 722 ms | backend is reached by IP. Candidate |
| `systemd-userdbd` (+3 workers) | 642 ms | candidate, tied to `logind` |
| `systemd-networkd` | 601 ms | lifeline. **Do not touch** |
| **`bluetooth`** | **485 ms** | remove |
| `rauc` | 398 ms | needed for OTA, but see §"RAM" |
| `rauc-mark-good` | 300 ms | keep — it is what stops a boot-loop exhausting the counter |
| **`bthelper@hci0`** | **299 ms** | remove |
| **`hciuart`** | **244 ms** | remove |
| **`syslog`** (busybox) | **230 ms** | remove — duplicates journald onto the SD card |
| `zram-swap` | 220 ms | keep, see §"zram" |
| **`zram`** | **162 ms** | **failing every boot.** Fix or remove; do not mask |

### The waste set does cost boot time — this section's own earlier claim was wrong

> **Correction, 2026-08-12 evening.** This section originally read: *"`avahi-daemon`, `neard`, `ofono`,
> `rpcbind` and `busybox-klogd` are all `inactive` and have consumed 0 ms of CPU this boot… They do not
> start on this image,"* concluding that removing them "will not move boot time." That was measured
> true at the time. **On the image running this evening, four of the five are `active`:**
>
> | unit | state | CPU |
> |---|---|---|
> | `ofono` | active | 468 ms |
> | `avahi-daemon` | active | 190 ms |
> | `rpcbind` | active | 95 ms |
> | `busybox-klogd` (+ `busybox-syslog`) | active | 93 + 88 ms |
> | `neard` | inactive | 0 ms — this section's claim was and is correct here |
>
> Masking the set — these four plus `busybox-syslog` and the already-failing `zram` — moved `surf`
> exec **34.42 → 32.50 s, −1.92 s, ranges do not overlap.** That is a combined figure for six units
> masked together; no per-service breakdown was measured. **Why they started is not established** —
> the original observation was presumably true when written, and nothing in this session identified
> what changed between then and now. Do not invent a reason.

Removing them from the image remains correct on the original grounds — bytes and surface — and on the
current image also buys measured boot time, for four of the five. `neard` remains the one unit in the
original set that genuinely never starts and buys bytes only.

## The answer, measured end to end

Everything the kiosk will never use, removed together and measured n=3 per step against an untouched
baseline. **Complete display 53.65 s → 47.66 s.** Adding `bootdelay=0` (owner, 2026-08-12) makes it
**55.65 s → 47.66 s from power-on, about 8 seconds.**

| Step | `wlan0` | complete display | what it is |
|---|---|---|---|
| baseline | 32.30 s | 53.65 s | image default |
| + camera/audio/GPIO modules out | 28.87 s | — | `bcm2835_isp/codec/v4l2`, `snd_bcm2835`, `vc_sm_cma`, `raspberrypi_gpiomem`, `uio*` |
| + `99-com.rules`, `serial-getty`, Bluetooth | 28.10 s | 50.79 s | see below |
| **+ `console=serial0,115200` removed** | **25.87 s** | **47.66 s** | the single biggest remaining item |
| *(+ `bootdelay=0`)* | — | *−2 s from power-on* | U-Boot, invisible to kernel-anchored measurement |

Complete-display ranges do not overlap at any point: baseline 52.65–54.89, final 47.38–48.01.

### The serial console was costing 2.4 s of *blocking*, not work

`console=serial0,115200` alongside `console=tty1` means every `printk` is also written synchronously
to a 115200 UART. 261 kernel lines × ~75 chars ≈ 19.6 KB ≈ 1.7 s at that baud, and the measured cost
was higher because early-boot messages predate journald.

**CPU work fell only 0.43 s while wall clock fell 2.43 s** — the core was not computing during those
writes, it was stalled on them. `Expecting device wlan0` moved from 7.7 s to **6.1 s**, so it slows
the kernel from the first `printk` onward.

There is no serial adapter on this unit and there will not be one: **the kiosk panel is the console**
(owner, 2026-08-12), so `console=tty1` already puts kernel output — including the `mmc_rescan` panic —
on a screen that is permanently attached. An earlier draft of this document argued for keeping serial
as an out-of-band channel; that was wrong, and the owner corrected it.

### `99-com.rules` forks a shell during coldplug

`/etc/udev/rules.d/99-com.rules` is GPIO/i2c/spi/PWM/serial-symlink plumbing carrying **six
`PROGRAM="/bin/sh -c …"` rules**, which fork a shell plus `cmp`, `chgrp -R` and `chmod -R` during udev
coldplug — on a core that is already 100 % busy, before the gate. `/dev/i2c*` and `/dev/spi*` do not
exist so those rules never match, but the gpio, `ttyS0` and `vtconsole` ones do.

Removing it is safe here because nothing on this kiosk uses GPIO, i2c, spi or PWM. It also removes
the `/dev/serial0` symlink, which is unrelated to the kernel `console=` alias.

## Measured and confirmed — do these first

Both proven on the device, n=3 per arm, against the canonical baseline, then **shipped in the image
and delivered by OTA** on 2026-08-12 — they are no longer runtime masks. See
[`image-migration.md`](image-migration.md).

| Change | `wlan0` | `surf` exec | `load_finished` | CPU work |
|---|---|---|---|---|
| baseline | 32.63 s | 40.00 s | 49.80 s | 44.27 s |
| **camera/ISP/codec/audio modules out** | **29.30 s** | 37.87 s | 48.10 s | 43.53 s |
| **+ Bluetooth out** | 29.10 s | **36.73 s** | **46.57 s** | **41.47 s** |

**Together: −3.23 s to `load_finished` with non-overlapping ranges, and −2.80 s of CPU work.** Add
`bootdelay=0` (owner, 2026-08-12) for a further 2 s of true power-on time that no kernel-anchored
measurement here can see, and the total is **~5.2 s**.

The module blacklist is `modprobe-kiosk-blacklist.conf` (kiosk-reference);
the Bluetooth removal is the three-unit form in [`service-changes.md`](service-changes.md). Neither
disturbed the display: framebuffer sampled at `rgb_mean=2.03 distinct=227`, against the baseline's
`1.84 / 221`.

> `vc_sm_cma` still loads after the blacklist, now with usage count 0 — something requests it
> directly. 24 KB, harmless, worth adding to the blacklist for completeness.

## Tier 1 — remove, no further analysis needed

The kiosk does not use these and they are in the image; several also cost measured boot CPU. The
`ofono`/`rpcbind`/`avahi-daemon` rows are part of the six-unit set in §"The waste set does cost boot
time" above — the CPU figure is per-unit, but the **−1.92 s** boot-time win is measured only for all
six together, not isolated per row.

| What | Buys back | Evidence | How |
|---|---|---|---|
| **Bluetooth** — `bluez5`, `pi-bluetooth`, `bluez-firmware-rpidistro-*` | **~1.03 s boot**, 4.2 MB RSS (`bluetoothd`), 5.4 MB image | `bluetooth` 485 ms + `bthelper@hci0` 299 ms + `hciuart` 244 ms, all active | drop `bluetooth` from `DISTRO_FEATURES`/`MACHINE_FEATURES`, which drops `packagegroup-base-bluetooth` |
| **Audio** — `alsa-conf`, `alsa-state(s)`, `alsa-ucm-conf`, `alsa-utils-*`, `libasound2` | image bytes | nothing on this kiosk plays audio; no unit in the CPU table | drop `alsa` from `DISTRO_FEATURES` → removes `packagegroup-base-alsa` |
| **3G/modem** — `ofono`, `mobile-broadband-provider-info` | 1.8 MB image, share of the measured **−1.92 s** (see above) | `ofono` **active, 468 ms** | drop `3g` → `packagegroup-base-3g` |
| **NFC** — `neard` | image bytes only — the one unit here confirmed to never start | `neard` inactive, 0 ms; no NFC hardware | drop `nfc` → `packagegroup-base-nfc` |
| **NFS/RPC** — `rpcbind` | image bytes, one listening socket, share of the measured **−1.92 s** | `rpcbind` **active, 95 ms** | drop `nfs` → `packagegroup-base-nfs` |
| **Zeroconf** — `avahi-daemon`, `libavahi-*`, `libnss-mdns` | image bytes, share of the measured **−1.92 s** | `avahi-daemon` **active, 190 ms**; backend reached by IP | drop `zeroconf` → `packagegroup-base-zeroconf` — **but read [`image-migration.md`](image-migration.md) §"A feature-flag inversion" first**: the same flag also changes what `systemd` builds with |
| **busybox syslog/klogd** | **~0.23 s boot** (share of the same −1.92 s), and stops duplicate logging onto the SD card | `syslog` active 230 ms; `busybox-klogd` also active (93 ms this session); journald already carries these records | `VIRTUAL-RUNTIME_base-utils-syslog = ""` |
| ~~**`rxvt-unicode`**~~ | — | **not installed.** `/usr/bin/urxvt` is absent from the running image, checked 2026-08-13. It is not in `packagegroup-core-x11`'s `RDEPENDS` either, so the "comes with" claim here was never true. Nothing to remove | — |
| **`xinput-calibrator`** | image bytes | touchscreen calibration; there is no touchscreen | same packagegroup |
| **Keyboard/console** — `kbd`, `kbd-keymaps*`, `kbd-consolefonts`, `keymaps`, `xkeyboard-config` (3.2 MB) | image bytes, `systemd-vconsole-setup` 232 ms | headless behind glass; no console, no keyboard | drop `keyboard` → `packagegroup-base-keyboard` |
| **`tzdata-{africa,antarctica,arctic,asia,atlantic,australia,europe,pacific,misc,right,posix}`** | image bytes | one fixed site; only `America/New_York` is read | keep `tzdata-core` + `tzdata-americas` only |
| **`openssh-sftp-server`** | image bytes | never used; `scp`/`ssh` are the lifeline and stay | `RDEPENDS` override on `packagegroup-core-ssh-openssh` |
| **locale packages** (22, incl. `*-locale-en-gb`) | 2.9 MB (`/usr/lib/locale`) | the kiosk renders one language | `IMAGE_LINGUAS = "en-us"` |

## Tier 2 — the big levers, which need a decision rather than a deletion

### Kernel modules — worth removing for image bytes, not for boot time

> **Correction, 2026-08-12 evening.** This section previously called the 1750-module set "the single
> largest measured cost after the browser" and "the highest-value item in this document," on the
> reasoning that `udevd` + `udev-trigger` "burn 7.88 s of CPU walking and matching against that set."
> Measured directly this evening (cold, caches dropped, n=1 each — crude, but the gap is ~100×):
>
> | | cold | minus process floor |
> |---|---|---|
> | `udevadm --version` (no indices) | 80 ms | — |
> | `systemd-hwdb query` (10.9 MB trie) | 110 ms | ~30 ms |
> | `modprobe -n` (1750-module indices) | 130 ms | ~50 ms |
>
> Both are mmap'd binary tries; a lookup touches a few pages, not the whole file. Warm,
> `systemd-hwdb query` (14.0 ms) is *cheaper* than the bare `udevadm` process floor (32.5 ms).
> **`udevd`'s cost is rule processing over device events, not module scanning.** Inventory: 1750
> `.ko` installed, 22 loaded, 345 `uevent` files, 55 carrying a `MODALIAS`, 54 distinct;
> `udevd` 5091 ms / 345 devices ≈ 14.8 ms per device.

**1750 `.ko` files are installed. 51 are loaded.** 23.9 MB on disk. The module trim remains worth
doing for **image bytes** — ~24 MB off a 130 MB OTA bundle, which matters because transfer size is a
reliability problem on a link that reliably wedges this board (see `STATUS.md` (kiosk-reference)) —
**but not for boot time**, and it carries real risk of cutting a module needed on a bad-boot path.

**The highest-value boot-time item in this document is §"The real `udevd` lever"**, not this section
— that one is a measured win of the kind this section claimed without evidence.

The honest position on the module set itself is that the 51 currently-loaded modules are a *lower*
bound, not the answer — a module that loads only when something is plugged in, or on a recovery path,
will not appear in `lsmod` on a healthy boot. Cutting to exactly the loaded set risks removing the
module needed for the one boot that goes wrong.

Suggested route, in order, for the **image-bytes** win:
1. Capture `lsmod` across several boots **and** a cold start from power-off, not just reboots.
2. Keep the whole `brcmfmac`/SDIO/WiFi chain, the SD/mmc chain, USB, ext4/vfat and the display path
   regardless of whether they appear — they are the lifeline and the recovery path.
3. Replace `kernel-modules` with an explicit list. Do not expect `udevd` CPU to move measurably.

**Do not** pursue this by editing anything under `/boot`.

### The real `udevd` lever — rules evaluated for hardware that is not there

Measured 2026-08-12 evening. Hardware actually present: `/sys/class/sound` **empty**,
`/sys/class/video4linux` **absent**, `/sys/class/drm` has only `version` (no cards — this kiosk
renders via fbdev), `/sys/class/input` has only the aggregate `mice` node. 1 input device, 2 usb, 1
pci device.

The image nonetheless ships and evaluates rules for sound cards, cameras, V4L, evdev, mice,
touchpads, joysticks, tape, MTD, CD-ROM, InfiniBand, FIDO and btrfs — 262 of 616 rule lines.

Masking 22 rule files (a `/dev/null` symlink in `/etc/udev/rules.d` shadows the `/usr/lib` file of the
same name, per `udev(7)`): 616 → 350 effective lines, `udevd` CPU **5091 → 4513 ms (−578 ms, −11 %)**,
`surf` exec **−0.91 s, ranges do not overlap.**

43 % of rule *lines* bought 11 % of the CPU — sub-proportional, because a rule whose first match key
fails is cheap to skip. Recorded because it bounds what further rule trimming can return; do not
expect a larger win from trimming rules further without also removing what the rules key on.

Deliberately **not** masked: `71-seat`, `73-seat-late`, `70-uaccess` (logind seat/ACL that Xorg may
want), `60-drm`, `60-persistent-storage`, and the net rules.

Also found: `/etc/udev/rules.d` ships three real rule files from the image — `99-fuse.rules`,
`can.rules` (no CAN hardware) and `touchscreen.rules`, the last surviving despite
`MACHINE_FEATURES:remove = "… touchscreen"`. Not masked this session; small; not costed.

### `udev-hwdb` — 8.4 MB package, 20 MB of `/usr/lib/udev`

A hardware database for matching peripherals. This device has no peripherals: no USB devices, no
input devices, no keyboard. It is loaded to answer questions nothing asks. Candidate for removal
alongside the module trim, for **image bytes** — the cold-read measurement above shows its `udevd`
CPU share is small, not the multi-second cost once assumed here.

### `at-spi2-core` — ~11.9 MB RSS, for accessibility nothing uses

`at-spi2-registryd` (6.3 MB) and `at-spi-bus-launcher` (5.6 MB) are resident. They are started by
GTK inside the kiosk session, not by a systemd unit, so they do not show in the unit CPU table — but
they are the **largest single RAM win available that is not the browser itself**.

> **Correction, 2026-08-12 evening: the build-side removal is not on the table.** The dependency chain
> was traced: `webkitgtk3` DEPENDS on `atk`, which `at-spi2-core` PROVIDES, so removing the package
> takes WebKit's build with it. Full trace in
> [`image-migration.md`](image-migration.md) §"The `systemd → webkit` chain runs through `dbus`". Only
> the runtime route below is available.

> **Correction, 2026-08-13: the runtime route does not work either, so there is no route at all.**
> `NO_AT_BRIDGE=1` and `GTK_A11Y=none` were added to the launcher and the device rebooted. All three
> at-spi processes came back unchanged.
>
> The env vars are not being ignored — they reached the process, confirmed by reading
> `/proc/<surf pid>/environ`. They suppress the **in-process** atk-bridge, which is a different thing
> from the daemons: `at-spi-bus-launcher` has **`PPid 1`**, because it is started by **D-Bus
> activation** through `/usr/share/dbus-1/services/org.a11y.Bus.service`, not by surf's GTK. Nothing
> set in the launcher's environment can prevent that.
>
> With the build-side removal already ruled out above (`at-spi2-core` PROVIDES `atk`, which
> `webkitgtk3` DEPENDS on), **both routes are now closed.** The remaining idea, untried, is masking
> the D-Bus activation file — which risks GTK blocking on a failed activation, for ~12 MB on a board
> with 320 MB available. Not attempted; the trade is poor.
>
> Reverted; the launcher is back to the image copy, md5 `5178acbe5a7b46b0754e5407da12c17a`.

### `rauc` — 9.5 MB resident, used for minutes per month

The daemon sits in RAM permanently to service an operation that happens during an update. Making it
socket- or D-Bus-activated rather than always-on is a straightforward RAM win. **Do not remove it** —
it is the OTA path, and `rauc-mark-good` is what prevents a boot loop from exhausting the slot
counter.

### `systemd-resolved`, `logind`, `userdbd` — 2.18 s of CPU between them

The backend is reached by IP and nobody logs in interactively. All three are plausible removals worth
~2 s of boot on a CPU-bound board. Flagged rather than recommended, because `logind` owns session and
seat management that Xorg may want, and finding that out by breaking the display is the expensive
way. Worth one careful experiment each, measured.

## Tier 3 — investigate before touching

### `zram` fails on every boot

```
/etc/init.d/zram: line 42: echo: write error: Device or resource busy
```

`zram.service` (the SysV init script) fails, while `zram-swap.service` succeeds and provides 209 MB
of swap. So there are two mechanisms for the same job and one of them is broken. The overnight
session masked the broken one, which removed the *symptom* and left the duplication.

Resolve which one is intended and delete the other. **Do not simply mask it** — a 437 MB board
running WebKit is exactly the case compressed swap exists for.

### `gstreamer1.0` and `libgst*` — 2.8 MB, pulled by WebKit

WebKit's media backend. If the kiosk page plays no audio or video this is removable via a
`PACKAGECONFIG` on `webkitgtk3`, but WebKit does not always build cleanly without it and a rebuild
here is expensive. Confirm the page's content first.

### `aspell`, `libaspell15`, `enchant2` — spellcheck inside WebKit

There is no text input on this kiosk. Same `PACKAGECONFIG` route and the same rebuild cost.

### `libicudata` — 29.4 MB, the second-largest file in the image

ICU's full locale data, required by WebKit. A reduced ICU data build is possible and is a genuine
~25 MB win, but it is a WebKit-adjacent rebuild and belongs in the same batch as any other
`webkitgtk3` change, not on its own.

## Do not touch — the lifeline

Named explicitly so a future cleanup pass has a deny-list rather than a memory:

`systemd-networkd`, `wpa-supplicant` (+ `wpa-supplicant-service`), `openssh-sshd`, `openssh-ssh`,
`openssh-keygen`, `sshdgenkeys`, `linux-firmware-rpidistro-bcm43430*` and the `brcmfmac` module
chain, `wireless-regdb-static`, `iw`, `udev-rules-rpi`, `u-boot-env`/`libubootenv`, `rauc` +
`rauc-mark-good`, and anything under `/boot`.

`systemd-journald` also stays. It is the only evidence channel this device has, and the network hang
already destroys its own logs.

> **`imagemagick` also stays, reversing this document's own Tier 1.** It was listed there for removal
> (6.3 MB image) on the grounds that "nothing on the kiosk converts images; not in any boot path" —
> written without knowing that `fbgrab`, the screenshot tool `remote-debugging.md` prescribed, had
> already been dropped from the image on 2026-08-11. `import -window root` (imagemagick) is the only
> verified-working capture path on this image as of 2026-08-12 evening; see
> [`remote-debugging.md`](remote-debugging.md) §"Recipe 9". Removing it leaves no screenshot
> capability at all.

## What this is worth, honestly bounded

**Boot time.** The measured, currently-running waste is Bluetooth ~1.03 s (already shipped) + the
six-unit waste set (`ofono`, `avahi-daemon`, `rpcbind`, `busybox-syslog`, `busybox-klogd`, failing
`zram`) at **−1.92 s** measured together, plus the udev-rules-for-absent-hardware trim at a further
**−0.91 s** measured on top of that (see §"The real `udevd` lever") — **~3.8 s** total, measured, not
estimated. **The module trim does not add to this figure** — see the correction above: its cost was
put at ~7.88 s of `udevd` CPU on an accounting since shown wrong, and the real cost of the 1750-module
set is closer to 50 ms. `resolved`/`logind`/`userdbd` add a further ~2.2 s if they prove safe. Against
a 50.1 s boot to `load_finished`.

**Nothing here is the 7–11 s that the overnight parallelisation proposal claimed**, and that remains
unavailable for the reason given in [`boot-profile-yocto.md`](boot-profile-yocto.md): the total
idle-plus-iowait in the entire boot is 6.56 s, and none of it sits in the window that proposal
targeted.

**RAM.** at-spi2 ~11.9 MB + `rauc` 9.5 MB + `bluetoothd` 4.2 MB ≈ **25 MB**, against 84 MB used and
313 MB available. Real, but this board is not currently memory-pressured — the case for these is
waste, not necessity.

**Image size.** Tier 1 plus the module and hwdb trims plausibly reach **50–70 MB** off a 310 MB
rootfs, with `libicudata` a further ~25 MB if the WebKit rebuild is being done anyway. That matters
mainly because the OTA bundle is 133 MB and **the risky half of an update is exactly the transfer
that reliably hangs this board** — so image size is a reliability lever here, not a storage one.

## How to verify any of it

Same protocol as the baseline, or the numbers are not comparable:

```bash
# n=3 per arm, one endpoint fixed in advance, journal-anchored windows
systemctl enable --now kiosk-bootprofile && systemctl reboot   # kiosk-bootprof ships in the image, disabled
tools/analyze-boot-cpu-io.py <sample-file>
```

Endpoint must be stated. `load_finished` is 50.1 s mean (n=3) on this baseline; complete display has
not been re-measured since the revert and is **not** the same number.

## `systemd-resolved` answers zero queries and costs 729 ms

Measured 2026-08-12 evening. Listed above as a candidate justified by "the backend is reached by
IP", which is true and was nearly the wrong reason: the kiosk fetches **nothing** client-side and
reaches only the Docker host serving the page (owner, 2026-08-12), so the external APIs in
[`mirror-deployment.md`](mirror-deployment.md) are fetched server-side and never resolve here.

`resolvectl statistics` reports **Total Transactions 0**, cache empty, on a normal boot. Nothing
queries it. `/etc/resolv.conf` chains to `/etc/resolv-conf.systemd` → `/run/systemd/resolve/resolv.conf`,
which lists the upstream nameserver directly rather than resolved's stub, so glibc queries the router
and bypasses the daemon entirely. Its whole job here is writing that one file, for 729 ms of CPU
starting at 19.96 s — before the gate.

Masking it and replacing the symlink with a static `nameserver 192.168.1.1`, n=3 against the arm
below it:

| | before | after | Δ | ranges |
|---|---|---|---|---|
| `Reached target Basic System` | 22.08 s | 20.81 s | **−1.27 s** | do not overlap |
| `wlan0` exists | 24.65 s | 23.63 s | −1.02 s | do not overlap |
| `surf` exec | 31.13 s | 30.27 s | −0.86 s | **overlap by 0.01 s** |

DNS keeps working — `timesyncd`, the only consumer, still resolves its NTP pool.

> **Applied at runtime only, and deliberately not in the image.** `/etc/resolv.conf` is not a
> packaged file: systemd's own `do_install` writes an `L!` line into `tmpfiles.d/etc.conf`
> (`systemd_255.21.bb:355`) that creates it at boot. Overriding that means winning a tmpfiles
> precedence contest, and the failure mode is silent DNS loss with a healthy-looking boot. Worth
> doing; not worth rushing.

## Measured total, and what it is measured to

Cumulative across 2026-08-12 evening, n=3 per arm, endpoint `SURFMS uptime_at_exec`. **Complete
display was not measured** and none of this is quoted against it.

| arm | `surf` exec | vs baseline |
|---|---|---|
| baseline | 34.42 s | — |
| + waste set (8 units) | 32.50 s | −1.92 s |
| + udev rules (22 files) | 31.59 s | −2.83 s |
| + Bluetooth kernel modules | 31.13 s | −3.29 s |
| + `systemd-resolved` | **30.27 s** | **−4.16 s** |

No arm's range overlaps the baseline's. Everything here is *removal*; §"The `wlan0` gate is a proxy"
in [`boot-profile-yocto.md`](boot-profile-yocto.md) records what happened when work was moved
earlier instead — it got 8.74 s worse.
