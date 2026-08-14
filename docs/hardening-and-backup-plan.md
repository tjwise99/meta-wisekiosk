# Hardening and nightly incremental backup — proposed

> **Nothing in this document is installed.** It is a proposal, written 2026-08-06, and it owns
> *proposed* work only. Current device state is `STATUS.md` (kiosk-reference); backup facts already
> established are [`backup-recovery.md`](backup-recovery.md). Where this document states a
> measurement, the sample count is given; where it states a judgement, it says so.

Two separate jobs that are easy to confuse:

| Job | Answers | Cadence | Artifact |
|---|---|---|---|
| **Card image** (`dd`) | "the card died" | rare, manual | bootable, bit-exact |
| **Incremental backup** (this) | "I broke a config three days ago" | nightly | file-level, **not bootable** |

The image does not replace the nightly backup and the nightly backup does not replace the image.
Neither is a substitute for the other, and a nightly `dd` is refused below.

---

# Part 1 — Nightly incremental backup

## Shape: pull from the mirror host, never push from the Pi

The scheduler, the logic, the retention rotation and the failure handling all live on
`192.168.1.3`. The Pi runs only `rsync --sender`, invoked over the same SSH the operator already
depends on.

This is the whole design decision, and the reason is recoverability, not elegance: **the backup
installs no unit, no timer and no crontab entry on the kiosk.** A bug in it therefore cannot wedge
the kiosk, cannot re-fire itself, and cannot interact with the deadman harness. Every failure mode
lands on a host that can be reached with a keyboard.

Corollary: the Pi is only ever **read**. Reads do not wear NAND
([`backup-recovery.md`](backup-recovery.md) §"Taking the image"), so nightly operation costs the
card nothing.

## Measured constraints this design is built around

| Fact | Value | Source |
|---|---|---|
| SSH pipe ceiling | **1.45 MB/s**, ARM11 core saturated | [`backup-recovery.md`](backup-recovery.md) |
| Compressing on the Pi | **slower than the wire** (0.89 MB/s on real data) | [`backup-recovery.md`](backup-recovery.md) |
| Full-root `rsync` | ~6.3 GB, **~1h18m** | [`backup-recovery.md`](backup-recovery.md) |
| Host free space | 938 G | `df`, 2026-08-06 |

Two consequences, both non-obvious:

- **Do not pass `-z`.** rsync's compression runs on the sender — the saturated ARM11 core. The
  project already measured that gzip on this device is slower than the pipe it feeds. `-z` would
  make the backup slower *and* steal cycles from the browser.
- **A nightly full-root rsync is refused.** 1h18m of saturated core every night, against a kiosk
  whose entire job is rendering. The fix is not scheduling it more cleverly; it is copying less.

## What to copy — and the measurement that decided it

Measured on the device 2026-08-06, one pass:

| Path | Size | Files | In backup? |
|---|---|---|---|
| `/home/pi/.cache` | 767 M | **189,654** | **no** — browser cache, regenerates |
| `/home/pi/.npm` | 64 M | 1,934 | **no** — rebuildable from registry |
| `/home/pi` (rest) | 61 M | — | yes |
| `/etc` | 5.7 M | 653 | yes |
| `/opt/chromium-72` | 272 M | **49** | yes — static after first sync |
| `/usr/local/sbin` | 28 K | 6 | yes |
| `/opt/Wolfram`, `/opt/sonic-pi`, `/opt/minecraft-pi` | 906 M | — | **no** — stock Raspbian, in the card image |

**`/home/pi/.cache` alone is 189,654 of the 193,332 files** under the candidate set — 98% of the
walk. Excluding it and `.npm` takes the nightly job from 193,332 files to **1,793 files / ~339 MB**.

That is the single fact that makes this cheap. The nightly cost is the *stat walk*, not the bytes,
and 99% of the walk was cache.

**Both runs have now been executed, so these are measurements, not estimates** (2026-08-06):

| | Result |
|---|---|
| Enumerated set | 3,668 entries — 2,004 regular files, 599 dirs, 1,065 links, **371 MB** |
| First run | ~25 min wall clock; snapshot 362 M; Pi load peaked **5.31** on one core |
| **Incremental (2nd) run** | **8.2 s**, exit 0 |
| Store after two snapshots | **365 M total** — hardlinking confirmed working |
| Verification | all 5 canaries present; `mmClient.sh` md5 `16baf045…` matches the live device |

