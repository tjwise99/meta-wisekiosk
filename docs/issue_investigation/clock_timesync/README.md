# Clock sync — DNS is not the fault, and the cost is not what the ticket named

Issue #31 asked whether intermittent `systemd-timesyncd` sync is a DNS problem — the static
resolver in
[`kiosk-static-resolv.bbclass`](../../../meta-wisekiosk/classes/kiosk-static-resolv.bbclass) was
named as a suspect — and whether the saved clock on `/data` is enough of a floor. Neither premise
survives contact with the data. DNS resolution never failed, on either board, in any sample
collected. What the evidence shows instead is a ~56 s structural window every boot in which the
rendered clock is wrong regardless of network health, and a second, sharper failure: the saved
clock does not live on `/data` at all, so every OTA install throws it away and the next boot starts
back at the epoch — which is what has already broken a real install with a "certificate is not yet
valid" refusal. This is the record of that reasoning, the data it rests on, and a recommendation for
the owner to decide against, not an implementation.

## Configuration under test

Pi Zero W, no RTC and no fake-hwclock — every boot starts at the epoch and only NTP moves the clock
forward. `timesyncd.conf` carries no `NTP=` and no `FallbackNTP=` override, so the compiled-in
default server list stands, which is a list of DNS hostnames, not literal addresses.
`systemd-resolved` is masked
([`kiosk-hardware_1.0.bb`](../../../meta-wisekiosk/recipes-core/kiosk-hardware/kiosk-hardware_1.0.bb)),
and `/etc/resolv.conf` is a symlink to `/data/config/resolv.conf`, written by provisioning
([`kiosk-static-resolv.bbclass`](../../../meta-wisekiosk/classes/kiosk-static-resolv.bbclass),
lines 10-11). `timesyncd` is the *sole* consumer of that resolver path — nothing else on
the image does a DNS lookup — so a boot's only DNS-dependent step is resolving its own NTP server
(the symlink itself is created at lines 27-32).
`wlan0` does not exist until ~32.6 s into boot
([`wlan0_udev_queue`](../wlan0_udev_queue/README.md)), which puts a hard floor under how early any
network-dependent step, DNS or NTP, can start.

`systemd-timesyncd.service` ships `StateDirectory=systemd/timesync`, which resolves to
`/var/lib/systemd/timesync` — on the rootfs, inside the slot RAUC overwrites. Nothing redirects it to
`/data`. `justfiles/ota.just:232-246` already carries a workaround for the consequence: `kiosk-install`
reads the device's epoch, compares it to the host's, and force-sets the device clock before
installing, because an install racing NTP from a cold epoch fails bundle verification with
"certificate is not yet valid" — a real failure, on 2026-08-13, after a clean 119 MB transfer that
had nothing wrong with it.

Two boards, two sample sizes. The **bench board** ran a bounded 40-boot reboot-loop harness
(`bootloop.service` + `/data/bootloop/collect.sh`, 2026-08-16/17), harvested after the loop
self-disabled at its N=40 bound. The **prod board** has no equivalent bulk run — its evidence is a
handful of boots retained in the persistent journal, plus an ongoing 5-minute soak sampler that PR
#40 (draft) extends to log `ntpsync=`/`dns=`/boot-counter fields alongside the existing memory and
network checks. Prod is materially under-sampled next to the bench sweep; that gap is the reason the
soak extension exists, and it is called out explicitly below rather than papered over.

## How the test was performed

