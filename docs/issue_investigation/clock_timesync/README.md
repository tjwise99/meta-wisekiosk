# Is boot-time DNS why the kiosk clock cannot be trusted — and what actually fixes it?

| | |
|---|---|
| **Issue** | #31 Intermittent systemd-timesyncd sync with no persistent clock — the kiosk renders a clock it cannot trust |
| **Status** | concluded → code change |
| **Opened / concluded** | 2026-08-14 / 2026-08-26 |

DNS at boot was never the fault: each of the two 40-boot corpora on the bench board, tabulated
separately because they are different builds, records `dns != ok` 0/40 and `synchronized != yes`
0/40. The real cost is that the board has no clock that survives an A/B update — a freshly installed slot
boots at the image's build-time floor, and RAUC refuses a bundle in that window because the fleet
signing certificate is not yet valid. The fix is `kiosk-timesync-persist`, which binds
systemd-timesyncd's saved clock onto the `/data` partition RAUC never touches, so a fresh slot boots
inside the certificate's validity window on its own. Both arms ran on #46-stamped images that name
their own build commit, host-side and on the board. Time-to-NTP-sync is unchanged by the fix and was
never expected to change; what collapses is the clock's error during that window, from ~15 months to
seconds, and with it a `rauc info` that went from `rc=1 certificate is not yet valid` to `rc=0`.

## Test runs

| Run | Board (role) | Image commit | Harness / scripts | Result (1 line) |
|---|---|---|---|---|
| A | bench · Pi Zero W Rev 1.1 | `34a917b018c154afddcd5fa2fe34afbf93033c01` | `bootloop-collect.sh` + `bootloop.service`, `earliest-ssh-capture.sh`, `analyze-bootloop.sh` — all one-off | Baseline reproduces the defect: fresh slot after an OTA reads `2025-05-29`, `rauc info` rc=1; 40/40 boots show zero DNS failures. |
| B | bench · Pi Zero W Rev 1.1 | `a9eb3a914793816881e7350ae21d3a2f49f1fbbc` | the byte-identical harness and scripts from Run A | Fix verified: fresh slot after an OTA reads the true time, `rauc info` rc=0; 40/40 boots add no new failure of any class. |

Same board, different builds — so these are two runs, and their numbers never share a table.

Every capture committed here was passed through an identifier scrubber before it entered this public
repo: LAN addresses read `<BENCH>`, the board's hostname reads `<BENCH-HOST>`, and the signing key's
SPKI fingerprint reads `<SPKI-FINGERPRINT>`. Nothing else was altered — the Yocto `MACHINE` name
`raspberrypi0-wifi`, the public NTP server addresses and every clock timestamp are as captured.

### Run A — bench, commit `34a917b`

- **Board:** bench (the OTA/reboot/abuse target), Raspberry Pi Zero W Rev 1.1, BCM2835, `armv6l`,
  512 MB. The prod board was never contacted in this investigation and nothing here says anything
  about it.
- **Image commit:** `34a917b018c154afddcd5fa2fe34afbf93033c01`, confirmed twice. Host-side, on the
  rootfs artifact before delivery: `tools/reproducibility-gate.sh --image` printed
  `ok image names HEAD (34a917b…)` — [`runA-gate-image.txt`](runA-gate-image.txt). On the board,
  after the OTA: `grep ^meta-wisekiosk /etc/buildinfo` →
  `meta-wisekiosk    = HEAD:34a917b018c154afddcd5fa2fe34afbf93033c01` —
  [`runA-onboard-buildinfo.txt`](runA-onboard-buildinfo.txt). The `<branch>` half reads `HEAD`
  because the build was made from a detached HEAD at that exact commit; the 40-char sha is the
  load-bearing half and matched in both checks. The same capture confirms the fix is **absent** from
  this image (`kiosk-timesync-dir.service` and `systemd-timesyncd.service.d/` both *No such file*).