**The first run is not cheap and the plan should not pretend otherwise:** load 5.31 on a single core
is heavily oversubscribed, and the kiosk is degraded for the duration. That is an argument for doing
the first sync deliberately (it is already done) rather than letting it land as the first scheduled
night, and for the 02:30 schedule. The *nightly* case is the 8.2 s one.

Also captured each run, because they cost nothing and are what a rebuild actually needs:
`dpkg --get-selections` (1,320 packages), `systemctl list-unit-files --state=enabled`, the partition
table, and `ip addr` / `iwconfig`.

## Why not incrementally update the disk image instead

The obvious objection: a file-level backup is not bootable, so why not keep the *image* fresh
incrementally and get both? It is the right question, and the answer is a measured cost, not a
principle.

**Nothing on this device can say which blocks changed without reading them.** ext4 on a plain
partition exposes no change journal to the block layer, so every block-level tool — `bdsync`,
`blocksync`, `rsync --copy-devices` — must read *and checksum every byte* each run. The tools that
avoid this (`btrfs send`, `zfs send`, LVM thin snapshots) all need a different filesystem or
partition layout, which is the hands-on class and refused.

`rsync --copy-devices` **is** available on the Pi's rsync 3.1.2 — Debian carries that patch — so this
was checked, not assumed off the table.

Measured on the device 2026-08-06, 256 MiB per sample, n=1 each:

| Operation on the Pi | Throughput | Extrapolated to the 15.9 GB card |
|---|---|---|
| Raw read, `iflag=direct`, no hashing | 22.1 MB/s | ~12 min |
| **Read + `md5sum`** | **10.9 MB/s** | **~24 min** |
| Read + `sha1sum` | 8.0 MB/s | ~33 min |
| **File-level incremental (measured, not extrapolated)** | — | **8.2 s** |

Hashing halves the raw read rate: the ARM11 core is the constraint, exactly as it is for the SSH
pipe. So a nightly block-delta costs **~24 minutes of fully saturated core before one byte moves**,
against 8.2 seconds for the file-level pass. That is the trade, and it is why nightly is file-level.

### Where a block-delta *does* earn its place

Not nightly — **periodically**, to refresh the bootable image. ~24 min beats re-running the full
`dd` (~3h) by roughly 7×, for the same bit-exact artifact. This is a genuine improvement over
"re-image from scratch occasionally" and is **proposed, not tested**:

```bash
# UNTESTED. Refreshes an UNCOMPRESSED local image in place.
rsync --copy-devices --inplace --no-whole-file --progress \
  -e "ssh -i ~/.ssh/id_ed25519 -c aes128-ctr" \
  --rsync-path="sudo rsync" \
  pi@192.168.1.6:/dev/mmcblk0  ~/kiosk-SL16G.img
```

> **The hazard that makes this a decision, not a default.** `--inplace` means a run that dies
> partway leaves the image **partially updated** — neither the old coherent image nor a new one.
> That is a one-way door across the only bootable artifact, and it is worse than having a stale
> image. Do not point this at your only copy. Either keep the previous `.img.gz` untouched until the
> refreshed image passes `verify-image.sh` (kiosk-reference), or hold two uncompressed
> copies (32 GB against 938 GB free — the space is not the constraint).

Storing uncompressed also gives up the 4.9 GB → 15.9 GB compression the current artifact has. Space
is free here; the reason to care is that `--copy-devices` cannot delta against a `.gz`.

## Hardlink snapshots, not a delta chain

`rsync --link-dest=<yesterday>` writes a **full-looking tree every night** where unchanged files are
hardlinks to the previous night. Disk cost is one full copy plus daily deltas.

Chosen because restore is `cp -a` from a plain directory — no chain to replay, no proprietary
format, no tool required. A backup format is a promise you keep under stress at 2am; this one is
"it's just a folder."

Retention: **7 daily, 4 weekly, 3 monthly.** At ~339 MB plus deltas this is comfortably under 5 GB
against 938 G free.

## The failure mode this must be built against

> If "it passed" would look identical when the thing failed, nothing was measured.

A backup that copies **nothing** produces a directory, exits 0, and looks exactly like a backup that
worked. This is the dominant risk — far more likely than the disk filling.

So the job asserts, and **fails loudly** rather than exiting 0:

1. `rsync` exit status captured directly — never through a pipeline, whose status is the *last*
   command's. (If a pipeline is unavoidable, `st=("${PIPESTATUS[@]}")` on the **very next line**.)
