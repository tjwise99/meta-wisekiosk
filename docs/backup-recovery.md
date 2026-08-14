# Backup and recovery — the Yocto kiosk

**Status 2026-08-13: the RAUC A/B slots are the recovery mechanism for a bad update. There is no
rehearsed backup of `/data` for this device** — at the most recent reflash the owner explicitly
declined one, and the 88 MB journal history that predated it is gone (`STATUS.md` (kiosk-reference)
§"The device was reflashed and provisioned"). This document describes the mechanism that exists, not
one that has been exercised end to end.

The Raspbian SL16G card this document used to describe (full-card `dd` imaging, the ARM11 SSH-pipe
throughput measurements) is shelved. That history now lives in `raspbian-card.md` (kiosk-reference).

## What is durable, and what needs backing up

The rootfs needs no backup: it is reproducible from the build tree, and either RAUC slot can be
reflashed from a freshly built bundle. What the build cannot regenerate is **`/data`**, the fourth
partition that survives both a reflash of either rootfs slot and every OTA update
([`provisioning.md`](provisioning.md) §"`machine-id` is the one that cannot come from `/data` at boot").
It carries:

| Path | What |
|---|---|
| `/data/config/wpa_supplicant.conf` | `WIFI_SSID` + `WIFI_PSK_HASH` |
| `/data/config/kiosk.conf` | `KIOSK_URL` |
| `/data/config/resolv.conf` | `KIOSK_NAMESERVER` |
| `/data/config/hostname` | `KIOSK_HOSTNAME` |
| `/data/etc/machine-id` | this device's identity, carried into each new slot by a RAUC hook |
| `/data/kiosk-netcheck.conf` | no-LAN withholding overrides (`TARGET`/`DEADLINE`/`IFACE`) |
| `/data/RECOVER.sh` | the runtime-recovery script itself — see below |
| journald's persistent storage, if `/data` is where it is retained | boot history |

Losing `/data` without a copy means re-provisioning from scratch — rebuilding
`wpa_supplicant.conf`/`kiosk.conf`/`hostname` by hand and accepting a new `machine-id` — not
restoring a multi-gigabyte card image. The whole set is a few kilobytes of config.

## Pulling a backup

`tools/kiosk-backup.sh` (kiosk-reference) is a pull-only rsync job: invoked from a host that can
reach the kiosk, installs nothing on the device, and only ever reads it. **As currently committed it
still targets the retired Raspbian paths** — `SRC="/boot /etc /home/pi /opt/chromium-72
/usr/local/sbin /var/spool/cron"` against `pi@<KIOSK_IP>`. None of `/home/pi`, `/opt/chromium-72` or
the `pi` user exist on this device. [NEEDS CONFIRMING: whether `kiosk-backup.sh` has been repointed
at `/data` and `root@<KIOSK_IP>` since the Yocto device went live — nothing in this tree indicates it
has.]

Until it is adapted, the mechanism is a plain pull, following the same `root@<KIOSK_IP>` pattern
already used elsewhere to pull artifacts off `/data` ([`remote-debugging.md`](remote-debugging.md)):

```bash
ssh -i ~/.ssh/id_ed25519 root@<KIOSK_IP> 'tar -C / -czf - data' > kiosk-data-$(date +%F).tar.gz
```

`/data` is small — config plus whatever journal is retained — so this is seconds, not the hours the
old card image took.

## Recovery: the RAUC slots

For a bad update, the primary recovery is the other slot:

```bash
just kiosk-rollback   # marks the booted slot bad; host defaults to root@<KIOSK_IP>
just kiosk-reboot     # switch to it
```

Both slots read the **same** `/data`, so this recovers a bad rootfs, not bad `/data` content or a
provisioning error — those are identical on both slots
([`provisioning.md`](provisioning.md) §"If you skip provisioning").

## `[Yocto]` Recovering a boot that succeeds with no network

Everything above recovers a **dead card**. This section covers the failure the A/B slots do not:
a boot that completes normally and comes up **without a network**. Nothing automatic catches it —
the watchdog does not fire because nothing is wedged, and `rauc-mark-good` still runs at ~33 s, so
the boot counters never decrement and U-Boot never falls back. It is the one class where a config
change on a wall-mounted unit costs a physical trip.

Two mechanisms cover it, in order of cost:

**A USB keyboard on tty1.** `kiosk-zero-w.yaml` keeps `keyboard` and `usbhost` in
`MACHINE_FEATURES` for exactly this, and the panel is already the console (`console=tty1`). This is
the only way in when the network is gone.

**`/data/RECOVER.sh`**, which undoes every runtime change and reboots:

