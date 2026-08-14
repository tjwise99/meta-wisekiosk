> ## Attribution
>
> **This repository is a copy of [jsmith212/meta-autonomos](https://github.com/jsmith212/meta-autonomos), not a GitHub fork.**
> The original author's commit history is preserved in full, and the original is configured as the
> `upstream` remote:
>
> ```sh
> git remote add upstream https://github.com/jsmith212/meta-autonomos.git
> git fetch upstream && git log upstream/main..main   # everything added here
> ```
>
> The upstream repository carries **no license file**, so all rights in the original work remain with
> its author. Nothing here is offered under any license on their behalf.
>
> **Why the copy exists:** to add a Raspberry Pi Zero W (BCM2835, ARMv6) kiosk target, which upstream
> does not support — its Raspberry Pi targets are the Pi 5 and Pi Zero 2 W, both ARMv7/v8. Upstream's
> own identifiers (the `autonomos` distro, `AUTONOMOS_FEATURES`, the `meta-autonomos-*` layer
> directories) are deliberately left unrenamed so that `git merge upstream/main` stays clean.

## TODO: fixes to send upstream

Three 1. juss found while bringing up the Zero W target. **None is specific to this board** — each
affects anyone building the upstream layer today — so they are worth offering back rather than
keeping as local divergence. Commits are on `zero-w-port`.

**1. `git://` repo URLs no longer resolve — a fresh checkout cannot fetch at all.** Highest priority;
it breaks the project for every new user. `git.openembedded.org` and `git.yoctoproject.org` both sit
behind Cloudflare now, which fronts HTTP/HTTPS only and refuses port 9418, so `meta-openembedded`,
`meta-arm` and `meta-virtualization` all fail with `ECONNREFUSED`. Verified it is upstream and not a
local firewall: `git://git.kernel.org` succeeds from the same host. Fix is three URLs to `https://`
in `includes/base.yaml`. Invisible to anyone whose layers were fetched before the move.

**2. `wpa_supplicant.service` gives a coin-flip boot on slow WiFi firmware.** The unit has no
ordering and no `Restart`, and is `Type=forking`. If it fires before the driver has created `wlan0`
it exits immediately and never retries — that boot has no network, and on a board reachable only
over WiFi, no way in. Observed here: one boot in three came up with the browser running and the
network unreachable. Fix is a drop-in with `After=sys-subsystem-net-devices-wlan0.device` and
`Restart=on-failure`. **Also**: `ExecStart=wpa_supplicant …` is a relative path, which systemd
rejects outright — same end state.

**3. `DISTRO_FEATURES:remove = " x11 wayland"` in `autonomos.conf` cannot be undone downstream.**
bitbake applies `:remove` after every append, so no image or `local.conf` can put x11 back; the
symptom is a recipe failing its `REQUIRED_DISTRO_FEATURES` check for a feature you can point at in
your own config. Making the removal conditional on an `AUTONOMOS_FEATURES` flag keeps the default
behaviour identical while letting a graphical target opt in, and matches how the distro already gates
`virtualization`, `k3s` and `read-only-rootfs`.

**Also worth a message, not a patch:** this repository is public and carries no license file, so
rights remain with the author — see the attribution note above.

## Status: Raspberry Pi Zero W kiosk

**Working.** Boots, joins WiFi, renders the kiosk page correctly on the real hardware.
Verified 2026-08-11 on a Pi Zero W (BCM2835, ARMv6, 512MB).

| | |
|---|---|
| Engine | WebKitGTK 2.44.3, `ENABLE_JIT=OFF`, `MinSizeRel` — genuine ARMv6 (`Tag_CPU_arch: v6KZ`) |
| Browser | `surf` 2.1 + the kiosk patch (milestones, override-redirect, shims) |
| Display | bare Xorg, `xf86-video-fbdev`, no display manager, no window manager |
| Update | RAUC A/B over U-Boot — both slots visible, **rollback never exercised** |
| Complete display | **57.08 s** (n=3) vs **47.53 s** for the Raspbian config it replaces — **slower**, see below |
| Memory | 87 MB used of 428; zram present and never touched |

**It is ~9.5 s slower than the configuration it replaces, and the gap is boot, not the browser.**
`surf` does not exec until ~41 s, against ~34 s on Raspbian. **No systemd unit in this image has ever
been trimmed**, while the Raspbian setup went through five rounds of removals. That is the first
place to look, not WebKit.

### Why the Zero W target exists

The impetus is **WiseKiosk**: this wall-mounted Zero W behind one-way glass. The previous build was
stock Raspberry Pi OS (Raspbian), and it hit two walls. **Compatibility** — the newest browser that
runs on genuine ARMv6 is years behind, the package archives for this board are going dark, and the
side-by-side Chromium install needed to work the platform was a standing maintenance cost.
**Performance** — a stock distribution boots a load of services this kiosk never uses, all paid on
one 1 GHz ARM11 core before a frame is drawn. A hand-rolled Yocto image answers both: the browser is
compiled from source for `Tag_CPU_arch: v6KZ` instead of pulled from a dying archive, and the image
starts from nothing and adds only what the kiosk needs — the boot-trim work is where the performance
win is meant to land, and RAUC A/B gives this unreachable device the over-the-air rollback the
Raspbian card never had.

Full field notes are in [`docs/`](docs/).

### Build and flash

```sh
curl -L -o ~/bin/kas-container https://raw.githubusercontent.com/siemens/kas/5.4/kas-container
chmod +x ~/bin/kas-container

cp secrets.yaml.tmpl ~/.config/wisekiosk/secrets.yaml   # fill in; lives OUTSIDE this public repo
kas-container build kiosk-zero-w.yaml

# writes to build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/*.wic.bz2
bzcat <image>.wic.bz2 | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress

# the image carries NO site config; provision the flashed card from your out-of-tree secrets:
tools/provision.sh card
```

A full build including WebKit takes **~4.5 h** on 8 cores / 11 GB. Anything that changes
`DISTRO_FEATURES`, `MACHINE_FEATURES` or webkit's `PACKAGECONFIG` **invalidates WebKit and costs that
again** — make those decisions before starting, not after. `config.txt`-only knobs (`GPU_MEM`, HDMI,
overscan, UART) are free to change.

### Configuration

Every device-specific value lives **outside this repository**, in `~/.config/wisekiosk/secrets.yaml`
(override with `$KIOSK_SECRETS`): WiFi SSID and PSK hash, kiosk URL, hostname, mirror host, machine-id.
The image carries **no** site config; `tools/provision.sh` reads these and writes `/data/config` on
the flashed card, which the device reads at runtime. The tracked `secrets.yaml.tmpl` carries names
with empty values only, and CI rejects a `secrets.yaml` committed to the tree.

**kas merges `local_conf_header` by block name and the top-level file wins**, so a block named the
same as one in `kiosk-zero-w.yaml` is discarded silently — no warning, no error, variables that never
reach bitbake. Keep the keys unique.

### Known gaps

- **Rollback has never been exercised.** RAUC reports healthy slots; that is not the same as proving
  a bad update rolls back, or that a slow-but-healthy boot does *not* trigger one. A first boot takes
  ~57 s to render, which a naive health-check timeout would fail.
- **Signing keys are the development keys** shipped upstream. Production needs its own, and the
  decision is one-way: a device trusts only the keyring baked into its rootfs.
- **The soak sampler is not a recipe** — it is installed at runtime and will not survive a reflash.
  Its log lives on `/data` and does survive an A/B update.
- **Config is build-time.** `KIOSK_URL` is baked; the runtime `/data/kiosk.conf` override is designed
  but not implemented, so a URL change is currently a rebuild.
- **Screen blanking over a long idle is unverified.** `-s 0 -dpms -nocursor` moved from lightdm into
  the kiosk unit; that failure only appears after ~20 minutes.

# AutonomOS

AutonomOS is a robust Yocto-based Linux distribution designed for embedded systems with full OTA (Over-The-Air) update capability. It provides a minimal, secure environment with modular feature groups and A/B partition updates via RAUC.

## Key Features

- **A/B Partition Updates**: Robust OTA updates with automatic rollback via RAUC
- **Modular Architecture**: Platform-agnostic core with separate platform layers
- **Feature Groups**: Easy-to-enable feature sets (containers, Kubernetes, shell tools)
- **Delta Updates**: Efficient bandwidth usage with casync chunk-based updates
- **Persistent Storage**: Dedicated `/data` partition survives updates

## Hardware Support

AutonomOS supports multiple hardware platforms through dedicated platform layers:

| Platform              | Layer                      | Status      |
| --------------------- | -------------------------- | ----------- |
| Raspberry Pi 5        | meta-autonomos-raspberrypi | Supported   |
| Raspberry Pi Zero 2 W | meta-autonomos-raspberrypi | Supported   |
| BeagleBone Blue       | meta-autonomos-beaglebone  | Placeholder |

## Layer Structure

```
meta-autonomos/
├── meta-autonomos-core/           # Platform-agnostic core (priority 6)
│   ├── classes/
│   │   ├── autonomos-features.bbclass
│   │   └── autonomos-rauc.bbclass
│   ├── recipes-core/
│   │   ├── base-files/            # /data mount, shell config
│   │   ├── bundles/               # RAUC update bundle
│   │   ├── data-partition-resize/
│   │   ├── packagegroups/
│   │   └── rauc/                  # RAUC keyring config
│   ├── recipes-images/
│   ├── recipes-shells/            # zsh, oh-my-zsh, plugins
│   ├── recipes-containers/        # Docker, k3s
│   ├── recipes-connectivity/      # Network config
│   └── files/rauc-example-keys/   # Development signing keys
│
├── meta-autonomos-raspberrypi/    # Raspberry Pi support (priority 7)
│   ├── wic/                       # Partition layout
│   ├── recipes-core/
│   │   ├── rauc/                  # RPi-specific system.conf
│   │   └── base-files/            # RPi-specific fstab
│   └── recipes-kernel/            # Kernel config fragments
│
├── meta-autonomos-beaglebone/     # BeagleBone support (priority 7)
│   ├── wic/
│   └── recipes-core/rauc/
│
└── includes/                      # KAS configuration includes
    ├── base.yaml                  # Core repos and layers
    ├── rauc.yaml                  # RAUC repo
    └── platforms/
        ├── raspberrypi.yaml       # Common RPi config
        ├── raspberrypi-5.yaml     # RPi 5 machine
        ├── raspberrypi-zero-2w.yaml
        └── beaglebone-blue.yaml
```

## Getting Started

### Basic Configuration

Create a KAS configuration file for your project:

```yaml
header:
  version: 20
  includes:
    - repo: meta-autonomos
      file: includes/base.yaml
    - repo: meta-autonomos
      file: includes/platforms/raspberrypi-5.yaml
    - secrets.yaml # WiFi credentials, etc.

build_system: oe
distro: autonomos
target:
  - autonomos-devel
  - update-bundle

repos:
  meta-autonomos:
    url: "https://github.com/sailorbob134280/meta-autonomos"
    branch: "main"
    path: "sources/meta-autonomos"
    layers:
      meta-autonomos-core:

local_conf_header:
  features: |
    AUTONOMOS_FEATURES = "shellplus containers"
```

### Available Feature Groups

Enable features by adding them to `AUTONOMOS_FEATURES`:

| Feature            | Description                                                           |
| ------------------ | --------------------------------------------------------------------- |
| `shellplus`        | Enhanced shell (zsh, oh-my-zsh, syntax highlighting, autosuggestions) |
| `containers`       | Docker container runtime                                              |
| `kubernetes`       | k3s lightweight Kubernetes                                            |
| `grow-data`        | Automatically expand /data partition to fill disk on first boot       |
| `read-only-rootfs` | Immutable root filesystem with persistent /data (see below)           |

Example:

```yaml
local_conf_header:
  features: |
    AUTONOMOS_FEATURES = "shellplus containers grow-data read-only-rootfs"
```

### Shell Aliases and Help

AutonomOS includes built-in shell aliases available in all shells (bash, zsh). Run `halp` to see available commands:

```bash
halp    # Show quick reference of available commands
ll      # List files (ls -alh)
switch-part  # Switch RAUC slot and reboot
```

Each enabled feature adds its own aliases and help content. The `halp` output adapts based on which features are installed.

### Read-Only Root Filesystem

The `read-only-rootfs` feature makes the root filesystem immutable, improving reliability and security. All mutable state is stored on the persistent `/data` partition.

**What gets persisted:**

| Path               | Purpose                            |
| ------------------ | ---------------------------------- |
| `/etc/machine-id`  | Unique system ID, provisioned to `/data/etc` (pin gap tracked in #10) |
| `/var/log/journal` | System logs (bind from /data)      |
| `/var/lib/docker`  | Docker images/volumes (symlink)    |
| `/data/*`          | All application data               |

**Note:** When using `containers` with `read-only-rootfs`, Docker data is automatically persisted via symlink to `/data/docker`. Pulled images and created volumes survive reboots.

**Configurable journal settings:**

| Variable                         | Default   | Description                |
| -------------------------------- | --------- | -------------------------- |
| `AUTONOMOS_JOURNAL_MAX_SIZE`     | `64M`     | Total journal size cap     |
| `AUTONOMOS_JOURNAL_MAX_FILE_SIZE`| `8M`      | Max size per journal file  |
| `AUTONOMOS_JOURNAL_MAX_RETENTION`| `1month`  | Max age before rotation    |

Example configuration:

```yaml
local_conf_header:
  read-only: |
    AUTONOMOS_FEATURES = "read-only-rootfs"
    AUTONOMOS_JOURNAL_MAX_SIZE = "128M"
    AUTONOMOS_JOURNAL_MAX_RETENTION = "2weeks"
```

**Development helpers:**

```bash
halp           # Show available commands and enabled features
write-enable   # Temporarily make rootfs writable (read-only-rootfs only)
write-disable  # Re-enable read-only protection (read-only-rootfs only)
```

The `halp` command displays a quick reference of available aliases based on which features are enabled. Each feature contributes its own help snippet.

**Notes:**
- SSH host keys are baked into the image at build time
- DHCP works normally (systemd-networkd stores leases in tmpfs)
- Package manager (opkg) will not work on read-only rootfs (use `write-enable` temporarily)

## OTA Updates with RAUC

### Partition Layout

AutonomOS uses a 4-partition A/B layout:

| Partition     | Mount | Size      | Purpose                   |
| ------------- | ----- | --------- | ------------------------- |
| p1 (boot)     | /boot | 200MB     | Kernel, DTB, boot files   |
| p2 (rootfs-a) | /     | 2GB       | Primary rootfs (slot A)   |
| p3 (rootfs-b) | -     | 2GB       | Secondary rootfs (slot B) |
| p4 (data)     | /data | Remaining | Persistent storage        |

### Building Update Bundles

Add `update-bundle` to your targets:

```yaml
target:
  - autonomos-devel
  - update-bundle
```

The bundle will be at: `tmp-<machine>/deploy/images/<machine>/update-bundle-<machine>.raucb`

### Configuring Signing Keys

For production, configure your own signing keys:

```yaml
local_conf_header:
  rauc-keys: |
    AUTONOMOS_RAUC_KEY_DIR = "/path/to/keys"
    AUTONOMOS_RAUC_KEYRING_FILE = "production.cert.pem"
    AUTONOMOS_RAUC_KEY_FILE = "production.key.pem"
    AUTONOMOS_RAUC_CERT_FILE = "production.cert.pem"
```

**Key Variables:**

| Variable                      | Default                | Description                  |
| ----------------------------- | ---------------------- | ---------------------------- |
| `AUTONOMOS_RAUC_KEY_DIR`      | (unset)                | Directory containing keys    |
| `AUTONOMOS_RAUC_KEYRING_FILE` | `development.cert.pem` | Certificate for verification |
| `AUTONOMOS_RAUC_KEY_FILE`     | `development.key.pem`  | Private key for signing      |
| `AUTONOMOS_RAUC_CERT_FILE`    | `development.cert.pem` | Certificate for signing      |

If `AUTONOMOS_RAUC_KEY_DIR` is not set, development keys from the core layer are used.

### Installing Updates

On the target device:

```bash
# Check current slot status
rauc status

# Install an update
rauc install /path/to/update-bundle.raucb

# The system will boot into the updated slot on next reboot
reboot
```

## Secrets Configuration

Site values live **outside this public repository**, at `~/.config/wisekiosk/secrets.yaml` (override
with `$KIOSK_SECRETS`). A `secrets.yaml` committed to the tree is rejected by CI. Copy the tracked
`secrets.yaml.tmpl` there and fill it in — `tools/provision.sh` reads it and writes `/data/config` on
the card.

## Adding New Platforms

1. Create a new platform layer: `meta-autonomos-<platform>/`
2. Add `conf/layer.conf` with appropriate dependencies
3. Create platform-specific recipes:
   - `wic/<platform>.wks.in` - Partition layout
   - `recipes-core/rauc/files/<machine>/system.conf` - RAUC slot config
   - `recipes-core/base-files/files/fstab` - Mount points
4. Create KAS include in `includes/platforms/<platform>.yaml`

## License

See individual recipe files for license information.