2. **Canary files must exist in the new snapshot**, verified present on the device 2026-08-06:
   `/home/pi/mmClient.sh`, `/home/pi/mmClient.sh.chromium60` (the rollback artifact),
   `/etc/systemd/system/kiosk-rngd.service`, `/etc/ssh/sshd_config`,
   `/etc/wpa_supplicant/wpa_supplicant.conf`.
3. **File-count floor** — fewer than 1,000 files in a completed snapshot is a failure, not a quiet
   success.
4. The snapshot is assembled under a `.partial` name and renamed only on success, so a
   half-finished tree is never mistaken for a good one or used as the next `--link-dest`.
5. `flock` on the whole run, so a slow night cannot overlap the next.

**Both directions must be proven before this is trusted**: that it fails when the Pi is unreachable
or the canaries are missing, *and* that it succeeds on a normal night. A gate only ever seen passing
has not been tested.

## Restore rehearsal

An untested restore is a guess — the card image carries the same caveat today
(`STATUS.md` (kiosk-reference) §"Card image"). The rehearsal costs nothing and touches no device:

```bash
# prove the snapshot contains a usable launcher and unit, without going near the Pi
d=~/kiosk-backups/daily.0
diff <(ssh-kiosk 'cat /home/pi/mmClient.sh') "$d/home/pi/mmClient.sh" && echo "launcher matches live"
grep -c . "$d/etc/systemd/system/kiosk-rngd.service"
```

Restoring a *file* to the Pi is a normal recoverable change. Restoring the *system* is the card
image's job, not this one.

## Installing it (not done)

A `systemd` timer on the mirror host — **not** cron, so failures land in the journal. The units are
written and reviewable but **not installed**: `kiosk-backup.service` (kiosk-reference)
and `kiosk-backup.timer` (kiosk-reference).

```bash
mkdir -p ~/.config/systemd/user
cp ~/kiosk-reference/tools/kiosk-backup.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now kiosk-backup.timer
systemctl --user list-timers kiosk-backup            # confirm next elapse
journalctl --user -u kiosk-backup -n 50              # read a real run

# so the timer still fires when nobody is logged in:
loginctl enable-linger "$USER"
```

`enable-linger` is the step that is easy to miss: without it a `--user` timer only runs while a
session exists, so the backup would silently not happen on exactly the nights nobody is at the
machine.

Revert: `systemctl --user disable --now kiosk-backup.timer`. Class: **recoverable**, and it does not
touch the Pi at all.

Schedule **02:30**, with the timer's `Persistent=true` so a host reboot does not silently skip
nights. Avoid 03:00–06:00 if a `dd` image is ever scheduled — they would compete for the same
saturated core.

## One copy, on the mirror host — unchanged trade-off, larger stake

The card image already lives on the host it protects, a **closed decision**
([`backup-recovery.md`](backup-recovery.md) §"One copy, on this host"). This proposal puts the
nightly backups in the same place, so it does not reopen that decision — but it does raise what a
single host failure costs, from one image to the image plus all history. Flagged for the owner as a
consequence, not re-argued here.

---

# Part 2 — Hardening

## Measured posture, 2026-08-06

Read-only checks, one pass. This is what is actually true, not what is assumed:

| Surface | Finding | Verdict |
|---|---|---|
| CDP debug port 9222 | bound **`127.0.0.1` only** | **already safe** |
| Listening on the network | **only** `:22` (v4+v6) | minimal |
| `PermitRootLogin` | `without-password` (key only) | good |
| `PubkeyAuthentication` | `yes`, 1 authorized key | good |
| **`PasswordAuthentication`** | **`yes`** — `pi` has a usable password | **the one real finding** |
| `iptables` | all chains default `ACCEPT`, no rules | see H2 |
| OS | Raspbian 9 stretch, **EOL, no security updates** | structural |

`PasswordAuthentication` is not set anywhere in `sshd_config` — every occurrence is commented. The
value above is the **effective** config from `sshd -T`, which is authoritative; reading the file
alone would have inferred it from the daemon default and inference is what this project distrusts.

Chromium's debug port being loopback-only is worth stating plainly because it is the highest-severity
thing that *could* have been wrong: an open 9222 on the LAN is full remote control of the browser.
It is not open. No action needed — recorded so nobody re-litigates it.

## H1 — Disable SSH password authentication — **DECLINED, keep it enabled**

