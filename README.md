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
| `/etc/machine-id`  | Unique system ID (bind from /data) |
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

Create a `secrets.yaml` file (do not commit to version control):

```yaml
local_conf_header:
  wifi: |
    WPA_SSID = "YourNetwork"
    WPA_PSK = "YourPassword"
```

Use the provided `secrets.yaml.tmpl` as a template.

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