- **Scripts deployed (each, with disposition):**
  - [`bootloop-collect.sh`](bootloop-collect.sh) — ONE-OFF, not shipped → committed here. This is the
    harness of record, sha256 `f69a367b…62abeb9c`, byte-identical to the copy that ran on the device
    and to the copy Run B ran. It is what produced every number in both corpora.
  - [`bootloop.service`](bootloop.service) — ONE-OFF, not shipped → committed here. **This unit is a
    reconstruction, not a recovered original.** The 2026-08-17 original was torn down and no copy
    survives; only `collect.sh` was preserved. It was rebuilt from the contract the collector's own
    header states — `Requires=` + `After=rauc-mark-good.service`, `Type=oneshot`,
    `WantedBy=multi-user.target` — with one deliberate deviation, `TimeoutStartSec=300`, because the
    collector blocks until `NTPSynchronized=yes` (or a 120 s cap) and then until uptime ≥ 90 s, which
    can exceed systemd's 90 s default and be SIGTERMed before it logs a boot. The deviation bounds
    nothing the counter-safety model relies on.
  - [`earliest-ssh-capture.sh`](earliest-ssh-capture.sh) — ONE-OFF, not shipped → committed here.
    Host-side: reboots the board and captures clock, `NTPSynchronized` and `rauc info` at the first
    instant sshd answers — the exact point a real `just kiosk-install` reaches a freshly rebooted
    board. Because it runs on the host it survives an OTA; a device-side witness unit does not,
    which is why the fresh-slot evidence is host-side in both runs. This repo is public, so the one
    line that held the board's address reads `HOST=${KIOSK_HOST:?…}` as committed; as run it was a
    literal `root@<addr>`. That is the only edit to any committed script.
  - [`clockproof.sh`](clockproof.sh) + [`clockproof.service`](clockproof.service) — ONE-OFF, not
    shipped → committed here. Device-side pre-timesyncd witness: the unit fires at `sysinit` after
    `data.mount` and before `systemd-timesyncd`, and the script records the clock, `NTPSynchronized`
    and `rauc info` at that point. Used only for the Run A baseline capture
    [`runA-pretimesyncd-witness.txt`](runA-pretimesyncd-witness.txt); superseded by
    [`earliest-ssh-capture.sh`](earliest-ssh-capture.sh), which is host-side and therefore survives
    an OTA into a fresh slot, which a device-side unit does not.
  - [`analyze-bootloop.sh`](analyze-bootloop.sh) — ONE-OFF, not shipped → committed here. Corpus
    analyzer. Self-tested against a seeded corpus carrying one DNS failure, one unsynchronized boot,
    one non-empty pstore, one mmc error and one dropped RAUC counter; all five fired, so a clean
    result below is a measurement rather than a silent pass.
- **Procedure:**
  1. `git checkout --detach 34a917b`; `tools/reproducibility-gate.sh --tree` passed.
  2. `just build` (kas-container, `kiosk-zero-w.yaml`) → exit 0.
  3. `tools/reproducibility-gate.sh --image …rootfs.ext4` → passed.
  4. `just kiosk-ota` → 118 713 029 B bundle, md5 MATCH, installed into the **inactive** slot; the
     other slot left bootable and RAUC counters at 3/3 throughout. `just kiosk-reboot`.
  5. Deployed the harness; dry-run first with `BOOTLOOP_DRYRUN=1` to prove the collector fires and
     does *not* reboot; `systemctl enable bootloop.service`; one reboot started the loop at
     23:37:28 EDT.
  6. The loop ran unattended. Per boot it waits for `NTPSynchronized=yes` or a 120 s cap, then for
     uptime ≥ 90 s, appends one field-keyed line, and reboots only as the last statement. It is
     bounded at N=40 and stoppable by a `/data/bootloop/STOP` file; it self-disabled at `count=40`.
  7. Harvested `/data/bootloop/bootloop.log`, ran `analyze-bootloop.sh` over it, tore the harness
     down and verified removal.
  8. Separately, `earliest-ssh-capture.sh` was run twice on this image: once against a **re-boot of
     an already-booted slot**, and once against a **fresh slot straight after an OTA**, made by
     re-running the OTA above into the other slot. The distinction is the point of the run — see
     Findings.