> **`[Yocto]` The device this decision was made about is no longer the running one, and the
> replacement is worse.** H1 concerns the Raspbian SL16G, where the account had a real password and
> root SSH login was off. The Yocto image ships `debug-tweaks`: an **empty root password** and
> `PermitRootLogin`. That is a different question from H1's — not *how* you authenticate but whether
> authentication exists at all — and it is a regression against the card it replaced.
>
> **Deferred by the owner, 2026-08-13, and out of scope for the current work.** Tracked as
> **#7 root password / debug-tweaks** on `meta-wisekiosk`, with the options and the recovery
> constraints that any change has to preserve. It compounds **#6 public RAUC signing key**: while an
> unauthenticated root shell is reachable on the LAN, the update path has no authentication anywhere,
> so fixing the key alone buys nothing.
>
> The H1 ruling below still stands on its own terms, and its reopening condition — the second device
> having its key installed — is also the gating question for #7. **Do not re-propose either without
> asking the owner whether that device still needs password access.**

> **Owner decision, 2026-08-06:** password authentication **stays on**. There is another device still
> to be set up that needs to reach the kiosk, and it has no key installed yet. Disabling password auth
> now would lock that setup out before it happens.
>
> This is a live constraint, not a permanent ruling. The condition that would reopen it is that
> device having its public key in `/home/pi/.ssh/authorized_keys`. Until then the procedure below is
> **not to be run** — do not re-propose it as an open item.

**Class: recoverable over the wire, but it touches the lifeline.** It would remove the only
credential-guessing surface on an EOL SSH daemon, which is why it was raised.

The danger is not the edit, it is doing it without a way back. Never close your only session.

```bash
# 1. KEEP THIS SESSION OPEN THROUGHOUT.
# 2. Confirm key auth already works from a second terminal before changing anything:
ssh -i ~/.ssh/id_ed25519 -o PasswordAuthentication=no pi@192.168.1.6 'echo key-auth OK'

# 3. Back up, then edit via temp + mv (never in place):
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak-$(date +%F)
sudo sed 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
    /etc/ssh/sshd_config > /tmp/sshd_config.new
sudo grep -c '^PasswordAuthentication no' /tmp/sshd_config.new   # must print 1, not 0
sudo mv /tmp/sshd_config.new /etc/ssh/sshd_config

# 4. Validate BEFORE restarting — a bad config that fails to start loses the device:
sudo sshd -t && echo "config valid"
sudo systemctl reload ssh        # reload, not restart: existing sessions survive

# 5. From a THIRD terminal, prove a new connection still works:
ssh -i ~/.ssh/id_ed25519 pi@192.168.1.6 'echo still reachable'
```

**Revert:** `sudo cp /etc/ssh/sshd_config.bak-<date> /etc/ssh/sshd_config && sudo systemctl reload ssh`

`sshd -t` before `reload` is the step that makes this safe. `reload` over `restart` means even a
mistake leaves the current session alive to fix it.

## H2 — Stretch is EOL: mitigate at the network, not on the device

The kiosk cannot be patched. `apt full-upgrade` after repointing `sources.list` pulls 69 upgrades
including `libc`, `openssh`, `dhcpcd` and `wpa_supplicant` — **the lifeline itself**
(`STATUS.md` (kiosk-reference)). That is refused, and named packages only remains the rule.

So harden the *network position* instead, where the work costs the device nothing:

- Keep the kiosk on the LAN with **no port-forward from the internet**. Verify at the router.
- Confirm no UPnP hole is opening 22 automatically — worth checking once, costs nothing.
- If the router supports it, restrict inbound 22 to the mirror host's address.

This is judgement, not measurement: the exposure is a LAN-only EOL SSH daemon with password auth
that H1 removes. Given the constraint that the device cannot be upgraded, network position is the
only lever that does not risk the lifeline.

### H2b — Egress restriction: the browser is the real surface, not `sshd`

**The ceiling is now confirmed against the live archive, not a cached index** (2026-08-06):
`archive.raspberrypi.org/debian` `dists/stretch/main/binary-armhf` carries **exactly one**
`chromium-browser`, `72.0.3626.121-0+rpt4` — the build already running. There is nothing newer to
fetch, so "update the browser" is closed, and an unpatched 72 is permanent.

That makes **outbound** the interesting direction. A LAN-only `sshd` is a smaller problem than a
browser with years of unpatched CVEs that can reach anything. The intended rule rejects `NEW`
outbound TCP to 80/443 except to `192.168.1.3`, leaving policy at `ACCEPT`.

