# Yocto image with OTA — the plan, now built

> **"Nothing built, nothing tested" was true when this was written on 2026-08-11 20:04. It is not
> true now.** The image is built, the A/B chain is exercised in both directions, and a trimmed image
> was delivered by OTA and booted on 2026-08-12. Live state is in `STATUS.md` (kiosk-reference);
> what the delivery actually takes is in [`image-migration.md`](image-migration.md) and
> [`experiment-log.md`](experiment-log.md).
>
> The body below is kept as the reasoning that produced the design, and its phase table records what
> has since been proven. Treat the *plan* as sound and the *"unbuilt"* framing as superseded.

This is the reference plan: what a minimal Yocto image for this board consists of, what it costs, and
the dependency that decided whether it was a project or a dead end.

Upstream facts marked **(read 2026-08-10)** were read from the named file or repository on that date.
Everything else is inference and is labelled as such. The distinction matters more than usual here:
almost every "Yocto on a Pi" write-up targets a Pi 4 or 5, and none of it transfers to ARMv6.

Reference architecture: **meta-autonomos** (`github.com/jsmith212/meta-autonomos`) — a RAUC A/B Yocto
distro with a core layer, per-board layers, KAS includes, feature groups and a persistent `/data`
partition. Its shape is worth copying wholesale. Its **boards are not**: Pi 5 and Pi Zero 2 W, both
ARMv7/v8 (read 2026-08-10). Nothing in it has been built against this SoC.

## Verdict

| Question | Answer |
|---|---|
| Can Yocto target this board? | **Yes.** `raspberrypi0-wifi.conf` is current in `meta-raspberrypi`, `DEFAULTTUNE = "arm1176jzfshf"` (read 2026-08-10) |
| Can it be applied to the live kiosk over SSH? | **No.** Card reflash — hands-on. See §"This is a hands-on change" |
| Is A/B OTA a solved path here? | **Yes, via U-Boot + RAUC.** `raspberrypi0-wifi.conf` already sets `UBOOT_MACHINE = "rpi_0_w_defconfig"` (read 2026-08-10) |
| Is WiFi-plus-URL as the only config input reasonable? | **Yes**, and it should be a runtime file on `/data`, not a build input |
| Is the whole thing gated on one thing? | **Yes — WebKit building and performing on ARMv6.** Everything else is routine |

**Chromium is out of scope entirely** (owner, 2026-08-10). It was never a candidate for the image —
it has no ARMv6 build past 72 — and the decision also retires it as a *fallback*: a Yocto card has no
`mmClient.sh` to `mv` back to. The Chromium rollback continues to exist, on the original SD card.

The browser is `surf`, as it runs today. That is better supported upstream than expected:
**`meta-openembedded` carries both `surf_2.1.bb` and `webkitgtk3_2.52.5.bb`** (read 2026-08-10), so
the browser needs no third-party layer at all.

The prize is not OTA. The prize is that this replaces a **2018 engine with a 2026 one** while keeping
the same 36KB browser shell — retiring the shims, the feature table and the build-time compat gate in
[`browser-constraints.md`](browser-constraints.md). OTA is the second prize.

## This is a hands-on change

Classify it before designing it. A `.wic` write is not reversible over the wire: it replaces the
partition table, so the NOOBS layout in [`pi-inventory.md`](pi-inventory.md) §"Storage" — including
`mmcblk0p1`, which the board needs to boot — is gone the moment it starts.

Consequences, all of which are advantages if taken deliberately:

- **Build on a different card.** The existing SL16G stays intact and unmodified.
- **Rollback is the best in this project**: power off, swap the old card back in, power on. No
  package operation, no `mv`, no partial state. It is a physical rollback for a physical change.
- **Therefore this is a plan for a card, not for the running device.** Under
  `CLAUDE.md` (kiosk-reference) the live kiosk is not migrated; it is *replaced*, on a swap that can
  be undone in the same trip.
- The card image and its verification are owned by [`backup-recovery.md`](backup-recovery.md);
  nothing here changes that, and the image gets more important, not less.

## What upstream already provides

| Layer | Gives you | Status |
|---|---|---|
| `poky` / `openembedded-core` | Toolchain, systemd, wpa_supplicant, ssh, X server, `wic` | Stable |
| `meta-openembedded` (`meta-oe`, `meta-python`, `meta-multimedia`) | **`surf_2.1.bb` and `webkitgtk3_2.52.5.bb`** — the entire browser | Recipes read 2026-08-10 |
| `meta-raspberrypi` | `raspberrypi0-wifi` machine, arm1176 tune, firmware, `vc4graphics` machine feature, U-Boot machine name | Machine conf read 2026-08-10 |
| `meta-rauc` | RAUC itself, bundle class, `DISTRO_FEATURES` hook | Upstream, maintained |
| `meta-rauc-community/meta-rauc-raspberrypi` | `sdimage-dual-raspberrypi.wks.in`, U-Boot integration, `update-bundle` target | README read 2026-08-10 — **it calls itself "for demo purpose only"** |
| `meta-autonomos` | The structure: core layer / board layer split, KAS includes, feature groups, `/data`, RAUC class | Reference only — no ARMv6 board |

**`meta-webkit` is not needed.** It carries the same engine version Igalia releases (2.52.5), and
using it would add a layer whose default target is WPE. Dropping it removes a pinned dependency.

`meta-rauc-raspberrypi`'s README documents `RPI_USE_U_BOOT = "1"` and `MACHINE = "raspberrypi3"` or
`raspberrypi4`. **It does not document `raspberrypi0-wifi`.** The pieces exist — the machine conf
names `rpi_0_w_defconfig` — but nobody upstream is claiming this combination works. Treat it as a
short spike, not a given.

> **Do not plan around `tryboot`.** A search result asserts every Pi model supports it; the Raspberry
> Pi documentation page for `config.txt` does **not** state model support (checked 2026-08-10), and
> on this board the bootloader is `bootcode.bin` on the card rather than an EEPROM. U-Boot is the
> path the layers actually support and the one that carries a bootcount. Unverified convenience is
> not worth a boot chain.

## The browser: surf, and the one thing it does not carry over

The live configuration is `surf` on WebKitGTK 2.18 with no window manager
(`README.md` (kiosk-reference)), built from `surf-kiosk.c` (kiosk-reference) and
`surf-kiosk.patch` (kiosk-reference). Under Yocto that becomes a `.bbappend` on
`surf_2.1.bb` carrying the same patch and `config.h` — genuinely small work, and the recipe already
exists upstream.

