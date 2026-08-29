# Are the stale layer pins this image's real CVE exposure, or is it the kernel?

| | |
|---|---|
| **Issue** | #80 Triage the layer-currency findings (bump stale layer pins) |
| **Status** | concluded → code change |
| **Opened / concluded** | 2026-08-28 / 2026-08-29 |

The ticket asked which stale pins to bump. The pins were not the exposure: of the three repositories
behind their branch heads, poky closed 16 unpatched findings of 3941 and the other two closed none.
**94.5% of the image's unpatched findings — 3723 of 3941 — were the kernel**, held at 6.6.63 by a
weak upstream default while the branch it comes from, `rpi-6.6.y`, had taken no commit in 17 months.
Mainline 6.6 is still LTS and that is beside the point: the Raspberry Pi fork stopped merging
kernel.org stable into it in March 2025, so the LTS runway exists but the delivery path to this board
does not. `rpi-6.12.y` is the only RPi branch still being merged into, and the already-pinned
meta-raspberrypi layer already shipped a 6.12.93 recipe — no pin bump involved. Selecting it took
unpatched findings from **3941 to 837 (−78.8%)** and the kernel's own from **3723 to 635 (−82.9%)**,
cross-checked by two tools reading the manifests by different paths. It also **re-opened 135 kernel
findings**, and the pin bumps that rode along cost a **4 h 52 m WebKit rebuild for zero closures**.
The kernel jump was validated on the bench board over an OTA: 6.12.93 boots, the SDIO WiFi driver
behind the board's only lifeline survives, and the display renders live.

## Test runs

Four runs. Runs 1 and 2 are audit builds on the build host, where the experiment is the build and
there is no board; the machine and the image commit are named instead. Runs 3 and 4 are the bench
board on two different images, so they are two runs and their numbers never share a table. The prod
board was contacted once, read-only, and that capture is **not** a run — see Run 4.

| Run | Board (role) | Image commit | Harness / scripts | Result (1 line) |
|---|---|---|---|---|
| 1 | none — build host, `MACHINE=raspberrypi0-wifi` | `58ce782` | `just cve-build`, `just cve`, `just kernel-cve` — all durable, PR #83 | Baseline: 3941 unpatched, 3723 of them the kernel at 6.6.63; `kernel-cve` refuses for want of compiled-sources SPDX. |
| 2 | none — build host, `MACHINE=raspberrypi0-wifi` | `c9905c4` | the same durable recipes, plus `just cve-delta` over runs 1↔2 | Post-change: 837 unpatched, kernel 635; the kernel move is labelled `software`; `kernel-cve` refuses again, for a different reason — an upstream defect. |
| 3 | bench · Pi Zero W | `a9eb3a9` | `tools/kiosk-ssh.sh`, `just soak-summary`, `just screenshot` — all durable | Pre-OTA baseline on 6.6.63: slot A booted and good, WiFi associated, no failed units, 288-sample soak settled. |
| 4 | bench · Pi Zero W | `c9905c4` | `just kiosk-ota`, `just kiosk-reboot`, `just soak-summary`, `just screenshot` — all durable | 6.12.93 installed into slot B, booted, marked good; WiFi and display survive the jump; slot A left on 6.6.63 as the fallback. |