**Why this cannot cost the lifeline, stated precisely:** SSH is *inbound*. Its `OUTPUT` packets are
always `ESTABLISHED` and always **source** port 22 — never destination 80 or 443 — so the match can
never select them. Combined with `-P OUTPUT ACCEPT` and no `iptables-persistent`, a mistake fails open
and a reboot clears it. This is the argument that separates it from the barred inbound case, where a
wrong rule silently eats port 22.

**Two dependencies found by measurement, both of which a blanket router-level "block this device from
the internet" would have broken silently:**

- **NTP is live and there is no RTC.** `timedatectl` reports `NTP synchronized: yes`, `RTC time: n/a`,
  and `/etc/systemd/timesyncd.conf` has **no `NTP=` line** — it is using the compiled-in pool, off-LAN.
  Cut it and every boot starts from `fake-hwclock` and drifts, with a clock on the display. Restricting
  only TCP 80/443 leaves NTP (UDP 123) and DNS untouched, which is the argument for doing this on the
  device rather than at the router.
- **Client-side module fetches are unproven either way.** A single `ss` showed chromium holding one
  socket, to `192.168.1.3:8080`. That is consistent with MagicMirror calling third-party APIs from
  server-side node helpers — but a module refreshing every few minutes would not appear in one sample,
  and blocking on that evidence assumes the thing being tested.

**The rule was measured before it existed**, as counters that took no action, and the measurement
overturned the plan: the first `ss` sample read as "never talks off-LAN" and the counters immediately
found 77 packets in 7 minutes. Converting straight to `REJECT` on that sample would have blocked live
traffic blind.

**DONE 2026-08-06** — applied, seeded in both directions, and made persistent by
`kiosk-egress.service` rather than by `iptables-persistent`, which would have required repointing
`sources.list` at a third party's frozen archive to gain a package that hooks into the network stack.
State, md5s, revert command and the three failure-mode seeds are in
`STATUS.md` (kiosk-reference) §"Egress restriction".

## H3 — Remove the broken deadman harness, do not fix it — **DONE 2026-08-06**

> **Executed on owner instruction.** `kiosk-arm`, `kiosk-confirm`, `kiosk-deadman`, `kiosk-revert`
> and `kiosk-snapshot` were **deleted** from `/usr/local/sbin/`; `kiosk-rngd` was left in place and
> verified intact by md5 immediately after. `/var/backups/kiosk-safe/` was kept — inert without the
> scripts, and the only surviving record of what the harness reverted. Current state is in
> `STATUS.md` (kiosk-reference); the reasoning below is why, and is kept because the argument
> generalises to the next safety harness someone proposes.

Six files at `/usr/local/sbin/kiosk-*`. `grep -c flock` returns **0** for `kiosk-deadman` and
`kiosk-arm` — the installed copy is the pre-`flock` version that disarms *after* its slow work and
takes no lock. It is currently harmless only because no crontab references it.

**A disarmed broken safety device is a trap, not a safeguard.** Its filenames advertise exactly the
function it performs incorrectly, and the next person to find it will arm it.

### What it actually does

A dead man's switch for risky remote changes. `kiosk-snapshot` tars the files listed in
`/var/backups/kiosk-safe/tracked.txt` plus the enabled-unit list; `kiosk-arm <minutes>` writes a
deadline; you make your change; `kiosk-confirm` deletes the deadline if you still have SSH. If you do
not confirm, `kiosk-deadman` — fired by cron every minute — runs `kiosk-revert`, which untars the
snapshot over `/`, re-enables the recorded units, and reboots.

### It fired on 2026-08-06, and the syslog shows the wedge

```
00:00:39  snapshot taken
00:05:02  REVERTING to snapshot 2026-08-06T00:00:39
00:06:02  REVERTING ...   <- cron fires again; the first is still running
00:07:02  REVERTING ...
00:08:02  REVERTING ...
00:09:02  REVERTING ...
00:10:02  REVERTING ...
00:11:02  REVERTING ...
00:12:02  REVERTING ...   <- eight concurrent reverts stacked
00:12:22  revert complete, rebooting
```

**`kiosk-revert` takes 7m20s on this hardware against a 60-second cron interval.** It removes the
deadline *last*, after `tar xzf` over `/` and a `systemctl enable` loop across ~40 units, so the
deadline stays readable for seven minutes and `kiosk-deadman` re-fires every 60s. Eight copies
untarred over the root filesystem at once. No `flock`. Only one reached "complete" — the reboot
killed the rest. This is the measured version of "disarm before acting, never after".