The bench harness rebooted the board 40 times unattended, capturing per-boot
`ntp_contact_s`/`ntp_sync_s`/`synchronized`/`dns`/`BOOT_ORDER`/`A_LEFT`/`B_LEFT`/`pstore`/`mmc_err`
from `collect.sh`'s log, bounded by `Requires=rauc-mark-good.service` and an uptime gate so the loop
could not consume a boot-attempt counter by rebooting out from under its own good-marking. All 40
lines and both `bootloop.log`/`mmc.log` captures were present at harvest; `pstore` was checked
non-empty on every boot as a `mmc_rescan`-panic watch (issue #18) — none fired.

`collect.sh` was deployed to `/data/bootloop/collect.sh` on the bench board for this run and was
never part of any shipped image; per the traceability rule above it is tracked alongside this
write-up as [`bootloop-collect.sh`](bootloop-collect.sh) — that file, not prose, is the harness of
record for the bench corpus.

Prod's earlier evidence came from reading `journalctl`'s retained boots directly — three, all that
survived rotation — for time-to-first-NTP-contact. The soak extension (PR #40, draft) was then
verified live: a fresh 5-minute sample line on the running prod board carries the new fields, and the
existing `--summary` parser (issue #27's field-keyed parser) still reads a mixed old/new-format log
cleanly. That confirms the instrument works; it does not yet supply a bench-scale corpus.

The tree facts above — the resolver chain, the masked units, `timesyncd`'s compiled defaults, the
state directory's location, and the `ota.just` workaround — were each read from source rather than
assumed, and are cited by file and line above.

**Board code provenance.** Both boards report identical `/etc/os-release`
(`ID=autonomos`, `VERSION="0.1 (Rubik)"`) and identical `/etc/version`
(`20180309123456`) — an unmodified OE-core distro default, not a value this tree sets or updates
per build; grepping `meta-wisekiosk/`, `classes/`, `includes/`, and `patches/` for anything that
writes `/etc/version`, `BUILDNAME`, or `DISTRO_VERSION` from the source tree's git state finds
nothing. **The image does not embed its own build commit — this is a real traceability gap, not
just an unrecorded fact**, and baking the source git commit into the image (e.g. into
`/etc/version` or a dedicated `/etc/build-info` at image build time) is the durable fix. Absent
that, this investigation's board-to-code link rests on the harness/instrument that gathered each
board's data, recorded here instead:

- The **bench board's** 40-boot corpus came from the boot-loop harness
  (`bootloop.service` + `collect.sh`, tracked in this directory as
  [`bootloop-collect.sh`](bootloop-collect.sh) — see "How the test was performed" below), run against
  the bench board's then-current shipped image; the harness itself is not part of any image and was
  torn down after harvest.
- The **prod board's** steady-state soak data was gathered with an **out-of-tree hot-swap**, not
  the prod board's current image build: the soak sampler's `ntpsync=`/`dns=`/boot-counter fields
  came from live-replacing the running `kiosk-soak` binary with the build from PR #40 / commit
  `ef834cf` (branch `soak-clock-instrument`), which is **not yet merged and not yet in the prod
  image build**. That data reflects the instrument under test, not the board's shipped code, and
  should not be read as validating anything about the currently-imaged prod build beyond the
  journal-derived NTP-contact figures below (which came from the shipped image's own
  `systemd-timesyncd`, not the hot-swapped binary).

## Metrics

**Bench, 40/40 boots:**

| metric | value |
|---|---|
| `ntp_sync_s` min / max / mean | 54.97 / 56.81 / 55.83 s |
| `ntp_sync_s` spread (max − min) | 1.84 s |
| `dns=FAIL` | 0 / 40 |
| `synchronized=no` | 0 / 40 |
| RAUC counter (`A_LEFT`/`B_LEFT`) | held `3`/`3` every boot |
| non-empty `pstore` | 0 / 40 |

Every boot synchronized, every boot resolved DNS, and the spread across 40 boots was under 2 seconds
— this is a tight, consistent ~56 s, not an intermittent fault. It is also 40 boots of negative
evidence against #18's `mmc_rescan` panic: pstore stayed empty throughout, so the panic did not
reproduce here (it remains #18's own hazard to chase, not this investigation's).

**Prod, ~3 retained boots:** time-to-first-NTP-contact of ~12.7 s, ~42.4 s and ~40.1 s — a spread far
wider than the bench's 1.84 s — with **zero DNS resolution failures** and every boot reaching the
same server. Three boots is not enough to characterize a distribution; it is enough to say the bench's
tight consistency does not hold on prod, and that whatever drives the difference, it is not DNS.

**What the ticket assumed, tested against both boards:** DNS is not the fault. 0/40 bench failures
and 0/3 prod failures, all resolving the same server, refutes the "DNS at boot? the static resolv
setup" framing issue #31 opened with directly. The static resolver chain
(`kiosk-static-resolv.bbclass` → `/data/config/resolv.conf`) works every time it was sampled.

**Hypotheses for prod's variance, tested against the evidence collected so far:**

- *DNS lookup cost or failure.* Dropped. Zero failures across every sample on both boards, and the
  variance shows up in prod's boots even though DNS succeeded in all of them — DNS cannot be the
  variable that is moving.
- *wlan0 association/DHCP timing.* Not dropped — not yet tested directly. The bench board's `wlan0`
  timing is itself tightly bounded (~32.6 s, per `wlan0_udev_queue`), which is consistent with the
  bench's tight `ntp_sync_s` spread, but prod's per-boot `wlan0`-up timestamp was not captured
  alongside its NTP-contact time in the retained journal entries, so this is a live candidate, not a
  ruled-out one.
- *Network path or gateway load on the prod network.* Open. Plausible — a production LAN carries
  traffic a bench setup does not — but nothing in hand measures gateway or path latency at the
  moments sampled.
- *Signal quality / AP association retries.* Open. Consistent with the ~30 s range in prod's first-
  contact numbers, and consistent with WiFi being the one meaningfully different variable between a
  bench board and a board mounted at its production site, but not instrumented in this dataset.

None of the three open candidates can be adjudicated from three boots. That is the honest state of
this investigation: the DNS question issue #31 asked is answered and closed, and the actual variance
mechanism is not — the soak extension in PR #40 is the instrument built to close it, and it has not
run long enough yet to produce a verdict.

**Severity, restated in terms that matter:** two distinct costs, not one.

1. A **~56 s window every boot** — tight on the bench, wider and unbounded-in-practice on prod —
   during which the board's clock is not just imprecise but confidently wrong (still near the epoch),
   and the kiosk renders it as if it were correct. That window is structural: it is roughly `wlan0`
   coming up (~32.6 s) plus association/DHCP plus the first NTP round trip, and no part of it is a
   fault to be patched, only a duration to be covered or shortened.
2. **No persistent clock across an OTA.** `timesyncd`'s saved clock lives under
   `/var/lib/systemd/timesync`, on the rootfs slot RAUC overwrites on every install. A freshly
   installed slot's first boot has no floor at all — not "imprecise," genuinely epoch-start — and
   that is the documented, already-observed cause of the "certificate is not yet valid" install
   failure the `ota.just:232-246` workaround exists to paper over. This is worse than the first cost:
   it is not a rendering nuisance, it is a hard blocker on the OTA path that issue #31's own triage
   flagged as blocking issue #25.

## Changes configured as a result

**Implemented: fix (2).** A new recipe
[`kiosk-timesync-persist`](../../../meta-wisekiosk/recipes-core/kiosk-timesync-persist/) redirects
`systemd-timesyncd`'s state onto `/data`, added to the `kiosk-zero-w` image. In the same change the
`justfiles/ota.just` host force-set of the clock is retired (the skew is still reported as a
diagnostic), since a fresh slot now inherits a real clock. Candidate `(1)` was rejected.

Candidate `(3)` (`systemd-time-wait-sync`) was **dropped after review, not shipped**: its two clauses
are "enable the unit *and order clock-dependent consumers after* `time-sync.target`", and this image
has no in-boot clock consumer to order — the only clock-sensitive step is the OTA install, which runs
over SSH, not as a boot unit. Enabling the unit alone gates nothing and, because a restored saved
clock does not clear `STA_UNSYNC` (only a live NTP exchange does), it sits `activating` until a real
sync, leaving `systemctl is-system-running` at `starting` on any board whose uplink is down. A
mechanism with no consumer and a downside was not worth shipping; if a boot-time consumer is added
later, enable it then.

Mechanism, as landed — the ordering is load-bearing, not a mirror of `kiosk-journal`'s tmpfiles half:
- `10-persist-clock.conf` — a `systemd-timesyncd.service.d` drop-in with
  `BindPaths=/data/systemd-timesync:/var/lib/systemd/timesync` and `After=data.mount`. **BindPaths,
  not a symlink**, because of the `ProtectSystem=strict` silent-`EROFS` no-op under candidate (2):
  confirmed against the built unit, which ships `ProtectSystem=strict` + `StateDirectory=systemd/timesync`
  + `User=systemd-timesync`. `After=`, not `RequiresMountsFor=`/`Requires=`: a failed `/data` must
  leave NTP running (non-persistent), per the image's degradation contract.
- `kiosk-timesync-dir.service` — a oneshot (`DefaultDependencies=no`, `After=data.mount`,
  `Before=systemd-timesyncd.service`) that creates and `chown -R`s the `/data/systemd-timesync` bind
  source. This ordering is the fix's linchpin: a tmpfiles `d` entry cannot guarantee the source
  exists before timesyncd binds it (`/data` is `nofail`, so nothing orders tmpfiles-setup after the
  mount), and a missing source fails timesyncd `226/NAMESPACE` into its restart limit — no time sync
  at all. `kiosk-journal` ships only the tmpfiles half and survives solely because its failure is
  soft (journal stays volatile); a written clock has no such slack. The `chown -R` also re-owns the
  clock file each boot, defusing a dynamic-UID drift across an OTA that would otherwise `EACCES`-
  then-`log_debug` into the same silent no-op candidate (2) forbids.

**Verification status: PASSED on hardware, 2026-08-18, bench board.** That the recipe parses and
packages its two units was never evidence the fix takes effect — whether it works is decided entirely
by boot-time ordering (whether the bind source exists before timesyncd binds it), and only hardware
can decide that. It has now run. The bundle carrying this change was built, verified as signed by
`CN = WiseKiosk Signing Key 2026`, installed, and booted:

- **timesyncd starts clean.** `systemd-timesyncd` came up `active` with **zero** `226/NAMESPACE`
  failures — the exact failure the `kiosk-timesync-dir.service` ordering exists to prevent, and the
  one that would mean no time sync at all.
- **The clock lands on `/data`.** `/data/systemd-timesync/clock` is present and advancing. The rootfs
  copy at `/var/lib/systemd/timesync` stays empty, which is the correct signature, not a fault: the
  bind is namespace-local to the unit, so the file is only ever visible at the `/data` path from
  outside it. An observer checking the rootfs path and finding it empty is looking in the wrong
  namespace.
- **A second boot resumed near true time.** Against a cold first boot that started in `May 2025`, the
  next boot came up within **~2 s** of true time — the persisted clock applied at startup, ahead of
  any NTP exchange. That is the ~56 s wrong-clock window collapsing, measured.
- **The re-stage wiring holds.** Four `systemctl restart systemd-timesyncd` cycles all returned
  `active`, none `226/NAMESPACE` — the restart path a `/data`-absent boot alone does not surface.
- **#31's failure mode is fixed.** At **uptime 53 s, before NTP sync**, the `/data`-restored clock was
  already sufficient for `rauc info` to verify the bundle's certificate. This is the 2026-08-13
  scenario — an install racing NTP from a cold epoch — passing with the `ota.just` host force-set
  retired. The workaround is dead code because the cause is gone, not because it was merely removed.

**Caveat — the first boot onto a freshly rolled-out slot is cold by construction.** The persisted
clock lives on `/data`, and a slot that has never run has never written it, so the first boot after
this change rolls out to a board starts at the epoch exactly as before. That is a one-time migration
artifact, not a regression: every boot from the second onward inherits a real clock. The first
post-rollout boot showing a cold clock should not be read as the fix failing.

Three candidate fixes were weighed against the measured data:

1. **Pin `NTP=` to a literal address**, removing the DNS hostname lookup from the sync path. This
   buys little. DNS is not the failing link — 0 failures in 43 combined boots across both boards — so
   removing a step that has never failed does not touch either measured cost (the 56 s window or the
   lost clock across OTA). It also trades away the resilience of a multi-host fallback list for a
   single address, and reintroduces the exact anti-pattern `kiosk-static-resolv.bbclass` was written
   to avoid: baking site-specific network configuration into the image. Not recommended.

2. **Move `timesyncd`'s state directory onto `/data`**, so the saved clock survives an OTA. This is
   the only one of the three that addresses the fix's evidence directly, on **both** counts:
   `timesyncd` applies a saved clock immediately at startup, ahead of a live NTP exchange, so a board
   that reboots with a persisted clock resumes near its last-known-good time instead of at the epoch
   — collapsing most of the 56 s window in which the rendered time is *wrong*, as opposed to merely
   *unconfirmed*. It also removes the actual cause of the OTA certificate failure: a freshly installed
   slot inherits the previous slot's saved clock instead of starting cold, so the install no longer
   races NTP from zero. The natural shape for this, mirroring how
   [`kiosk-static-resolv.bbclass`](../../../meta-wisekiosk/classes/kiosk-static-resolv.bbclass)
   already redirects `/etc/resolv.conf` to a `/data`-backed path rather than baking it into the
   rootfs, is a rootfs-postprocess step that points `timesyncd`'s state path at `/data` instead of
   `/var/lib` — the same technique already proven for exactly this class of problem on this image.
   **Recommended as the primary fix.**

   **Must-resolve before implementation, not covered by the resolv.conf analogy:**
   `systemd-timesyncd.service` ships `ProtectSystem=strict` with no `ReadWritePaths=` or
   `BindPaths=` declared. That sandbox remounts the rootfs read-only inside the unit's private
   mount namespace except for paths it explicitly manages (`StateDirectory=`, `RuntimeDirectory=`,
   and anything listed in `ReadWritePaths=`/`BindPaths=`) — `/data` is not on that list today.
   `resolv.conf` tolerates a bare symlink because timesyncd only *reads* it; the clock state file
   is different — it is *written* on every sync, on the ~60 s `SaveIntervalSec` timer, and at
   shutdown. A write outside the sandbox's writable set fails `EROFS`, and both
   `manager_save_time_and_rearm()` and `load_clock_timestamp()` in systemd's
   `timesyncd-manager.c`/`timesyncd.c` swallow that failure at `log_debug` level — no warning, no
   visible error. A bare rootfs symlink at the target path, with `StateDirectory=`/
   `ProtectSystem=strict` otherwise left unchanged, risks being a **silent no-op**: the board boots
   fine, looks fixed, and the state file is never actually persisted to `/data` — reproducing the
   exact epoch-restart failure this fix exists to close, just without even a log line to notice it
   by. The fix must grant write access to the new location explicitly — a drop-in adding
   `ReadWritePaths=`/`BindPaths=` for the `/data` path (e.g.
   `BindPaths=/data/systemd-timesync:/var/lib/systemd/timesync`), or an equivalent mount-unit
   ordered ahead of the service — not a bare symlink assumed to behave like the resolv.conf case.
3. **Enable `systemd-time-wait-sync` and order clock-dependent consumers after `time-sync.target`.**
   This changes *ordering*, not the window's length: nothing boots faster or syncs sooner, units
   ordered after the target simply wait rather than run against a wrong clock. It is a correctness
   improvement for any system-level consumer that needs a trustworthy clock before it starts — which
   plausibly includes the install/verification path itself — but it does not touch the OTA-breaking
   root cause, and the kiosk's own displayed clock is rendered by the page this repo does not build,
   so the "suppress until synced" half of issue #31's ask cannot be delivered from here regardless.
   Cheap enough to add as a complement to (2), not a replacement for it.

**Recommendation: (2), combined with (3) as a low-cost complement, not (1).** Persisting the clock to
`/data` is the only candidate that is directly load-bearing against both measured costs — the
render-wrong window and the OTA install failure — while pinning `NTP=` spends effort on a link that
has not failed once in 43 sampled boots. `systemd-time-wait-sync` is worth adding alongside it purely
for any unit still ordered ahead of a real sync, at negligible cost, but should not be mistaken for a
fix to either measured problem on its own.

Once a persisted clock is in place, the `ota.just:232-246` host-donated-clock workaround becomes dead
code and should be retired in the same change — a fresh slot inheriting a real clock from `/data`
should already be within the certificate's validity window without the host stepping in. Verification
should mirror the instruments this investigation already built: rerun the bench board's 40-boot
`bootloop.service` harness and confirm `ntp_sync_s` collapses toward zero on boots after the first
(rather than reproducing the current ~56 s every time), and perform a live `rauc install` immediately
after a fresh boot — the scenario that failed on 2026-08-13 — confirming the certificate check passes
with the `ota.just` skew-correction step disabled. Prod's variance mechanism stays open regardless of
which fix ships; closing it is what the PR #40 soak extension is for, and it should keep running
until it has a bench-comparable sample size.
