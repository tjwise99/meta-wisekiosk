# Can this layer build the WiseKiosk application from source, and does it run on the board?

| | |
|---|---|
| **Issue** | #52 app from source (opened as the Yocto toolchain-currency spike) |
| **Status** | concluded → code change |
| **Opened / concluded** | 2026-08-26 / 2026-08-30 |

Yes, both halves, and the answer is a working image rather than a recommendation. #52 was written as
a paper spike — compare five Go-toolchain options, and record Node as out of scope because the
frontend would be consumed as a pre-built bundle from the application's CI. The owner rejected that
premise: the frontend is a static-site generator, so there is no reason for the image to take its
build from another pipeline. The spike therefore became the build. Go comes from the
`meta-lts-mixins` `scarthgap/go` branch (1.26.7 against poky's 1.22.12) with no move off the LTS
base; Node 24.20.0 is unpacked as a build-host binary and never reaches the device; the frontend's
260-package closure is fetched offline by bitbake's `npmsw://` fetcher and built by `vite`; the
backend cross-builds static for armv6 with `CGO_ENABLED=0` and needs no vendoring at all, because its
reachable graph is stdlib-only. One bench-board run over RAUC OTA confirmed the image boots, the
service runs as the pinned unprivileged account, and — the requirement this ticket existed to settle
— `config.json` is read from the slot-shared `/data` partition through a baked symlink, appearing and
disappearing under a running server with no restart. The changes ship in
[PR #92](https://github.com/tjwise99/meta-wisekiosk/pull/92).

## Test runs

| Run | Board (role) | Image commit | Harness / scripts | Result (1 line) |
|---|---|---|---|---|
| 1 | bench/HITL · Pi Zero W | `ff5c7289222cbfab2a1be65efef2d0d7a4828bfb` | shipped `just` OTA recipes — durable, PR #92 | PASS — booted slot A in 56 s, backend active as uid/gid 10001 on `:8080`, and the four-step `/data` config lifecycle held with the server's PID unchanged. |

One board, one build, one test. There is no second run to blend with, and none of the figures below
is compared against a different build.

### Run 1 — bench/HITL, commit `ff5c728`

- **Board:** bench / HITL — the desk swap board, the designated OTA, reboot and rollback target.
  Raspberry Pi Zero W, BCM2835, armv6. **Not prod.** Role was confirmed by logging in and matching
  several independent signals against the gitignored `local/device-identity.md` *before any write*;
  those signals stay in that file, because this repository is public. The prod board was read only
  where its role table permits status reads, and was never written to.
- **Image commit:** `ff5c7289222cbfab2a1be65efef2d0d7a4828bfb`, confirmed on the board —
  `grep ^meta-wisekiosk /etc/buildinfo` reads exactly
  `52-app-from-source:ff5c7289222cbfab2a1be65efef2d0d7a4828bfb`. The application commit it carries is
  pinned in the tree, not re-recorded in the image: `wisekiosk-src.inc:17` fixes
  `SRCREV = "33e710338d9b03afa9968194717ff0ddc4e3a72d"`, and the image manifest shows
  `wisekiosk-backend` and `wisekiosk-frontend` at `0.0+git0+33e710338d`, so the application commit
  rides the package version.
- **Scripts deployed (each, with disposition):**
  - *None.* Delivery used only shipped `just` recipes — `kiosk-bundle`, `kiosk-preflight`,
    `kiosk-send-direct`, `kiosk-install`, `kiosk-reboot` — which live in `justfiles/ota.just` and
    ship with the repository. R2 is satisfied by there being nothing one-off to commit, rather than
    by committing something.
- **Procedure:** rebuild the bundle (`just kiosk-bundle`) — the `.raucb` already on disk was two days
  older than the image, and `just build` does not rebuild it, so shipping the stale one would have
  silently reinstalled the previous image and reported success. Read the pending image offline from
  its ext4 with `debugfs` before shipping, to confirm `/etc/buildinfo`, the presence and mode of
  `/usr/bin/wisekiosk`, and that `/srv/kiosk/config.json` is a symlink 24 bytes long — the length of
  `/data/config/config.json`. Then preflight, transfer with an md5 comparison, `rauc install`, and
  reboot. On the board: read `lsblk`, `df -h /data`, `rauc status`, `systemctl` state and
  `/proc/<pid>/status` for the service's ids; then run the four-step configuration lifecycle in the
  table below, checking `MainPID` and `NRestarts` at each step.
- **Raw capture:** **none committed, deliberately.** The three display captures are PNGs of a
  rendered kiosk and live in gitignored `local/`; a screenshot of this device carries site content
  and is exactly what `tools/scrub-identity.py` exists to keep out of a public repository, and unlike
  a text log it cannot be scrubbed by substitution. They are described by result below instead. The
  console evidence is reproducible from the procedure above using shipped recipes.

## Configuration under test

The tree facts this run rests on, as of commit `ff5c728`.

**The Go toolchain is a pinned kas repository, not a recipe copied into this layer.**
`includes/base.yaml:99-103` adds `meta-lts-mixins-go` at branch `scarthgap/go`, commit
`df1df57da4ee43ecf23413796531b8942d949963`. That branch sets `GOVERSION = "1.26%"` and depends on
oe-core alone, so the LTS base does not move and nothing outside the toolchain re-hashes — WebKit in
particular does not, because `surf`'s `DEPENDS` contains no Go. Keeping it a kas pin keeps it inside
the staleness reporting [`layer-currency.md`](../../layer-currency.md) owns; a hand-maintained recipe
family would sit outside it. The same repository is already pinned at `scarthgap/u-boot` elsewhere,
and the two coexist because their layer collections differ (`lts-go-mixin` against
`lts-u-boot-mixin`).

**The backend is built offline without vendoring.** `wisekiosk-backend_git.bb:30` inherits `go-mod`
and line 34 exports `GOPROXY = "off"`, which makes a network fetch at compile time fail the task
rather than succeed quietly. This is sufficient because the reachable graph is stdlib-only:
`backend/go.mod` at the pinned commit declares external modules only behind a `tool` directive
(`oapi-codegen`), which the built binary never reaches. `go-vendor` was rejected for the opposite
reason — Go 1.24+ vendors `tool` directives, so vendoring would have meant pinning and shipping the
source of a code generator absent from the binary.

**The binary is static, and two of poky's arm defaults had to give way for that.**
`wisekiosk-backend_git.bb:38` sets `CGO_ENABLED = "0"`; lines 56-57 clear `GO_DYNLINK:arm` and remove
`-buildmode=pie`. Go refuses both combinations outright without cgo, so these are consequences of the
static-binary decision rather than independent choices. `GO_DYNLINK` carries the `:arm` suffix
because that is the assignment it countermands — the bare name parses without complaint and does
nothing.

**The runtime account's numeric ids are pinned, and pinned before `/data` held anything it owns.**
`wisekiosk-backend_git.bb:93-94` fix both: `GROUPADD_PARAM` at gid 10001 and `USERADD_PARAM` at uid
10001. `/data` is slot-shared, so an A/B update replaces the rootfs and leaves it standing; what
survives an update is the number, not the name. Left to itself `useradd` assigns a gid, which is the
same orphaning hazard with nobody having chosen the value.

**The frontend's closure is fetched offline and `;dev=1` is load-bearing.**
`wisekiosk-frontend_git.bb:21` carries the `npmsw://` URL with `dev=1`. All 260 packages in the
committed shrinkwrap are devDependencies — `vite`, `svelte`, `typescript` and `ajv` among them — so
without that parameter the fetcher resolves an empty closure and the failure surfaces much later as a
missing tool. Node reaches the build host only, from
`nodejs-binary-native_24.20.0.bb:25-27`, SHA256-pinned per build-host architecture.

**The configuration path is a baked symlink into the slot-shared partition.**
`wisekiosk-frontend_git.bb:64` installs `/srv/kiosk/config.json` pointing at
`/data/config/config.json`. It works because the backend serves this tree from disk per request
through `http.Dir`, which follows a symlink, and the page fetches `/config.json` from the served
root. `/data` is partition 4 and RAUC is configured for rootfs slots only —
`meta-wisekiosk/recipes-core/rauc/files/raspberrypi0-wifi/system.conf:10-18` declares
`slot.rootfs.0` as `mmcblk0p2` and `slot.rootfs.1` as `mmcblk0p3` and no boot slot — so neither an
update nor this delivery can touch `/data` or the shared, A/B-unprotected `/boot`.

**The kiosk browser has a local default that the site can still override.**
`kiosk.service:14` sets `Environment=KIOSK_URL=http://localhost:8080` and line 19 reads
`EnvironmentFile=-/data/config/kiosk.conf`. systemd applies these in file order, so the file wins
where it sets the variable; the leading dash is what lets an unprovisioned board boot to the local
app rather than fail. This replaced a deliberate earlier rule that made the file mandatory so an
unprovisioned board failed loudly, whose reason — nothing local to point at — the baked-in app
removes. See finding 1 for what it means on a board that was provisioned before this change.

## Metrics

Run 1 only. Single cold post-OTA boot; cold and warm were not separated, and every figure is n=1.

| Measurement | Value | Samples |
|---|---|---|
| Bundle transfer | 43 s, 2 795 KB/s, 123 075 269 B, md5 MATCH | 1 |
| Reboot to reachable | 56 s | 1 |
| Clock skew at install | 0 s | 1 |
| Slot fit | image 2 147 483 648 B = slot A = slot B, exact | 1 |
| `/data` free before install | 380 540 KB, against 128 382 KB needed | 1 |
| `/data` after boot | 479.2 M total, 43 % used | 1 |
| Backend response | `GET /` → 200, 391 B, `text/html` | 1 |

Clock skew is recorded because [`clock_timesync`](../clock_timesync/README.md) established it as a
precondition for a RAUC install. At 0 s it was satisfied here, and nothing in this run tests it.

## Findings

**1. The bench display was not exercising the baked-in app, and no already-provisioned board will
be.** `confirmed` — this is the "site wins" arm of `kiosk.service` behaving exactly as designed, not
a defect. The board's `/data/config/kiosk.conf`, written weeks earlier by site provisioning, sets
`KIOSK_URL` to a remote origin, and `/data` survives the update, so after the OTA the browser was
still running against that origin while `wisekiosk.service` served the baked app correctly on
`:8080`. The new local default therefore takes effect only on a board whose `kiosk.conf` omits
`KIOSK_URL` — at the time of this run, no provisioned board. Two things worth carrying forward:
whether provisioning should stop writing `KIOSK_URL`, and how fielded boards migrate, is a fleet
decision recorded as a follow-up rather than invented here; and `systemctl show -p Environment`
does **not** reveal this,
because it reports only the unit directive — `/proc/<pid>/environ` of the running browser is the
ground truth, which is worth knowing before anyone concludes from `systemctl` that a rollout worked.

**2. The A/B-agnostic configuration requirement is met.** `confirmed` — the four-step lifecycle ran
against the live server, and `MainPID` stayed 258 with `NRestarts=0` throughout, so every transition
was the running process re-reading the tree rather than a restart picking up a new state.

| Step | `/data/config/config.json` | `GET /config.json` |
|---|---|---|
| 1 | absent (the board's original state) | **404** |
| 2 | minimal valid configuration written | **200**, 104 B, `application/json`, exact bytes |
| 3 | contents changed | **200**, new bytes served |
| 4 | removed again | **404** |

`readlink -f /srv/kiosk/config.json` resolves to `/data/config/config.json`, dangling when the file
is absent. The control runs in both directions and the 404 is a distinguishable state, so a passing
result could not have looked identical to a broken one — which is the only reason the two
absent-file rows are in the table at all.

**3. The service runs as the pinned unprivileged account.** `confirmed` — `wisekiosk.service` is
`active (running)` and `enabled`, MainPID 258, `uid=10001(kiosk) gid=10001(kiosk)`, matching
`wisekiosk-backend_git.bb:93-94` exactly. It binds `0.0.0.0`, confirmed by serving off-device as well
as on the loopback.

**4. The delivery was reversible throughout and `/boot` was never written.** `confirmed` — the
install wrote the inactive slot and the board came up on slot A with slot B still holding the
previous image at `boot status: good`. Rollback was one command and was never needed; U-Boot would
also have fallen back automatically had slot A failed three boots.

**5. "No module named 'clock'" is correct, not a regression.** `dropped as a defect` — with a valid
configuration the page renders its region frame and a per-region unknown-module notice. At the pinned
application commit `frontend/src/lib/modules.ts` is deliberately empty, commented as empty until the
first module lands, so the baked-in app can render no modules yet by design. The richer page visible
when the browser pointed at the remote origin comes from a different application build; that visual
difference is not a fault in this integration. Tracked in the application repository as
WiseKiosk#12 first module end-to-end. Related and harmless: the application's own
`deploy/config.example.json` names a `clock` module that does not exist at the pinned commit, and it
is the example an operator would copy.

**6. Two host-side tooling papercuts, neither affecting the result.** `open` — `just tcp-state`
reports no connections when the browser is on the loopback, because it observes the LAN address only;
correct output, but it cannot see a locally-served kiosk, which will matter once boards do point at
localhost. `just screenshot` takes a bare address and prepends `root@` itself, so passing
`root@<addr>` fails.

## Considerations

Recorded, not acted on.

- **PIE against a static binary.** `CGO_ENABLED = "0"` makes `-buildmode=pie` impossible, so the
  shipped binary is not position-independent and loses ASLR. That is the cost of a binary with no
  dynamic linkage on a device that carries no reason to link libc for a stdlib-only server, and the
  static-binary mandate is the appliance decision's. It is a genuine trade rather than a free win,
  and reversing it means reversing `CGO_ENABLED = "0"`, not adding a flag. No `INSANE_SKIP` is needed
  alongside it: the `textrel` check reads `DT_TEXTREL` from the dynamic section and this binary has
  no dynamic section.
- **Neither the Go module graph nor the npm closure appears in `cve-check`.** Per-recipe attribution
  and what it can see is [`cve-and-sbom.md`](../../cve-and-sbom.md)'s; the consequence here is that
  the application's dependency surface reaches neither the CVE report nor the SBOM, which shows one
  component where the frontend has 260. Accepted knowingly for this change and tracked separately.
- **Every figure in Metrics is n=1** from a single cold boot. They characterise the delivery; none is
  a claim about variance, and none should be compared against a different build without a fresh run.

## Changes configured as a result

**Code change** — [PR #92](https://github.com/tjwise99/meta-wisekiosk/pull/92) on issue #52 builds
both halves of the application from source into the image: the Go toolchain mixin, a
`nodejs-binary-native` recipe, the committed shrinkwrap, the `wisekiosk-frontend` and
`wisekiosk-backend` recipes sharing one source pin, the runtime account, the systemd unit, the
`/data` configuration symlink, the kiosk session's local default, and image integration.

Follow-ups opened rather than folded in, so none of them is silently accepted:

- #93 app dependency CVE blind spot — ecosystem scanning over the two lockfiles.
- #94 scrub-identity blind to a site value in a systemd `Environment=` line.
- #95 kernel restored from sstate emits no per-package SPDX.
- #96 provisioned boards keep their old `KIOSK_URL` — the rollout decision behind finding 1.

No one-off script was placed on the board, so none is committed here; delivery used the shipped
`just` OTA recipes named in Run 1.