- **Raw capture:** [`runA-bootloop.log`](runA-bootloop.log) (40 raw lines),
  [`runA-bootloop-summary.txt`](runA-bootloop-summary.txt),
  [`runA-gate-image.txt`](runA-gate-image.txt),
  [`runA-onboard-buildinfo.txt`](runA-onboard-buildinfo.txt),
  [`runA-warmslot-earliest-ssh.txt`](runA-warmslot-earliest-ssh.txt),
  [`runA-freshslot-earliest-ssh.txt`](runA-freshslot-earliest-ssh.txt),
  [`runA-pretimesyncd-witness.txt`](runA-pretimesyncd-witness.txt).

### Run B — bench, commit `a9eb3a9`

- **Board:** the same bench board, Raspberry Pi Zero W Rev 1.1. Prod was not contacted.
- **Image commit:** `a9eb3a914793816881e7350ae21d3a2f49f1fbbc`, confirmed twice. Host-side:
  `tools/reproducibility-gate.sh --image` printed `ok image names HEAD (a9eb3a9…)`, and a `debugfs`
  read of the same rootfs confirmed `10-persist-clock.conf` is present in it —
  [`runB-gate-image.txt`](runB-gate-image.txt). On the board:
  `meta-wisekiosk    = HEAD:a9eb3a914793816881e7350ae21d3a2f49f1fbbc` —
  [`runB-onboard-fix-health.txt`](runB-onboard-fix-health.txt).
