# What makes the kiosk panel stutter, and does GPU compositing fix it?

| | |
|---|---|
| **Issue** | #100 gpu-compositing |
| **Status** | open — the compositing premise is **disproven**, the stutter's dominant cause is found and fixed in the WiseKiosk frontend, and a residual ~1/s frame stall is bounded to WebKit's own rendering and unexplained |
| **Opened / last updated** | 2026-09-19 / 2026-09-22 |

The investigation opened on the premise that the marquee stutters because WebKit repaints in
software, and that enabling GPU compositing would fix it. Run 2 achieved compositing and the stutter
survived. Run 5 then measured the premise **backwards**: with WebKit's dma-buf renderer disabled —
accelerated compositing off — the board runs **3.7x faster on the mean** than with compositing on.
Runs 6 and 7 bisected the page in the deployed (compositing-off) configuration and found the
dominant cost is one element: the clock's `.seconds` text update forces a whole-document relayout
once a second, a ~400 ms main-thread stall in every second. The remedy is two CSS properties in a
WiseKiosk frontend file, worth an ~8x collapse in p90 frame time with no visible change. **The
stutter was never a meta-wisekiosk problem**; the display-stack work in this branch is a wrong turn
that must not ship as committed.

A residual stutter survives that fix, owner-observed and measured: roughly **one frame per second
over 250 ms**, 300–476 ms of it inside the engine rather than in app JS. Runs 8 to 13 bound it rather
than explain it. Eight app-level interventions are measured nulls against it, including removing the
park-card remount; the X server's own stalls are 5–6x too rare to account for it; and it survives
with every piece of the measuring probe stripped out. What is left is WebKit's own rendering
pipeline on this hardware, and **which** part of it is the open question. #100 gpu-compositing stays
open on that.

## Test runs

<!-- One row per (board x image build x test). A `### Run N` block below expands each. -->

Every run ran on **prod**, on the image Run 2 delivered. Run 2 and Run 3 each read the
commit off the board; Runs 4 to 7 inherit it by continuity, and the basis is stated rather than
assumed: each of those runs' own change ledger records **no OTA, no reflash, no image rebuild and no
reboot**, and Run 4 confirms the browser and X processes kept the same PIDs across it. Runs 8 to 13
re-read the commit off the board: `/etc/buildinfo` names
`100-gpu-compositing:7ce44ba671730ed5a7a4470da697c2e128e9bc4d`, slot A. What *does*
differ between them is the **page** served from the mirror and the **kiosk config** the renderer
inherits, so each run names both. From Run 8 onward the **frontend bundle hash** is also named and
read off the board's own cache, because the frontend changed under the board mid-investigation and
the hash is the only thing that says which page a number belongs to. Numbers are never read across
runs.

| Run | Board (role) | Image commit | Harness / scripts | Result (1 line) |
|---|---|---|---|---|
| 2 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A, `/etc/buildinfo`) | `tools/kiosk-gpu-check.sh` — durable; `kiosk-soak` | GPU compositing achieved (dma-buf, observed); **the marquee still stutters**. Compositing ruled out as the cause |
| 3 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) | `stutter-profile` probes — one-off | Panel vblank is a steady 60 Hz and one scanout buffer is blitted, never flipped; rAF runs at 0.76–0.82 Hz; the core stays saturated **with every animation paused and the body hidden**. The vsync-trap hypothesis is refuted |
| 4 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) | `stutter-localize` probes — one-off | ~1.26 core-seconds per frame, split WebKit 53% / X 25% / surf 19%; glamor is enabled and no software rasterizer is mapped; a 2.25x pixel cut buys 1.38x |
| 5 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) | `inspect3.mjs` rAF sampler — one-off | **Compositing off is 3.7x faster than compositing on** (0.782 → 2.91 fps, mean). WebKit's dma-bufs are never imported as DRM framebuffers at all. The #100 gpu-compositing premise is inverted |
| 6 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) | `exp2`–`exp6` surf user-scripts — one-off | Bisection: the clock's `.seconds` is the dominant cost (~3x), through **layout, not paint**. Marquee off is null; every containment variant is null; `content-visibility` is absent from this engine |
| 7 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) | `exp7`/`exp8` surf user-scripts — one-off | The fix (`.seconds` out of flow + size containment) takes p90 frame time from 368–567 ms to 59–67 ms and is statistically indistinguishable from deleting the seconds |
| 8 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A, `/etc/buildinfo`) · bundle `index-Bb_NEXIe.js` | [`probe4.tmpl.js`](probe4.tmpl.js) family — one-off, committed here | The residual stall is **1.02–1.09 frames over 250 ms per second** and engine-dominated. Capping scrolling rows at 2 cuts mean frame time by a third and leaves that rate untouched |
| 9 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` | [`p4_a.js`](p4_a.js) — one-off, committed here | The park-card remount is **removed and verified removed** (`ROT` 97 → 0) and the floor does not move: **1.07/s**. The remount is not the hang |
| 10 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` | [`p5_clock.js`](p5_clock.js) — one-off, committed here | The clock's 1 Hz `.seconds` repaint is **not** the floor: hidden for 120 s, verified hidden, the rate lands on the drift line between its own controls. ~30% within-run drift measured |
| 11 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` | [`p6_title.js`](p6_title.js) — one-off, committed here | The floor does **not** track the probe's exfil cadence: a 3.6x span in `WM_NAME` writes moves the big-frame rate by 0.88x |
| 12 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` | [`xcpu-sample.sh`](xcpu-sample.sh) — one-off, committed here | X's own sustained stalls run at **0.16–0.20/s with no probe installed at all** — real, but 5–6x too rare to be the floor. The probe does not perturb X (20.0% vs 20.1% of a core) |
| 13 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` | [`p7_min.js`](p7_min.js) — one-off, committed here | Stripping every wrapped getter, wrapped timer and the `MutationObserver` leaves the floor at **1.06/s against 1.07/s**. The stall is not the instrument |

**R2 is satisfied for Runs 8 to 13 and not for Runs 3 to 7.**

The probe family Runs 8 to 13 put on the board is committed beside this README, with the raw
captures those runs' numbers are computed from:

| File | What it is |
|---|---|
| [`probe4.tmpl.js`](probe4.tmpl.js) | The frame-time probe template every variant is spliced from |
| [`p4_a.js`](p4_a.js) · [`p4_b.js`](p4_b.js) · [`p4_d.js`](p4_d.js) | Baseline, marquee-off and rows-capped-at-2 arms (Runs 8, 9) |
| [`p5_clock.js`](p5_clock.js) · [`p6_title.js`](p6_title.js) · [`p7_min.js`](p7_min.js) | The clock, exfil-cadence and stripped-instrumentation probes (Runs 10, 11, 13) |
| [`run-phase.sh`](run-phase.sh) | Deploys one variant, restarts onto a cleared cache, reads the payload back with `xprop` |
| [`parse4.py`](parse4.py) · [`parse_arms.py`](parse_arms.py) · [`parse_title.py`](parse_title.py) · [`parse_min.py`](parse_min.py) · [`phase1hz.py`](phase1hz.py) | The analysers, one per payload shape |
| [`xcpu-sample.sh`](xcpu-sample.sh) · [`analyze_xcpu.py`](analyze_xcpu.py) | Run 12's forkless on-board X-CPU sampler and its analyser |
| [`phaseA.txt`](phaseA.txt) · [`phaseA2.txt`](phaseA2.txt) · [`phaseB.txt`](phaseB.txt) · [`phaseD.txt`](phaseD.txt) · [`hang-after-raw.txt`](hang-after-raw.txt) · [`clock-ablation-raw.txt`](clock-ablation-raw.txt) · [`title-cadence-raw.txt`](title-cadence-raw.txt) · [`minprobe-raw.txt`](minprobe-raw.txt) · [`xcpu-noprobe.log`](xcpu-noprobe.log) · [`xcpu-probe.log`](xcpu-probe.log) | Raw captures, one per run arm |

`run-phase.sh` takes the board on its command line. No device address is in any of these files; this
repository is public and the address is resolved at use time from the gitignored
`local/device-identity.md`.

Every one-off script **Runs 3 to 7** put on the board — `probe.sh`, `inspect3.mjs`, `exp2-script.js`
through `exp8-script.js` and the two `diag` scripts — is named in its run block and each was removed
from the device, but none is committed here. They exist only in a scratch directory outside this
repository, and R2 says that is not enough. Committing them is an outstanding obligation on this
investigation, and Runs 3 to 7's numbers are not independently reproducible until it is met.

Two further pieces of work sit outside this table because they are not board runs: the Chromium
layout-scope measurements that designed the fix, and the render-freeze diagnosis. They are recorded
under "Off-board measurements" and "A separate defect found on this board".

### Run 2 — the vc4 image

- **Board:** prod, Raspberry Pi Zero W. See "Delivery and board" for the authorization it carries.
- **Image commit:** the commit `just build` stamps into `/etc/buildinfo` for this build, confirmed by
  `grep ^meta-wisekiosk /etc/buildinfo` on the board. The base is `364a42f`, plus this branch's vc4
  edits and nothing else: **no application is baked into the image and no `SRCREV` is bumped**. The
  page comes from the dev mirror over `KIOSK_URL`, so a frontend change reaches the board by
  redeploying the mirror, independently of this image. That keeps one variable per run — the display
  stack — rather than shipping a browser change and a rendering change in one build.
- **Scripts deployed:**
  - [`kiosk-gpu-check.sh`](../../../tools/kiosk-gpu-check.sh) — DURABLE, committed at that path with
    its self-test [`kiosk-gpu-check-test.sh`](../../../tools/kiosk-gpu-check-test.sh) and wired into
    `tools/ci-guards.sh`. Reads the GPU path's footprint in the web process over SSH and exits
    non-zero when it is absent or software-only. Its header records why the buffer mode itself is
    not readable headless.
  - `kiosk-soak.sh` — DURABLE, already in the image via
    `meta-wisekiosk/recipes-core/kiosk-soak/kiosk-soak_1.0.bb`.
- **Kiosk config:** `KIOSK_URL`, `KIOSK_INSPECTOR=0`, `WEBKIT_FORCE_VBLANK_TIMER=1`. Accelerated
  compositing on.
- **Procedure:** deliver as "Delivery and board" sets out, reboot, then `just gpu-check <host>` for
  the exit-coded guard and `just gpu-capture <host>` to read `webkit://gpu`'s Renderer row off the
  capture by eye.
- **Raw capture:** the within-image compositing A/B designed for this run and the one-hour soak were
  **not** taken. The owner's direct observation that the stutter survived settled the primary
  question and redirected the run to root-cause. Run 5 took that A/B, with the result that inverted
  the premise.

### Run 2 — observations

Run on prod, image `100-gpu-compositing:7ce44ba`, slot A. Delivered by the two-route procedure below:
the rootfs half by `kiosk-ota`, the boot half hand-edited over SSH. One correction the build needed
mid-run — the first boot segfaulted the web process for a missing `libGLESv2.so.2`; the image was
rebuilt with `IMAGE_INSTALL:append = " libgles2-mesa"` (committed `7ce44ba`) and redelivered.

**The compositing objective succeeded.** With vc4 + mesa the web process holds `/dev/dri` open with a
`vc4`/`v3d` gallium driver and carries dma-buf fds — the `Hardware`/dma-buf path, confirmed on the
board by [`kiosk-gpu-check.sh`](../../../tools/kiosk-gpu-check.sh)'s proxy.

**The marquee still stutters** — owner's direct observation, which is the #100 gpu-compositing gate.
Compositing being achieved did not remove it. It is not the CSS (the animating row promotes a
`transform` layer with `will-change`, confirmed) and not the compositing mode (hardware dma-buf,
confirmed).

**Display divergence — the branch as committed does not ship.** `7ce44ba` bakes full KMS
(`VC4DTBO = "vc4-kms-v3d"`). On this panel full KMS presents a **black scanout on a live signal**, so
the running board was hand-edited back to `dtoverlay=vc4-fkms-v3d` to restore a picture. The
committed image and the working device therefore diverge: an OTA or reflash of `7ce44ba` would black
the panel. Every run from Run 3 onward measures the hand-edited firmware-KMS state.