### The finding that settles it: what it protects is not what can hurt you

`tracked.txt` is **three files**, all browser-launcher config:

```
/home/pi/mmClient.sh
/home/pi/.config/lxsession/LXDE-pi/autostart
/etc/chromium-browser/default
```

It does **not** cover `sshd_config`, `wpa_supplicant.conf`, `dhcpcd.conf` or `/etc/network/`. So the
harness **cannot save you from the only failure class that needs saving from** — losing SSH or the
network. It guards a broken browser launcher, which is already recoverable over SSH with
`mv /home/pi/mmClient.sh.chromium60 /home/pi/mmClient.sh`.

Blast radius: the whole system, demonstrated. Protective scope: three files restorable in one
command. That asymmetry is the argument, and it does not depend on fixing the `flock` bug.

### Three further defects, for the record

- **`tar xzf … 2>/dev/null`** — a corrupt or empty snapshot restores nothing, disarms, reboots and
  logs `revert complete`. A revert that did not revert is indistinguishable from one that did.
- **Unit restore is one-directional.** It re-enables what was enabled at snapshot time and never
  disables what was enabled since, so it does not actually restore unit state.
- **The deadline is wall-clock and `kiosk-deadman` runs at boot**, on a box where the clock jumps
  mid-boot (fake-hwclock, then timesyncd — [`remote-debugging.md`](remote-debugging.md) §"Gotchas").
  A stale restored clock can read the deadline as not yet due and skip a revert that was wanted.

`kiosk-arm` checks only that the snapshot is non-empty (651 bytes here) — not that it is valid, nor
that it contains the file about to be changed.

Recommendation, since taken: **delete or rename the installed copies**, rather than install the
corrected draft.
The operator case against the harness is that it is untested automation with a whole-system blast
radius, guarding a change whose revert is a one-line `mv` over an SSH that is not at risk. It adds
risk and removes none.

```bash
# recoverable; the files are also inside the 2026-08-06 card image
# what was run, 2026-08-06. Names spelled out individually and never kiosk-*,
# which would take the live entropy fix with them.
for f in kiosk-arm kiosk-deadman kiosk-confirm kiosk-revert kiosk-snapshot; do
  sudo rm -f "/usr/local/sbin/$f"
done
```

**`kiosk-rngd` was not touched** — it is the live entropy fix, enabled and active, and its md5 was
re-checked immediately after the deletion.

**Recovery**, if it is ever wanted: the five are inside the 2026-08-06 card image, and their md5s are
recorded in `STATUS.md` (kiosk-reference). There is no on-device copy — that is the intended outcome,
not an oversight.

This is a recommendation for the owner, not a decision taken.

## H4 — Backend container, on the mirror host

Already correct in the ways that matter: runs as `USER node` (not root), has a `HEALTHCHECK`, and
`docker ps` reports `healthy`. Optional tightening, all recoverable and all on this host rather than
the Pi:

- Publish as `-p 192.168.1.3:8080:8080` rather than all interfaces, if it is not already.
- Add `--read-only` with a `tmpfs` for scratch, `--cap-drop=ALL`, `--security-opt=no-new-privileges`.
- Pin the image by digest so `magicmirror:chrome72` cannot be silently replaced — the tag is a local
  build and **which branch produced it was unrecorded until 2026-08-06**.

## Explicitly not recommended

Stating these so they are not re-proposed each session:

- **`iptables`/`ufw` on the Pi, *inbound*.** Only port 22 is open and it is the lifeline. A firewall
  rule that goes wrong costs the device; the benefit is near zero when the port count is one.
  **This bars INPUT filtering only** — the reasoning is entirely about the one open port. It was read
  as barring all `iptables` use on 2026-08-06; it does not. Egress is a separate question, decided
  and applied in §H2b.
- **`fail2ban`.** Once H1 lands there is no password to brute-force, and it is one more EOL package
  with the ability to add `DROP` rules against the lifeline.
- **`unattended-upgrades`.** The archive 404s and `full-upgrade` is forbidden. Automating a package
  operation that is manually refused is strictly worse.
- **Any automatic rollback harness.** See H3.
- **`apt-get install -s` as evidence of anything.** It reports success for packages that cannot be
  fetched, because the index is cached while the archive is dead.