- **Scripts deployed (each, with disposition):** the same four one-off artifacts as Run A, unmodified
  — `bootloop-collect.sh` (sha256 re-verified on the device against Run A's), `bootloop.service`
  (still the reconstruction described above), `earliest-ssh-capture.sh` and `analyze-bootloop.sh`.
  All are committed in this directory. The only variable between the runs was the image.
- **Procedure:**
  1. `git checkout --detach a9eb3a9`; `--tree` gate passed; `just build` → exit 0; `--image` gate
     passed.
  2. **Cleared the stale `/data/systemd-timesync`** left by an earlier session before installing, so
     the fix had to create and populate the directory itself and could not appear to work on
     inherited state.
  3. `just kiosk-ota` into the inactive slot; reboot. Verified the mechanism on-device, then tested
     it against timesyncd restarts.
  4. **Second OTA, fix → fix, into the other slot.** This is the step that actually tests
     persistence: the *first* fix boot inherits nothing to persist, so one OTA cannot demonstrate the
     claim. `/data` clock mtime immediately before this OTA was recorded —
     [`runB-preota2-state.txt`](runB-preota2-state.txt).
  5. Rebooted and captured at earliest SSH with the same `earliest-ssh-capture.sh` Run A used.
  6. Re-armed the byte-identical boot-loop harness for a like-for-like N=40 corpus, then tore it
     down and verified removal.
- **Raw capture:** [`runB-bootloop.log`](runB-bootloop.log) (40 raw lines),
  [`runB-bootloop-summary.txt`](runB-bootloop-summary.txt),
  [`runB-gate-image.txt`](runB-gate-image.txt),
  [`runB-onboard-fix-health.txt`](runB-onboard-fix-health.txt),
  [`runB-freshslot-earliest-ssh.txt`](runB-freshslot-earliest-ssh.txt),
  [`runB-freshslot-bootstart.txt`](runB-freshslot-bootstart.txt),
  [`runB-clock-correction-point.txt`](runB-clock-correction-point.txt),
  [`runB-restart-resilience-rapid.txt`](runB-restart-resilience-rapid.txt),
  [`runB-restart-resilience-spaced.txt`](runB-restart-resilience-spaced.txt),
  [`runB-namespace-regression-check.txt`](runB-namespace-regression-check.txt).

## Configuration under test

The tree facts the runs rest on.

**The board has no RTC and no fake-hwclock.** Every boot starts at systemd's compiled-in build-time
floor and only a recorded timestamp or NTP moves it forward — the tree stated this before the
investigation, in the host-skew workaround's own comment at `justfiles/ota.just:243-246` as of commit
`34a917b`. The floor is visible in the captures as `System time before build time, advancing clock`
at monotonic 3.43 s ([`runB-clock-correction-point.txt`](runB-clock-correction-point.txt)) and as a
first kernel journal line dated `2025-05-29`
([`runA-onboard-buildinfo.txt`](runA-onboard-buildinfo.txt)).

**Partitioning is A/B with a persistent `/data`.** `p2` is rootfs.0 (A), `p3` is rootfs.1 (B), `p4`
is `/data`, which RAUC never touches. On the fix image the bind source resolves to `/dev/mmcblk0p4`
([`runB-onboard-fix-health.txt`](runB-onboard-fix-health.txt)), i.e. the `/data` partition and not
the rootfs slot.

**The signing certificate's validity floor is what makes a cold clock fatal.** The fleet key is
gitignored and lives outside the tree; the build wires it in at `kiosk-zero-w.yaml:210-213`
(`AUTONOMOS_RAUC_KEY_DIR` / `_KEY_FILE` / `_CERT_FILE` / `_KEYRING_FILE`). The floor itself is read
off the bundle: `CN = WiseKiosk Signing Key 2026`, `Not Before: Aug 15 02:56:16 2026 GMT`
([`runB-freshslot-earliest-ssh.txt`](runB-freshslot-earliest-ssh.txt)). A clock at the 2025 image
floor is below it, so signature verification fails before the bundle is ever read.

**The fix under test, as it sits in the tree.** The recipe
`meta-wisekiosk/recipes-core/kiosk-timesync-persist/kiosk-timesync-persist_1.0.bb` installs two
files and auto-enables the oneshot (`:15-16`, `:18-24`). The drop-in
`meta-wisekiosk/recipes-core/kiosk-timesync-persist/files/10-persist-clock.conf:16` carries
`BindPaths=-/data/systemd-timesync:/var/lib/systemd/timesync`, ordered behind the staging oneshot and
`data.mount` at `:12-13`. The leading `-` on the source makes a missing
`/data/systemd-timesync` skip the bind instead of failing timesyncd's namespace setup
(`226/NAMESPACE`), so a degraded `/data` leaves the board running NTP non-persistent rather than with
no time source at all. The oneshot
`meta-wisekiosk/recipes-core/kiosk-timesync-persist/files/kiosk-timesync-dir.service:22` creates and
chowns the bind source in one statement, ordered `After=data.mount`,
`Before=systemd-timesyncd.service` at `:10-11`. It is a `BindPaths` and not a symlink because
timesyncd ships `ProtectSystem=strict`: a write outside the sandbox's writable set fails EROFS and
systemd swallows that at `log_debug`, so a symlink would be a silent no-op.

**Image wiring:** `kiosk-zero-w.yaml:112` adds `kiosk-timesync-persist` to `IMAGE_INSTALL:append`.
Run A's image predates that line, which is why the units are absent there.

**The host-skew workaround (baseline `34a917b`).** On `34a917b`, `justfiles/ota.just:242-255` force-set
the device clock from the host before every install. On this branch, `justfiles/ota.just:242-253`
reports the skew and does not correct it, so a persistence failure surfaces as the documented
`certificate is not yet valid` refusal rather than being masked by the host.

**NTP servers are not configured in this tree**, so timesyncd uses its compiled-in defaults; the
captures show it contacting `time3.google.com`
([`runB-freshslot-bootstart.txt`](runB-freshslot-bootstart.txt)).

## Metrics

One table per run. Run A's corpus and Run B's corpus are never merged.

### Run A — image `34a917b`, N = 40 boots, 2026-08-25 23:39:10 → 2026-08-26 00:47:47 EDT

| metric | value |
|---|---|
| N boots completed | 40 / 40 |
| `dns != ok` | 0 / 40 |
| `synchronized != yes` | 0 / 40 |
| `ntp_sync_s` min | 29.752144 s |
| `ntp_sync_s` max | 58.809002 s |
| `ntp_sync_s` mean | 55.438640 s |
| `ntp_sync_s` median | 56.049667 s |
| `ntp_sync_s` sd | 4.210532 s |
| `ntp_sync_s` spread | 29.056858 s |
| RAUC counter < 3 | 0 / 40 (`A_LEFT=3 B_LEFT=3` every boot) |
| non-empty `pstore` | 0 / 40 |
| `mmc_err > 0` | 0 / 40 |

Source: [`runA-bootloop-summary.txt`](runA-bootloop-summary.txt), computed by
[`analyze-bootloop.sh`](analyze-bootloop.sh) over [`runA-bootloop.log`](runA-bootloop.log).

**The spread is one outlier and is reported as one.** 39 of the 40 boots fall in 55.366–58.809 s.
Boot 13 alone synced at 29.752 s, and its `ntp_contact_s` was 29.751 — `wlan0` and DNS simply came up
early on that boot, not a sync anomaly. Excluding it, n = 39: mean **56.097 s**, median **56.076 s**,
sd **0.622 s**, spread **3.443 s**.

`ntp_sync_s − ntp_contact_s` averaged 0.0077 s over all 40 boots, maximum 0.0183 s. Sync follows
contact essentially instantly, so the window is time-to-reach-a-time-server, not
time-to-agree-with-one.

### Run B — image `a9eb3a9`, N = 40 boots, 2026-08-26 01:29:39 → 02:38:26 EDT

| metric | value |
|---|---|
| N boots completed | 40 / 40 |
| `dns != ok` | 0 / 40 |
| `synchronized != yes` | 0 / 40 |
| `ntp_sync_s` min | 29.191336 s |
| `ntp_sync_s` max | 57.725337 s |
| `ntp_sync_s` mean | 55.534233 s |
| `ntp_sync_s` median | 56.216116 s |
| `ntp_sync_s` sd | 4.294302 s |
| `ntp_sync_s` spread | 28.534001 s |
| RAUC counter < 3 | 0 / 40 (`A_LEFT=3 B_LEFT=3` every boot) |
| non-empty `pstore` | 0 / 40 |
| `mmc_err > 0` | 0 / 40 |

Source: [`runB-bootloop-summary.txt`](runB-bootloop-summary.txt), computed by
[`analyze-bootloop.sh`](analyze-bootloop.sh) over [`runB-bootloop.log`](runB-bootloop.log). The
`226/NAMESPACE` count is deliberately *not* in this table: it was counted over the whole persistent
journal, a wider scope than these 40 boots, and is reported with that scope in Findings.

Same shape, including exactly one sub-50 s outlier — boot 8 at 29.191 s. Excluding it, n = 39: mean
**56.210 s**, median **56.249 s**, sd **0.443 s**, spread **2.177 s**.

## Findings

**Hypothesis: "DNS at boot is the fault" — DROPPED.** This was the ticket's framing. Run A's corpus
records `dns != ok` 0/40 and `synchronized != yes` 0/40; Run B's records the same 0/40 and 0/40 on
its own image. The analyzer was seeded with a DNS failure and did report it, so the zeros are a
measurement, not a silent pass. Decided by Run A, and unchanged by Run B.

**Hypothesis: "The real cost is that no clock survives an OTA" — CONFIRMED.** Decided by the
fresh-slot arm of each run, and this is the headline result.

The boot loop reboots a slot that has *already booted*, so its rootfs `clock` file was refreshed at
the previous shutdown. That is not where the baseline fails, and measuring only it would have missed
the defect: on the baseline, a re-boot of an already-booted slot reached first SSH at uptime 28.09 s
with the clock correct, `NTPSynchronized=yes` and `rauc info` rc=0
([`runA-warmslot-earliest-ssh.txt`](runA-warmslot-earliest-ssh.txt)). So the control was re-run as
the true mirror of the Run B test — a fresh slot straight after an OTA, whose rootfs `clock` file is
only as new as the image:

| fresh slot after an OTA, at first SSH | Run A (`34a917b`), n = 1 | Run B (`a9eb3a9`), n = 1 |
|---|---|---|
| uptime at measurement | 39.63 s | 39.34 s |
| `NTPSynchronized` at that moment | no | no |
| clock reading | `2025-05-29T14:48:58-0400` | `2026-08-26T01:26:27-0400` |
| clock error vs true time | ~15 months | ~seconds |
| `rauc info` on a real bundle | rc=1, `certificate is not yet valid` | rc=0, signature verified |

This is a synthesis across the two runs, not a blended corpus: each column is that run's own
measurement, taken by the same script at effectively the same point in the boot (39.63 s vs 39.34 s)
and both before NTP sync. **It is n = 1 per arm.** The result is mechanistic and categorical rather
than distributional — a certificate either is or is not yet valid — but one sample per arm is one
sample per arm. Captures: [`runA-freshslot-earliest-ssh.txt`](runA-freshslot-earliest-ssh.txt) and
[`runB-freshslot-earliest-ssh.txt`](runB-freshslot-earliest-ssh.txt).

The mechanism behind the Run B column is caught in the log
([`runB-clock-correction-point.txt`](runB-clock-correction-point.txt)):

```
[   16.722149] systemd[1]: Starting Network Time Synchronization...
[   18.961484] systemd-timesyncd[181]: System clock time unset or jumped backwards,
                 restored from recorded timestamp: Wed 2026-08-26 02:36:48 EDT
[   19.068533] systemd[1]: Started Network Time Synchronization.
```

The clock is corrected at monotonic **18.96 s** from the `/data` record. That is one boot's reading,
so it is not subtractable from the **~55.5 s Run B mean** time-to-NTP-sync, which is an average over
40 boots; the comparable single-boot figure is the fresh slot, where NTP sync landed at monotonic
**58.15 s** ([`runB-freshslot-bootstart.txt`](runB-freshslot-bootstart.txt)). Either way the ordering
is what carries: the record restores a real clock within a few seconds of timesyncd starting, tens of
seconds before any NTP packet lands. That ordering is an **n = 1 observation**, not a corpus result —
`bootloop-collect.sh:103` records `ntp_contact_s`, `ntp_sync_s`, `synchronized`, `dns`, the RAUC
counters, pstore and mmc errors, and **no clock-restore field at all**, so neither 40-boot log
contains a single `restored from recorded timestamp` line to count. The restore is witnessed only by
the two single-boot captures above, matching the n = 1 fresh-slot arm noted under Limits. On the fix
image the
bind is live inside timesyncd's own namespace —
`/proc/<MainPID>/mountinfo` shows `/systemd-timesync /var/lib/systemd/timesync … ext4 /dev/mmcblk0p4`
([`runB-onboard-fix-health.txt`](runB-onboard-fix-health.txt)). `findmnt` from an ordinary shell
reports "not a mountpoint" on a *working* fix, because `BindPaths` exists only inside the unit's
namespace; a `findmnt`-based check would have looked like a failure on a healthy board.

One further baseline capture shows the same refusal mechanism from a different angle. A device-side
witness that fires before timesyncd, on an *already-booted* slot, caught the board at uptime 16.14 s
with the clock at `2025-05-29T14:48:34` and `rauc info` rc=1
([`runA-pretimesyncd-witness.txt`](runA-pretimesyncd-witness.txt)). It is not a fresh-slot
measurement — one reboot later the warm-slot capture answered rc=0 at uptime 28.09 s — so it
corroborates *what a cold clock does to an install*, not the fresh-slot condition itself. That
condition is measured only by the table above.

**Hypothesis: "The fix shrinks the sync window" — REJECTED, and the claim it is often confused with
is the one that holds.** Time-to-NTP-sync did not change and was never expected to: it is gated by
`wlan0` appearing and the DNS/NTP round trip, none of which the fix touches. Run A mean 55.439 s,
Run B mean 55.534 s — separate corpora, each in its own table above, and statistically
indistinguishable at these spreads. **The window did not shrink.** What collapsed is the clock's
*error* during that window, from ~15 months to seconds, per the fresh-slot table. Anyone quoting this
investigation as evidence that the fix makes the board sync faster is quoting it wrong.

**Regression check — CLEAN.** Across the 40 boots of the fix image in Run B's corpus: zero dropped
RAUC boot counters, zero DNS failures, zero unsynchronized boots, zero pstore records and zero mmc
errors. The namespace class is counted at a wider scope — `226/NAMESPACE` occurrences and
`kiosk-timesync-dir` failures were both **0 across the whole persistent journal on this image, 88
recorded boots**, which spans Run B's 40 plus the earlier fix boots
([`runB-namespace-regression-check.txt`](runB-namespace-regression-check.txt)). On the fresh slot
`kiosk-timesync-dir.service` reported `Result=success`, `ExecMainStatus=0`, `NRestarts=0`
([`runB-freshslot-bootstart.txt`](runB-freshslot-bootstart.txt)). Under a restart stress test, 8 timesyncd restarts spaced 12 s apart were 8/8 active
with the bind present every time
([`runB-restart-resilience-spaced.txt`](runB-restart-resilience-spaced.txt)). A first attempt at 10
back-to-back restarts saw one failure at restart 6, and the journal names the cause as systemd's own
5-starts-per-10 s burst limit — `Start request repeated too quickly` /
`start-limit-hit`, not `226/NAMESPACE`, whose count stayed 0 — so that is an artifact of the test
method, and it recovered by itself on restart 7
([`runB-restart-resilience-rapid.txt`](runB-restart-resilience-rapid.txt)). That capture's
`timesyncd failures this boot: 2` is not two failures: the harness greps log lines, and the one
start-limit event emits two of them (`Start request repeated too quickly` and `Failed with result
'start-limit-hit'`). One event, counted twice.

### Limits to carry with these findings

- **The fresh-slot result is n = 1 per run.** Stated again here because it is the headline.
- **`bootloop.service` is a reconstruction**, not the 2026-08-17 original, which does not survive.
  `bootloop-collect.sh`, which produced every number in both corpora, is byte-identical to the
  harness of record.
- **A per-boot journal reconstruction was attempted and abandoned as unsound**, because journald had
  vacuumed the older boots on this device. Nothing in this write-up rests on it. One committed
  capture carries its residue: the line
  `boots where kiosk-timesync-dir ran cleanly: 1 ; without a clean record: 39` inside
  [`runB-namespace-regression-check.txt`](runB-namespace-regression-check.txt) is **a broken query,
  not a finding** — the "39 without a clean record" are boots whose journals no longer exist. The
  whole-journal counts in the same file (`226/NAMESPACE … 0`) are sound.
- **The baseline's missing "restored from recorded timestamp" line was never observed.** That boot's
  journal was vacuumed. That the baseline had nothing useful to restore from is an *inference* from
  the live measurement — the clock still sat at the image floor at 39.63 s — not a log line anyone
  read.
- **Network variation is not controlled.** The two loops ran about 2 h apart against the same
  compiled-in default NTP servers, and the first few minutes of Run A's loop overlapped a host build.
- **The prod board was never contacted.** This investigation says nothing about prod.

## Changes configured as a result

- **Code change:** `kiosk-timesync-persist` — the recipe at
  `meta-wisekiosk/recipes-core/kiosk-timesync-persist/kiosk-timesync-persist_1.0.bb` with its
  `kiosk-timesync-dir.service` oneshot and `10-persist-clock.conf` drop-in, wired into the image at
  `kiosk-zero-w.yaml:112` — and `justfiles/ota.just:242-253`, which reports the host/device skew
  instead of force-setting the device clock (the `34a917b:242-255` behavior). Both ship in PR #59
  persist the clock across an OTA, which closes #31.

Every one-off script named above is committed in this directory. Every durable change links to its
recipe/PR.