### Run 3 — the presentation path, profiled

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`, named by the run's own report.
- **Kiosk config:** `KIOSK_URL`, `KIOSK_INSPECTOR=0`, `WEBKIT_FORCE_VBLANK_TIMER=1`; accelerated
  compositing on. `WEBKIT_SHOW_FPS=1` and the inspector were each enabled transiently for one
  measurement and reverted, verified against `/data/config/kiosk.conf.bak-stutter` by `diff`.
- **Scripts deployed:** ONE-OFF `/tmp/probe.sh`, a batched `/proc`, `/sys` and debugfs reader, plus
  in-page JS evaluated over the remote inspector. Removed; device `/tmp` confirmed clean.
- **Procedure:** six timed windows across four X restarts, each window reading the `vc4 firmware kms`
  and `vc4` V3D interrupt counters, `/sys/kernel/debug/dri/0/{state,framebuffer}`, and per-process
  `/proc/<pid>/stat` deltas against total jiffies. Two causal arms — every animation paused, then the
  body hidden on top of that — each with its own baseline window either side. rAF and
  `setTimeout(fn, 0)` cadence collected in-page over the inspector, armed in one evaluate and read in
  a later one so no protocol traffic flows during the counting window.

### Run 4 — where the core-second goes, and the 720p cut

- **Board:** prod, Raspberry Pi Zero W.
- **Image commit:** `100-gpu-compositing:7ce44ba` by continuity — this run wrote no file to the
  device, restarted no service, and ended with X, surf and the web process on the **same PIDs** its
  first probe saw.
- **Kiosk config:** unchanged from Run 3's baseline; compositing on. Verified identical to
  `kiosk.conf.bak-stutter` at the end.
- **Scripts deployed:** ONE-OFF diagnostics in device `/tmp`, deleted and their absence verified.
- **Procedure:** `utime+stime` deltas from `/proc/<pid>/task/*/stat` over two independent windows;
  voluntary-versus-involuntary context-switch counts from `/proc/<tid>/status`; a 40-sample
  `wchan`/`syscall`/`stat` profiler across the four hot threads; the mapped-library set of each
  process from `/proc/<pid>/maps`. Then three back-to-back windows — 1080p, `xrandr --fb 1280x720`,
  1080p restored — with the scanout framebuffer's size and pitch read out of DRM debugfs in each, so
  a mode change that failed to apply could not be read as a null.
- **Bound condition:** the 720p arm shrank the X screen and scanout buffer only. surf's window is
  override-redirect at 1920x1080 with no window manager, so WebKit went on rendering 1920x1080,
  clipped rather than scaled. The arm therefore tests the X and surf stages' pixel cost, not
  WebKit's.

### Run 5 — the compositing A/B that inverted the premise

- **Board:** prod, Raspberry Pi Zero W.
- **Image commit:** `100-gpu-compositing:7ce44ba` by continuity; no rebuild, no `/boot` write, no
  OTA, no overlay change.
- **Kiosk config:** baseline as Run 3. Two conditions, each one added line in
  `/data/config/kiosk.conf`: `WEBKIT_DISABLE_COMPOSITING_MODE=1`, and
  `WEBKIT_DISABLE_DMABUF_RENDERER=1`. Reverted to `kiosk.conf.bak-stutter` at the end, verified by
  `diff`.
- **Scripts deployed:** ONE-OFF `inspect3.mjs`, an rAF timestamp collector driven over the WebKit
  remote inspector's HTTP server variant, run from the workstation across an SSH port-forward. Two
  `/proc` reads per 20 s window are the only device-side sampling.
- **Procedure:** 30 s rAF windows alternated with 20 s per-process CPU windows, in each of three
  conditions. **Every condition asserts its variable by exact match in
  `/proc/<webprocess>/environ` before any measurement is taken** — see the method error under
  "Findings", which is why that assertion exists. Steady state is compared against steady state:
  the compositing-off arm starts ~2x faster than it settles, and only its plateau is reported.
- **Raw capture:** a full-screen capture under the compositing-off condition, read visually for
  correctness — clock, weather chart, icons, fonts, four park cards, three mid-scroll marquees, no
  artifacts and no layout change.

### Run 6 — bisecting the page

- **Board:** prod, Raspberry Pi Zero W.
- **Image commit:** `100-gpu-compositing:7ce44ba` by continuity. No `/data/config/kiosk.conf` write,
  no `/boot` write, no OTA, no reboot; `od -c` on the config at the end confirms it untouched.
- **Kiosk config:** `KIOSK_URL`, `KIOSK_INSPECTOR=0`, `WEBKIT_FORCE_VBLANK_TIMER=1`,
  `WEBKIT_DISABLE_DMABUF_RENDERER=1` — the compositing-off state Run 5 measured, made persistent
  between the two runs. **This run and Run 7 therefore measure the configuration the board runs
  in**, not the composited one.
- **Scripts deployed:** ONE-OFF `exp2-script.js` … `exp6-script.js` and `diag-script.js` /
  `diag2-script.js`, written to `/home/root/.surf/script.js` (surf's user-script hook) one at a time
  and left at its pristine **0 bytes** at the end, confirmed by `wc -c`. All were smoke-tested
  end-to-end off-device before reaching the board.
- **Procedure:** one rAF chain records per-frame intervals; a 100 ms self-rescheduling `setTimeout`
  records its own lateness, separating "main thread busy" from "main thread free, waiting
  downstream"; a state machine walks a fixed phase list and accumulates results into
  `document.title`, read from the workstation with one `xprop`. Each phase is a 10–20 s window.
  Three disciplines are load-bearing and each of them changed a conclusion:
  - **A fresh baseline is interleaved between every phase**, and every result is compared only
    against the baselines immediately either side, because the board's baseline drifts 2–3x within a
    single run.
  - **Every manipulation is verified by computed value** at the end of its own window, reported as
    `prop:<before>><after>:inl<n>/<total>:chg<n>`, where `chg` counts elements whose *computed* value
    actually differs. Marking elements with a JS property at apply time rather than string-comparing
    the inline value is required, because normalisation breaks the comparison.
  - **`#app{display:none}` is carried as a positive control** in the same run, so a null can be
    distinguished from a dead instrument.
- **Bound conditions:** a continuously-requesting rAF loop keeps frames being produced, so absolute
  fps describes frame-production capability under a continuous driver, not what the idle page would
  produce — only the within-run comparisons are valid. Each phase is one window, so only the results
  that reproduce across two independent runs are treated as findings.

### Run 7 — the fix, measured on the board

- **Board:** prod, Raspberry Pi Zero W.
- **Image commit:** `100-gpu-compositing:7ce44ba` by continuity. No config write, no `/boot` write,
  no OTA, no reboot, no image rebuild.
- **Kiosk config:** as Run 6 — compositing off.
- **Scripts deployed:** ONE-OFF `exp7-script.js` and `exp8-script.js` through the same user-script
  hook, checksum-verified against the local file on write, left at 0 bytes at the end.
- **Procedure:** the Run 6 method, with three additions. The deploy sequence is fixed by the
  stale-document hazard recorded under "Findings" — write `script.js`, **clear `~/.surf/cache`**,
  restart. Content is verified from inside the page before measuring (`app[all=298,card=12,sec=1]`),
  because the white-panel failure mode reports `all=9`; a screenshot would have perturbed the very
  baseline it precedes. `.seconds{display:none}` is the positive control, the prior run's known ~3x
  effect. Run 1 uses 12 s windows and four manipulations; Run 2 uses 30 s windows and a structural
  content guard keyed on card count, wait count and total element count.
- **What was measured, stated precisely:** the manipulation is an **injected inline style** on the
  live `.seconds`, not a deployed build. Given the board's 2–3x within-run baseline drift a
  two-deploy before/after would be uninterpretable, so interleaved baselines in one page load are
  the only valid comparison — and that requires injection. The consequence is that this run measures
  **the mechanism** (out-of-flow plus size containment), not **the exact source structure**, which
  adds a slot element the live DOM does not carry. The source structure is proven equivalent against
  a real vite build in Chromium; it has **not** been measured on the board.

### The `probe4` family — the harness Runs 8 to 13 share

Stated once here rather than six times. All six runs install a JavaScript probe at
`/home/root/.surf/script.js` (surf's user-script hook), restart the kiosk onto a cleared WebKit
cache, let it run, and read a payload back out of the X window title with `xprop`. The page's own
`console.log` does not reach the journal on this image — measured, count 0 — so the window title is
the exfil path. [`run-phase.sh`](run-phase.sh) is the driver and takes the board role's address on
its command line.

The probe times every `requestAnimationFrame` interval and splits each frame three ways: `js` is
time inside app callbacks (wrapped rAF, `setTimeout`, `setInterval`, `queueMicrotask`), `lay` is
time inside forced-synchronous-layout getters (wrapped `scrollWidth`, `clientWidth`, `offsetWidth`,
`getBoundingClientRect`, `getComputedStyle`), and `engine` is the remainder — `dt − js`, time the
engine spent outside app code. The headline metric is **frames over 250 ms per second**, chosen
because Run 6 established the distribution is bimodal and the perceived chop is the slow minority,
not the mean.

Three disciplines are load-bearing, and each was arrived at by being burned:

- **Every manipulation carries an in-band landed-check in its own payload.** A manipulation that
  silently fails to apply is indistinguishable from one that has no effect, and that has produced a
  false finding three times in this body of work. The probe reports `M<n>/20` (rows currently
  animating), `ROT` (remounts detected), `wmax`/`wlast` (the ablated element's measured box) or `tw`
  (the probe's own title writes), depending on the arm.
- **Arms are interleaved inside one continuous capture wherever the manipulation allows it**, because
  the board drifts ~30% within a single run at flat load (Runs 10 and 11, independently). A plain
  before/after of two two-minute windows cannot resolve an effect smaller than that.
- **Every analyser is proven to report both outcomes before being trusted**, against synthetic
  payloads for the landed and the failed case. A discriminator that cannot come out both ways
  discriminates nothing.

Bound condition on all six: **each arm is n=1.** The effect sizes that carry conclusions here are
far outside the noise, but no condition was replicated except the Run 8 A/A2 baseline pair.

Device state touched, on every run: `~/.surf/script.js`, the WebKit cache, and in Run 12 one sampler
script in device `/tmp`. No image rebuild, no `/boot` write, no OTA, no reboot, no keyring touch, no
`/data/config/kiosk.conf` write. Each run ends by deploying a zero-byte `script.js`, restarting, and
verifying the board is clean and the render advancing with
[`kiosk-render-check.sh`](../../../tools/kiosk-render-check.sh).

### Run 8 — the residual floor, and the app-level ablations that do not move it

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`, read off the board's `/etc/buildinfo`.
- **Frontend bundle:** `index-Bb_NEXIe.js` — the deployed build carrying the Run 7 seconds fix,
  before the park-card remount change. Read off the board's own WebKit cache.
- **Kiosk config:** as Run 7 — compositing off (`WEBKIT_DISABLE_DMABUF_RENDERER=1`),
  `WEBKIT_FORCE_VBLANK_TIMER=1`. Full-open **demonstration** park data: four parks, 19–20 ride rows,
  5–6 of them long enough to scroll. That is a heavier page than the live payload and is stated
  because it sets the amplifier Run 8 measures.
- **Scripts deployed:** ONE-OFF [`p4_a.js`](p4_a.js), [`p4_b.js`](p4_b.js) and [`p4_d.js`](p4_d.js),
  committed here. Left at 0 bytes at the end, confirmed by `wc -c`.
- **Procedure:** four continuous captures of 286–315 s, back to back within one hour, one per
  condition — baseline, baseline repeat, marquee off, scrolling rows capped at 2. Raw captures
  [`phaseA.txt`](phaseA.txt), [`phaseA2.txt`](phaseA2.txt), [`phaseB.txt`](phaseB.txt),
  [`phaseD.txt`](phaseD.txt).
- **Bound conditions, and they decide how the table is read.** The four captures are sequential, not
  interleaved, so the A/A2 replicate is the only estimate of noise available — about **7%** on mean
  frame time, and Runs 10 and 11 later show that figure understates the real variability.
  **Arm B is unmeasured and must not be read as a result:** it injects a `<style>` element, and the
  mirror serves `style-src 'self'`, under which only a style *attribute* survives — and it carries no
  in-band landed-check, so a dropped rule and a real null look identical. Its own internal oddity says
  the same thing: arm D kept two rows fully animating and still beat arm B, which was supposed to have
  none.

### Run 9 — the park-card remount removed

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`. No rebuild, no OTA, no `/boot` write, no reboot.
- **Frontend bundle:** `index-dKJ9KDWL.js` — a new build in which the `{#key ride.name}` wrapper is
  deleted in source. Gated before the capture was accepted: the hash was read off the board's cache
  and was the **only** `index-*.js` there, so no stale document could be in play.
- **Kiosk config:** as Run 8, same demonstration data.
- **Scripts deployed:** ONE-OFF [`p4_a.js`](p4_a.js) — the identical baseline arm Run 8 used, so the
  only variable is the bundle. Left at 0 bytes at the end. Raw capture
  [`hang-after-raw.txt`](hang-after-raw.txt).
- **Procedure:** one continuous 287 s capture, read against Run 8's archived A and A2 baselines.
  Three acceptance gates were fixed before the run and all three passed: the loaded bundle is
  `index-dKJ9KDWL.js`, `ROT` is ≈0, and `M<n>/20` is comparable to the baselines' 5–6.
- **Bound conditions.** This is the one comparison in Runs 8 to 13 that is **not** interleaved, and
  it cannot be — the manipulation is a deployed build, not an injected style. Its "before" comes from
  a session about 2.5 h earlier, and cross-session drift is not covered by the 7% within-session
  figure. That does not rescue the result: the rate did not merely fail to improve, it landed in the
  middle of the baseline range. Second, `ROT=0` makes phase-locking **unmeasurable** — with no
  detected events the bursts can only be described as still clustered, not as still locked to
  rotation. Third, the run cannot prove rotation is still running; the conclusion holds either way,
  because bursts surviving the remount's removal and bursts surviving rotation's removal both say the
  remount is not the cause.

### Run 10 — the clock's 1 Hz seconds repaint, ablated against the floor

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`. **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** as Run 9, same demonstration data.
- **Scripts deployed:** ONE-OFF [`p5_clock.js`](p5_clock.js), committed here. Raw capture
  [`clock-ablation-raw.txt`](clock-ablation-raw.txt); arms read by
  [`parse_arms.py`](parse_arms.py).
- **Procedure:** one continuous 386 s capture, interleaved ON / OFF / ON with a 20 s warmup excluded
  and three 120 s arms, no restart between arms. `.seconds` is hidden by style attribute with
  `!important`, the one injection form the page's CSP permits.
- **Why hiding `.seconds` is the correct ablation, read from `Clock.svelte` rather than assumed.**
  The component's `setInterval` updates one `$state` date every second, feeding the hours, the
  seconds, the meridiem and both date lines — but Svelte 5's text setter compares before it writes,
  so `secondsText` is the **only** value that actually changes 59 seconds in 60. Hiding `.seconds`
  therefore removes the 1 Hz *paint* while leaving the 1 Hz *JS* running, which is precisely the
  paint-side ablation the hypothesis needs. Layout is undisturbed: `.seconds` is already absolutely
  positioned under `contain: size layout` inside a slot held open by hidden generated content, so the
  slot keeps its box whether or not the reading is drawn.
- **Landing check, in band and sampled throughout:** `getBoundingClientRect().width` on `.seconds`
  every 2 s. `display:none` collapses the box to 0 px, so a 0 px maximum across the whole OFF arm is
  positive evidence the element was not rendered, and its return to 50 px proves the revert took.
  The parser was proven against synthetic payloads to report `hidden` for a landed ablation and
  `ABLATION DID NOT LAND … UNMEASURED` for a failed one before it was trusted.
- **A second, weaker arm in the same run:** the phase of every big frame against a 1000 ms period,
  computed from the four archived captures at zero device risk. Phase must be computed in **integer
  tenths** — timestamps are quantised to 0.1 s and `t % 1.0` in floating point silently drops values a
  bin, which manufactures a striking every-other-bin-empty pattern that reads exactly like clustering.

### Run 11 — the exfil cadence, varied 3.6x

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`. **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** as Run 10, same demonstration data.
- **Scripts deployed:** ONE-OFF [`p6_title.js`](p6_title.js), committed here — byte-identical to
  [`p4_a.js`](p4_a.js) except for when the title is written. Raw capture
  [`title-cadence-raw.txt`](title-cadence-raw.txt), read by [`parse_title.py`](parse_title.py).
- **Procedure:** one continuous 386 s capture, interleaved FAST / SLOW / FAST at 1000 / 4000 /
  1000 ms title periods after a 20 s warmup. The prediction was fixed before the run: if the floor is
  the probe's `WM_NAME` poke, the big-frame rate tracks the write rate across a 4x span; if it is
  independent, all three arms sit at ~1/s.
- **Landing check:** the probe counts its own title writes per arm.
- **Bound conditions, both stated rather than buried.** The base timer changes — the gated writer
  polls every 200 ms instead of firing every 2000 ms — which adds ~4.5 trivial wakeups/s present
  *identically in all three arms*, so the between-arm comparison holds while the absolute level may
  shift slightly against stock [`p4_a.js`](p4_a.js). And the write path bundles two costs, the
  `WM_NAME` poke and two `querySelectorAll` sweeps; since the floor did not track cadence both are
  excluded, but had it tracked, they could not have been separated.

### Run 12 — the X server's own stalls, with and without a probe

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`. **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** as Run 11, same demonstration data.
- **Scripts deployed:** ONE-OFF [`xcpu-sample.sh`](xcpu-sample.sh) in device `/tmp`, committed here;
  removed and its absence verified. Raw captures [`xcpu-noprobe.log`](xcpu-noprobe.log) and
  [`xcpu-probe.log`](xcpu-probe.log), read by [`analyze_xcpu.py`](analyze_xcpu.py).
- **Procedure:** two arms of ~125 s each, sampling the X server's own CPU counters at ~110 ms from
  **outside** the browser — arm B1 with `~/.surf/script.js` at 0 bytes, arm B2 with
  [`p4_a.js`](p4_a.js) installed. Each arm asserts its own control in band by reporting the script's
  byte count (0 against 5760). On one core X can use at most one jiffy of CPU per 10 ms of wall time,
  so a stall shows as consecutive sample windows at ~100% of a core.
- **The sampler forks nothing**, and that is the whole reason the number is usable. It reads
  `/proc/<Xpid>/stat` and `/proc/uptime` with shell `read` builtins; an `awk`-per-sample loop would
  fork 1200 processes onto a saturated 1 GHz single core and manufacture the very bursts it is meant
  to detect. Timestamps come from `/proc/uptime` rather than the loop index, because `sleep 0.1` plus
  loop overhead makes the true interval ~110 ms and a rate computed from an assumed 100 ms would be
  wrong by exactly that drift.
- **Analyser validated in both directions** on seeded data before use: a seeded 300 ms stall every
  1.0 s is reported as 1.00/s with ~330 ms durations and ~1.0 s gaps; a seeded quiet X at 5% load is
  reported as 0.00/s.
- **Bound conditions.** `CLK_TCK` could not be read on the board (`getconf` returns empty), so the
  analyser assumes the Linux standard 100 Hz; the data self-validates, in that utilisation caps near
  1.00 of a core and never implausibly above it, which a wrong divisor would have broken. The two
  arms are **sequential, not interleaved** — probe state cannot be toggled without a restart — so
  their 0.16 against 0.20/s difference is read as equal, not as a real 25% increase. And the arms
  measure **X**; the probe's real weight lands inside `WebKitWebProcess`, which is what Run 13 is for.

### Run 13 — the same floor with the instrumentation removed

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`. **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** as Run 12, same demonstration data, same 2000 ms title cadence.
- **Scripts deployed:** ONE-OFF [`p7_min.js`](p7_min.js), committed here — 1687 B against
  [`p4_a.js`](p4_a.js)'s 5760 B, a bare `requestAnimationFrame` frame-time loop with no wrapped
  geometry getters, no wrapped rAF or timers, no `MutationObserver` and no `querySelectorAll` sweeps.
  Raw capture [`minprobe-raw.txt`](minprobe-raw.txt), read by [`parse_min.py`](parse_min.py).
- **Procedure:** one continuous 306 s capture, compared against Run 11's whole-run figure on the same
  board, same bundle and same data. The byte count was confirmed at install (`SURF_SCRIPT_BYTES`
  1687), so the swap is verified rather than assumed.
- **Bound condition:** the two probes are sequential captures, not interleaved arms, and the board's
  ~30% within-run drift applies. The measured difference is 1%, an order of magnitude inside that
  drift, which is what makes the null readable in spite of it.

### Delivery and board

Run 2 is on prod, the wall-mounted Pi Zero W. `local/device-identity.md` is unchanged; the guard
still matches the delivery steps and still `exit 2`s, and each is approved by a human at the prompt,
the same as any gated operation here.

**The change does not fit one delivery route, so it takes two.** Not a reflash, and not all by
bundle:

- The **rootfs half** — mesa, `xf86-video-modesetting`, the GLX extension, the launcher without
  `GDK_GL=disable` — rides the RAUC bundle: `KIOSK_HOST=… just kiosk-ota` (the host is an environment
  default, not a recipe argument). The deployed RAUC boot script loads the kernel from the rootfs
  slot, so kernel, modules and mesa are all inside A/B rollback cover. **Do not reboot at this step.**
- The **boot half** — `dtoverlay=vc4-kms-v3d` into `/boot/config.txt` and
  ` video=HDMI-A-1:1920x1080@60D` into `/boot/cmdline.txt` — is hand-edited over SSH, because OTA
  cannot carry it: both files live on the shared FAT partition and `RAUC_BUNDLE_SLOTS = "rootfs"`
  means RAUC never writes them.

  This **accepts the no-A/B-protection risk on `/boot`**, knowingly. That partition is shared by both
  slots, so a bad write breaks both and needs the card pulled. It is bounded by: a backup taken first
  (a `tar` of the partition plus a raw `dd | gzip` of p1 and the pre-vc4 `config.txt`, into the
  gitignored `local/`), one small atomic write per file (temp → fsync → `mv` → fsync, no stray
  newline), verification by grepping for the two specific lines present and nothing duplicated, and
  the operator present during delivery.

**Recovery, in the order to try it.** Unreachable after the reboot: `kiosk-netcheck` rolls the slot
back automatically after three failed boots. Reachable but black: `just kiosk-rollback`, then restore
`config.txt` and `cmdline.txt` **file by file** from the backup — never untar the whole partition
over `/boot`, which clobbers `uboot.env` and takes out both slots. The irreducible risk is a power
cut or a card failure during the single FAT write, which costs a physical trip to the unit; nothing
in this procedure removes it.

## Configuration under test

The tree facts the runs rest on; each cited to its source.

- WebKit **is** built with accelerated compositing: `ENABLE_GRAPHICS_CONTEXT_GL=ON`, `USE_GBM=ON`,
  `USE_LIBDRM=ON`, `ENABLE_X11_TARGET=ON` — `build/tmp-raspberrypi0-wifi/.../webkitgtk3/2.44.3/build/CMakeCache.txt`.
  Removing `jit gtk4 enchant` and adding `reduce-size` in `kiosk-zero-w.yaml` has no effect on GL
  (`jit`/`gtk4` are not PACKAGECONFIG items; JIT is off via unconditional `EXTRA_OECMAKE:append:armv6`).
- Compositing was off behind three runtime blockers, traced in the extracted WebKit 2.44.3 source
  (`Source/WebKit/UIProcess/gtk/{AcceleratedBackingStoreDMABuf.cpp, AcceleratedBackingStore.cpp, HardwareAccelerationManager.cpp}`):
  the board's Broadcom userland EGL advertises neither `EGL_KHR_platform_gbm` nor
  `EGL_MESA_platform_surfaceless`, so no accelerated backing store is created at all; `GDK_GL=disable`
  in the launcher; and no GLX module in the X server on the fbdev path.
- The tree closes all three. `kiosk-zero-w.yaml` sets no `DISABLE_VC4GRAPHICS`, so
  `sources/meta-raspberrypi/conf/machine/include/rpi-base.inc:125` puts `vc4graphics` in
  `MACHINE_FEATURES`; that routes `virtual/egl` to mesa
  (`rpi-default-providers.inc:5`, `EGL_MESA_platform_surfaceless` unconditional in
  `mesa-24.0.7/src/egl/main/eglglobals.c`), swaps `xf86-video-fbdev` for `xf86-video-modesetting`
  and adds `xserver-xorg-extension-glx` (`rpi-base.inc:13-14`).
  `meta-wisekiosk/recipes-core/kiosk-session/files/kiosk-launch` exports no `GDK_GL`.
- Full KMS is a hard set, not a default taken: `VC4DTBO` is `?=` in
  `sources/meta-raspberrypi/recipes-bsp/bootfiles/rpi-config_git.bb:28`, and several of
  meta-raspberrypi's machine configs override it to `vc4-fkms-v3d`.
  `kiosk-zero-w.yaml`'s `graphics` block sets `VC4DTBO = "vc4-kms-v3d"`.
- The firmware HDMI keys in `meta-wisekiosk/recipes-bsp/bootfiles/rpi-config_%.bbappend` are inert
  under KMS. `kiosk-zero-w.yaml`'s `graphics` block carries
  `CMDLINE:append = " video=HDMI-A-1:1920x1080@60D"` in their place; the
  trailing `D` forces the connector enabled and digital, which is what `hdmi_force_hotplug` did
  (`Documentation/fb/modedb.rst:49-50` in the pinned kernel source).
- mesa is pinned to poky's 24.0.7 by `PREFERRED_VERSION_mesa` and `PREFERRED_VERSION_mesa-gl` in
  `kiosk-zero-w.yaml`'s `graphics` block. meta-raspberrypi ships
  `mesa_25.1.6.bb`, which `inherit`s the `rust` class where poky's `mesa.inc` does not, and ships no
  `mesa-gl` at that version. `just preferred-version` reports the pin as behind by design; the
  reason is at the pin. See [`../../layer-currency.md`](../../layer-currency.md).
- **The Renderer row is page-only, and that shaped the tooling.** WebKit computes the buffer mode in
  `AcceleratedBackingStoreDMABuf::rendererBufferMode()` from EGL extension queries
  (`Source/WebKit/UIProcess/gtk/AcceleratedBackingStoreDMABuf.cpp:62-87`), writes it to no
  `WEBKIT_DEBUG` channel and no log at all, and surfaces it in exactly one place: the **Renderer**
  row that `handleGPU` renders into the `webkit://gpu` page
  (`Source/WebKit/UIProcess/API/glib/WebKitProtocolHandler.cpp:163-179, 357`). It is therefore
  readable only as pixels, by a browser, by eye. There is no way to read it over SSH and no way to
  exit-code on it.

  This is why [`kiosk-gpu-check.sh`](../../../tools/kiosk-gpu-check.sh) has two modes rather than
  one. Its default mode is the durable regression guard and reads a **proxy** — whether a web process
  holds `/dev/dri` open with a `vc4`/`v3d` gallium driver mapped — which is decidable from `/proc`
  and is what fails if a future change re-disables the GPU. Its `--capture` mode drives the page and
  produces a PNG, and deliberately issues **no verdict**, because nothing in it ever read that row.
  A single-mode tool here would either have been unable to fail, or would have asserted a string it
  never saw.
- **`WEBKIT_DEBUG` does not exist in this build.** `grep -a -c WEBKIT_DEBUG` over
  `/usr/lib/libwebkit2gtk-4.1.so.0.13.7` returns **0** while ~380 other `WEBKIT_*` names are present:
  logging is compiled out of this release build. `WEBKIT_SHOW_FPS` *is* present and works.
- **`WEBKIT_FORCE_COMPOSITING_MODE=1` could not have rescued the old stack** — it is read only after
  the requirements check has already passed.
- **`TearFree` does not exist in this driver build.** `strings` over
  `/usr/lib/xorg/modules/drivers/modesetting_drv.so` finds `SWcursor`, `PageFlip`, `Atomic`,
  `VariableRefresh` and `AsyncFlipSecondaries`, and no `TearFree`: it is an amdgpu/intel option that
  upstream `xf86-video-modesetting` does not carry. There is nothing to enable.
- **The page's own CSP shapes what an experiment can do.** The mirror serves
  `style-src 'self'; style-src-attr 'unsafe-inline'`. A `<style>` element or a constructed stylesheet
  is **silently dropped**; a style *attribute* is permitted, so `el.style.setProperty(prop, val,
  'important')` is the one injection form that survives. This is not a footnote — it produced a false
  "the cost is content-independent" result in an earlier pass, because every manipulation in that
  pass was discarded before it applied.
- Cost: the `MACHINE_FEATURES` change invalidates WebKit and costs a full rebuild (~4.5 h), per
  [`../../../README.md`](../../../README.md) §"Quick start".

## Metrics

Per run. Never merged across runs.

*Run 2 (the vc4 image, `7ce44ba`, prod, slot A):*

- **GPU path:** `Hardware`/dma-buf. Web process holds `/dev/dri` with a `vc4`/`v3d` driver mapped and
  carries dma-buf fds (`kiosk-gpu-check.sh` proxy on the board).
- **Composited marquee CPU:** ~9–15% of the single core (samples), read as an absolute footprint of
  the composited state. **This figure does not reproduce** — see the Run 3 table below and the
  finding "The Run 2 CPU sample is not reproducible" — and nothing downstream rests on it.
- **Formal within-image A/B and one-hour soak / `CmaFree`:** not taken in this run. Run 5 took the
  A/B.
- **Marquee smoothness:** still stutters (owner's eye). The gate is not met.

*Run 3 (`7ce44ba`, prod, compositing on):*

| Condition | v3d jobs/s | X | surf | web process | idle | load1 |
|---|---|---|---|---|---|---|
| baseline 1 | 14.42 | 25.6% | 19.6% | 52.6% | **0.0%** | 2.96 |
| baseline 2 (after restart) | 14.13 | 24.8% | 19.5% | 53.8% | **0.0%** | 3.29 |
| all animations paused | 13.75 | 24.3% | 19.9% | 54.2% | **0.0%** | 3.36 |
| body hidden **and** animations paused | 15.66 | 28.1% | 22.7% | 46.9% | **0.2%** | 3.22 |
| final baseline (restored) | 14.44 | 25.5% | 19.4% | 53.0% | **0.0%** | 3.34 |

- **Panel vblank:** 59.84, 60.08, 60.00, 59.95, 59.85 and 59.96 Hz across six windows spanning four
  X restarts. The panel is a rock-steady 60 Hz.
- **Scanout:** exactly two DRM framebuffers exist, one owned by X and one by the console. `plane-0`
  is bound to X's and **never changes** — 40 consecutive samples over 2.87 s, and one X framebuffer
  in every one of the six windows.
- **rAF cadence:** run A 23 frames / 29.14 s = **0.76 Hz**, mean 1324 ms, SD 301 ms, min 941, max
  2003. Run B 18 frames / 20.67 s = **0.82 Hz**, mean 1216 ms, SD 278 ms. WebKit's own
  `WEBKIT_SHOW_FPS` counter independently reads single digits, 0–1, in every sample.
- **`setTimeout(fn, 0)` in the same window:** 2.35 Hz, median **224 ms**, min 0, max 1582 ms.
- **Animating layer sizes:** the four `SPAN.ride-name-text.marquee` layers are 378–550 px wide by
  24 px tall — every one far inside the 2048 px VC4 texture limit.
- **DOM mutation rate:** 8.1/s (214 mutations over 26.6 s), mostly text and `SPAN` attributes.

*Run 4 (`7ce44ba`, prod, compositing on):*

| Process | % of core (window 1) | % of core (window 2) | ms of core per frame |
|---|---|---|---|
| WebKitWebProcess (all threads) | **53.0%** | 50.5% | ~660 |
| Xorg | **24.7%** | 24.4% | ~320 |
| surf (UIProcess, all threads) | **19.1%** | 18.8% | ~245 |
| WebKitNetworkProcess | 0.3% | 0.2% | ~4 |
| idle | **0.0%** | **0.0%** | |

Total ~**1.26 core-seconds per frame**, against a 16.7 ms budget at 60 Hz.

| Thread | voluntary ctxt switches | asleep in a syscall | running in userspace |
|---|---|---|---|
| WebKitWebProcess main | **383** in 2 h 52 m | **0 / 40** | **38 / 40** |
| Xorg | 3 565 | 26 / 40 (`do_epoll_wait`) | 14 / 40 |
| surf main | 3 915 | 20 / 40 (`do_sys_poll`) | 20 / 40 |
| ThreadedCompositor | 5 258 | 28 / 40 (`do_sys_poll`) | 12 / 40 |

| Window | v3d jobs/s | scanout fb | pitch | bytes |
|---|---|---|---|---|
| baseline 1080p (22 s) | 13.59 | 1920x1080 | 7680 | 8 355 840 |
| **720p** (21 s) | **18.76** | **1280x720** | **5120** | **3 768 320** |
| restored 1080p (21 s) | 14.48 | 1920x1080 | 7680 | 8 355 840 |

**Measured 1.38x against a 2.25x pixel cut**; predicted 1.32x from the 43.2% of the core that the
arm actually shrank. The ratio is computed from the same counter on both sides, so the
jobs-per-frame constant cancels.

*Run 5 (`7ce44ba`, prod; compositing on versus off, same board, same boot):*

| | compositing on | compositing off | change |
|---|---|---|---|
| Frame rate (rAF), steady state | **0.782 fps** (7 samples, 0.744–0.821, SD 0.02) | **2.91 fps** (8 samples, 2.25–3.46) | **3.72x** |
| Core-seconds per frame | 1.273 | 0.340 | −73% |
| WebKitWebProcess | 696 ms/frame | 173 ms/frame | −75% |
| Xorg | 324 ms/frame | 121 ms/frame | −62% |
| surf (UIProcess) | 253 ms/frame | 46 ms/frame | **−82%** |
| V3D jobs per frame | 18.4 | 2.05 | −89% |
| dma-buf objects on the device | 2 (16 588 800 bytes) | **0** | — |
| Page-flip | none | none | unchanged |

*Run 6 (`7ce44ba`, prod, compositing off). Each phase is read only against the baselines immediately
either side of it; the baseline band is given per table because it drifts 2–3x within a run.*

Does isolation work? Baseline band 4.6–13.1 fps.

| Phase | fps | rAF med / p90 (ms) | timer late med / p90 (ms) | landed |
|---|---|---|---|---|
| b0 baseline | 11.2 | 23 / 297 | 2 / 295 | — |
| **`#app{display:none}`** *(control)* | **55.7** | 17 / 21 | 1 / 3 | chg 1/1 |
| b1 baseline | 8.3 | 24 / 409 | 2 / 308 | — |
| `.ride-name{contain:paint}` | 6.6 | 36 / 457 | 4 / 335 | **chg 20/20** |
| b2 baseline | 13.1 | 22 / 295 | 2 / 470 | — |
| marquee `animation:none` | 12.7 | 21 / 307 | 4 / 599 | chg 1/1 |
| b3 baseline | 4.6 | 87 / 570 | 14 / 513 | — |
| `#app{visibility:hidden}` | 19.4 | 21 / 133 | 2 / 124 | chg 1/1 |
| b4 baseline | 7.2 | 36 / 435 | 11 / 512 | — |

X server CPU in the same run, jiffies per 10 s: normal operation 340–380; `#app{display:none}` **1**;
`#app{visibility:hidden}` **382**, i.e. full rate.

Is the cost area, or a fixed per-frame present? Synthetic damage rectangle of known size at a known
rate, with `#app` hidden.

| Phase | What | fps | rAF med / p90 | verified |
|---|---|---|---|---|
| app hidden, no damage | — | 54.2 | 17 / 21 | box `none`, 0 updates |
| 40x40 px, every frame | small, fast | 44.5 | 21 / 27 | 40x40, 535 updates |
| 1920x270 px, every frame | large, fast | **6.9** | 139 / 174 | 1920x270, 84 updates |
| 1920x270 px, every 8th frame | large, slow | 40.5 | 20 / 46 | 1920x270, 61 updates |

Which part of the page? Baseline band 7.5–13.5 fps; `wasarea` is the hidden element's measured area.

| Phase | Hidden | area (k px²) | fps | rAF med / p90 | late p90 |
|---|---|---|---|---|---|
| **clock section** | the region holding the clock | 264 | **31.7** | 18 / 39 | 44 |
| weather section | the region holding the weather | 264 | 10.6 | 30 / 349 | 195 |
| **park-cards section** | the region holding the cards | 264 | **33.0** | 20 / 30 | 186 |
| **`div.clock`** | the clock itself | 182 | **39.5** | 17 / 35 | 46 |
| `div.weather` | the weather itself | 381 | 10.4 | 35 / 356 | 199 |
| **`div.park-wait-times`** | the cards themselves | 644 | **30.1** | 20 / 36 | 188 |

Which element, exactly? `display:none` on each, baseline band 8.5–11.0 fps.

| Phase | Hidden | fps | rAF med / p90 | late p90 | landed |
|---|---|---|---|---|---|
| **`.seconds`** | the seconds readout | **29.9** | 17 / 57 | 43 | chg 1/1 |
| `.clock` | the whole clock | 26.2 | 20 / 58 | 60 | chg 1/1 |
| `.ride-name-text` | the marquee text | 19.3 | 21 / 66 | 321 | chg 10/10 |
| `.wait` | the wait-time numbers | 9.7 | 30 / 411 | 407 | chg 10/10 |

Can it be fixed without removing it? Baseline band 6.6–15.6 fps.

| Phase | Manipulation | fps | rAF med / p90 | late p90 | landed |
|---|---|---|---|---|---|
| T1 | `.seconds{contain:layout paint}` | 7.8 | 28 / 405 | 479 | chg 1/1 |
| T2 | `.clock{contain:layout paint}` | 6.2 | 23 / 483 | 748 | chg 1/1 |
| T3 | `.seconds{font-variant-numeric:tabular-nums}` | 10.2 | 24 / 357 | 354 | **chg 0 — already tabular** |
| T4 | `.seconds{visibility:hidden}` | 9.2 | 24 / 374 | 451 | chg 1/1 |

*Run 7 (`7ce44ba`, prod, compositing off). `F1`/`F1b` = `position:absolute` in a `position:relative`
parent, `contain:size layout`, 53 x 34.5625 px. `F2` = the same with `contain:strict`. `C1` =
`display:none`, the positive control.*

12 s windows:

| Phase | fps | med (ms) | **p90 (ms)** | late med | **late p90** | landed |
|---|---|---|---|---|---|---|
| b0 | 6.8 | 30 | 545 | 21 | 546 | — |
| **F1** | **26.3** | 18 | **61** | 4 | **87** | chg 1/1 |
| b1 | 7.9 | 22 | 430 | 6 | 475 | — |
| **F2** | **23.9** | 20 | **67** | 6 | **97** | chg 1/1 |
| b2 | 7.6 | 25 | 471 | 3 | 491 | — |
| **C1** *(control)* | **20.0** | 23 | **75** | 7 | **132** | chg 1/1 |
| b3 | 6.2 | 48 | 532 | 16 | 452 | — |
| **F1b** *(replicate)* | **27.8** | 20 | **59** | 5 | **85** | chg 1/1 |
| b4 | 5.4 | 50 | 567 | 17 | 537 | — |

30 s windows, with the structural content guard reporting `ok` on all five:

| Phase | fps | med (ms) | **p90 (ms)** | late med | **late p90** | landed |
|---|---|---|---|---|---|---|
| b0 | 9.0 | 25 | 368 | 5 | 419 | — |
| **F1** | **26.0** | 21 | **60** | 6 | **55** | chg 1/1 |
| b1 | 7.2 | 30 | 494 | 4 | 494 | — |
| **C1** *(control)* | **29.3** | 20 | **56** | 5 | **63** | chg 1/1 |
| b2 | 7.1 | 39 | 416 | 6 | 460 | — |

Rolled up **within this run only**, across its eight baseline windows and four fix windows:

| | p90 frame time | p90 timer lateness | fps against adjacent baselines |
|---|---|---|---|
| baselines (8 windows) | **368–567 ms** | 419–546 ms | 5.4–9.0 |
| **the fix** (4 windows, including the `contain:strict` variant) | **59–67 ms** | **55–97 ms** | 23.9–27.8 |
| control, seconds hidden (2 windows) | 56–75 ms | 63–132 ms | 20.0–29.3 |

The shipped form (`contain: size layout`) scored 26.0, 26.3 and 27.8 across its three windows —
**3.2–4.8x** its adjacent baselines. The `contain: strict` variant scored 23.9 at a p90 of 67 ms,
no better than the shipped form's 61, which is why the source edit omits paint containment and its
clipping risk: the reading's glyphs overflow the box, so clipping is a real cost for no gain.

*Run 8 (`7ce44ba`, prod, compositing off, bundle `index-Bb_NEXIe.js`, demonstration data). Four
sequential captures. **Arm B is unmeasured** — see the run block — and its number is printed only as
the record of what was run.*

| arm | ablation | scrolling rows | frames / window | mean frame | fps | `<50 ms` | 500 ms–1 s | **>250 ms/s** |
|---|---|---|---|---|---|---|---|---|
| A | none (baseline) | `M6/20` | 4403 / 315 s | 72 ms | 14.0 | 67.2% | 1.4% | **1.09** |
| A2 | none (baseline repeat) | `M5/20` | 4263 / 286 s | 67 ms | 14.9 | 70.7% | 2.1% | **1.02** |
| B | `animation:none` + `will-change:auto` *(unmeasured)* | `M5/20` | 4470 / 286 s | 64 ms | 15.6 | 74.7% | 1.6% | 1.06 |
| D | live marquee rows capped at 2 | **`M2/20`** | 6192 / 288 s | **46 ms** | **21.5** | **82.8%** | **0.8%** | **1.09** |

Mean frame time by phase since the last detected rotation remount, same run — the correlation that
motivated Run 9. Each cell is the mean of every frame whose time since the last remount fell in that
bucket.

| phase since remount | A | A2 | B | D |
|---|---|---|---|---|
| 0–1 s | **174 ms** | **217 ms** | **293 ms** | **142 ms** |
| 1–2 s | 77 ms | 141 ms | 179 ms | 55 ms |
| 2–3 s | 53 ms | 66 ms | 56 ms | 32 ms |
| 3–4 s | 45 ms | 39 ms | 41 ms | 23 ms |
| 4–5 s | 40 ms | 35 ms | 31 ms | 23 ms |
| 5–6 s | 31 ms | 24 ms | 23 ms | 19 ms |
| 6–7 s | 27 ms | 19 ms | 21 ms | 18 ms |
| 7–8 s | 20 ms | 18 ms | — | 18 ms |

Big-frame series, arm A, last 14 of 344 frames over 250 ms. `t` is seconds into the capture, `dt` the
frame time, `js` time inside app callbacks, `lay` time inside forced-layout getters, `engine` the
remainder.

```
    303.5s   474ms  js=  15  lay= 0   since_rot= 1.2s  engine= 459ms
    303.9s   380ms  js=   0  lay= 0   since_rot= 1.6s  engine= 380ms
    305.7s   320ms  js=  23  lay= 3   since_rot= 0.4s  engine= 297ms
    306.1s   344ms  js=   0  lay= 0   since_rot= 0.7s  engine= 344ms
    307.2s   307ms  js=   4  lay= 3   since_rot= 1.9s  engine= 303ms
    308.3s  1063ms  js= 813  lay= 4   since_rot= 0.1s  engine= 250ms
    308.7s   414ms  js= 102  lay=88   since_rot= 0.5s  engine= 312ms
    309.1s   413ms  js=   0  lay= 0   since_rot= 0.9s  engine= 413ms
    310.8s   353ms  js=  29  lay=14   since_rot= 0.4s  engine= 324ms
    311.2s   423ms  js=   0  lay= 0   since_rot= 0.9s  engine= 423ms
    313.2s   337ms  js=  21  lay= 0   since_rot= 2.9s  engine= 316ms
    313.7s   498ms  js=  61  lay= 0   since_rot= 0.3s  engine= 437ms
    314.1s   387ms  js=   5  lay= 3   since_rot= 0.7s  engine= 382ms
    314.5s   386ms  js=  19  lay= 0   since_rot= 1.1s  engine= 367ms
```

*Run 9 (`7ce44ba`, prod, compositing off, bundle `index-dKJ9KDWL.js`, demonstration data). One
287 s capture. The `index-Bb_NEXIe.js` columns are Run 8's archived arms, reproduced here because the
comparison is the point of the run — they are a **different bundle and a different session**, which
is the bound condition the run block states.*

| metric | Run 8 arm A (`Bb_NEXIe`) | Run 8 arm A2 (`Bb_NEXIe`) | **Run 9 (`dKJ9KDWL`)** | read |
|---|---|---|---|---|
| scrolling rows | `M6/20` | `M5/20` | **`M6/20`** | amplifier held, identical to arm A |
| remounts `ROT` | 97 / 315 s | — | **0** | **remount structurally gone** |
| window | 315 s | 286 s | 287 s | comparable |
| frames | 4403 | 4263 | 4437 | comparable |
| mean frame | 72 ms | 67 ms | 65 ms | inside the 7% floor |
| fps | 14.0 | 14.9 | 15.5 | inside the floor |
| `<50 ms` share | 67.2% | 70.7% | 72.5% | inside the floor |
| 500 ms–1 s band | 1.4% | 2.1% | 1.3% | inside run-to-run spread |
| **frames >250 ms** | **1.09/s** | **1.02/s** | **1.07/s** | **unchanged** |

Last 14 frames over 250 ms in that capture, still arriving in tight clusters rather than evenly
spread — 7 frames in 4.7 s, then 7 in 3.2 s, matching the 3.1–4.1 s inter-burst cadence of Run 8:

```
274.9s 381ms   275.9s 324ms   276.2s 358ms   277.1s 404ms   277.6s 422ms
279.2s 398ms   279.6s 389ms
282.6s 430ms   282.9s 345ms   283.8s 527ms   284.4s 634ms
285.0s 526ms   285.4s 429ms   285.8s 409ms
```

Engine-dominated exactly as in Run 8: `engine` **294–476 ms** against `js` 0–194 ms and `lay`
0–182 ms. Startup is separate and expected — the five worst frames (2180, 2127, 1869, 1453, 1447 ms)
all land in the first 11 s and are **js**-dominated (`js` 837–1491 ms), which is page load, not the
steady state.

*Run 10 (`7ce44ba`, prod, compositing off, bundle `index-dKJ9KDWL.js`, demonstration data). One
continuous 386 s capture, `M6/20`, `ROT0`; whole run 5753 frames, mean 67 ms, 408 frames over 250 ms
= **1.06/s**. Load 2.01 / 2.10 / 2.13, `VmRSS` 98.9 MB.*

| arm | window | `.seconds` box | frames | >250 ms | **>250 ms/s** | mean frame |
|---|---|---|---|---|---|---|
| warmup | 0–20 s | 50 px | — | — | excluded | — |
| **ON1** | 20–140 s | **50 px (visible)** | 2101 | 111 | **0.93** | 57 ms |
| **OFF** | 140–260 s | **0 px (hidden)** | 1824 | 132 | **1.10** | 66 ms |
| **ON2** | 260–380 s | **50 px (visible)** | 1573 | 145 | **1.21** | 76 ms |

The run drifts monotonically worse across its own arms, so the OFF arm is read against the line its
two controls define rather than against either one:

| metric | ON1 | predicted at the OFF midpoint by drift alone | **OFF measured** | ablation effect |
|---|---|---|---|---|
| frames >250 ms/s | 0.93 | **1.07** | **1.10** | **+0.03/s (+3%)** |
| mean frame time | 57 ms | **66.5 ms** | **66 ms** | **−0.5 ms (−1%)** |

Phase of the big frames against a 1000 ms period, 100 ms bins, computed on frame *start* (`t − dt`)
because these frames run 300–600 ms and a 1 Hz-locked cause phased on the end would smear across
several bins. The 5% critical value at df=9 is **16.92**:

| capture | bin counts (0.0 → 0.9) | chi² (df 9) | largest bin |
|---|---|---|---|
| Run 9 (`dKJ9KDWL`) | `0 2 2 1 1 3 1 1 2 1` | 4.57 | 3/14 = 21% |
| Run 8 arm A | `1 1 3 1 1 1 1 3 2 0` | 6.00 | 3/14 = 21% |
| Run 8 arm A2 | `1 1 0 1 1 3 1 1 2 3` | 6.00 | 3/14 = 21% |
| Run 8 arm D | `2 1 1 0 3 2 2 0 2 1` | 6.00 | 3/14 = 21% |

Phase on frame *end* is also flat (chi² 8.86 / 10.29 / 4.57 / 7.43). **This arm is underpowered on
its own** and carries no verdict: only 14 of the big frames are retained per capture and they are not
independent — they arrive in bursts, so the effective sample is the 3–6 bursts per run. A perfect
lock would have been caught; a partial one would not.

*Run 11 (`7ce44ba`, prod, compositing off, bundle `index-dKJ9KDWL.js`, demonstration data). One
continuous 386 s capture, `M6/20`, `ROT0`; whole run 5747 frames, mean 67 ms, 413 frames over 250 ms
= **1.07/s**. Load 2.71 / 2.36 / 2.23, `VmRSS` 98.4 MB.*

| arm | title period | **measured writes/s** | frames | >250 ms | **>250 ms/s** | mean frame |
|---|---|---|---|---|---|---|
| **FAST1** | 1000 ms | **0.84** (101 writes) | 2049 | 112 | **0.93** | 59 ms |
| **SLOW** | 4000 ms | **0.23** (28 writes) | 1790 | 142 | **1.18** | 67 ms |
| **FAST2** | 1000 ms | **0.85** (102 writes) | 1653 | 138 | **1.15** | 73 ms |

Title-write ratio FAST:SLOW is **3.6x**; the big-frame ratio is **0.88x**. Drift control: FAST1 0.93
→ FAST2 1.15/s predicts 1.04/s at the SLOW midpoint, and SLOW measured 1.18/s — 14% high, and in the
*wrong direction* for the artifact hypothesis. Had the floor been the exfil, SLOW should have fallen
to ~0.26/s.

The landing check fired on FAST1 — 101 writes against an expected ~120 — and on inspection the
**expectation** was wrong, not the manipulation: the gated writer polls on a 200 ms base tick, so a
1000 ms target can only fire on a 200 ms boundary and under load landed at ~1190 ms, which yields
~101 writes in 120 s. The SLOW arm is barely affected because the same quantisation is proportionally
far smaller against 4000 ms. The measured span is 0.84 / 0.23 / 0.85 per second, essentially the
intended 4x.

*Run 12 (`7ce44ba`, prod, compositing off, bundle `index-dKJ9KDWL.js`, demonstration data). Two
sequential arms, X-server CPU sampled at ~110 ms from outside the browser.*

| | **B1 — no probe** | **B2 — `p4_a.js` installed** |
|---|---|---|
| in-band control check | `SURF_SCRIPT_BYTES=0` | `SURF_SCRIPT_BYTES=5760` |
| samples / window | 1157 / 126.0 s | 1133 / 124.3 s |
| **X total CPU** | **20.0% of one core** | **20.1% of one core** |
| runs ≥80% of a core | 45 | 50 |
| **sustained bursts ≥200 ms** | **20 → 0.16/s** | **25 → 0.20/s** |
| burst durations | 210–340 ms | 210–330 ms |
| median inter-burst gap | 5.34 s | 3.30 s |

*Run 13 (`7ce44ba`, prod, compositing off, bundle `index-dKJ9KDWL.js`, demonstration data). One
306 s capture, 4188 frames, probe byte count confirmed 1687 at install. The `p4_a.js` row is Run 11's
whole-run figure on the same board, bundle and data.*

| probe | mean | fps | `<50 ms` | **>250 ms/s** |
|---|---|---|---|---|
| `p4_a.js` — full instrumentation (5760 B) | 67 ms | 14.9 | 72.5% | **1.07** |
| **`p7_min.js` — bare rAF loop (1687 B)** | 73 ms | 13.7 | 65.5% | **1.06** |

The bursts persist with the same shape under the bare loop: the last 14 big frames arrive as 6 in
3.2 s (295.5–298.7 s) then 8 in 3.5 s (301.8–305.3 s), inter-arrivals of 0.4–0.8 s inside a burst and
1.5–3.1 s between.

## Off-board measurements

These designed and verified the fix. They are not board runs and carry no board or image commit, so
they are kept out of the runs table deliberately rather than dressed up as one. They were run in
Chromium 1228 under playwright-core, headless, at a 1920x1080 viewport, against the same mirror URL
the board loads, with the park route answered from a frozen full-park fixture built from the live
response's own shape.

**Why the seconds write forces a page-wide layout.** Chromium's `Layout` trace event carries
`beginData.partialLayout`, and `false` means the layout root is the whole document. Letting the app's
own interval tick for 10 s: **14 layouts, 14 of them full-page, 0 subtree**, 12 dirty objects of 402,
every one attributed to `#text :: Text changed`. Every box between `span.seconds` and the 1920 px
grid is auto-sized from its content, and the frame's grid tracks are `minmax(0, 1fr)`, so nothing up
the chain is a relayout boundary.

**Which remedy the engine accepts.** A 10 s trace window cannot attribute a layout to one mutation,
so the decisive instrument brackets **one synchronous block** — force layout clean, mutate, force
layout, thirty times, never yielding — with two synthetic control phases so a null can be told from
a dead instrument.

| Phase | Layouts | full-page | subtree | median duration (ms) | median dirty/total |
|---|---|---|---|---|---|
| ctrl-uncontained | 30 | 30 | 0 | 0.123 | 12/517 |
| ctrl-contained | 30 | 30 | 0 | 0.098 | 12/517 |
| seconds-base | 30 | 30 | 0 | 0.127 | 12/517 |
| seconds, `contain: size layout` | 30 | 30 | 0 | 0.103 | 12/517 |
| seconds, `contain: strict` | 30 | 30 | 0 | 0.107 | 12/517 |
| **seconds, out of flow + `strict`** | 30 | **0** | **30** | **0.036** | **2/4** |

**Against a real vite build**, not an inline approximation — the edited tree built to a scratch
`outDir` and served locally, the mirror's own unedited build measured the same way in the same
browser on the same fixture:

| | Layouts | full-page | subtree | median duration (ms) | dirty/total |
|---|---|---|---|---|---|
| mirror, unedited build | 30 | 30 | 0 | 0.258 | 12/402 |
| edited build | 30 | **0** | **30** | **0.034** | **2/2** |

**Visually unchanged.** All eight clock elements are byte-identical in position and size between the
two builds in twelve-hour form, and in twenty-four-hour form — the case the slot element exists for —
`.annotations` measures 53 x 172.8 px in both, so the column does not collapse where there is no
meridiem. A pixel comparison of the annotations column gives **AE = 0**. The suites pass: 24
Playwright clock tests across three viewports, 2 vitest unit tests.

## Findings

Each finding names the run that decided it. **OBSERVATION** is something read off an instrument;
**INFERENCE** is reasoning on top of observations.

- **DISPROVEN — the #100 gpu-compositing premise is backwards (Run 5).** OBSERVATION: with
  accelerated compositing disabled, the board runs at 2.91 fps steady state against 0.782 fps with it
  on — **3.7x faster** — and per-frame cost falls in every one of the three processes at once, most
  sharply in surf's UI process (−82%). Visual output under the fix was captured and read: correct,
  no artifacts, no layout change. The investigation's opening sentence, that the animation stutters
  *because* WebKit repaints in software, does not survive this.

  OBSERVATION: `WEBKIT_DISABLE_DMABUF_RENDERER=1` and `WEBKIT_DISABLE_COMPOSITING_MODE=1` are **the
  same lever** — under the former, the device reports zero dma-buf objects and surf holds zero dma-buf
  fds, and the two conditions produce near-identical CPU splits (X 719 / web 994 / surf 272 versus
  X 708 / web 1004 / surf 271 jiffies per 20 s) and near-identical V3D rates. The variable does not
  select a better transport; it fails WebKit's accelerated-compositing requirements check, which
  disables compositing outright.

- **OBSERVATION (Run 5) — WebKit's composited buffers never reach the display pipeline at all.** The
  complete DRM framebuffer list on the device is X's one scanout buffer and the console's, **both
  `imported=no`**, while WebKit's two 1920x1080x4 dma-bufs sit in `bufinfo`. There is no second
  scanout candidate for the CRTC — not a rejected one, not a wrongly-formatted one, none. The
  format/modifier mismatch that was expected to force a copy is a dead end: the buffer never reaches
  the point where a modifier would be checked. INFERENCE: with one X-allocated scanout buffer, a
  page flip is structurally impossible regardless of format, which is consistent with the constant
  `fb=` ID observed in Runs 3, 4 and 5.

- **REFUTED — the vsync-trap hypothesis (Run 3).** The prior working explanation required an evenly
  produced ~60 fps stream landing at a beating phase against the panel. Two of its three
  preconditions are measured false. OBSERVATION: production is **0.76–0.82 Hz**, not 60 — you cannot
  drop or double a frame out of a stream that is not being produced. OBSERVATION: the present is an
  unsynced copy into a single permanently-scanned-out buffer, so there is no phase relationship to
  beat against. No positive evidence for the hypothesis was found, and it is dropped.

- **REFUTED — two claims this document previously carried about firmware KMS (Run 3).** OBSERVATION:
  X is on the vc4 DRM device, not fbdev — `using drv /dev/dri/card0`, with `fbdev` explicitly failing
  to load — and a real DRM vblank ticks at 59.84–60.08 Hz on the `vc4 firmware kms` interrupt, with
  a real atomic KMS CRTC and a real mode in DRM debugfs. The earlier statement that firmware KMS
  "exposes no vblank source", and the "untried lead" of putting X on the vc4 DRM device rather than
  fbdev, were both already false on the running board. That lead was never open, and reaching that
  state fixed nothing.

- **CONFIRMED by reproduction (Run 3) — the forced vblank timer is load-bearing.** Removing
  `WEBKIT_FORCE_VBLANK_TIMER=1` and restarting reproduced the SIGFPE: `Floating point exception (core
  dumped)` from `xinit`, twice, with no web process alive. The config was restored and the board
  recovered on the next restart. INFERENCE: GDK is not reporting the real 60 Hz vblank to WebKit,
  because one exists and the crash still happens without the forced timer.

- **The Run 2 CPU sample is not reproducible (Run 3).** Run 2 recorded composited marquee CPU at
  ~9–15% of the single core and read that as ample headroom. Run 3 measured five windows across four
  X restarts and found **0.0% idle in four of them and 0.2% in the fifth, at load 2.96–3.36 on one
  core**. Run 4 reproduced that split from an independently written probe, at 0.0% idle in both of
  its windows. The Run 2 figure is left in Metrics as the record
  of what that run sampled; nothing in this investigation rests on it, and the "ample headroom"
  reading is withdrawn.

- **OBSERVATION (Run 4) — no single pathological stage, and no software fallback.** glamor is loaded
  and initialized on the hardware V3D 2.1; `swrast_dri.so`, `kms_swrast_dri.so` and `llvmpipe` are on
  the image but mapped by none of surf, the web process or X, each of which maps the hardware
  `vc4_dri.so` and only that. X's ~320 ms per frame is therefore not a CPU memcpy done for lack of
  acceleration. The cost is spread WebKit 53% / X 25% / surf 19%, and the 720p arm's measured 1.38x
  against a predicted 1.32x says the cost is **pixel-proportional and distributed**: shrinking one
  stage's pixels buys back exactly that stage's share. INFERENCE: the pipeline is over a 60 Hz budget
  by roughly 75x, which is a hardware-capability gap rather than a misconfiguration.

- **OBSERVATION (Run 4) — the producer is saturated, the consumers are asleep.** The WebKit web
  process main thread took **383 voluntary context switches in 2 h 52 m** and was asleep in **0 of 40**
  profiler samples, while X, surf and the compositor thread each spent most samples in `epoll_wait`
  or `poll`. The pipeline is **busy, not blocked** — every callback is waiting for CPU, not for I/O.
  The two have nothing in common as fixes.

- **ROOT CAUSE — the clock's seconds readout forces a whole-document relayout every second (Run 6,
  with the mechanism established off-board).** OBSERVATION: `display:none` on `.seconds` alone takes
  the panel from 11.0 and 10.2 fps either side of it to **29.9 fps**, and hiding the whole clock adds
  essentially nothing on top (26.2). The marquee text is a real but smaller second at ~1.9x, and the
  wait-time numbers cost nothing measurable.

  OBSERVATION: **the cost is layout, not paint.** `visibility:hidden` on that same element — still in
  layout, simply not painted — gives **nothing** (9.2 against adjacent baselines of 6.6 and 9.9),
  where `display:none` on it gave 29.9. The only difference between the two is participation in
  layout.

  OBSERVATION (off-board): the mechanism is that nothing between `.seconds` and the document is a
  relayout boundary. Every ancestor box is auto-sized from its content, so 14 of 14 layouts root at
  the document, touching 402 layout objects, each attributed to a text change. INFERENCE: the engine
  cannot reason that tabular figures guarantee the width will not change — it must lay out to find
  out. Run 6's T3 phase corroborates this from the other side: the app already sets tabular figures,
  re-applying them changed nothing (`chg 0`), and it duly landed in the noise band.

- **The frame-time distribution is bimodal, and "2.5 fps" is the wrong mental model (Run 6).**
  OBSERVATION: median frame time is 20–36 ms with a p90 of 300–570 ms, and main-thread timer lateness
  has the same shape (median 2 ms, p90 ~300–600 ms). Most frames are cheap; a minority are
  catastrophic, and the mean is what reads as a low fps figure. The perceived chop **is** that
  catastrophic minority, and the timer's lateness shows the main thread is genuinely unavailable
  during it rather than idling downstream.

- **Measured dead ends, each verified to have landed before being called a null (Run 6).**
  - **CSS containment does nothing, at any level.** `contain: paint`, `contain: layout paint` and
    `contain: strict` were applied at six different targets across three runs, computed value
    confirmed changed each time, and every one landed inside its run's baseline band — including on
    the actual culprit (`.seconds{contain:layout paint}` at 7.8 against baselines of 15.6 and 14.2).
    This is a real negative: the same instrument in the same run moved **6x** on its control.
  - **`content-visibility` does not exist on this WebKitGTK build.** The computed value was empty
    both before and after applying it, `chg 0`, while `contain` computed correctly in the same run.
    An fps-only probe would have logged this as "tried it, didn't help"; it was never applied at all.
  - **The marquee is not the driver.** Turning it off completely (`animation: none`, verified
    landed) scored 12.7 fps against adjacent baselines of 13.1 and 4.6, and quantising it with
    `steps(8)` was also null. **No motion tradeoff is owed to anyone.**
  - **It is not a fixed per-frame present.** With a synthetic damage rectangle, cost tracks damaged
    area **times** update rate: 40x40 px every frame costs almost nothing (44.5 fps), 1920x270 px
    every frame collapses the board (6.9 fps), and the *same* 1920x270 px every eighth frame
    recovers (40.5 fps). An empty page with the rAF loop running still reaches 54.2 fps. Area is a
    real lever; containment simply fails to narrow the area WebKit damages.
  - **Cost does not track element area on the real page.** The clock is the *smallest* of the three
    top-level regions at 182k px² and gives the *largest* win; the weather block is the largest at
    381k px² and costs nothing measurable. It tracks how often an element dirties itself.
  - *(Off-board, and it disqualified the obvious fix)* **Containment alone does not work even in
    Chromium — not even `contain: strict` with an exact box.** 30 of 30 layouts still rooted at the
    document across 517 objects. Only removing the element **from flow** collapses the scope. Both
    halves are required, and that is the finding the fix is built on.

- **CODE CHANGE — the fix, and exactly what has been measured about it (Run 7, plus off-board).** The
  remedy is in the **WiseKiosk frontend**, at
  `frontend/src/modules/clock/Clock.svelte`: `.seconds` is taken out of flow (`position: absolute`
  inside a `position: relative` slot) under `contain: size layout`, with the slot held open by
  generated content so the annotations column does not collapse in twenty-four-hour form.

  OBSERVATION (Run 7): **p90 frame time 368–567 ms → 59–67 ms** and p90 main-thread lateness
  419–546 ms → 55–97 ms, reproduced over four fix windows in two runs at two window lengths, each
  against the baselines immediately either side. The ~400 ms-per-second stall is gone with the
  seconds still on screen. It is statistically **indistinguishable from deleting the seconds
  entirely** — it beat that control in one run and the control edged it in the other — so it
  captures essentially the whole available win and costs no product tradeoff.

  OBSERVATION (off-board): the source edit's own build is measured, not an inline approximation.
  Layout scope collapses from 402 objects to 2, geometry is byte-identical across all eight clock
  elements in both twelve- and twenty-four-hour forms, the annotations column is pixel-identical
  (AE = 0), and 24 Playwright plus 2 vitest checks pass.

  **The board is running the fix.** The kiosk was restarted onto a cleared WebKit cache and the
  bundle the browser loaded was read back off the board's own cache: a new asset hash carrying the
  fix's marker class. **What has *not* been done is a post-deploy re-measure**: the p90 collapse
  above is the injected-inline-style A/B on the live element, and the deployed source structure adds
  a slot element the measured DOM did not have. That re-measure is open, and one pure-baseline run
  of the Run 7 harness before and after a redeploy would close it.

- **OBSERVATION (Run 8) — the residual stutter is a ~1/s engine-dominated frame stall, and it is
  owner-observed as well as measured.** The rate of frames over 250 ms sits at **1.02–1.09 per
  second**, and those frames are **engine**-dominated: `engine` 294–476 ms against `js` 0–194 ms and
  `lay` 0–182 ms. Whatever produces them is neither app JS nor the marquee's forced-layout geometry
  reads. They arrive **clustered**, 2–4 at a time with 3–5 s between clusters, not evenly spread.
  Between the clusters the page renders at 18–23 ms per frame, so the seconds fix is holding.

  OBSERVATION: **the number of simultaneously scrolling rows is a real amplifier of the mean and does
  nothing to the rate.** Capping live marquee rows at 2 — verified in band, `M2/20` against `M5/20`
  and `M6/20` — took mean frame time from 67–72 ms to **46 ms**, the `<50 ms` share from 67–71% to
  83% and halved the 500 ms–1 s band, while frames >250 ms/s stayed at 1.09. This is why full-open
  demonstration data reads worse than the live payload: more long names overflow, and every one adds
  to the mean. It is not why the panel hangs.

- **FALSIFIED — the park-card rotation remount is not the hang (Run 9).** The `{#key ride.name}`
  wrapper was deleted in source and the removal **verified in band**: `ROT` went from 97 remounts in
  315 s to **0**, with the bundle hash gated and the amplifier held constant at `M6/20`. The rate of
  frames over 250 ms did not respond — **1.07/s**, against 1.09 and 1.02 in the baselines — and the
  burst structure and magnitude are unchanged. Expected on a working fix was the 0–1 s post-remount
  bucket collapsing from 174–217 ms toward the 18–23 ms floor; it did not happen.

  This falsifies the inference Run 8's phase-locking invited, that only the remount cadence could set
  the big-frame count. **The change is a valid cleanup and must not be described as the hang fix.**
  It removes pointless DOM churn, it reconciles the marquee class in both directions, and it is not a
  regression — every metric is equal or marginally better. Shipping it as the answer to the hang
  would claim a result the measurement does not support.

  One thing found while reading the test, recorded because a naive fix would break it: the
  `{#key ride.name}` remount is the **only** way the marquee class is *removed* from a row that has
  stopped overflowing — the action only ever adds it — and a render test asserts that iff. Any
  change that avoids the remount has to carry that invariant itself.

- **NULL — the clock's 1 Hz seconds repaint is not the floor either (Run 10).** The arithmetic
  invited the hypothesis: the board runs the seconds fix, so the reading still repaints once a
  second, and the floor sits within 9% of exactly 1 Hz. OBSERVATION: with `.seconds` hidden for 120 s
  and **verified hidden** — its box measured 50 px → **0 px** → 50 px across the three arms — the
  rate measured **1.10/s**, between its own bracketing controls at 0.93 and 1.21/s. Interpolating the
  run's own drift to the OFF midpoint predicts 1.07/s; measured is 1.10/s, an ablation effect of
  **+3%**, and −1% on mean frame time. Had the hypothesis been right, the OFF arm should have
  collapsed toward 0/s. It did not move.

  The ablation is the paint-side one the hypothesis needs, not a blunter one: hiding `.seconds`
  removes the 1 Hz repaint while leaving the component's 1 Hz JS running, and Svelte's text setter
  compares before writing so the reading is the only value that actually changes 59 seconds in 60.

- **REAL, not an artifact of the instrument — the floor survives every attempt to measure it away
  (Runs 11, 12, 13).** Three independent tests, each carrying its own in-band control:

  | test | manipulation, verified | floor |
  |---|---|---|
  | Run 11 — exfil cadence | title writes **0.84 → 0.23 → 0.85/s**, a 3.6x span | **unchanged**, ratio 0.88x |
  | Run 12 — X server, probe against none | `SURF_SCRIPT_BYTES` 0 against 5760 | X identical (20.0% / 20.1% of a core) |
  | Run 13 — instrumentation stripped | probe 5760 B → **1687 B** | **1.06/s against 1.07/s** |

  If the floor were the probe, Run 11 would have tracked the poke rate, Run 12 would have shown X
  quiet without the probe, and Run 13 would have collapsed. None did. Run 13 is the sharpest of the
  three: stripping every wrapped getter, every wrapped timer, the `MutationObserver` and both
  `querySelectorAll` sweeps changed the rate by **1%**, and left the minimal probe marginally *worse*
  on mean frame time (73 against 67 ms) — consistent with this board's drift, not with instrumentation
  cost.

- **CORRECTED — X's own stalls are real but 5–6x too rare to be the floor (Run 12).** An earlier
  reading in this body of work had X bursting at roughly once a second while the web process sat
  idle, and concluded the big frames *were* those bursts. That over-stated the rate. The sampler
  behind it forked `usleep` about seven times a second onto an already-saturated core and its own
  write flagged the cadence as probe-contaminated; a forkless sampler, reading `/proc` with shell
  builtins, measures sustained X bursts at **0.16–0.20 per second** — about one every five seconds —
  **with no probe installed at all**.

  What survives the correction: the bursts are real, 210–340 ms at ~90–100% of a core, present in
  both arms. What does not: their rate. INFERENCE: 0.16–0.20/s cannot produce a 1.02–1.10/s frame
  stall rate, and the ~1/s reading is also arithmetically inconsistent with X sitting at 20% of a
  core, because one 300 ms burst per second is a 30% duty cycle from the bursts alone, leaving
  nothing for X's ordinary work. The same run establishes that **the probe does not perturb X** —
  20.0% against 20.1% of a core, with and without it.

- **OBSERVATION (Runs 10 and 11) — the board drifts ~30% within a single run at flat load, and that
  is a constraint on every future comparison here.** Run 10 degraded monotonically from 0.93 to
  1.21 frames >250 ms/s (+30%) and 57 to 76 ms mean frame (+33%) over five minutes; Run 11
  independently reproduced it at +24% on both. Load average was flat in both (2.01–2.13, 2.23–2.71).

  Two consequences carried forward. **The interleaved design is necessary, not ceremony** — a plain
  before/after in Run 10 would have read 0.93 → 1.10 and been misread as the clock ablation making
  things *worse*. And **the 7% between-run noise floor understates real variability**: within-run
  drift alone is ~30%, so an effect smaller than that cannot be resolved by a single-arm comparison
  of two short windows. This does not overturn Run 9's null, which predicted a collapse toward 0/s —
  far above drift — but it bounds what any future null here can mean. The drift's own cause is not
  identified. `VmRSS` sat at 98–99 MB in every run, the top of the 83–99 MB sawtooth, which makes
  memory pressure the obvious candidate; it was not measured across arms and is not guessed at here.

- **OPEN — what sets the ~1/s floor. It is inside WebKit's own rendering, and that is as far as the
  evidence reaches.** Everything else reachable has been excluded. Eight interventions, each verified
  to have landed except the one marked, and the rate is pinned across all of them:

  | intervention | run | >250 ms/s |
  |---|---|---|
  | baseline | 8 (arm A) | 1.09 |
  | baseline repeat | 8 (arm A2) | 1.02 |
  | `animation:none` + `will-change:auto` *(unmeasured — no landed-check)* | 8 (arm B) | 1.06 |
  | scrolling rows capped at 2 | 8 (arm D) | 1.09 |
  | `{#key}` remount removed, `ROT` 97 → 0 | 9 | 1.07 |
  | clock 1 Hz seconds repaint hidden | 10 | 1.10 |
  | title exfil 3.6x slower | 11 | 1.18 *(drift-predicted 1.04)* |
  | all probe instrumentation removed | 13 | 1.06 |

  INFERENCE, and the bound it supports: it is not the app — four app-level manipulations that changed
  everything else about the page left it untouched. It is not the display server — X's own stalls are
  5–6x too rare. It is not the instrument — Runs 11 and 13 exclude both halves of that. What is left
  is the engine, which is also what the frame attribution said from the first capture: these frames
  are `engine` 294–476 ms with `js` and `lay` near zero.

  **What is not decided is which part of the engine**, and the two candidates need different fixes:
  a periodic cost WebKit pays regardless of content, or the cost of compositing an animation at
  1920x1080 on this hardware. The discriminating test is cheap and carries no device risk beyond the
  usual user-script swap: point the board at a static page with one CSS animation and no app at all,
  and run [`p7_min.js`](p7_min.js) against it. If ~1/s persists with no app in the picture, the floor
  belongs to WebKit, the compositor or the driver on this hardware and no frontend change will ever
  move it.

  **The direction of any fix is below the app and is not full KMS.** The cheap frontend levers are
  exhausted and measured. Full KMS is separately excluded on this panel — it presents a content-black
  scanout on a live signal, chased to a dead end — and whether the vc4 display-stack work ships at
  all remains the owner's decision on the record below, unchanged by these runs.

  Three further diagnostics stand open, ordered by discriminating power: correlate Run 12's
  0.16–0.20/s X bursts against the frame stalls by timestamp, to establish whether X accounts for the
  *largest* frames while something else produces the rest; sample `WebKitWebProcess` CPU alongside
  the frames, to separate "the engine is working hard" from "the engine is blocked waiting"; and take
  a capture long enough to hold several of the frontend's 5-minute module polls, to settle whether
  the one observed 1063 ms **js**-dominated frame (Run 8, arm A, t=308.3 s, `js=813 ms`) is a real
  recurring second event with a different signature from the floor. That observation is n=1.

<!-- PLACEHOLDER — a localization run is in flight at the time of writing. Replace this comment and
     the subsection below with the run block, its metrics table and its finding when it reports.
     Do not pre-write a result here. -->

- **PENDING — the app-versus-engine localization run.** The test named above, pointing the board at a
  trivial page under [`p7_min.js`](p7_min.js), is running in parallel with this write-up and has not
  reported. **No result for it is recorded here, and none should be inferred from its absence.** When
  it reports it earns its own run block under "Test runs", its own metrics table, and a finding that
  either bounds the floor to WebKit independently of content or attributes it to compositing this
  page's animation on this hardware.

- **A standing deploy hazard, demonstrated rather than argued (Runs 6 and 7).** OBSERVATION: the
  mirror serves `index.html` with **no `Cache-Control` and no `ETag`, only `Last-Modified`**, so
  WebKit caches the document heuristically and reuses it across kiosk restarts. The assets it names
  are content-hashed and rotate on every frontend build; the document that names them does not. After
  any frontend deploy the next kiosk restart can therefore load a stale document whose only script is
  a 404, and a failed module import is **terminal** — the page never retries and the panel stays
  white permanently. This was diagnosed from inside the page (`DIAG rs=complete all=9 … FETCH404 …
  IMPORT_FAIL`), the stale asset hashes were read out of the board's own cache and confirmed to 404
  against the mirror, and the stale document had sat there for six hours: no race is needed. The
  immediate recovery is `rm -rf ~/.surf/cache` plus one restart, which is why Run 7's procedure makes
  the cache clear a precondition of the restart. The class fix is off-board and outside this
  investigation's scope: serve `Cache-Control: no-store` on `index.html` from the mirror, leaving the
  hashed assets cacheable.

  Recorded because a plausible alternative was proposed and would have failed: reverting the renderer
  flag could not have restored that panel. The DOM held nine elements — there was nothing to paint —
  so a renderer flag was never in the path.

- **Method failures that changed a conclusion, recorded so they are not repeated.**
  - **A manipulation that silently fails to apply is indistinguishable from one that has no effect.**
    An earlier pass concluded the cost was "content-independent"; its injected `<style>` elements were
    being dropped by the page's CSP and never applied at all. Every manipulation from Run 6 onward is
    verified by **computed value** at the end of its own window.
  - The same class bit the config side: a driver script built a config block in a command
    substitution, which strips the trailing newline, so two variables were written glued onto one
    line and the first compositing-off condition read as a null. Every condition from Run 5 onward
    **asserts its variable by anchored exact match in `/proc/<pid>/environ` before measuring**, and
    that assertion is what makes the 3.7x trustworthy.
  - And it bit a third time, in [`p4_b.js`](p4_b.js): Run 8's arm B injects a `<style>` element under
    the same CSP, and carries no landed-check of its own. Its number is printed as the record of what
    was run and is scored as **unmeasured**, because a dropped rule and a real null are
    indistinguishable there. Arm D, which kept two rows fully animating, beat arm B, which was
    supposed to have none — the signature of a no-op ablation rather than an effect. Every arm from
    Run 9 onward carries an in-band landed-check in its own payload.
  - **The board's baseline drifts 2–3x within a single run** (4.6 to 13.1 fps in one, 6.6 to 15.6 in
    another). A phase compared against a single baseline taken at the start of a run measures
    nothing. Interleaved adjacent baselines, plus a positive control in the same run, are the minimum.
  - A frame-rate sample taken while a screen capture was running was depressed by the capture and is
    excluded. Probing a saturated single core is itself load: a 40-sample profiler forked ~480
    processes onto it.

- **Pre-work probe — prod's pre-vc4 state. NOT a run, and nothing is read against it.** Before this
  change, the board showed `webkit://gpu` with the **Renderer row absent entirely** — the state that
  means no DMABuf mode is available at all. The image it was running **cannot be named**: it carries
  no `/etc/buildinfo`, runs kernel 6.6.63 against the tree's pinned
  `PREFERRED_VERSION_linux-raspberrypi = "6.12.%"`, and points `KIOSK_URL` at the dev mirror rather
  than the baked `http://localhost:8080`. R1 is explicit that an unnameable image is not a run, so
  this is recorded as a **qualitative probe**: it says the GPU path was off, which is what motivated
  the work. It contributes **no number** to any comparison.

- **Confirmed pre-run, from source and probes, and still standing:** WebKit is compositing-capable;
  the block was the Broadcom EGL, not a missing feature. Legacy dispmanx/Broadcom GLES is a dead end
  (WebKitGTK has no dispmanx target, and the EGL fails the extension gate regardless). vc4 + mesa is
  the only path to compositing — which Runs 5 onward show is not a path worth taking for the stutter.

- **Confound, stated rather than resolved — `will-change` and vc4 shipped together.** Once
  compositing is on, the `infinite` transform animation self-promotes its layer within about 1.2 s,
  so the `will-change: transform` hint's marginal contribution is the startup hitch alone. The two
  arrive in the same delivery and are not separated by these runs. **Nothing here credits that line
  for any result**; its independent benefit is not measured, deliberately, because a
  hint-on-software-image run would be a null by construction.

- **Accepted verification gap — nothing in the tree obliges the substantive check.** The in-tree
  verification of #100 gpu-compositing proves **the CSS declaration resolved on the animating row and
  nowhere else — nothing more**. It asserts nothing about layer creation, about compositing, or about
  CPU. Every on-device claim here rests on the runs above, which TST018's own rationale says are
  obliged by nothing: TST018 is `active:false` / proposed and concerns emulated boot, not this.
  Wherever this record describes on-device evidence it carries that qualifier.

- **OBSERVATION (Run 2) — full KMS blacks the panel outright, worse than the risk anticipated.** The
  geometry change (1824x984 → 1920x1080) is moot: on this panel full KMS does not present a picture at
  all — a content-black scanout on a live signal, owner-confirmed, with content present in an X grab.
  It was chased to a dead end: it persists across forcing 1080p and 720p,
  `disable_fw_kms_setup=1`, an `xrandr` modeset kick, and with WebKit's dma-buf renderer both on and
  off. Firmware KMS (`vc4-fkms-v3d`), which the running board was restored to, drives the picture.

- **Decided — take the overlay's CMA default for this build, and raise it only if a soak says so
  (owner, 2026-09-20).** The KMS framebuffer is allocated from CMA, and this tree sets no pool size:
  `CMDLINE_CMA` is referenced at `sources/meta-raspberrypi/recipes-bsp/bootfiles/rpi-cmdline.bb:57`
  and **assigned in no file** under `sources/meta-raspberrypi`, and the `graphics` block sets no
  `cma-` overlay parameter. What ships is therefore the `vc4-kms-v3d` overlay's own default. An
  earlier draft named `cma-128`; it was removed, and this is the decision that replaces it.

  **Trigger:** add `cma-128` **only if a soak shows CMA pressure**.
  [`kiosk-gpu-check.sh`](../../../tools/kiosk-gpu-check.sh) reads `CmaTotal`/`CmaFree`.

  **Rationale:** `cma-128` takes 128 MB of a 512 MB machine away from everything else, most of it
  from WebKit's headroom — on a board whose whole problem is that it has none. The pool is not
  pre-spent on a shortage nobody has measured. The cost of the bet losing is known and accepted: too
  small for 1920x1080 surfaces as an allocation failure hours into a soak rather than a blank screen
  at boot, and correcting it means a 4.5 h rebuild plus a second hand-edit of prod's `/boot`.

- **OPEN, OWNER DECISION — how the prod guard should treat `gpu-capture`.** `just gpu-capture`
  rewrites `/data/config/kiosk.conf` and restarts the kiosk twice, which is a mutation of the
  wall-mounted board. `.claude/hooks/guard.sh` rule 1 did not know the recipe existed: neither its
  read-only prose list nor its blocking regex named it, its `systemctl` alternation carries no
  `restart`, and the restart is inside a heredoc in any case — so it would have run unprompted. Both
  spellings, the recipe and the direct `tools/kiosk-gpu-check.sh … --capture` path, sit in the
  blocking regex, with `gpu-check` (read-only) left in the allowed list, and
  `.claude/hooks/guard-test.sh` covers both directions. Whether the blocking form should stay or
  become a scoped exemption is the owner's call. The blocking form is the reversible default: it
  fails safe, and relaxing it later is one alternative in one regex.

- **Accepted risk — rollback is unexercised, on the board this runs against.** Delivery touches
  `/boot`, which has no A/B protection, on prod, with RAUC rollback never yet proven in anger (see
  [`../../../README.md`](../../../README.md) §"Known gaps"). It is a known condition of the run, not
  a blocker, and the recovery order is in "Delivery and board".

## A separate defect found on this board

Distinct from the stutter and from this investigation's question, recorded here because it was
diagnosed on the same board during these runs, it invalidated readings taken while it was live, and
the instrument built to catch it is part of the same body of work. It stays part of this
investigation rather than being split into its own directory (owner, 2026-09-22).

**The symptom.** The panel held one frame for 52+ minutes on an outage banner while the backend was
healthy and the browser held an ESTABLISHED connection to it, exchanging data. The frozen frame's
rendered clock read ~71 minutes behind the device clock at capture.

**What was ruled out, by direct measurement on the frozen board.** Not one thread in the surf, WebKit
or X family was in `D` state — every one sat in an ordinary finite `poll` or `futex` wait, with plain
kernel stacks. Both dma-buf fences read `signalled` with static sequence numbers. The V3D interrupt
count was **identical across 115 s** while the panel's vblank ran at 60.1–60.9 Hz, so the GPU was
unused rather than stuck. X's CPU counters were **byte-identical across 150 s**, so X was receiving
nothing rather than dropping it. Memory was not it: 202 MB available, zero swap used, surf's RSS
byte-identical for 45 consecutive minutes, and no OOM line in the kernel log this boot. No GPU fault,
no driver reset. The service had not restarted.

**Root cause, and the correction that matters.** The first reading of this was that WebKit's forced
vblank loop had idled for want of an animation client. That was wrong. The cause is a single uncaught
`TypeError` that kills the Svelte 5 reactive runtime at the instant the page enters its degraded
state: Svelte's `bind:this` teardown writes **`null`** back through a binding whose guard tested only
`=== undefined`, and because the binding is `$state`, that write re-runs the very effect that then
dereferences it. The complete prod symptom — banner stuck up, clock frozen, no recovery with a
healthy backend — was **reproduced in plain headless Chromium**, where the forced vblank timer does
not exist and hardware vblank is present. The vblank theory is not needed to explain any prod
measurement, and the keep-alive animation it implied would not have fixed the board: with the runtime
dead, no DOM mutation reaches the screen however many animation clients are alive.

**The fix** is a widened type and a two-arm guard in the WiseKiosk frontend, with a regression check
staged as live → dead → live on one page with the real module. The existing suite could not have
caught it, for two reasons that were checked rather than assumed: the tier with recovery cases uses
stub modules that hold no binding across the transition, and the module's own stand-down case loads a
page that is *already* unreachable, so it never draws a grid to tear down. The new check was **proven
to fail** with the original guard seeded back in.

**A class-level exposure, assessed and not built.** There is no `<svelte:boundary>`, no
`window.onerror`, no `error` listener and no `unhandledrejection` handler anywhere in the frontend, so
**any** uncaught error permanently freezes this kiosk in whatever state it was in. What makes that
specifically dangerous here is that the failure is silent and indistinguishable from correct
operation — a frozen clock showing a plausible time reads as a working display — and every signal
the deployment carries says green: the backend health check passes, the container is healthy, the
browser is running and the script is running.

**The instrument.** Nothing on the board could tell "rendering" from "frozen": the service supervisor
only sees `xinit` exit, the hardware watchdog only sees PID 1, the boot gate is not a liveness loop,
and the soak sampler records without acting. `kiosk-render-check.sh` closes that gap — capture the X
root window twice across an interval spent **on the device**, hash each, compare — with a three-valued
exit that keeps "could not tell" out of "frozen", because on a wall-mounted panel one of those sends
someone up a ladder. Its rc1 branch was proved end-to-end against the live frozen board, three runs,
identical hashes, both captures verified good and the region verified non-uniform; its rc2
uniform-region branch also fired for real. **rc0 has never been observed end-to-end against a live
board** — prod was frozen and the bench board was unreachable — so that gap stands and is the first
thing to close when bench is back.

## Changes configured as a result

- **The stutter's fix is a WiseKiosk frontend change, not a meta-wisekiosk one.** `.seconds` out of
  flow under size containment, in `frontend/src/modules/clock/Clock.svelte`. It is running on the
  board. **It carries no commit, branch or pull request** — it exists as a working-tree edit in the
  WiseKiosk checkout, which is where the traceability gap is and where it has to be closed.

- **A WiseKiosk frontend cleanup, not a hang fix — the park-card `{#key ride.name}` remount
  removed.** Run 9 verified the removal (`ROT` 97 → 0) and measured no effect on the residual stall.
  It ships or not on its own merits — less DOM churn, and the marquee class reconciled in both
  directions — and the record must not describe it as the answer to the hang.

- **Not resolved — the residual ~1/s engine frame stall.** Open. It is real, owner-observed and
  measured; it is bounded to WebKit's own rendering by Runs 8 to 13; and which part of the engine
  produces it is undecided, with a localization run in flight. **#100 gpu-compositing stays open on
  it**, and the direction of any fix is WebKit, compositor or driver level — not full KMS, which
  blacks this panel, and not a further frontend change, four of which are now measured nulls.

- **`WEBKIT_DISABLE_DMABUF_RENDERER=1` in prod's `/data/config/kiosk.conf`** — the 3.7x of Run 5,
  applied as a device config line and not baked into any image. It survives an OTA because `/data` is
  its own partition that RAUC does not write, which also means **it is not reproduced by a reflash**.
  Reversible over the wire: `cp /data/config/kiosk.conf.bak-stutter /data/config/kiosk.conf &&
  systemctl restart kiosk`. Whether it belongs in the image is an owner decision that has not been
  taken, and the measurement behind it is 25 minutes long, not a soak.

- **[`kiosk-render-check.sh`](../../../tools/kiosk-render-check.sh) and its self-test
  [`kiosk-render-check-test.sh`](../../../tools/kiosk-render-check-test.sh)** — the render-advance
  detector built against the freeze, with 34 verdict fixtures and 7 mutations proving each guard can
  fail independently. Committed at those paths; invocation matches `kiosk-gpu-check.sh`. It has **no
  `just` recipe and is not wired into [`tools/ci-guards.sh`](../../../tools/ci-guards.sh)**, where
  `kiosk-gpu-check.sh`'s self-test does run — that wiring is an owner decision that has not been
  taken, and the tool is usable by path in the meantime.

- **The `probe4` harness and its raw captures, committed beside this README** — the R2 obligation for
  Runs 8 to 13, discharged. The equivalent obligation for Runs 3 to 7 is still outstanding; see
  "Test runs" for the inventory of what is missing.

- **Must not merge as committed — the branch bakes full KMS, which blacks this panel.** `7ce44ba`
  sets `VC4DTBO = "vc4-kms-v3d"`; the running board was hand-edited back to firmware KMS, and
  `WEBKIT_FORCE_VBLANK_TIMER=1` is load-bearing on it but lives only in the device's `kiosk.conf`,
  not the image. An OTA or reflash of this commit blacks the wall panel.

- **OWNER DECISION, not taken here — whether the vc4 display-stack work should ship at all.** It was
  undertaken to fix the stutter; Run 5 measures the opposite of its premise, and the board runs
  faster with compositing off. What the change still buys, against a ~4.5 h rebuild and a hand-edit
  of prod's `/boot`, is a question for the owner against this record. The compositing sub-question
  it opened is answered: compositing is reachable, `kiosk-gpu-check.sh` proves it and will fail on a
  re-disable.

Separately and outside this investigation's scope: any shippable image also needs the WOFF2 font
support proven this session (the `woff2` recipe and `PACKAGECONFIG:append:pn-webkitgtk3 = " woff2"`,
uncommitted on this branch) so the weather-icon glyphs render from the baked build rather than the
WOFF1 stopgap served through the mirror.
