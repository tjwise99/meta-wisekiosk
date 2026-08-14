# meta-wisekiosk

A wall-mounted Raspberry Pi Zero W kiosk: `surf` on WebKitGTK against a bare Xorg, no desktop, no
window manager, no display manager. The unit shows one page and is reached only over WiFi, so
everything here is shaped by the fact that a broken image costs a physical trip to the wall.

Updates are RAUC A/B over U-Boot, delivered over the LAN. Site configuration — SSID, PSK hash, URL,
hostname, machine-id — is **never** in the image; it is written to the device's `/data` partition by
provisioning and read at runtime.

> ## Attribution
>
> This project builds on [jsmith212/meta-autonomos](https://github.com/jsmith212/meta-autonomos),
> which supplies the `autonomos` distro, the RAUC bundle recipe and the Raspberry Pi platform layer.
> kas fetches it at a pinned commit into `sources/`; this repository contains none of it.
>
> The upstream repository carries **no license file**, so all rights in that work remain with its
> author. Nothing here is offered under any license on their behalf, and nothing here redistributes
> it — `sources/` is gitignored and every user fetches upstream directly from upstream.
>
> Upstream's identifiers — the `autonomos` distro, `AUTONOMOS_FEATURES`, the `meta-autonomos-*` layer
> names — are deliberately left unrenamed. Two concrete reasons: the RAUC *compatible* string derives
> from the distro, and a deployed board refuses a bundle whose compatible does not match its own, so
> renaming the distro is a one-way change that strands every unit in the field. And the two patches
> in `patches/meta-autonomos/` have to apply to upstream's files as upstream writes them.

## Layout: scaffolding vs. layer

The repository is a project, not a layer. Exactly one directory in it is a BitBake layer.

```
meta-wisekiosk/                    <- the repository (project scaffolding)
├── kiosk-zero-w.yaml              kas config: the one entry point
├── includes/                      repo pins and machine config, pulled in by the above
│   ├── base.yaml                  every repo + commit, incl. meta-autonomos and its patches
│   ├── rauc.yaml
│   └── platforms/
│       ├── raspberrypi.yaml
│       └── raspberrypi-zero-w.yaml
├── patches/meta-autonomos/        two patches kas applies to the upstream checkout
├── meta-wisekiosk/                <- THE LAYER: recipes, bbappends, classes
│   ├── conf/layer.conf
│   ├── classes/
│   └── recipes-*/
├── Justfile, justfiles/           build, OTA and device commands
├── tools/                         provisioning, chunked bundle delivery, CI guards
├── docs/                          layers-and-kas.md
└── sources/                       gitignored; everything kas fetches lands here
```

Nothing outside `meta-wisekiosk/` is read by BitBake. Nothing inside it is read by anything else.
If you are new to Yocto, read **[docs/layers-and-kas.md](docs/layers-and-kas.md)** — it explains what
a layer is, what kas does with these files, and why the two patches cannot be bbappends.

## Quick start

```sh
curl -L -o ~/bin/kas-container https://raw.githubusercontent.com/siemens/kas/5.4/kas-container
chmod +x ~/bin/kas-container

mkdir -p ~/.config/wisekiosk
cp secrets.yaml.tmpl ~/.config/wisekiosk/secrets.yaml   # fill in; lives OUTSIDE this public repo

just build          # kas fetches sources/, applies the patches, builds core-image-base
```

`just build` is `kas-container build kiosk-zero-w.yaml`. The first run clones every repo in
`includes/base.yaml` into `sources/` — several GB and a long while before any compiling starts.

A full build including WebKit takes **~4.5 h** on 8 cores / 11 GB. Anything that changes
`DISTRO_FEATURES`, `MACHINE_FEATURES` or webkit's `PACKAGECONFIG` **invalidates WebKit and costs that
again** — make those decisions before starting, not after. `config.txt`-only knobs (`GPU_MEM`, HDMI,
overscan, UART) are free to change.

### Flashing a card

```sh
# build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/*.wic.bz2
bzcat <image>.wic.bz2 | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

# the image carries NO site config; provision the card before first boot
tools/provision.sh card /mnt/data
```

The card must be provisioned before it boots. WiFi credentials are what let you reach the device, so
the first write cannot come over the network.

### Updating a running device

```sh
just kiosk-ota      # bundle -> preflight -> chunked send -> rauc install
just kiosk-reboot
just kiosk-rollback # if the new slot comes up wrong
```

`kiosk-preflight` refuses a delivery that cannot work — wrong slot size, stale bundle, no room on
`/data` — before spending twenty-five minutes transferring it. The transfer is chunked because this
board wedges on sustained SDIO traffic in either direction; a plain `scp` of the bundle hangs it.

## Configuration and secrets

Every device-specific value lives **outside this repository**, in `~/.config/wisekiosk/secrets.yaml`
(override the path with `$KIOSK_SECRETS`): WiFi SSID and PSK hash, kiosk URL, hostname, mirror host,
machine-id. `tools/provision.sh` reads that file and writes `/data/config` on the card or on a
reachable device; the device reads it at boot.

The tracked `secrets.yaml.tmpl` carries names with empty values only. `tools/ci-guards.sh` — run by
CI and by the pre-commit hook — rejects a `secrets.yaml` anywhere in the tree, and fails if any of
those value names becomes a build input again in the kas config, the layer, `includes/` or
`patches/`. Install the hook with `just install-hooks`.

**kas merges `local_conf_header` by block name and the top-level file wins**, so a block named the
same as one in `kiosk-zero-w.yaml` is discarded silently — no warning, no error, variables that never
reach bitbake. Keep the keys unique.

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
- **Signing keys are upstream's development keys.** Production needs its own, and the decision is
  one-way: a device trusts only the keyring baked into its rootfs.
- **Screen blanking over a long idle is unverified.** `-s 0 -dpms -nocursor` moved from lightdm into
  the kiosk unit; that failure only appears after ~20 minutes.