**What does not carry over is the engine version, and that is the whole risk.** There is no
WebKitGTK 2.18 in Yocto and no reason to want one; `meta-oe` builds **2.52.5**. So "the simple surf
install we had going" means *the same browser shell against an engine eight years newer* — not the
configuration that has been measured on this board. Consequences in both directions:

- **Good:** the `globalThis` and `queueMicrotask` shims become unnecessary, and every gap in
  [`browser-constraints.md`](browser-constraints.md) — flex `gap`, `?.`, `:is()`, `structuredClone` —
  closes. `scan-bundle.py` and the compat gate can retire. Keep the shims anyway; they cost ~100
  bytes and make the card bootable against the old engine too.
- **Half-answered as of 2026-08-10.** It *builds* — see §"Phase 0a: PASSED, 2026-08-10". What is
  still unknown is whether it **renders this page in acceptable time** on one 1GHz ARM11 core with
  432MB visible, with no JIT. Eight years of engine growth on fixed hardware is a real risk, not a
  formality. The baseline to beat is **71.7s to complete display** (n=3, WebKit 2.18 —
  [`browser-constraints.md`](browser-constraints.md) §"Run for real as the kiosk: a dead heat on
  speed, no memory win without more work").

Two concrete knobs found while reading the recipes (2026-08-10):

- `webkitgtk3` ships `jit` in its default `PACKAGECONFIG`. JavaScriptCore has no ARMv6 JIT baseline,
  so expect to remove it and land on the CLoop interpreter. **Measure the JS cost of that**; it is
  the single most likely reason Phase 0 fails.
- `surf_2.1.bb` declares `REQUIRED_DISTRO_FEATURES = "x11 opengl"`. **surf pulls in an X server** —
  it is not a DRM/KMS client. That is the honest price of this choice: a "minimal" image still ships
  Xorg. It is also exactly what runs on the device today, with no window manager, so it is the
  configuration with the fewest unknowns rather than the smallest one.

### Chromium is not coming back, and the reason to want it is already solved

Recorded with the argument, not just the conclusion, because "let's try Chromium again for the
debugging" is a question that will recur otherwise.

**Building it is a dead end.** V8's 32-bit ARM backend requires ARMv7; ARMv6 support was removed
years ago. The `armv6` Chromium 72 on the device is a *patched Raspberry Pi Foundation build*, and
those patches were abandoned after Buster — which is precisely why 72 is the ceiling
([`browser-constraints.md`](browser-constraints.md) owns that). `meta-chromium` targets ARMv7 and up.
There is no supported path and no maintained patch set to revive.

**Importing the cached 72 binaries into the image is conceivable and still wrong.** A recipe could
unpack the `.deb`s; `glibc` and `libstdc++` are backward-compatible so it might even run. But it pins
a 2019 engine inside a 2024 rootfs and puts every gap in the constraint table back — which discards
the entire reason for building this image.

**The capability that motivated the question already exists.** Read out of the library this project
built, 2026-08-10:

| | |
|---|---|
| `WEBKIT_INSPECTOR_SERVER` | present in `libwebkit2gtk-4.1` |
| `RemoteInspector` | 1083 symbol hits — compiled in, not a stub |
| `WebKitWebDriver` | binary built, shipped as `WebKitWebDriver3` |
| `surf -N` | calls `webkit_settings_set_enable_developer_extras()` |

So `surf -N` with `WEBKIT_INSPECTOR_SERVER=127.0.0.1:2999` gives a full Web Inspector — DOM, console,
network timeline, JS evaluation — over an SSH tunnel, the same shape as
`--remote-debugging-port=9222` bound to loopback. **Different protocol, same capability.** What is
actually lost is two Python clients, not the error channel.

> **`WebKitWebDriver` is not the replacement for `cdp-eval.py`, and an earlier revision of this
> section said it was.** WebDriver *launches its own browser instance*; it cannot attach to the
> already-running kiosk. `cdp-eval.py`'s entire value was evaluating JS inside the **live** page, and
> only the remote inspector does that. WebDriver is still worth having — scripted checks against the
> mirror without touching the kiosk — but it is a different job, and conflating them would send
> someone to the wrong tool at 2am.

Both ship in the same package, so neither needs its own `IMAGE_INSTALL` entry: `surf` depends on
`webkitgtk3`, which carries the library *and* `/usr/bin/WebKitWebDriver3`.

> **The alternative, recorded so it is not rediscovered later:** `cog` on WPE WebKit renders straight
> to DRM/KMS and would drop X, GTK and a compositor from the image. It is the port designed for this
> job. It was **not** chosen because it is a browser this project has never run, on a graphics path
> (`wpebackend-fdo` on vc4 KMS, or `wpebackend-rdk` on legacy dispmanx) that is untested on BCM2835 —
> two unknowns stacked on top of the engine-version unknown that exists either way. If Phase 0 fails
> on X or on memory rather than on the engine, this is where to go next.

**Phase 0 answers this and nothing else, and it can kill the project.** See §"Phases".

## Image contents

Minimal means "what a kiosk needs plus the lifeline", not "smallest possible".

| In | Why |
|---|---|
| systemd | Restart supervision replaces the `while true` loop in `mmClient.sh`; unit ordering replaces the lxsession chain |
| `openssh` + a baked authorized key | **The lifeline.** An image that omits it makes every future change hands-on |
| wpa_supplicant (or iwd) + systemd-networkd | `wlan0` is the only interface |
| `surf` + `webkitgtk3` + a bare X server | The kiosk. No display manager, no session manager, no window manager — `surf` runs fullscreen as it does today |
| Roboto fonts | The `local()` alias trap is owned by `STATUS.md` (kiosk-reference); a fresh image has no fontconfig history and must ship the real families |
| `rauc` + keyring | OTA |
| ~~`rng-tools`~~ | **Deliberately absent** (owner, 2026-08-10). The entropy work in the Raspbian card notes (kiosk-reference `raspbian-card.md`) was the largest bring-up cost on this board, but it was Chromium's cost — `kiosk-rngd` is disabled on the device today precisely because surf does not need it. Dropping Chromium drops the daemon with it |
| Read-only rootfs + `/data` | Removes SD wear from `/var` churn and makes A/B honest |
| Out | Why |
| LXDE, lightdm, openbox, lxsession | `surf` is a systemd unit started against a bare `Xorg`. The autostart chain in [`pi-inventory.md`](pi-inventory.md) §"Kiosk launch chain" disappears entirely |
| Chromium, and the `mv`-back rollback | Owner decision, 2026-08-10. The Chromium fallback lives on the original card |
| Package manager | An A/B image is replaced, not patched |
| Bluetooth, avahi, triggerhappy, apt timers | The trim list in [`pi-inventory.md`](pi-inventory.md) becomes "never built in" |

> **`-s 0 -dpms -nocursor` must move.** Screen blanking is suppressed on the *X server command line*
> by lightdm today ([`pi-inventory.md`](pi-inventory.md) §"Display and session"), not in any config
> file. Dropping lightdm drops the flags with it, and the failure mode is a kiosk that blanks after
> ten minutes — days later, once nobody is watching.

## Partitions

`sdimage-dual-raspberrypi.wks.in` gives the layout; the sizes are the decision, and **slot size is
fixed at flash time** — growing it later is another card write, not an update.

| Partition | Suggested | Note |
|---|---|---|
| boot (FAT) | 128–256MB | Firmware, U-Boot, both kernels. Also the drop point for first-boot config — see below |
| rootfs A | 1.0–1.5GB | Size against the *measured* image, then add ~2× headroom for a future engine |
| rootfs B | same as A | Must be identical |
| `/data` | remainder (~12GB) | Config, logs, WebKit cache. Survives updates by design |

meta-autonomos uses 200MB boot / 2GB / 2GB / remainder (read 2026-08-10) — a reasonable starting
point, and sized for a Pi 5 image with containers. A WPE kiosk should be far smaller; measure before
committing.

## Config surface: WiFi and URL

The requirement — "the only inputs are WiFi credentials and a URL" — is the right requirement, and it
should be satisfied at **runtime**, not at build time. A PSK baked into an image makes the image a
secret, which means it cannot be shared, cached, or rebuilt casually, and a URL change becomes a
full OTA cycle for a one-line edit.

Proposed: one file, one code path, three ways to populate it.

```sh
# /data/kiosk.conf
WIFI_SSID=
WIFI_PSK=
KIOSK_URL=
```

1. **`/data/kiosk.conf` is the source of truth.** A `oneshot` unit ordered before
   `wpa_supplicant.service` renders it into `wpa_supplicant.conf` (mode 600) and into an
   `EnvironmentFile` the cog unit reads.
2. **First boot, if absent:** the same unit looks for `kiosk.conf` on the FAT boot partition and
   copies it in. That partition is readable and writable from any card reader on Windows — which is
   exactly how SSH was enabled on this device on 2026-08-05 ([`pi-inventory.md`](pi-inventory.md)
   §"Access"). It means a card can be provisioned with no build and no console.
3. **Build-time defaults** via the KAS `secrets.yaml`, as meta-autonomos does.

> **Every device-identifying value goes through `secrets.yaml`** (owner, 2026-08-10) — not just the
> WiFi PSK, but the kiosk URL, the mirror host and the hostname. The build repo
> [`meta-wisekiosk`](https://github.com/tjwise99/meta-wisekiosk) is **public**, and that class of
> detail is not credential-shaped, so no secret scanner stops it: an SSID, a LAN address or a
> hostname fingerprints the site while passing every gate. `secrets.yaml` is gitignored upstream and
> only `secrets.yaml.tmpl` is tracked (verified 2026-08-10) — so the rule is that the tracked
> template carries **names with empty values**, and nothing else in the tree ever names a real one.
>
> This does **not** make the URL a build-time-only input. `secrets.yaml` supplies the *default* baked
> into the image; `/data/kiosk.conf` still overrides it at runtime, which is what keeps a URL change
> from being a software release. Build-time and runtime are the same three names, resolved in that
> order.

Consequences worth stating up front:

- **A URL change stops being a software release.** Write the file, restart one unit. Most changes you
  will actually want are URL changes.
- **`/data` surviving updates is also how a bad config survives an update.** Ship
  `kiosk.conf.default` in the read-only rootfs and a documented reset path, or the first bad SSID is
  a hands-on trip.
- Whatever reads the URL for the kiosk must be the same thing that reads it for the health check
  below. Two copies of a URL is a way to mark a broken boot good.

## OTA

**Mechanism.** RAUC A/B: `bitbake update-bundle` produces a signed `.raucb`; the device runs `rauc
install`. U-Boot holds the bootcount and the slot selection; a boot that never reports success falls
back. This is the standard shape and `meta-rauc-raspberrypi` implements it.

**Signing is the part that is easy to get permanently wrong.** The device trusts exactly the keyring
baked into its rootfs. Rotating that keyring requires an update signed by the *current* key — so a
lost or compromised key is a hands-on recovery on every device. Decide custody before the first card
ships, not after.

**Delivery, in increasing order of commitment:**

| Tier | What | When it is right |
|---|---|---|
| 1 | `rauc install <path>` over SSH after `scp` | Always. Build this first; it is the fallback for every later tier |
| 2 | Bundle at an HTTPS URL + a `systemd` timer that checks a version file | One to a handful of kiosks. Probably the answer here |
| 3 | hawkBit or equivalent | A fleet with staged rollouts and per-device state |

casync/delta bundles (meta-autonomos supports them) buy bandwidth. On LAN WiFi against a local
mirror host, bandwidth is not the constraint — [`pi-inventory.md`](pi-inventory.md) §"Network" —
so skip them until they are.

**The rollback health check is the hard part, and it is not "did the unit start".** This repo has
already recorded a DOM check reporting perfect health while the screen was visibly broken
([`browser-constraints.md`](browser-constraints.md)). A `mark-good` that fires on process liveness
will happily confirm a black screen. Candidates, none tested: a page-side heartbeat written to a
file, cog's remote inspector, or a framebuffer capture compared against a floor. Whichever is chosen,
it must be able to *fail*.

> **The rollback harness is itself an untested change with system-wide blast radius.** Prove it in
> three directions before it guards anything: it fires on a deliberately broken slot, it does **not**
> fire on a slow-but-healthy boot, and it behaves when its own check overruns the window. Take a
> lock; disarm before acting rather than after. A boot on this board reaches a rendered page around
> 70s — a health-check timeout set from a developer's intuition will roll back every good update.

**Install time is unmeasured.** The card reads at ~22.7–22.9 MB/s (n=3, 2026-08-06,
[`backup-recovery.md`](backup-recovery.md)); write is slower and untested. A ~500MB slot write plus
reboot is plausibly several minutes with the kiosk display live throughout — RAUC writes the
*inactive* slot, so there is no visible outage until the reboot. Measure it in Phase 5.

## Build host

Cross-build on the WSL host; never on the Pi. WebKit is the long pole — expect tens of GB of
downloads plus sstate and hours on the first build, then minutes on incremental ones. Use KAS with
pinned layer revisions from the start: an unpinned `meta-webkit` will move under you mid-project, and
"it built last week" is not a reproducible image.

## Phases

Each phase answers one question and has a way to fail.

| # | Question | Done when | Rough size |
|---|---|---|---|
| **0** | **Does WebKitGTK 2.52.5 build for `arm1176jzfshf`, and does patched `surf` render this page fast enough without a JIT?** | The live mirror page displayed on the real board from a hand-flashed image, with time to complete display measured the same way as the baseline (n≥3) and compared against **71.7s** | 2–5 days. **Kill gate** |
| 1 | Does a minimal image boot, join WiFi and accept SSH? | Reboot to a shell over `wlan0`, twice | 1–2 days |
| 2 | Is the kiosk a supervised unit rather than a session chain? | `surf` on bare Xorg, no WM, survives a killed browser and a reboot; blanking still suppressed after 20 minutes | 2–4 days. **Blanking leg passed 2026-08-11** |
| 3 | Does A/B work on this machine? | `rauc status` correct, `update-bundle` installs, deliberate bad slot rolls back | 2–4 days |
| 4 | Is the config surface really just WiFi + URL? | A blank card + a `kiosk.conf` on the FAT partition boots to the right page with no build | 1–2 days |
| 5 | Can an update ship without a trip? | Tier-1 then tier-2 delivery, install time measured | 1–3 days |
| 6 | Does it survive? | Soak with the existing sampler; update, roll back, update again | 3–5 days elapsed |

Roughly **3–5 weeks part-time**, entirely contingent on Phase 0. Phase 0 before any layer scaffolding
— the temptation is to build the pretty core/board layer split first, and that work is worthless if
the engine does not run.

## Phase 0 runbook

Written 2026-08-10 against this WSL host, measured not assumed: **8 cores, 7GB RAM, 931GB free on
the ext4 root, `/mnt/c` with 22GB free, host `python3` 3.14.4, no card reader visible to WSL.**

> ## Phase 0a: PASSED, 2026-08-10
>
> **WebKitGTK 2.44.3 and surf 2.1 build clean for `arm1176jzfshf`.** Measured, not inferred:
>
> | | |
> |---|---|
> | `readelf -A` on both binaries | **`Tag_CPU_arch: v6KZ`, `Tag_FP_arch: VFPv2`** — genuine ARMv6 hard-float, the same check [`browser-constraints.md`](browser-constraints.md) used on Chromium 72 |
> | Linkage | `surf` → `libwebkit2gtk-4.1.so.0`, `libgtk-3.so.0` |
> | Shipped size | **45 MB** stripped (506 MB unstripped; 462 MB of debug info goes to a `-dbg` package that never reaches the image) |
> | surf | 182 KB |
> | Build | 3596 tasks, 0 errors, 0 OOM kills, **4h31m wall** on 8 cores / 11 GB, `-j4` then `-j6` |
> | `ENABLE_JIT=OFF` | confirmed reaching cmake |
>
> ## Phase 0b: PASSED on feasibility, 2026-08-11 — and it is SLOWER
>
> **The image boots on the real board and renders the page correctly. It is also ~20% slower than the
> configuration it would replace.** Both halves matter.
>
> | run | complete display |
> |---|---|
> | 1 | 59.59 s |
> | 2 | 55.44 s |
> | 3 | 56.21 s |
> | **mean** | **57.08 s** (range 55.44–59.59) |
> | **live Raspbian, optimised** | **47.53 s** (`STATUS.md` (kiosk-reference)) |
>
> > **Corrected within the hour it was written.** This first claimed ~20% *faster* by comparing
> > against **71.7 s** from [`browser-constraints.md`](browser-constraints.md) — an older figure from
> > a different harness, which `STATUS.md` explicitly warns is not comparable. The live kiosk had been
> > taken to **47.53 s** on 2026-08-09 by five removals (bare X session, `GDK_GL=disable`, no window
> > manager, rngd off, prefetch off). `STATUS.md` is the document that carries current device state
> > and the one to read first; a baseline was taken from elsewhere.
>
> **The gap is boot, not the browser.** `uptime_at_exec` is ~41 s here against ~34 s on Raspbian, and
> the render itself is comparable. The Yocto image has never had a single systemd unit trimmed, while
> the Raspbian configuration went through five rounds of removals. The deficit sits in the part that
> has had no attention, not in WebKit.
>
> The config already matches every one of those five removals — bare X, `GDK_GL=disable`,
> override-redirect instead of a WM, no rngd, no prefetch — so the gap is not missing tuning that was
> already known about.
>
> **The fbturbo caveat still stands and now cuts the original way:** the baseline ran an accelerated
> 2D driver this image does not have, so part of the 9.5 s may be the X driver rather than anything
> else. Engine and driver remain indistinguishable without a second experiment.
>
> Correct rendering was confirmed **as pixels by the owner**, not by a DOM check — `fbgrab` returned a
> blank white capture against a screen that was demonstrably working.
>
> > **CORRECTED 2026-08-11: `fbgrab` is a usable capture path, and always was.** It captures X
> > correctly; it writes RGBA with **every alpha byte 0**, and viewers composite that onto white. The
> > RGB data underneath was intact the whole time — the capture that read as blank decodes to
> > `min=0 max=255 mean=4.1`, and rendering it opaque gives a legible kiosk screen. Run
> > `fbgrab-fix.py` (kiosk-reference) on the PNG before looking at it;
> > [`remote-debugging.md`](remote-debugging.md) §"Recipe 9" has the full path.
> >
> > The original note read a broken *reader* as a broken *capture path*, and closed off the pixel
> > check on the one image where nothing else can substitute for it.
>
> | | |
> |---|---|
> | Memory | 87 MB used, vs 84 MB on Raspbian — **essentially unchanged**, not the large win first claimed. That comparison had put system-used against a sum of per-process RSS, which double-counts shared pages |
> | zram | 0 KB used on every run — the safety net never engaged |
> | Entropy | 256, no daemon, confirming kiosk-rngd was Chromium's requirement |
> | Temperature | **not comparable** — these samples are bench, open air; the baseline is the wall enclosure |
> | Framebuffer | 1824x984 — identical to the live kiosk, so the pixel count is comparable |
>
> **Phases 1 and 2 passed with it**: WiFi, SSH, and a supervised kiosk on bare Xorg with no display
> manager and no window manager. Building anything bootable required their work up front.
>
> **RAUC is already functional on this card** — both slots visible, correct booted slot, U-Boot
> integration reading back, `/data` mounted. Phase 3 is nearer than this document assumed.

### Split it in two. The first half needs no card at all

**Phase 0a — does it compile?** `bitbake webkitgtk3 surf` for `MACHINE = "raspberrypi0-wifi"`. No
image, no flash, no hardware. This is the highest-risk question and the cheapest one to ask; if
WebKit does not build for `arm1176jzfshf`, the project is over and the spare card was never touched.

**Phase 0b — does it render fast enough?** Only after 0a is green: build an image, flash the spare
card, boot the real board, measure.

Running 0b's setup before 0a is the classic wasted week.

### Pick the branch, because the branch picks the engine

`surf_2.1.bb` is on every branch; `webkitgtk3` is not (read 2026-08-10):

| Branch | WebKitGTK |
|---|---|
| `scarthgap` (LTS) | 2.44.3 |
| `walnascar` | 2.48.1 |
| `whinlatter` | 2.48.7 |
| `master` | 2.52.5 |

**Start on `scarthgap`.** It is the LTS, `meta-raspberrypi` and `meta-openembedded` both carry the
branch, **meta-autonomos already pins every repo to it**, and 2.44.3 is the *smallest* of the four — on a board where the question is whether an engine
fits at all, older is a feature, not a compromise. It is still a 2024 engine and still closes every
gap in [`browser-constraints.md`](browser-constraints.md). Chasing 2.52.5 on `master` adds an
unstable branch to a bring-up that already has one unknown.

### Yes, meta-autonomos bootstraps this — start from it, do not start from poky

Read from a clone on 2026-08-10, not from the README. What it hands you:

| It already has | Detail |
|---|---|
| **The branch this plan chose independently** | `includes/base.yaml` pins every repo to `scarthgap` |
| **`kas-container` — the build runs in Docker** | Docker 29.6.1 is up on this host. See below; it deletes a whole class of problem |
| The Pi plumbing | `meta-raspberrypi`, `meta-rauc`, `meta-rauc-community` (scarthgap), `meta-lts-mixins` on `scarthgap/u-boot` with a comment recording *why* (a U-Boot/rpi patch incompatibility), and `RPI_USE_U_BOOT = "1"` |
| A parameterised A/B layout | `autonomos-dual-raspberrypi.wks.in`: boot 200MB, rootfs A/B at `AUTONOMOS_ROOTFS_SIZE` (2048), data at `AUTONOMOS_DATA_SIZE` (512) |
| **A new board as a four-line file** | `includes/platforms/raspberrypi-zero-2w.yaml` is a header, an include, a `machine:` line and one override |
| WiFi as a build input | A `wpa-supplicant` bbappend seds `WIFI_SSID` / `WIFI_PSK_HASH` into `wpa_supplicant.conf`, fed from `secrets.yaml`. **Exactly right for Phase 0**; Phase 4 replaces it with the runtime file |
| Operator ergonomics | `Justfile` with build / flash / `rauc-status`, and casync delta packaging in `justfiles/ota.just` |

**`kas-container` is the single biggest thing it gives you.** The build runs inside the kas Docker
image, so the host's toolchain is irrelevant. An earlier draft of this section told you to build
`buildtools-extended-tarball` to work around this host's `python3` 3.14.4 — **ignore that; it is
unnecessary via kas-container**, which is the better answer anyway because it makes the build
reproducible off this machine.

### Four things in it that will fight an ARMv6 kiosk

1. **`autonomos.conf` does `DISTRO_FEATURES:remove = " x11 wayland"`, and you cannot undo that from
   `local.conf`.** bitbake applies `:remove` last, after every append from every file, so a
   `DISTRO_FEATURES:append = " x11"` in a kas `local_conf_header` is silently defeated. What you see
   is `surf` failing its `REQUIRED_DISTRO_FEATURES` check for a feature you can point at in your own
   config. **Fix: copy `autonomos.conf` to `kiosk.conf`, delete that one line, set `DISTRO =
   "kiosk"`, and set `distro: kiosk` in the kas file.** `opengl` needs no rescue — it arrives from
   `poky.conf`, which `autonomos.conf` requires, and is not in the removal list. Confirm both with
   `bitbake -e | grep '^DISTRO_FEATURES='` before you start a long build.
2. **`AUTONOMOS_FEATURES = "shellplus containers kubernetes"`** in `reference.yaml` — Docker and k3s
   on a 512MB ARMv6 board. Set it to `""`.
3. **`raspberrypi0-2w-64` is aarch64; this target is 32-bit ARMv6.** Anything in
   `meta-autonomos-raspberrypi` assuming 64-bit — kernel fragments,
   `packagegroup-autonomos-raspberrypi`, `base-files` — needs a read before the first *image* build.
   Do not copy the `MENDER_SWAP_PART_SIZE_MB` line out of the Zero 2 W include; it is a Mender
   variable sitting in a RAUC project, i.e. vestigial.
4. **`IMAGE_ROOTFS_MAXSIZE` is pinned to `AUTONOMOS_ROOTFS_SIZE`**, so an image that outgrows its
   slot fails the build instead of producing an unflashable card. That is a good property. Just know
   that a WebKit image is what will find it.

### Two host facts to settle before the first command

- **RAM is the binding constraint, not disk** — 931GB free against a need of ~100–150GB, but only
  ~7.7GB of RAM. WebKit's link step wants multiple GB *per linker process*, and his `reference.yaml`
  sets `PARALLEL_MAKE` to `cpu_count()`, which is 8 here. That combination OOMs hours in. Override it
  (below), and consider raising the WSL2 memory cap in `C:\Users\<you>\.wslconfig`.
- **The spare card must be ≥8GB.** 200 + 2048 + 2048 + 512 ≈ 4.8GB of fixed partitions. If the spare
  is smaller, drop `AUTONOMOS_ROOTFS_SIZE` to 1024 *before* building — the size is baked into the
  `.wic`, so discovering it at flash time costs another build.
- **WSL cannot see the card reader** (no `/dev/mmcblk*`, no removable `/dev/sd*`). Copy the
  `.wic.bz2` to `/mnt/c` — 22GB free, ample — and flash from Windows with Raspberry Pi Imager or
  balenaEtcher. `usbipd-win` would let `bmaptool` do it from WSL, but that is a second bring-up to
  debug during the first.

### The morning sequence

**Step 0 — `kas-container` on PATH (5 min).** It is a single script; pin it to a release tag rather
than `master`.

```sh
mkdir -p ~/bin && curl -L -o ~/bin/kas-container \
  https://raw.githubusercontent.com/siemens/kas/<pinned-tag>/kas-container
chmod +x ~/bin/kas-container && kas-container --help
```

**Step 1 — fork and branch (5 min).** Work on a branch of his repo, not in it. `just` is already
installed here.

**Step 2 — three files.** This is the whole port.

`meta-autonomos-core/conf/distro/kiosk.conf` — copy of `autonomos.conf` with `DISTRO = "kiosk"` and
the `DISTRO_FEATURES:remove = " x11 wayland"` line deleted.

`includes/platforms/raspberrypi-zero-w.yaml`:

```yaml
header:
  version: 20
  includes:
    - includes/platforms/raspberrypi.yaml

machine: raspberrypi0-wifi
```

`kiosk-zero-w.yaml` at the root:

```yaml
header:
  version: 20
  includes:
    - includes/base.yaml
    - includes/platforms/raspberrypi-zero-w.yaml
    - secrets.yaml

build_system: oe
distro: kiosk
target: core-image-base          # Phase 0b only; 0a builds recipes, not an image

local_conf_header:
  standard: |
    PATCHRESOLVE = "noop"
    CONF_VERSION = "2"
    TMPDIR = "${TOPDIR}/tmp-${MACHINE}"
    EXTRA_IMAGE_FEATURES ?= "debug-tweaks"

  kiosk: |
    AUTONOMOS_FEATURES = ""
    PACKAGECONFIG:remove:pn-webkitgtk3 = "jit gtk4"
    IMAGE_INSTALL:append = " surf packagegroup-core-x11 xwininfo xprop ttf-roboto fbgrab"

  memory: |
    BB_NUMBER_THREADS = "4"
    PARALLEL_MAKE = "-j4"
    PARALLEL_MAKE:pn-webkitgtk3 = "-j2"
```

Then `cp secrets.yaml.tmpl secrets.yaml` and fill `WIFI_SSID` / `WIFI_PSK_HASH` — the hash comes from
`wpa_passphrase <ssid> <psk>`. **`secrets.yaml` is gitignored in his repo; confirm that holds in your
fork before the first commit.**

Recipe names verified against the layers on 2026-08-10: `xwininfo`, `xprop` and
`packagegroup-core-x11` are oe-core; `ttf-roboto` and `fbgrab` are meta-oe. **There is no `scrot`
recipe.** The open question of whether `fbgrab` captures X or the console is **closed, 2026-08-11: it
captures X**, because `xf86-video-fbdev` renders into `/dev/fb0`. `imagemagick`'s `import` is not
needed. Its captures need `fbgrab-fix.py` (kiosk-reference) run over them first —
see [`remote-debugging.md`](remote-debugging.md) §"Recipe 9".

**Step 3 — parse-only sanity check (10–20 min). The first real checkpoint.**

```sh
KAS_CONFIG=kiosk-zero-w.yaml kas-container shell kiosk-zero-w.yaml
# inside:
bitbake -e | grep -E '^(DISTRO_FEATURES|MACHINE|DEFAULTTUNE)='
bitbake -p
```

You are looking for `x11` and `opengl` present, `MACHINE=raspberrypi0-wifi`,
`DEFAULTTUNE=arm1176jzfshf`. A clean `bitbake -p` means every layer parses for this machine — cheap,
and it catches the aarch64 assumptions in his Pi layer before they cost hours.

**Step 4 — Phase 0a, the gate.** Still inside the kas shell:

```sh
bitbake webkitgtk3
bitbake surf
```

No image, no RAUC, no wic. The extra layers ride along harmlessly because nothing asks them for a
recipe. Expect the first `webkitgtk3` to run for hours — start it and leave it. **This is the
answer the whole plan is waiting on.**

**Step 5 — Phase 0b image (only if 0a is green).** `KAS_CONFIG=kiosk-zero-w.yaml just build`, plus
a systemd unit that starts Xorg and `surf` — no display manager, no window manager, and carrying
`-s 0 -dpms -nocursor` onto the X server command line.

**Step 6 — flash.** `cp build/tmp-*/deploy/images/raspberrypi0-wifi/*.wic.bz2 /mnt/c/Users/<you>/`,
then Imager or Etcher from Windows onto the spare card.

**Step 7 — measure.** Ported `measure-surf.sh`, three reboots, monotonic form, then look at the
pixels.

### At the bench: what to do once the card is written

The Pi comes off the wall to a desk with a monitor and mini-HDMI, next to the card reader. There is
**no USB-serial adapter**, so the panel is the only console — which is why `console=tty1` is on the
kernel command line. Work in this order; each step tells you something the next one assumes.

| # | Do | Expect | If not |
|---|---|---|---|
| 1 | Card in, power on, watch the monitor | Kernel messages scrolling within ~10s | Nothing at all: firmware/boot partition. Re-flash, or check the card seated. This is the only failure with no diagnostic |
| 2 | Watch for `wlan0` and the DHCP lease | An address on `Wise-Fi` | The console shows why — `wpa_supplicant` failing, firmware missing, wrong PSK. All readable |
| 3 | From the workstation: `ssh root@<addr>` | Prompt, no password | If 1–2 passed and this fails, it is sshd config, and the console still gets you in |
| 4 | Wait for the kiosk | `surf` fullscreen on the mirror page | `journalctl -u kiosk` names it. X, fonts, URL, or the engine |
| 5 | Look at the pixels | Clock ticking, live wait times | A DOM that reports healthy while the screen is wrong has happened here before. Only pixels settle it |
| 6 | `cat /var/log/surf-milestones.log` | `SURFMS` lines with an `uptime_at_exec` anchor | No milestones means the patch did not take, and the measurement is impossible |
| 7 | Reboot ×3, run the ported `measure-surf.sh` | Complete-display, monotonic form, n≥3 | Compare against **71.7s** — but read the caveat below before concluding anything |

**Two things to check that are easy to forget:**

- **Blanking — CONFIRMED WORKING 2026-08-11, and the mechanism is readable in one command.** `-s 0
  -dpms -nocursor` moved from lightdm to the unit's `ExecStart`, and `xset -display :0 q` shows both
  took: `timeout: 0`, and `Server does not have the DPMS Extension` — the extension is gone, so
  nothing can blank the screen. **Read that rather than waiting 20 minutes**: waiting tells you it has
  not blanked *yet*, the query tells you it cannot. (15.9 h unattended agrees with it.)
- **Memory.** `free -m` and `cat /proc/swaps`. This is where you find out whether a 2024 engine fits
  in 432MB, and whether zram was needed or is idle.

> **Do not compare the timing naively.** The 71.7s baseline was measured under `fbturbo`, which does
> accelerated 2D blits. meta-raspberrypi has no `fbturbo` recipe, so this image runs plain
> `xf86-video-fbdev`. If the new number is slower, *"WebKit 2.44 is slower"* and *"fbdev is slower
> than fbturbo"* are **not distinguishable** without a second experiment. Record the number; do not
> convert it into a verdict about the engine.

**Turning on the inspector**, if something renders wrong and you want to see why — no rebuild, no
re-flash:

```sh
sed -i 's/^KIOSK_INSPECTOR=0/KIOSK_INSPECTOR=1/' /etc/kiosk.conf && systemctl restart kiosk
ss -ltn | grep 2999            # confirm it is listening
# from the workstation: ssh -L 2999:127.0.0.1:2999 root@<addr>, then http://127.0.0.1:2999/
```

**Rollback is the original card.** Power off, swap, power on. The SL16G is untouched and its layout
is unchanged, so this works regardless of anything above.

### Where each step can fail, and what the failure means

| Where | Failure | Reading |
|---|---|---|
| Parse check | Layer will not parse for `raspberrypi0-wifi` | An aarch64 assumption in his Pi layer. Cheap to fix, do it now |
| Parse check | `DISTRO_FEATURES` has no `x11` | The `:remove` trap. You did not create `kiosk.conf`, or kas is still pointed at `distro: autonomos` |
| Phase 0a | `webkitgtk3` fails to compile for `arm1176jzfshf` | **The project's answer.** Report it; it is not a setback to work around |
| Phase 0a | Build dies with the OOM killer | Host, not target. Lower `PARALLEL_MAKE`, raise the WSL2 memory cap, resume — sstate means you do not start over |
| Image build | Image exceeds `IMAGE_ROOTFS_MAXSIZE` | Raise `AUTONOMOS_ROOTFS_SIZE` **before** flashing, since the size is baked into the `.wic` |
| Measurement | Renders, but far slower than 71.7s | Engine problem if it is JS-bound (CLoop), *port* problem if it is Xorg+GTK on 432MB. The second one points at cog/WPE |

### What must be in the image, or the phase yields no number

This list is the difference between a measurement and a second overnight build:

| Must ship | Because |
|---|---|
| `openssh` + baked key | The lifeline, and the only way results leave the board |
| `xwininfo`, `xprop` | `measure-surf.sh` (kiosk-reference) walks the window tree with them |
| `fbgrab` (there is no `scrot`) | **Look at the pixels.** A DOM check once reported perfect health on a visibly broken screen — [`browser-constraints.md`](browser-constraints.md). Read its output through `fbgrab-fix.py` (kiosk-reference) or a healthy screen looks blank white |
| Roboto fonts + `99-kiosk-roboto-local.conf` (kiosk-reference) | Without them the render is wrong for a reason that has nothing to do with the engine, and you will chase it |
| systemd | `measure-surf.sh` reads `systemd-analyze` |

> **No `rng-tools`, and keep it that way.** The entropy daemon existed for Chromium. Two things
> reinforce that on a Yocto image rather than weakening it: the scarthgap kernel is ~6.6, where the
> CRNG initialises far earlier than on this device's 4.19, and there is no Chromium left to feed.
> **The check stays even though the package goes** — `measure-surf.sh` already prints
> `entropy_avail`, so read that field on the first boots. It costs nothing, and it is the one place
> a fresh image differs from the measured device: no persisted random seed, and a first-boot sshd
> generating host keys.

### Port the harness before you flash, not after

`measure-surf.sh` will not run unmodified. It hardcodes `/home/pi`, `/home/pi/surf-2.0/surf`,
`/webkit2gtk-4.0/WebKit*Process`, `kiosk-prefetch.service`, `kiosk-rngd.service` and an openbox check
— none of which exist on this image, where the user is `root`, surf is `/usr/bin/surf` and the
WebKit API version differs. Port it against the Yocto paths **before** the card goes in the board;
the alternative is discovering it after a boot you cannot repeat cheaply.

Two things it depends on that are not in the image at all: the mirror host must be reachable over
WiFi and serving the **instrumented** page (the title carries `navigationStart` and
`performance.now()`), and the milestone log written by the patched surf needs a writable path — pick
one now rather than inheriting `/home/pi/surf-milestones.log`.

### The gate

| | Pass | Fail |
|---|---|---|
| 0a | `webkitgtk3` and `surf` build clean for `arm1176jzfshf` | Stop. Report the failure — it is the project's answer, not a setback |
| 0b | Page renders correctly **as pixels**, and complete display measured n≥3 over real reboots, monotonic form, against the **71.7s** baseline | See below |

**Failing 0b is not automatically fatal, and the reason matters.** Slow because of CLoop is an engine
problem and points at cog/WPE or at nothing. Slow or OOM because of Xorg plus GTK on 432MB is a
*port* problem and points squarely at cog/WPE on DRM, which drops both. Record which one it was.

> **Compare like with like.** The 71.7s baseline was measured with the prefetch disabled and by the
> monotonic form, because a mid-boot clock step once produced a fake 27s reading. n=1 against an n=3
> baseline is how the earlier speed claims in this repo went wrong twice. Three reboots minimum.

Realistic cost: half a day of host prep, then an overnight first build. 0a answers the question that
matters within a day of the build finishing.

## What has to be ported, and what is lost

| Today | Under Yocto |
|---|---|
| `mmClient-surf.sh` retry loop | `Restart=always` + `RestartSec` |
| `surf-kiosk.c` + `surf-kiosk.patch` | A `.bbappend` on `surf_2.1.bb`. **The only browser work in the plan** |
| `99-kiosk-roboto-local.conf` | Ships in the image. The `local()` alias problem is a property of the bundle, not of the OS, so it survives the migration |
| `kiosk-rngd` | **Not ported.** It was Chromium's dependency; surf does not have it, and the daemon is already disabled on the device for that reason |
| `kiosk-egress.rules` | nftables ruleset baked in |
| Boot service trims | Not built in the first place |
| `scan-bundle.py` compat gate | Obsolete if 2.52.5 lands — **verify against the built engine before deleting it** |
| `cdp.py` / `cdp-eval.py` | **The clients do not port; the capability does.** They speak CDP, which WebKit does not. But WebKit's own remote inspector is a peer, not a downgrade — see §"Chromium is not coming back, and the reason to want it is already solved" |
| `kiosk-soak.sh` | Keep. It becomes the evidence that an update was good |
| The measured Chromium-72 body of knowledge | Retired. [`browser-constraints.md`](browser-constraints.md) becomes history rather than constraint — **do not delete it until 2.52.5 is measured on the board** |

## Open questions for the owner

1. **How many kiosks, on what hardware?** Already the fork in [`provisioning.md`](provisioning.md)
   and `STATUS.md` (kiosk-reference) §"Owner decisions". Yocto+OTA is heavy for one device and
   obviously right for ten; nothing below three makes the tooling pay for itself against a shell
   script and a card image.
2. **Is this device in scope at all**, given the project it serves is being superseded?
3. **Who holds the RAUC signing key**, and where is the backup?
4. **Who hosts the bundle**, if delivery goes past tier 1?

## A stale `/data/update.raucb` makes the sender ship nothing

[`send-bundle-chunked.sh`](../tools/send-bundle-chunked.sh) resumes by reading the **durable on-disk
size** of the destination and skipping to that offset — the property that let it survive the hangs
this board used to take mid-transfer, traced to CPU-frequency instability and fixed by
`kiosk-cpufreq` (see [`experiment-log.md`](experiment-log.md) §"ROOT CAUSE + FIX"). Resume-from-offset
is unrelated to that fix and still holds: it is what makes an interrupted transfer cheap to retry. Its
loop exits when `cur >= SIZE`.

So a destination left over from a previous update that is **larger** than the new bundle satisfies
that immediately. Observed 2026-08-12: `/data/update.raucb` held the previous session's
130 730 634 bytes against a new bundle of 129 292 938. The sender would have reported a complete
transfer having moved **zero bytes**, and `rauc install` would have reinstalled the previous image —
the failure `justfiles/ota.just` already warns about for a stale *local* `.raucb`, arriving from the
other end.

The end-to-end `md5sum` at the tail of the script catches it (`MISMATCH -- do not install`, exit 1,
and `just` stops before installing), so it fails safe. It fails safe **after ~25 minutes** of
apparent progress.

```sh
ssh root@<kiosk> 'rm -f /data/update.raucb; sync'    # before every delivery
```

Removing it also returns ~130 MB of `/data`, which matters because the bundle stages there and each
A/B update orphans a journal namespace on the same partition.

## `send-bundle-chunked.sh` exists twice, byte-identical, with nothing syncing them

The script lives at `tools/send-bundle-chunked.sh` in **both** this repo and `~/meta-wisekiosk`
(md5 `f1e3b8ef831508ca2ab3b715de97796f` in each, 2026-08-12). `just kiosk-send` runs the build
tree's copy; this document and `STATUS.md` link to this one. Editing either leaves the other stale
with nothing to say so — the same shape as the `fbgrab` drift in
[`remote-debugging.md`](remote-debugging.md) §"Recipe 9". Not resolved; recorded so a change to one
is known to need the other.

## The first boot of a freshly OTA'd slot is not a normal boot

Two things fire once, on the first boot of a slot that has just been written, and both distort
anything measured on it.

**SSH host keys are regenerated, and the device is unreachable while they are.** Measured on slot A,
2026-08-13:

```
25.13  Starting OpenSSH Key Generation...
25.77    generating ssh RSA host key...     <- 25.6 s
51.35    generating ssh ECDSA host key...
51.69    generating ssh ED25519 host key...
52.07  Finished OpenSSH Key Generation
```

`sshd.socket` listens at 23.98 s but cannot serve a session until the keys exist. **Do not expect to
reach a slot for the first ~50–80 s after an OTA**, and do not read a failed connection in that
window as a failed update — the first thing to check is `ping`, which answers throughout.

That 27 s of key generation runs *on the same saturated core as the browser start*, so it also
inflates the boot it happens on: `surf` exec read 33.05 s on slot A's first boot against 31.26 s on
its second, with zero keygen lines. **1.79 s**, which corroborates the ~1.6 s
`ConditionNeedsUpdate` penalty in [`boot-profile-yocto.md`](boot-profile-yocto.md) §"The first boot
after an OTA" — measured here on a different slot, image and `machine-id`.

**Take the steady-state number from the second boot, never the first.**

## Delivered 2026-08-13 — slot A, verified against the running system

| | |
|---|---|
| Bundle | `fa5e0b748e2615f0c007d69ae7b5a5eb`, 129 292 938 B |
| Transfer | 62 bursts, 24 min, end-to-end md5 **MATCH** |
| Install | `Activated: rootfs.0 (A)`, `BOOT_ORDER=A B`, both slots `good`, counters at 3 |
| Modules loaded | **16** (22 before the Bluetooth blacklist) |
| udev rule masks | 22 |
| `ofono` / `avahi-daemon` / `rpcbind` | absent |
| Failed units | **0** — the every-boot `zram` failure is gone |
| `surf` exec, steady | **31.26 s** against a 34.42 s baseline |

31.26 s falls inside the range measured for the same change set applied at runtime
(30.55–31.45 s), so the build-tree route reproduces the runtime result rather than merely
resembling it.

Slot B holds the previous image and remains the rollback: `just kiosk-rollback`, then reboot.