No one-off script was written for this investigation and nothing was deployed to a board — every
command above is a Justfile recipe shipping in this repository, which is why R2 has nothing to
record. The single exception ran on the build host and never touched a device: see
[Limits to carry with these findings](#limits-to-carry-with-these-findings) on the out-of-tree copy
of poky's kernel-CVE filter.

Raw captures are **not committed beside this README**. They carry the bench board's LAN address, its
hostname and the site SSID, and this repository is public; the screenshots are framebuffer captures
of the live page. They are named in backticks below and held out of tree.

### Run 1 — build host, commit `58ce782`

- **Board:** none. This run is a build, not a device test. The build host is 8 cores / 11 GB; the
  image is built for `MACHINE=raspberrypi0-wifi`, the same machine both boards run.
- **Image commit:** `58ce7822293d71522f61877a0728b21865023295`, recorded by the audit snapshot's own
  `snapshot.json` (`commit`, `machine`, `datetime` `20260828043708`) and carried in the image at
  `KIOSK_BUILDINFO_REV`. This is the branch point — the tooling of PR #83 as merged through
  `#71 CVE delta-triage`, before any change in this investigation.
- **Scripts deployed:** none. `just cve-build` (`Justfile:196`), `just cve` (`Justfile:156`) and
  `just kernel-cve` (`Justfile:176`) are durable recipes shipping in this repository.
- **Procedure:** `just cve-build` — a full build with `includes/cve-audit.yaml` joined on, which
  inherits `cve-check` and writes a `.cve` manifest beside the image. `Justfile:199` then calls
  `tools/cve-delta.py snapshot`, which copies the manifest, the image manifest and a package map into
  `~/.cache/wisekiosk/cve-history/raspberrypi0-wifi/<datetime>-<shortsha>/`. `just cve` was run over
  the manifest for the roll-up, and `just kernel-cve` to establish the pre-change behaviour of the
  compiled-sources filter.
- **Raw capture:** the snapshot directory `20260828043708-58ce782` (`manifest.cve` 22 MB,
  `pkgmap.json`, `image.manifest`, `snapshot.json`), which is the durable record — the deploy
  directory has since been turned over twice and its `.cve` file no longer exists.

### Run 2 — build host, commit `c9905c4`

- **Board:** none, as Run 1. Same host, same `MACHINE`.
- **Image commit:** `c9905c4df3f109681f953d386d7c610e4abb1676`, confirmed three ways: the image's own
  `KIOSK_BUILDINFO_REV` in `…rootfs-20260828163401.testdata.json`, the snapshot's `snapshot.json`,
  and `tools/reproducibility-gate.sh --image`, which refuses an image not naming HEAD.
- **Scripts deployed:** none. As Run 1, plus `just cve-delta` (`Justfile:171`), which compares the
  newest snapshot with the previous one.
- **Procedure:** the tooling of Phase 1, then the kernel move, then the pin bumps were committed and
  pushed (the reproducibility gate refuses a dirty or unpushed tree), then `just cve-build`. Three
  attempts were needed and only the third is this run — see
  [The build took three attempts](#the-build-took-three-attempts-and-only-the-third-is-a-measurement),
  which also states the two gates every number here is conditional on. `just cve`, `just cve-delta`
  and `just kernel-cve` were then run over the result.
- **Raw capture:** snapshot `20260828163401-c9905c4`; the build log `cve-build3.log` (9467 lines,
  zero `ERROR` lines) and `cve-delta.out` (3388 lines), both out of tree.

### Run 3 — bench, commit `a9eb3a9`

- **Board:** bench (the OTA, reboot and abuse target), Raspberry Pi Zero W, BCM2835, `armv6l`,
  512 MB. Read-only throughout: this run establishes what the board looked like before the kernel
  jump.
- **Image commit:** `a9eb3a914793816881e7350ae21d3a2f49f1fbbc`, read off the board —
  `grep ^meta-wisekiosk /etc/buildinfo` gives
  `meta-wisekiosk = HEAD:a9eb3a914793816881e7350ae21d3a2f49f1fbbc`. That is the #31 clock-persistence
  image, three commits before this branch began.
- **Scripts deployed:** none. Every read went through `tools/kiosk-ssh.sh`; the soak read is
  `just soak-summary` and the screenshot `just screenshot`, both durable.
- **Procedure:** the two boards on the LAN were identified by logging in and reading `hostname`
  rather than by remembered address — a Raspberry Pi OUI says "a Pi", not "which Pi". Then, on the
  bench board only: `uname -r`, `rauc status`, the U-Boot boot counters, `wlan0` state and
  association, the `brcmfmac` module and firmware version, unit states, `/data` free space, load and
  entropy. `just soak-summary <bench> 288` read the last 288 samples — 24 h — of the soak log on
  `/data`.
- **Raw capture:** `bench-pre-baseline.txt`, `bench-pre-soak.txt`, `bench-pre-status.txt`, and the
  screenshot `phase4b-bench-pre-ota-20260828.png`.

### Run 4 — bench, commit `c9905c4`

- **Board:** the same bench board. This is the run that puts 6.12.93 on hardware.
- **Image commit:** `c9905c4df3f109681f953d386d7c610e4abb1676`, confirmed twice. Host-side, before
  delivery: `tools/reproducibility-gate.sh --image` passed against the rootfs, and again as `--tree`
  at send. On the board, after the OTA: `/etc/buildinfo` reads
  `meta-wisekiosk = 80-cve-triage:c9905c4…`. It is the same commit Run 2 measured, so the CVE numbers
  and the hardware result describe one image.
- **Scripts deployed:** none. `just kiosk-ota` builds the bundle, re-runs the reproducibility gate,
  checks slot fit and `/data` space, transfers with an end-to-end md5 and calls `rauc install`;
  `just kiosk-reboot`, `just soak-summary` and `just screenshot` are likewise durable.
- **Procedure:**
  1. Preconditions re-derived rather than remembered — the deploy directory had moved on from the
     artifact recorded at the start of the phase, so both gates were re-run against the *current*
     rootfs, and the board was re-checked as still pre-OTA on 6.6.63 with slot A booted.
  2. The lifeline argument was re-derived from the device before anything was written. `/boot` on
     this board is a shared vfat partition with no A/B protection, so "does the kernel travel inside
     the rootfs slot?" is the question the whole safety case rests on. Two independent reads settled
     it: `boot.scr`, read off the device, sets `BOOT_DEV` to the *selected slot* and loads
     `boot/uImage` from there, and a `debugfs` read of the new rootfs shows `uImage -> uImage-6.12.93`
     inside the slot payload. The `uImage` visible under the runtime `/boot` mount is a flash-time
     leftover that masks the rootfs's own `boot/` and is not what boots.
  3. `just kiosk-ota` into the inactive slot (B). Slot A was left bootable and marked good
     throughout.
  4. `just kiosk-reboot`, with the SSH control master closed first because a reboot orphans it.
  5. Validation: kernel version, `/etc/buildinfo`, slot and boot-counter state, `rauc` mark-good,
     `boot-complete.target`, `wlan0` up/associated/leased, the `brcmfmac` module and firmware, the
     `kiosk-netcheck` verdict, failed units, machine-id, entropy, `dmesg`, a screenshot and a fresh
     soak window.
  6. **Rollback was not exercised**, because nothing failed. `just kiosk-rollback` remains the
     documented, never-exercised path, and slot A still holds the 6.6.63 image marked good.
- **Raw capture:** `run3-ota.txt`, `run3-reboot.txt`, `run3-validate.txt`, and the screenshot
  `phase4b-bench-post-ota-20260828.png` (captured 2026-08-29; the filename's date stem is wrong and
  is left as captured rather than silently corrected).

**The prod reference capture is not a run.** One read-only `just screenshot` was taken against the
prod board, to give a human something to compare the bench render against; the device guard
classifies a screenshot as observation, and nothing else was run against prod in this investigation.
It is not numbered as a run because **its image commit was never read**, and R1 is explicit that an
unverifiable "probably this build" is not a commit. It therefore supports exactly one claim — that
the two boards render the same page layout — and no metric in this document is derived from it. The
capture is `phase4b-prod-reference-20260828.png`.

## Configuration under test

The tree facts the runs rest on. Everything under `sources/` is gitignored and fetched by kas at the
pin named beside it.

**The kernel was selected by a weak upstream default, and nothing in this repository said so.**
meta-raspberrypi is pinned at `6ca1f75` (`includes/platforms/raspberrypi.yaml:9`), which was and
remains the head of its `scarthgap` branch — the pin was *current*. Inside it,
`conf/machine/include/rpi-default-versions.inc:3` sets
`PREFERRED_VERSION_linux-raspberrypi ??= "6.6.%"`, and a tree-wide search found no override anywhere:
not in `kiosk-zero-w.yaml`, not in `includes/`, not in `meta-wisekiosk/`. Because it is `??=`, one
`local_conf_header` line overrides it — no bbappend and no layer patch. The same pinned layer already
shipped `linux-raspberrypi_6.12.bb` at 6.12.93, structurally identical to the 6.6 recipe apart from
four version and `SRCREV` lines.

**The override, as it now sits in the tree:** `kiosk-zero-w.yaml:52` sets
`PREFERRED_VERSION_linux-raspberrypi = "6.12.%"` as a hard `=`, with the reason at `:49-50`.

**One kernel patch was dropped and one kept.** Both were carried by
`meta-wisekiosk/recipes-kernel/linux/linux-raspberrypi_%.bbappend`, a `%` wildcard bbappend that
applies to whichever version is selected — so a `PREFERRED_VERSION` change drags the patches onto the
new source with no other edit. `brcmfmac-857282b819cb.patch` was upstreamed at 6.6.66 and is present
in 6.12.93, so its context no longer exists and `do_patch` would fail; it is deleted along with its
`SRC_URI` line. `brcmfmac-52e8726d6782.patch` was never backported to either series and is kept
(`linux-raspberrypi_%.bbappend:13`), with its rationale rewritten at `:3-12` — the old text reasoned
entirely about 6.6.63 and would have become false.

**Three pins were bumped** in `includes/base.yaml`: poky to `69ae79bf5a` (`:52`),
meta-openembedded to `bec755063a` (`:63`) and meta-virtualization to `f980aefbc8` (`:81`), each
confirmed twice — by `just currency` and by a direct `git ls-remote` — and `kas-container checkout`
verified clean at the new SHAs with both meta-autonomos patches still applying.

**The compiled-sources flag is audit-only.** `includes/cve-audit.yaml:19` sets
`SPDX_INCLUDE_COMPILED_SOURCES:pn-linux-raspberrypi = "1"`, which is what makes `just kernel-cve`
measurable at all. It is a `do_create_spdx` vardep, so a build predating it cannot supply the file
list from sstate — which is why Run 1 could not produce a filtered number even in principle.

**The tools the numbers come from all ship in this repository** and are the subject of PR #83:
`just cve` (`Justfile:156`), `just cve-delta` (`Justfile:171`), `just kernel-cve` (`Justfile:176`),
`just currency` (`Justfile:181`), `just preferred-version` (`Justfile:186`) and `just gap`
(`Justfile:191`). What each answers is [`docs/cve-and-sbom.md`](../../cve-and-sbom.md) and
[`docs/layer-currency.md`](../../layer-currency.md); this document does not restate them.

## Metrics

One table per run.

### Run 1 — build host, image `58ce782`, baseline audit build

Source: `just cve` over `…rootfs-20260828043708.cve`, and the snapshot of the same manifest.

| metric | value |
|---|---|
| total records | 18374 |
| Unpatched | **3941** |
| Patched / Ignored | 14291 / 142 |
| packages carrying ≥1 unpatched | 19 |
| unpatched — meta-raspberrypi (kernel) | **3723** |
| unpatched — meta-oe | 117 |
| unpatched — meta (poky) | 95 |
| unpatched — meta-lts-mixins | 6 |
| critical / high / medium / low | 201 / 1709 / 1987 / 44 |
| kernel version in the manifest | `linux-raspberrypi 1_6.6.63+git` |
| coverage | 96 recipes carry CVE records; 86 checked and carry none; 20 installed packages map to no recipe record |
| `just kernel-cve` | **refuses, exit 2** — "lists no compiled sources, so the filter would measure nothing" |

The single largest package is `linux-raspberrypi` at 3723, then `imagemagick` at 113, `libsoup` 18,
`gstreamer1.0` 15.

### Run 2 — build host, image `c9905c4`, post-change audit build

Source: `just cve` over `…rootfs-20260828163401.cve`; the delta line from `just cve-delta` over the
snapshot pair.

| metric | value |
|---|---|
| total records | 18377 |
| Unpatched | **837** |
| Patched / Ignored | 17397 / 143 |
| packages carrying ≥1 unpatched | 17 |
| unpatched — meta-raspberrypi (kernel) | **635** |
| unpatched — meta-oe | 117 |
| unpatched — meta (poky) | 79 |
| unpatched — meta-lts-mixins | 6 |
| critical / high / medium / low | 44 / 323 / 431 / 39 |
| kernel version in the manifest | `linux-raspberrypi 1_6.12.93+git` |
| coverage | 96 recipes carry CVE records; 86 checked and carry none; 20 installed packages map to no recipe record |
| `cve-delta` vs Run 1's snapshot | 3381 changes: 5 added, 2 removed, 3374 status-changed |
| `cve-delta` labels | 3358 `software`, 22 `feed`, 1 `annotation` |
| unpatched findings closed | 3239 |
| unpatched findings opened | **135**, all `linux-raspberrypi` |
| build wall time | 6 h 51 m, of which `webkitgtk3 do_compile` alone was **4 h 52 m** |
| `just kernel-cve` | **refuses, exit 2** — a different refusal: `improve_kernel_cve_report.py exited 1: KeyError: 'detail'` |

### Run 3 — bench, image `a9eb3a9`, pre-OTA baseline

| metric | value |
|---|---|
| `uname -r` | 6.6.63 (`#1 Fri Dec 6 10:10:05 UTC 2024 armv6l`) |
| booted slot | rootfs.0 (A), boot status `good` |
| partner slot | rootfs.1 (B), inactive, `good` |
| boot counters | `BOOT_ORDER "A B"`, `BOOT_A_LEFT=3 BOOT_B_LEFT=3` |
| uptime at capture | 2 d 16 h 44 m |
| `wlan0` | UP, LOWER_UP, dynamic lease held |
| WiFi association | 2417 MHz, −60 dBm, rx 65.0 / tx 72.2 MBit/s |
| `brcmfmac` | BCM43430/1, firmware 7.45.98 |
| failed units | 0 |
| `/data` free | 375.3 MB of 479.2 MB |
| loadavg | 0.50 / 0.56 / 0.55 |
| entropy_avail | 256 |

Soak, N = 288 samples over 24.0 h, from the log on `/data`:

| metric | value |
|---|---|
| reboots / browser restarts / samples without a browser | 0 / 0 / 0 |
| `rss_total` range | 170404 – 171120 kB |
| fitted slope | **−12.3 kB/h** (n = 288) |
| peak temperature | 47.1 °C |
| samples throttled | 0 |

Screenshot `phase4b-bench-pre-ota-20260828.png`: `mean=3.898`, so not blank, and the rendered clock
matched the device clock to the second — the render is live, not a frozen frame.

### Run 4 — bench, image `c9905c4`, post-OTA on 6.12.93

| metric | value |
|---|---|
| `uname -r` | **6.12.93** (`#1 Fri Jun 12 11:45:31 UTC 2026 armv6l`) |
| bundle transfer | 120 289 989 B in 45 s (2610 kB/s), end-to-end md5 MATCH |
| host/device clock skew at install | 0 s |
| booted slot | rootfs.1 (B), activated and marked good |
| partner slot | rootfs.0 (A), still `good` on 6.6.63 |
| boot counters after mark-good | `BOOT_ORDER "B A"`, `BOOT_A_LEFT=3 BOOT_B_LEFT=3` |
| time from reboot to reachable | 75 s |
| `boot-complete.target` | reached |
| `wlan0` | UP, LOWER_UP, lease acquired at 17:41:46 |
| WiFi association | −55 dBm, 72.2 MBit/s both ways |
| `brcmfmac` | BCM43430/1, firmware 7.45.98 — identical to Run 3 |
| `kiosk-netcheck` | LAN reachable at 27 s uptime |
| failed units | 0 |
| machine-id | unchanged from before the OTA |
| entropy_avail | 256 |

Soak, N = **3** samples over 0.2 h — a new series, deliberately not blended with Run 3's:

| metric | value |
|---|---|
| reboots / browser restarts / samples without a browser | 0 / 0 / 0 |
| `rss_total` range | 171284 – 172084 kB |
| fitted slope | **not computed — 3 samples cannot support one** |
| peak temperature | 36.3 °C |
| samples throttled | 0 |

Screenshot `phase4b-bench-post-ota-20260828.png`: `mean=4.561`, not blank, and the rendered clock and
date matched the device to the second — live.

## Findings

**Hypothesis: "the stale layer pins are the exposure" — DROPPED.** This was the ticket's framing.
Decided by Run 1 and quantified by Run 2. `just gap poky` found 69 commits naming 56 CVEs, of which
16 intersected the unpatched set across five packages, and Run 2 closed **exactly 16**: expat 10,
curl 3, gnutls 1, glib-2.0 1, and nghttp2 1 as an `Ignored` annotation rather than a code fix. Those
16 are 0.4% of 3941. meta-openembedded's 117 unpatched findings are real but its pin was already
level on the recipes carrying them, so the bump closed none; meta-virtualization contributes zero
recipes to this image, so it could not have closed any. Both were bumped anyway, as currency for its
own sake, on the owner's call to move all three in one PR.

The ticket's own worked example did not survive either: it cited an openssh `CVE_STATUS` commit as
sitting in poky's gap, and that commit turned out to *be* the current pin, not something the gap
contained.

**Hypothesis: "the kernel is the exposure, and 6.6 is a dead branch" — CONFIRMED.** This is the
headline, and it is a reframe of the ticket rather than an answer to it.

The count made it unmissable: 3723 of 3941 unpatched findings, 94.5%, were `linux-raspberrypi`. What
made it *actionable* was that the branch is dead. `rpi-6.6.y` last took a commit on 2025-03-26 and
sits at 6.6.78; `rpi-6.12.y` took one on 2026-08-24, and its head commit subject is literally a merge
of `stable/linux-6.12.y`. Every other `rpi-6.x.y` branch — 6.13 through 6.16 — is frozen too. RPi
maintains one long-lived branch and it is 6.12.

**The "6.6 is LTS until December 2027" argument is true and does not apply.** Mainline 6.6 is an LTS
series at 6.6.155. The board does not run mainline 6.6; it runs the RPi fork, which stopped merging
kernel.org stable in March 2025 and is 77 point releases behind the series it forked from, with no
mechanism to close that. Staying on 6.6 is not choosing a supported kernel; it is choosing an
unsupported one that shares a version number with a supported one.

**The cheap-looking alternative was not cheaper.** Bumping `SRCREV` within 6.6 to the branch head
gains 6.6.63 → 6.6.78, about 3.5 months of fixes, and then dead-ends. It also breaks
`brcmfmac-857282b819cb.patch`, upstreamed at 6.6.66 — the *same* patch the 6.12 move breaks. There is
no bump of any kind that keeps that patch applying, which removes "but 6.12 costs a patch rework" as
a discriminator between the options. Verified by fetching the affected source file at all four refs
and counting the marker hunks, then confirmed on real hardware when `do_patch` succeeded against
6.12.93 in Run 2.

**The measured result, as a synthesis across Runs 1 and 2.** Each column is that run's own
measurement from its own manifest, taken by the same command; this is not a blended corpus.

| | Run 1 (`58ce782`, 6.6.63) | Run 2 (`c9905c4`, 6.12.93 + pins) | change |
|---|---|---|---|
| total unpatched | 3941 | **837** | **−3104 (−78.8%)** |
| kernel | 3723 | **635** | −3088 (−82.9%) |
| meta-oe | 117 | 117 | 0 |
| meta (poky) | 95 | 79 | −16 |
| meta-lts-mixins | 6 | 6 | 0 |
| critical | 201 | **44** | −157 (−78.1%) |
| high | 1709 | **323** | −1386 (−81.1%) |
| medium | 1987 | 431 | −1556 |
| low | 44 | 39 | −5 |

**Two tools reading by different paths agree.** The roll-up reads each `.cve` manifest and reports
3941 → 837, a fall of 3104; `cve-delta` joins the two snapshots through `pkgdata` and independently
computes 3239 closed minus 135 opened = **−3104**. On the kernel alone the roll-up says −3088 and
`cve-delta` says 3223 − 135 = **−3088**. The agreement is the check; either figure alone would be one
tool's word for it.

**The tooling fixes proved themselves on this data, which was the point of doing them first.** Three
in particular:

- **The kernel move is labelled `software`, not `feed`.** All 3358 `linux-raspberrypi` transitions
  carry `[software]`; the 22 `[feed]` labels are genuine NVD movements and the 1 `[annotation]` is
  the nghttp2 `CVE_STATUS` ruling. Before the fix, `cve-delta` read the kernel's version as the
  truncated `1_6.6.63+git` and could not see a version move at all, so it would have attributed the
  largest software change this image has ever had to the CVE feed shifting underneath it. This is the
  fix demonstrating itself on the exact case it was written for.
- **A ruling is now its own category.** `nghttp2 CVE-2026-58055 Unpatched → Ignored` is an
  `annotation` — somebody judged it inapplicable. Counting it inside the 16 closures is right for "no
  longer actionable" and wrong for "the vulnerability is gone", and the label is what lets a reader
  tell those apart.
- **Free prose can no longer take over a record key.** The delta's own footer reports
  `linux-raspberrypi CVE-2024-53144: prose CVE 'CVE-2024-8805' ignored for 'CVE-2024-53144'` — a
  `CVE:` string inside an NVD summary that the shared field regex would previously have accepted as
  the record's identity.

**The honest cost side, which must travel with the headline.**

*135 kernel findings were re-opened.* All 135 are `linux-raspberrypi`, all labelled `software`,
all `Patched → Unpatched`: CVEs that 6.6.63 was judged patched for and 6.12.93 is not. They are
either genuinely present in the 6.12 series and absent from 6.6, or CNA re-judgements. The net is
still −3104 by a wide margin, but "3239 closed" is not the number — the number is 3239 closed and 135
opened, and quoting the first without the second overstates the move.

*The meta-openembedded pin bump cost a 4 h 52 m WebKit rebuild and closed nothing.* This is a
**fourth WebKit-cost trigger**, alongside the three the README already names, and it is now recorded
there. Ruling out the alternative explanation mattered, because five recipes were cleaned mid-phase
and a clean is the obvious suspect: the mechanism says no — `bitbake -c clean` removes a workdir and
stamps but does not change task signatures, so dependents keying off an unchanged output hash cannot
be invalidated by it — and the evidence says no, because the task graph was **7723 tasks in all three
build attempts**, two of which predate any clean. Cleaning five recipes added zero tasks, which is
only possible if webkit was already scheduled for rebuild before anything was cleaned. Note that the
kernel move itself is *not* the trigger: the kernel is provably outside `webkitgtk3`'s dependency
closure, and the one kernel-shaped edge, `linux-libc-headers`, is poky's own recipe versioned by the
poky pin and unmoved by a `PREFERRED_VERSION`.

**Hypothesis: "filtering the kernel's CVEs by compiled sources is a large win" — REJECTED, and the
tool cannot report it anyway.** Two separate results, and conflating them would misreport this in
either direction.

`just kernel-cve` refuses in both runs, but for different reasons, and the difference is the whole
G5 result. In Run 1 it refused because the SPDX document carried no file list — the compiled-sources
flag did not exist yet, and a build predating it cannot supply the list from sstate. In Run 2 that
gate is cleared: the SPDX names **87360 compiled files**, and the tool's own reader and poky's filter
agree on that number. The refusal in Run 2 comes from further downstream — poky's
`scripts/contrib/improve_kernel_cve_report.py:365` dereferences `cve_data[cve]['detail']` without a
guard, and `detail` is an optional key that `cve-check` writes only where a `CVE_STATUS` override
supplied one. Measured against this build's own summary, **not one of the 14802 kernel issue records
has a `detail` key**, so the first CNA record reporting Unpatched over a cve-check Patched crashes
the script. It is deterministic for this image, not environmental. `tools/kernel-cve.py` captured the
helper's stderr and refused rather than printing a partial number, which is the fail-closed design
doing its job — a tool that swallowed the error would have reported a filtered count that meant
nothing.

Sized out of tree, so that the size of the prize is known even though the tool cannot report it:
poky's script was copied to the scratchpad with the single change `['detail']` → `.get('detail')` and
run against the same inputs. **No file in this repository was modified.** It completes, and both
readers still agree at 87360 files:

| figure | value |
|---|---|
| `filtered` — findings dropped because the config does not compile the affected files | **34** |
| `net` — the move in Unpatched | 635 → **2128**, an *increase* of 1493 |
| CVE ids the filter introduces that `cve-check` never had | 3973 (1574 of them Unpatched) |

**`filtered` is 34.** On a kernel whose SPDX lists 87360 compiled source files, this defconfig
excludes very little of what the CNA actually files CVEs against — the compiled-sources idea is
sound and its yield here is two orders of magnitude smaller than the exercise suggests. The
`net` increase is not the filter failing; it is the CNA database being more complete than
`cve-check`'s NVD view and re-judging every kernel CVE against it. On the 14802 ids present both
before and after, the filter is a mild net improvement — 84 closed against 3 opened — and the whole
increase comes from records `cve-check` never scored at all.

### The build took three attempts, and only the third is a measurement

Stated because two of the three produced numbers that would have been wrong, and one of them nearly
became a finding about the kernel bump.

Attempt 1 was killed at exactly 60 m 06 s by the harness's cap on background tasks, mid
`do_cve_check`, with zero bitbake errors. Attempt 2 resumed incrementally and **failed in
`glibc do_compile`** with undefined references to `__wait4`, `__spawni` and `__sysconf` — ordinary
glibc internals, missing from a `libc.a` that attempt 1 had left half-written when its process group
died 5 m 29 s into the same task. That failure was *not* attributed to the poky bump on the strength
of the timeline alone: attempt 3, after cleaning, compiled the same source at the same poky commit in
under nine minutes. The finding's own reproduction was re-run against the fix and did not reproduce.

The clean was necessary rather than precautionary, and the reason is the one that matters here: the
**kernel's** `do_compile` had also been interrupted, and attempt 2 then resumed it to a reported
success. A kernel built over a half-written object tree fails loudly at link time if you are lucky
and miscompiles silently if you are not — and every number in this document is downstream of that
binary. So two gates were set before any attempt-3 figure was trusted, and both were met in attempt
3's own log: `linux-raspberrypi-1_6.12.93+git-r0 do_configure` **and** `do_compile` both succeeded
there, which is positive evidence of a from-scratch rebuild because a recipe restored from sstate
never runs `do_configure`; and `do_image_complete` succeeded. Attempt 3 finished `EXIT=0` with 7723
tasks, all succeeded, and zero `ERROR` lines.

Attempt 2 also emitted **702** `Error adding the same package … twice` errors during CVE summary
generation, from poky's `cve_check_merge_jsons`, which `return`s rather than `continue`s and so
*drops* a package's record when it sees a duplicate. That would make every count in this document an
undercount, so it was tested rather than argued: `build/tmp-*/log/cve` was **moved aside, not
deleted**, preserving its 453 entries as evidence, and attempt 3 ran against an empty directory. It
emitted **zero**. Same code, same commit, same image — the only variable being whether the directory
carried another build's output. The flood is interrupted-run collateral, not a standing defect, and
the earlier caution against asserting attribution was right.

The counts were then gated directly rather than inferred from that. Comparing the two snapshot
manifests: 96 CVE-carrying packages in each, and the set difference taken in **both** directions is
empty — the package name sets are identical, and the record count rose by 3 rather than falling.
There is no dropped-record signature. The 19 → 17 fall in unpatched-*carrying* packages is fully
explained by `glib-2.0` and `nghttp2` each having their last unpatched finding closed, both already
inside poky's 16.

### The hardware result

**Hypothesis: "a six-series kernel jump breaks the SDIO WiFi driver, which is the board's only
lifeline" — DROPPED.** Decided by Run 4. `wlan0` came up, associated at −55 dBm, took a lease at
17:41:46 and held a default route; `brcmfmac` loaded against the same BCM43430/1 chip with the same
firmware 7.45.98 as Run 3. One transient in the netcheck journal — `ip: can't find device 'wlan0'` at
17:41:42, then `LAN reachable at 27s uptime` five seconds later — is the retry loop working as
designed.

That risk was worth naming because the bench board is reachable over exactly one path — SDIO WiFi to
a DHCP lease to `sshd`, with no serial console, no keyboard and no wired fallback. It was
nonetheless **recoverable over the wire** rather than hands-on, and the argument was checked against
the tree rather than remembered: a RAUC bundle writes only the inactive rootfs slot; `kiosk-netcheck`
is ordered `Before=boot-complete.target` and withholds good-marking on a boot with no usable LAN, so
three such boots drain the counter and drop the slot from `BOOT_ORDER` by themselves; and the slot
hook writes only `machine-id` into the new slot, touching nothing in shared `/boot`. The exact
failure being tested for is the failure the device recovers from unattended.

**Display parity: pass**, read element-for-element from the two images rather than inferred — date
and large clock top-left, six park sections in the same order with hours and two attractions each, a
weather block top-right, a METAR panel bottom-right. Differences are the expected ones: the captures
are a day apart, the page rotates attraction rows per section, and the weather figures move. A
pre-existing METAR fetch error present on **both** boards before the OTA had resolved by Run 4, which
confirms it was an upstream application state and never a board fault — and it is recorded here
precisely so that it cannot later be attributed to the kernel.

**One `dmesg` warning is pre-existing and is explicitly not attributed to 6.12.** `FAT-fs
(mmcblk0p1): Volume was not properly unmounted` names the shared, non-A/B-protected boot partition,
which is where a new fault would matter most. The same line appears in the two preceding boots, both
on 6.6.63. The cause is U-Boot's `saveenv` writing `uboot.env` to that partition outside the OS on
every boot, leaving the dirty bit set; `/boot` mounts rw and all its files are readable. No action
taken — writing that partition is the one hands-on-class risk on this board.

### Limits to carry with these findings

- **The 24 h soak on 6.12 is still owed.** Run 4's soak is 3 samples over 12 minutes of a
  freshly-started browser. It establishes that the sampler resumed, the browser came up once and
  stayed up, nothing throttled, and RSS is in the same ballpark as Run 3's settled 170404–171120 kB.
  It establishes nothing about stability, and the +800 kB across it is warm-up, not a leak. A figure
  comparable to Run 3's −12.3 kB/h needs about 24 h on 6.12. This is elapsed time, not an unresolved
  risk.
- **Rollback remains documented and never exercised.** Nothing failed, so nothing was rolled back.
- **The prod board's image commit was never read**, which is why its screenshot is a reference
  capture and not a run.
- **The `filtered = 34` and `net = 635 → 2128` figures are an out-of-tree estimate**, produced by a
  one-line-modified copy of poky's script held in a scratchpad and never committed — this repository
  redistributes no part of poky. `just kernel-cve` itself reports nothing until the upstream defect
  is resolved.
- **`just cve` and `just cve-delta` read the deploy directory, which has since turned over twice.**
  The durable record is the snapshot history under `~/.cache/wisekiosk/cve-history/`, which is where
  every number above was re-derived from when this document was written. `just cve` on a turned-over
  deploy directory reports its skip path, by design, rather than a stale number.
- **`just status <host>` is unusable against the bench board and reports success anyway.**
  `justfiles/device.just:33` runs a bare `ssh` that honours `~/.ssh/known_hosts`, unlike every other
  device recipe, and the board's host key rotates with an image rebuild; each call is suffixed
  `|| true`, so the recipe exits 0 with three host-key errors where the data should be. Not fixed
  here — it is outside this ticket, and the alternative was mutating the user's `known_hosts`. Every
  reading in Runs 3 and 4 went through `tools/kiosk-ssh.sh`, which is unaffected.

### Deliberately not done

- **`imagemagick` was not dropped from the image.** It is 113 of meta-oe's 117 unpatched findings and
  the largest remaining single source after the kernel, but removing a package from the image is a
  different question from triaging CVEs and belongs to its own ticket.
- **The kernel was not tracked past the recipe's own pin.** `rpi-6.12.y` is at 6.12.105; the pinned
  meta-raspberrypi ships 6.12.93. Taking a newer `SRCREV` means moving a pin rather than selecting a
  recipe, which is a different change with a different review.
- **meta-virtualization was bumped, not removed**, although it contributes zero recipes to this
  image. That is the owner's call to move all three pins in one PR; whether the layer earns its place
  at all is a separate question nobody has asked yet.
- **Poky's `improve_kernel_cve_report.py` was not patched in `sources/`.** It is a checked-out
  upstream tree that kas re-fetches; a local edit there is invisible to the build's provenance and
  would be silently lost. Both this defect and the `cve_check_merge_jsons` `return` belong upstream,
  and neither belongs to #80.

## Changes configured as a result

**Code change**, all in PR #83, which closes #80:

- **The kernel moves to 6.12.93** — `kiosk-zero-w.yaml:52` overrides upstream's weak default, and
  `meta-wisekiosk/recipes-kernel/linux/linux-raspberrypi_%.bbappend` drops the patch 6.12 already
  carries while keeping the one no kernel bump delivers.
- **Three pins bumped to their branch heads** — poky, meta-openembedded and meta-virtualization, at
  `includes/base.yaml:52`, `:63` and `:81`. Poky's is worth 16 findings; the other two are currency,
  recorded as such.
- **The compiled-sources flag** at `includes/cve-audit.yaml:19`, which is what would make
  `just kernel-cve` measurable once the upstream defect is fixed.
- **The triage tooling that found all of this** — `tools/cve-report.py`, `tools/cve-delta.py`,
  `tools/kernel-cve.py`, `tools/layer-currency.py`, `tools/preferred-version.py` and the shared
  `tools/cve_manifest.py`, each with a seeded fixture in `tools/cve-tools-test.py` wired into
  `tools/ci-guards.sh`. What they do is [`docs/cve-and-sbom.md`](../../cve-and-sbom.md) and
  [`docs/layer-currency.md`](../../layer-currency.md).

Two things are left open on purpose and are not this PR's to close: the 24 h soak comparison on 6.12,
and the two upstream poky defects named above.

No one-off script was written, so this directory holds no committed script. Every durable change
links to its recipe or PR.