```sh
sh /data/RECOVER.sh
```

It unmasks the units masked for boot trimming, deletes the udev rule **symlinks**, removes the
Bluetooth modprobe drop-in, restores the `resolv.conf` symlink, and reboots. It lives on `/data`,
which survives both a reflash of a rootfs slot and an A/B update. Safe to run twice. It does not
touch `/boot`, `sshd`, `systemd-networkd` or `wpa_supplicant`.

> **Proven by running it, not by reading it — and that is what found its defect.** The first version
> deleted `/etc/udev/rules.d/*.rules` with a glob, which took `99-fuse.rules`, `can.rules` and
> `touchscreen.rules` with it: three real files the image ships, alongside the symlinks it meant to
> remove. They were restored byte-for-byte from the assembled rootfs and the script narrowed to
> `-type l`. An inspection pass called the original correct.

**Recovery machinery is itself an untested change.** This script deliberately does nothing
automatically — no timer, no deadman, no auto-revert. On a device whose revert is already a
one-liner, a harness that acts on its own adds a failure mode and removes none.

## `[Yocto]` The no-LAN boot recovers itself — `kiosk-netcheck`

The section above ends by arguing against automatic recovery machinery, and that argument still
holds for everything it covers. This is the one case it does not: **a revert you cannot reach is not
a one-liner.** `RECOVER.sh` assumes a person at a keyboard, which is exactly what an unreachable
board denies. So the automatic mechanism is justified here by the same reasoning that rejects it
elsewhere, not in spite of it.

`kiosk-netcheck.service` is ordered `Before=boot-complete.target`, which `rauc-mark-good.service`
already `Requires`. That hook is upstream systemd design, so nothing about `rauc-mark-good` is
patched or overridden. If the check exits non-zero, `boot-complete.target` is never reached,
`mark-good` never runs, U-Boot's boot counter is **not** reset, and three such boots drop the slot
from `BOOT_ORDER` — turning "boots fine, unreachable" into the A/B fallback that already works.

The check waits up to 120 s for an IPv4 default gateway on `wlan0` and one successful ping to it.
The gateway, not the internet: this must work on an isolated LAN.

**It only ever withholds.** It never marks a slot bad. Withholding is recoverable from the other
slot; marking bad is not. And it suppresses itself entirely — marks good despite having no LAN —
when the partner slot's boot status is not `good`, because a kiosk nobody can reach still beats a
card with no bootable slot, which is the one failure that costs a physical trip.

Overrides live in `/data/kiosk-netcheck.conf` (`TARGET`, `DEADLINE`, `IFACE`), which survives both an
OTA and a slot reflash. Setting `TARGET` to an unroutable address is how the failure path is tested
without taking the real network down — the lifeline stays up while the *check* fails.

### Proven by making it fire, in all three directions

Runtime install on slot A, 2026-08-13. Script-level first, then across real reboots:

| Case | Expected | Observed |
|---|---|---|
| Healthy LAN | pass | exit 0 in 93 ms; gateway answered at 28.4 s of boot |
| No LAN, partner slot `good` | withhold | exit 1; `boot-complete` **inactive**, `rauc-mark-good` refused with "Dependency failed", **`BOOT_A_LEFT` 3 → 2** |
| No LAN, partner slot **not** `good` | mark good anyway | exit 0, "WITHHOLDING SUPPRESSED" — exercised against a stubbed `rauc status` rather than by marking a live slot bad |
| Restore, reboot | counter recovers | `BOOT_A_LEFT` back to **3**, all units active, zero failed |

The kiosk stayed `active` with its full browser tree through the failing boot: the blast radius is
exactly one unit, because `rauc-mark-good` is the only thing on this image that requires
`boot-complete.target` and `kiosk.service` does not.

**Cost: `rauc-mark-good` moved 25.9 s → 30.1 s**, because it now waits for the LAN. That slightly
widens a hazard already recorded in `STATUS.md` (kiosk-reference): a watchdog fire landing *before*
`mark-good` runs, three times running, would exhaust the boot counter on its own.

> **The third row is the weakest evidence here, and deliberately so.** The escape hatch was proven
> against a stubbed `rauc status --output-format=shell`, not by marking slot B bad on the live
> board. That substitutes rauc's *output* while exercising the real script, real parser and real
> branch — but it does not prove RAUC reports a genuinely bad slot in the shape the parser expects.
> The second row covers that half: it parsed real output and correctly found slot B `good`. Together
> they cover the path; neither covers it alone.

## The Raspbian SL16G card

Full-card imaging, restore, and the ARM11-core throughput measurements behind it describe the
shelved card, not this device: see `raspbian-card.md` (kiosk-reference).
