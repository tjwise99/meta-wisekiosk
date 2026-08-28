# meta-wisekiosk

A wall-mounted Raspberry Pi Zero W kiosk: `surf` on WebKitGTK against a bare Xorg, no desktop, no
window manager, no display manager. The unit shows one page and is reached only over WiFi, so
everything here is shaped by the fact that a broken image costs a physical trip to the wall.

Updates are RAUC A/B over U-Boot, delivered over the LAN. Site configuration — SSID, PSK hash, URL,
hostname, machine-id — is **never** in the image; it is written to the device's `/data` partition by
provisioning and read at runtime.

The page the kiosk shows is **WiseKiosk** ([`tjwise99/WiseKiosk`](https://github.com/tjwise99/WiseKiosk)),
a separate system served from elsewhere on the LAN that this repository neither builds nor deploys.
Only its URL enters here, as site config — `KIOSK_URL` in `secrets.yaml`, written to the device's
`/data` at provisioning.

> ### Related project
>
> That boundary is being moved. WiseKiosk epic
> [#208 appliance-first-class](https://github.com/tjwise99/WiseKiosk/issues/208) brings the board
> inside WiseKiosk's requirements boundary and bakes the application into this image, so the app
> stops being a URL this repository points at and becomes something it ships. The two repositories
> stay separate. This is in progress and will change the paragraph above.

How to work in this repository — the gates, the conventions and the review checklist — is
[CONTRIBUTING.md](CONTRIBUTING.md); the rules an AI agent works under are [CLAUDE.md](CLAUDE.md).

> ## Attribution
>
> This project builds on [jsmith212/meta-autonomos](https://github.com/jsmith212/meta-autonomos),
> which supplies the `autonomos` distro, the RAUC bundle recipe and the Raspberry Pi platform layer.
> kas fetches it at a pinned commit into `sources/`; this repository contains none of it.
>
> The upstream repository carries **no top-level license**. Its core layer contains a `COPYING.MIT`
> (standard Yocto layer boilerplate) and its README defers to per-recipe licenses, so the licensing
> of the tree as a whole is unclear — all rights not clearly granted remain with its author. Nothing
> here is offered under any license on their behalf, and nothing here redistributes it — `sources/`
> is gitignored and every user fetches upstream directly from upstream.
>
> Upstream's identifiers — the `autonomos` distro, `AUTONOMOS_FEATURES`, the `meta-autonomos-*` layer
> names — are deliberately left unrenamed. Two concrete reasons: the RAUC *compatible* string is
> `autonomos-${MACHINE}`, a literal set by upstream's `autonomos-rauc.bbclass`, and a deployed board
> refuses a bundle whose compatible does not match its own — so moving off upstream's class or
> renaming its identifiers is a one-way change that strands every unit in the field. And the two patches
> in `patches/meta-autonomos/` have to apply to upstream's files as upstream writes them.

## Layout: scaffolding vs. layer

The repository is a project, not a layer. Exactly one directory in it is a BitBake layer.

```
meta-wisekiosk/                    <- the repository (project scaffolding)
├── README.md, CONTRIBUTING.md     what this is; how to change it and get it merged
├── CLAUDE.md                      working rules for an AI agent, and who owns which fact
├── .claude/                       session settings and hooks: the commit self-review, the
│                                  device guard and its self-test, the compaction snapshot
├── kiosk-zero-w.yaml              kas config: the one entry point
├── includes/                      repo pins and machine config, pulled in by the above
│   ├── base.yaml                  every repo + commit, incl. meta-autonomos and its patches
│   ├── rauc.yaml
│   ├── cve-audit.yaml             opt-in cve-check overlay, joined on by `just cve-build`
│   └── platforms/
│       ├── raspberrypi.yaml
│       └── raspberrypi-zero-w.yaml
├── patches/meta-autonomos/        two patches kas applies to the upstream checkout
├── meta-wisekiosk/                <- THE LAYER: recipes, bbappends, classes
│   ├── conf/layer.conf
│   ├── classes/
│   └── recipes-*/
├── Justfile, justfiles/           build, OTA and device commands
├── tools/                         provisioning, bundle delivery, device debugging, doc gate,
│                                  CI guards, the identity scan, the build-commit writer and
│                                  reproducibility gate
├── docs/                          layers-and-kas.md, rauc-key-rotation.md, cve-and-sbom.md,
│                                  issue_investigation/
└── sources/                       gitignored; everything kas fetches lands here
```

Nothing outside `meta-wisekiosk/` is read by BitBake. Nothing inside it is read by anything else.
If you are new to Yocto, read **[docs/layers-and-kas.md](docs/layers-and-kas.md)** — it explains what
a layer is, what kas does with these files, and why the two patches cannot be bbappends.

Every change that was acted on is documented at the recipe carrying it; the per-issue investigations
behind those changes are indexed in **[docs/README.md](docs/README.md)**.

## Quick start

`kas-container` runs the build inside a container, so a working **Docker** is a
prerequisite. The flash and OTA paths additionally need `git`, `debugfs` (`e2fsprogs`) and `openssl`,
and the repository guards (`just guards` and the pre-commit hook) and `just currency` need **PyYAML**
to read the kas YAML — all of them refuse rather than skip when one is missing. On an
externally-managed (PEP 668) `python3`, install PyYAML with a virtualenv, the distro's
`python3-yaml`, or `python3 -m pip install --break-system-packages pyyaml`.

A **`.venv/` at the repository root is used automatically** where it exists, by the Justfile and by
`tools/ci-guards.sh` alike — neither `just` nor a git hook sources a shell startup file, so a venv
is never on `PATH` and a bare `python3` would take a host interpreter that may have no PyYAML. No
activation is needed, and nothing requires the venv: without one both fall back to `python3`, which
is what CI uses.

```sh
curl -L -o ~/bin/kas-container https://raw.githubusercontent.com/siemens/kas/5.4/kas-container
chmod +x ~/bin/kas-container

mkdir -p ~/.config/wisekiosk
cp secrets.yaml.tmpl ~/.config/wisekiosk/secrets.yaml   # fill in; lives OUTSIDE this public repo

just build          # kas fetches sources/, applies the patches, builds core-image-base
```

`just build` writes `meta-wisekiosk/conf/build-rev.inc` (the commit being built, see
[what commit an image was built from](docs/layers-and-kas.md#what-commit-an-image-was-built-from))
and then runs `kas-container build kiosk-zero-w.yaml`. Calling `kas-container` directly skips the
first half: on a fresh clone bitbake refuses to parse, and on a tree that has built before it builds
against the *previous* run's commit — which the gate then refuses at flash. The first run clones
every repo declared across the kas include chain — `includes/base.yaml`, `includes/rauc.yaml` and
`includes/platforms/raspberrypi.yaml` — into `sources/`: nine repositories, several GB and a long
while before any compiling starts.

A full build including WebKit takes **~4.5 h** on 8 cores / 11 GB. Anything that changes
`DISTRO_FEATURES`, `MACHINE_FEATURES` or webkit's `PACKAGECONFIG` **invalidates WebKit and costs that
again** — make those decisions before starting, not after. `config.txt`-only knobs (`GPU_MEM`, HDMI,
overscan, UART) are free to change.

### Flashing a card

```sh
just flash /dev/sdX                 # writes build/.../*.wic.bz2, re-reads the partition table
just provision-fresh-card /dev/sdX  # mounts partition 4, writes the site config, unmounts
```

`flash` refuses an image not baking the fleet signing keyring, or one mixing builds: a wrong keyring
is repairable only by another reflash. It also refuses, with no override, a build from a dirty or
unpushed tree, or one whose `/etc/buildinfo` does not name the current HEAD — see
[what commit an image was built from](docs/layers-and-kas.md#what-commit-an-image-was-built-from).
Provision before first boot — WiFi credentials are the way in.

`/data` is the **fourth** partition, and nothing on the card says so — the layout is boot, rootfs-a,
rootfs-b, data. `provision-fresh-card` derives it; provisioning by hand instead
(`tools/provision.sh card <mountpoint>`) means picking that partition yourself, and picking the
rootfs or the vfat boot partition leaves a unit that boots with no network and no way in but a USB
keyboard. `tools/provision.sh` refuses either — vfat cannot hold the 0600 the wifi credentials need,
and a non-root run leaves them owned by the wrong uid — but only after the card is already written.

### Updating a running device

```sh
just kiosk-ota      # bundle -> preflight -> verified scp -> rauc install
just kiosk-reboot
just kiosk-rollback # if the new slot comes up wrong
```

Every recipe that defaults to a device — `kiosk-ota`, `kiosk-send-direct`, `kiosk-install`, `kiosk-reboot`,
`kiosk-rollback`, `kiosk-preflight`, `kiosk-backup`, `provision-device` — takes its default from one
`kiosk-host` variable in the [`Justfile`](Justfile), so `export KIOSK_HOST=root@<addr>` retargets all
of them at once. Boards get swapped on this unit; `just find <cidr>` is how you learn the address of
the one now on the bench. An explicit `host` argument still wins over both.

`kiosk-preflight` refuses a delivery that cannot work — wrong slot size, stale bundle, no room on
`/data` — before the transfer. Every recipe that puts software on a board also refuses, with no
override, a build from a dirty or unpushed tree, so a build shipped from this host is always one
someone else can check out; tying a bundle to the rootfs inside it is #48 bundle-image-tie.
Delivery is a single md5-verified `scp` (`kiosk-send-direct`, ~45s for the ~114MB bundle): the
sustained-transfer wedge that once forced chunking was top-OPP memory corruption, fixed by the
clock cap in
[`kiosk-cpufreq`](meta-wisekiosk/recipes-core/kiosk-cpufreq/kiosk-cpufreq_1.0.bb), so the chunker was
removed (issue #29 remove chunked bundle delivery, verified 5/5 on the capped board).

## Configuration and secrets

Every device-specific value lives **outside this repository**, in `~/.config/wisekiosk/secrets.yaml`
(override the path with `$KIOSK_SECRETS`): WiFi SSID and PSK hash, kiosk URL, hostname, mirror host,
machine-id. `tools/provision.sh` reads that file and writes `/data/config` on the card or on a
reachable device; the device reads it at boot.

The tracked `secrets.yaml.tmpl` carries names with empty values only. `tools/ci-guards.sh` — run by
CI and by the pre-commit hook — rejects a `secrets.yaml` at the repository root (the only place kas
would pick one up), and fails if any of those value names becomes a build input again in the kas
config, the layer, `includes/` or `patches/`. Install the hook with `just install-hooks`.

**kas merges `local_conf_header` by block name and the top-level file wins**, so a block named the
same as one in `kiosk-zero-w.yaml` is discarded silently — no warning, no error, variables that never
reach bitbake. Keep the keys unique.

Losing `/data` is a re-provisioning, not a restore. `tools/provision.sh` writes the site config
again from `secrets.yaml`, and a machine-id not recorded there comes back as a new one; there is no
multi-GB image to put back.

## Recovery

`kiosk-recover` reverses `kiosk-hardware`'s boot trims for a debugging session: it unmasks the DNS
resolver, login/session and userdb units, deletes the masked udev rule symlinks, re-enables
Bluetooth, restores the `/etc/resolv.conf` symlink into `/data`, and reboots.

It is **not a boot un-bricker**: it runs on a slot that already gives a shell; a slot that does not is
an A/B rollback (`just kiosk-rollback`). It is idempotent, touches neither `/boot`, `sshd`, networkd
nor `wpa_supplicant`, has no timer/deadman/auto-revert, and leaves `zram.service` masked (issue #17:
that mask is a defect workaround, not a trim).

It lives on **`/data`** (placed at `/data/RECOVER.sh` by `tools/provision.sh`; source in the
[`kiosk-recover`](meta-wisekiosk/recipes-core/kiosk-recover/) recipe), so it survives an A/B flip and
a reflash. On the device:

```sh
/data/RECOVER.sh --dry-run   # list exactly what would change; touch nothing
/data/RECOVER.sh             # apply and reboot
```

Run `--dry-run` first to confirm targeting.

## Upstream fixes

Two changes to upstream cannot be expressed from a downstream layer and live as patches in
`patches/meta-autonomos/`, each header recording why it cannot be a bbappend and whether it is
suitable to submit upstream:

1. **`DISTRO_FEATURES:remove = " x11 wayland"` cannot be undone downstream.** bitbake applies
   `:remove` after every append, so no image or `local.conf` can put x11 back. Made conditional on
   `AUTONOMOS_FEATURES`, matching how the distro already gates `containers` and `kubernetes`.
2. **The wpa-supplicant bbappend baked WIFI_SSID and WIFI_PSK_HASH into the image.** One image per
   site, and the site's wireless credentials inside every update bundle.

Two more fixes belong upstream but did not need a patch, because a downstream layer can express them:

- **`wpa_supplicant.service` gives a coin-flip boot on slow WiFi firmware.** No ordering, no
  `Restart`, `Type=forking`: if it fires before the driver has created `wlan0` it exits and never
  retries, and that boot has no network at all. Addressed here with a drop-in
  (`After=sys-subsystem-net-devices-wlan0.device`, `Restart=on-failure`) plus an absolute
  `ExecStart` — systemd rejects the relative path upstream ships.
- **`git://` repo URLs no longer resolve.** `git.openembedded.org` and `git.yoctoproject.org` sit
  behind Cloudflare, which fronts HTTP/HTTPS only and refuses port 9418. `includes/base.yaml` uses
  `https://`.

## Status

**Working.** Boots, joins WiFi, renders the kiosk page on the real hardware. Verified on a Pi Zero W
(BCM2835, ARMv6, 512 MB).

| | |
|---|---|
| Engine | WebKitGTK 2.44.3, `ENABLE_JIT=OFF`, `MinSizeRel` — genuine ARMv6 (`Tag_CPU_arch: v6KZ`) |
| Browser | `surf` 2.1 + the kiosk patch (milestones, override-redirect, shims) |
| Display | bare Xorg, `xf86-video-fbdev`, no display manager, no window manager |
| Update | RAUC A/B over U-Boot — both slots visible, **rollback never exercised** |
| Memory | 87 MB used of 428; zram present and never touched |

### Known gaps

- **Rollback has never been exercised.** RAUC reports healthy slots; that is not the same as proving
  a bad update rolls back, or that a slow-but-healthy boot does *not* trigger one.
- **Issue #6 RAUC signing private key is committed in this public repository** — closed by rotation;
  history keeps the dev key and purging it undoes nothing. Its replacement, the WiseKiosk 2026 key,
  is uncommitted in gitignored `local/` — back it up, git cannot. [rotation](docs/rauc-key-rotation.md)
- **Root login is unauthenticated.** The image carries `debug-tweaks`, so root has an empty password.
  Deferred deliberately while a second device still depends on unauthenticated access; tracked as
  issue #7 debug-tweaks empty root password, which carries the detail.
- **Screen blanking over a long idle is unverified.** `-s 0 -dpms -nocursor` moved from lightdm into
  the kiosk unit; that failure only appears after ~20 minutes.
- **The image's packages are scanned for CVEs only when somebody asks.** The scan is a manual opt-in
  audit build on a build host, and nothing detects that the last one was months ago. Deciding which
  finding matters is manual too. [CVE and SBOM](docs/cve-and-sbom.md)
