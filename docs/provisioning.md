# Provisioning a kiosk — what has to happen at flash time

**The image contains no site configuration.** No SSID, no PSK hash, no backend URL, no hostname, no
nameserver, no `machine-id`. A card flashed from the `.wic` and booted without provisioning comes up
with **no network**, and the only way in is a USB keyboard on `tty1`.

That is deliberate. While any of those values live in the rootfs it is one image per site, and every
update bundle carries that site's wireless credentials — which is what blocks a shared fleet
artifact. See **#8 config provisioning** on `meta-wisekiosk`.

## The order is forced, and it is the whole reason this page exists

Wireless credentials are what let you *reach* the device, and they live on the device. So the first
write **cannot** come over the network. It happens on the mounted `/data` partition, before first
boot. There is no way around this and no clever ordering that avoids it.

## You edit one file and run one command

```sh
# once, per site -- outside the repo, never in it
$EDITOR ~/.config/wisekiosk/secrets.yaml     # WIFI_SSID, WIFI_PSK_HASH, KIOSK_URL,
                                             # KIOSK_HOSTNAME, KIOSK_NAMESERVER,
                                             # KIOSK_MACHINE_ID (optional -- generated if blank)

# per unit
sudo just provision-card /mnt/kiosk-data     # a freshly flashed card
just provision-device root@<kiosk>           # or a unit you can already reach
```

That is the whole interface. Everything below is what the tool writes and how to debug it when a
unit comes up wrong — you do not author these by hand.

## What it writes, and who reads it

Five files, because each consumer only accepts its own format at its own path: `wpa_supplicant`
reads a supplicant config, glibc reads `resolv.conf`, systemd reads `machine-id`. That is imposed by
the consumers, not a choice about the interface.

`/data` is the **fourth** partition (`mmcblk0p4` on the device; `/dev/sdX4` on the card). It survives
both an A/B update and a slot reflash, so provisioning is once per unit, not once per image.

| path | generated from | read by | mode |
|---|---|---|---|
| `/data/config/wpa_supplicant.conf` | `WIFI_SSID` + `WIFI_PSK_HASH` | `wpa_supplicant -c` **directly** | **0600** root |
| `/data/config/kiosk.conf` | `KIOSK_URL` | `kiosk.service` `EnvironmentFile=` | 0644 root |
| `/data/config/resolv.conf` | `KIOSK_NAMESERVER` | glibc, via an `/etc/resolv.conf` symlink | 0644 root |
| `/data/config/hostname` | `KIOSK_HOSTNAME` | `kiosk-provision.service` | 0644 root |
| `/data/etc/machine-id` | `KIOSK_MACHINE_ID` | the RAUC hook, into each new slot | 0644 root |

Nothing is copied into `/etc`: `wpa_supplicant` and `kiosk.service` read `/data` in place, and
`/etc/resolv.conf` is a symlink. One location, no sync problem. `kiosk.service`'s `EnvironmentFile`
is mandatory with no leading `-`, so an unprovisioned unit fails loudly rather than launching a
browser at an empty URL.

## Doing it

```sh
# 1. flash the image to the card
sudo dd if=…/core-image-base-raspberrypi0-wifi.rootfs.wic of=/dev/sdX bs=4M conv=fsync status=progress

# 2. mount the fourth partition -- /data, NOT rootfs
sudo mkdir -p /mnt/kiosk-data && sudo mount /dev/sdX4 /mnt/kiosk-data

# 3. write the config from the secrets file
sudo just provision-card /mnt/kiosk-data

# 4. verify, then unmount
sudo umount /mnt/kiosk-data
```

`just provision-card` reads **`$KIOSK_SECRETS`, defaulting to `~/.config/wisekiosk/secrets.yaml`** —
deliberately *outside* the repository. `meta-wisekiosk` is public, and none of these values is
credential-shaped, so no scanner would stop them. Keeping them out of the tree also means the build
**cannot** read them: a leftover `${WIFI_SSID}` expands to empty and breaks loudly instead of
silently shipping a real credential. `tools/ci-guards.sh` enforces all three halves of that.

If `KIOSK_MACHINE_ID` is unset the tool generates one. **It must be unique per physical unit** —
systemd derives the networkd DUID from it, so two units sharing one collide on the same LAN, and
hawkBit would key them as the same device.

### Verify before you boot, not after

```sh
ls -l /mnt/kiosk-data/config /mnt/kiosk-data/etc/machine-id   # 0600 on wpa_supplicant.conf, root-owned
grep -c '^[[:space:]]*ssid=' /mnt/kiosk-data/config/wpa_supplicant.conf   # must be 1
wc -c /mnt/kiosk-data/etc/machine-id                          # 33 = 32 hex + newline
```

Checking after boot is much more expensive: a unit that comes up unprovisioned is unreachable, and
recovering it means physical access.

## Re-provisioning a unit you can already reach

```sh
just provision-device root@<kiosk>
```

Same files, delivered over SSH as a single small `tar` stream — nothing like the sustained transfer
that wedges this board. Takes effect on the next boot.

> **`tar` preserves the sending host's uid/gid.** The first version of this landed the wifi config
> owned by uid 1000 on the device. It is now forced to `root:root`; if you write these files by hand,
> `chown 0:0` them.

## `machine-id` is the one that cannot come from `/data` at boot

journald reads `/etc/machine-id` at **~8.2 s**, long before `/data` is mounted, and caches it. A bind
mount or a boot-time copy is too late — the journal directory for that boot is already chosen. The
value therefore has to be **in the rootfs of each slot**.

Two mechanisms cover that, and provisioning only handles the first:

- **A fresh card** — `provision-card` writes `/data/etc/machine-id`, and the first boot's
  `kiosk-provision` seeds from whatever the rootfs has.
- **Every OTA afterwards** — a **RAUC `slot-post-install` hook** copies `/data/etc/machine-id` into
  the freshly written slot before it ever boots. It is self-seeding, so a unit already in the field
  needs no flash-time step.

Getting this wrong is not cosmetic: a per-slot generated `machine-id` makes journald orphan a
namespace on every update, and `SystemMaxUse` is enforced **per** `machine-id`, so it never bounds
the total. Four namespaces reached 136.6 MB on a 479 MB `/data` that also stages the ~125 MB bundle.

## If you skip provisioning

The unit boots, `wpa_supplicant` has no config, and there is no network. `kiosk-provision` says so in
the journal — it logs `MISSING` per absent file and `UNPROVISIONED` — but nobody can read that
remotely, which is the point.

> **`kiosk-netcheck` does not rescue this.** It withholds `rauc-mark-good` when a boot comes up with
> no LAN, so the boot counter drains and U-Boot falls back to the other slot — but the fallback slot
> reads the **same** `/data`. A provisioning error is identical on both slots, so the counter simply
> drains to zero. That is an argument for verifying config at flash time, not a hole in the gate.

Recovery is the same as any no-network boot: a USB keyboard on `tty1`, which the image keeps
`keyboard` and `usbhost` in `MACHINE_FEATURES` for, with the panel as the console. See
[`backup-recovery.md`](backup-recovery.md).

## `[Raspbian, historical]` The pre-Yocto provisioning notes

Everything below describes the **SL16G Raspbian card**, which is no longer in the device. Kept for
the portable/device-specific split, which still informs the design above.

| Thing | Why it existed |
|---|---|
| `mmClient.sh` | Retry loop + `--remote-debugging-port`, the only real error channel |
| `kiosk-rngd` + unit | Chromium's entropy dependency, **not** a headless-device one — surf does not need it |
| Boot service trims | Chosen against `critical-chain`, not `blame` |
| Autologin → session → kiosk chain | lightdm autologin, `-s 0 -dpms -nocursor` |

Device-specific and never committed in the clear: `wpa_supplicant.conf`, `authorized_keys`,
`/boot/config.txt` (panel-specific HDMI mode), hostname, static addressing.

Not portable at all: Chromium 72 in `/opt`, the `chrome72` build target, Raspbian Stretch itself.
