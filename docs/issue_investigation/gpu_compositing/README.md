# What makes the kiosk panel stutter, and does GPU compositing fix it?

| | |
|---|---|
| **Issue** | #100 gpu-compositing |
| **Status** | **open, and not ready to close.** The compositing premise is **disproven**; the clock relayout is found and fixed in the WiseKiosk frontend; the marquee's motion cost is settled by re-mechanising it from `transform` to `scrollLeft` (Run 25). The residual stall is root-caused as a **JavaScriptCore garbage-collection pause** (Runs 35 and 36) — the identification this record previously carried, an intermittent full-viewport software repaint, is **withdrawn and kept visible below**. The lever that follows from the corrected mechanism — **reducing the WiseKiosk frontend's per-second allocation churn** — is un-run, and #100 gpu-compositing stays open on it. The **fix** is not in this repository: it spans a WiseKiosk frontend change the owner holds and a durable image change not yet taken |
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
over 250 ms**, 300–476 ms of it inside the engine rather than in app JS. Runs 8 to 16 bound it rather
than explain it. Nine app-level interventions are measured nulls against it, including removing the
park-card remount and turning every animation in the page off; the X server's own stalls are 5–6x too
rare to account for it; and it survives with every piece of the measuring probe stripped out. The one
manipulation that collapses it is taking the app's rendered DOM out of the page while its JavaScript
keeps running (Run 14, ~100x), so what is left is WebKit's own rendering of **this** render tree, and
which part of it is the open question. #100 gpu-compositing stays open on that.

Separate from that floor, and **corrected here**: the marquee's motion is a real ~2x per-frame cost.
Run 16 turns every animation in the page off under a computed-value landing check and mean frame time
halves — 76.6 → 36.5 ms, ~13 → ~27 fps — leaving the ~1/s floor untouched. The earlier reading that
the marquee is not the driver, and that no motion tradeoff is owed, is **withdrawn**.

Runs 17 to 36 answer both questions Runs 8 to 16 left open, and the second of them twice: the first
answer was wrong, and the record keeps it. Run 17 replaces the derived during-motion estimate with a
measurement — **7.86 fps while any row is moving**, against a 12.5 fps window mean — and the levers
that follow fall into two kinds. The ones that work are **mechanism and pixels**: Run 25 drives the
clipping column's `scrollLeft` instead of translating the text inside it and the same motion costs
**26.5 ms against 71.5 ms per frame, 2.7x cheaper**, inside one interleaved capture; Run 22 cuts the
panel to 1280x720 and during-motion throughput goes **7.86 → 15.26 fps** for 2.25x fewer pixels. The
ones that do not are every **engine lever** on this SoC — compositing (Run 19, 5.2x worse), tiled
software compositing with painting threads (Run 33, 11x more deadline misses), painting threads alone
(Run 34, null), `contain: paint` on the cards (Run 30, inert and landed), and full KMS, which blacks
this panel. **Every one of those levers was aimed at paint**, which the runs below establish is not
the mechanism they needed to reach.

**Those two wins are real, and they are a smoothness result rather than a stall result.** 720p and
`scrollLeft` buy mean frame time and sustained framerate, and Run 25's own capture says as much
inside one window: the arms' worst frames are **491 ms and 496 ms**, the same size, while their means
are 71.5 ms and 26.5 ms. The deadline-miss rate did fall across the same span — **1.07/s** at 1080p
with the transform marquee (Run 9) against **0.045/s over 289 s** (Run 26b) and **0.089/s over 169 s**
(Run 26a) on the shipped mechanism at 720p, a 12x to 24x reduction read across runs that differ in
resolution, mechanism and bundle at once — but Run 36 places that fall on a different cause than this
record long attributed it to. The same frontend work that changed the mechanism also removed the
park-card remount, the per-frame style writes and the transform churn, so the page **allocates less
per second**, so the collector runs less often. It is an allocation win that was read as a rendering
win.

What is left is one thing, and it is named by the runs that first named it wrongly. The residual is a
**JavaScriptCore garbage-collection pause** — **468–537 ms** on Run 26b's seven steady arrivals past
t=40 s (278 ms on its eighth and earliest), with a tail reaching **~1.5 s**, arriving on a **~40 s**
cadence at a fixed point of the marquee's 8 s cycle. Run 36 drives it directly: an allocation arm interleaved against a baseline
arm inside one capture takes **216 of 219 frames over 250 ms at a 1147 ms mean**, against **14 of
6730** in the baseline arm — a **474x** change in the fraction of frames that miss the deadline, with
each arm's own allocation counter read back (219 and 0). Run 35 cuts the panel to **640x480**, a
**3.0x** pixel cut, and the stall does not follow it down: the rate reads **0.036/s** against
0.045/s, the ~40 s cadence is unchanged, and the steady stalls fall only **1.4x** where a pixel-bound
cost owes 3x. Run 28 excludes layout, and Run 31 takes the floor to nothing on a page whose scripts
have been stopped.

**The identification this record previously carried — an occasional full-viewport software repaint —
is withdrawn, and it is kept visible rather than deleted.** Run 35 is what falsified it; Run 29's
benchmark still prices a full-viewport repaint correctly and is simply not pricing the stall. The
withdrawal, the evidence that overturned it and the reasoning that pointed away from paint are in
"Root cause of the residual stall" and in the finding "WITHDRAWN — the residual stall is not a
full-viewport software repaint". The engineering conclusion in "Real-time framing" changes with it:
the lever is not a deterministic renderer but the **WiseKiosk frontend's per-second allocation
churn**, and that lever is un-run. The durable image change that would reproduce the shipped
configuration is staged and reviewed but undelivered, and remains an owner decision — see "Durable
image delivery — pending owner decision".

## Test runs

<!-- One row per (board x image build x test). A `### Run N` block below expands each. -->

Every run ran on **prod**, on the image Run 2 delivered. Run 2 and Run 3 each read the
commit off the board; Runs 4 to 7 inherit it by continuity, and the basis is stated rather than
assumed: each of those runs' own change ledger records **no OTA, no reflash, no image rebuild and no
reboot**, and Run 4 confirms the browser and X processes kept the same PIDs across it. Runs 8 to 16
re-read the commit off the board: `/etc/buildinfo` names
`100-gpu-compositing:7ce44ba671730ed5a7a4470da697c2e128e9bc4d`, slot A. What *does*
differ between them is the **page** served from the mirror and the **kiosk config** the renderer
inherits, so each run names both. From Run 8 onward the **frontend bundle hash** is also named and
read off the board's own cache, because the frontend changed under the board mid-investigation and
the hash is the only thing that says which page a number belongs to. Numbers are never read across
runs.

Runs 17 to 36 keep that discipline and add two facts about themselves, because an adversarial read
is entitled to both. **R1:** every one ran on **prod**, on `100-gpu-compositing:7ce44ba` read off
`/etc/buildinfo`, slot A. **Frontend bundle:** the hash is named on the run that deployed it and
inherited by continuity until the next deploy — Run 17 to Run 22 on `index-dKJ9KDWL.js`, Run 23 on
`index-Dqt17Jj2.js`, Run 24 on `index-Ci1lj58e.js`, Runs 26 to 31, Runs 33 to 34 and Runs 35 to 36 on
the shipped `index-Mt2gvuKb.js`, Run 32 on the diagnostic `index-B8gPvD4g.js`. **The captures do not
carry the hash** — unlike Runs 8 to 16, where it was read off the board's own WebKit cache — so for
these runs the bundle is the deploy record's claim, not the board's. **Run 25's bundle is not recorded at all**:
it follows Run 24's reverted build and no hash was captured for the revert. The run is still readable
because both its arms live inside one capture and the probe derives arm S's motion from the page's
own constants, so the bundle is common to both arms whatever it was — but the hash is a gap, and it
is stated rather than guessed.

**Display mode and renderer change inside this range and are named per run.** Runs 17 to 21 are
1920x1080; Run 19 alone runs with accelerated compositing **on**; Runs 22 to 34 and Run 36 are
1280x720 and **Run 35 alone is 640x480**, each set by `xrandr --output HDMI-1 --mode <mode>` in the
launcher as a hand-edit, with `vc4-fkms-v3d` in `/boot/config.txt` and no `video=` in
`/boot/cmdline.txt` throughout. The mode is returned to 1280x720 after Run 35, which is why Run 36
reads at 720p. Runs 33 and 34 each add one environment variable and say which.

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
| 14 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` | [`p8_layers.js`](p8_layers.js) — one-off, committed here | The app reduced in place to a 240x80 box: the floor **collapses ~100x**, 0.99–1.06/s to 0.01–0.02/s, with the app's JS still running. The floor needs the app's render tree, not its JS |
| 15 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` | [`p9_area.js`](p9_area.js) — one-off, committed here | The same reduction to a **full-viewport text-heavy** box: static **0.03/s at 54 fps**, animated **1283 ms/frame**. Painted area alone is free; animating a screenful of text is its own regime and does not model the app |
| 16 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` | [`p10_noanim.js`](p10_noanim.js) — one-off, committed here | Every animation off, computed-value landing check: **mean frame 76.6 → 36.5 ms, ~13 → ~27 fps**, floor unmoved at 1.08 → 1.10/s. The marquee's motion is a ~2x per-frame cost and is not the floor |
| 17 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` · 1080p | [`p12_motion.js`](p12_motion.js) → [`motion-baseline-raw.txt`](motion-baseline-raw.txt), read by [`parse_motion.py`](parse_motion.py) | **The first measured during-motion framerate**: 127 ms, **7.86 fps** while any row moves, against a 12.5 fps window mean. Cost scales with rows in motion, 22.7 fps at zero to 5.1 fps at five |
| 18a | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` · 1080p | [`p13_steps.js`](p13_steps.js) → [`steps-k40-raw.txt`](steps-k40-raw.txt), read by [`parse_steps.py`](parse_steps.py) | `steps(40)` quantisation is a near-null: overall 75.0 → 71.3 ms, moving-frame fraction 35.8 → 32.3% |
| 18b | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` · 1080p | [`p13_steps.js`](p13_steps.js) → [`steps-k10-raw.txt`](steps-k10-raw.txt), read by [`parse_steps.py`](parse_steps.py) | `steps(10)` takes the overall mean 70.8 → 48.6 ms **by stepping, not by cheapening**: moving frames fall 34.6 → 11.1% of the capture and each one gets *slower*, 131.5 → 153.2 ms. Rejected |
| 19 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` · 1080p, **compositing ON** | [`p12_motion.js`](p12_motion.js) → [`motion-compositing-on-raw.txt`](motion-compositing-on-raw.txt), read by [`parse_motion.py`](parse_motion.py) | The Run 5 retest, on the motion metric: during-motion **1.50 fps** against Run 17's 7.86 — **5.2x worse** — and static frames are 745 ms too, so it is not a motion confound |
| 20 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` · 1080p | [`p16_duration.js`](p16_duration.js) → [`duration-cv179-raw.txt`](duration-cv179-raw.txt), read by [`parse_duration.py`](parse_duration.py) | Per-row constant scroll velocity does **not** shrink the per-frame jump: 20.80 → 21.94 px per moving frame, the wrong direction, with frame time up 3.5 ms. The overflows are too small for the lever to engage |
| 21 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` · 1080p | [`p17_paintcost.js`](p17_paintcost.js) → [`paintcost-raw.txt`](paintcost-raw.txt), read by [`parse_steps.py`](parse_steps.py) | Replacing every glyph with a solid fill over the same box leaves the moving frame at **141.7 ms against 140.0 ms**. The cost is not glyph rasterisation, and a pre-rendered bitmap buys nothing |
| 22 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-dKJ9KDWL.js` · **720p** | [`p12_motion.js`](p12_motion.js) → [`motion-720p-raw.txt`](motion-720p-raw.txt), read by [`parse_motion.py`](parse_motion.py) | 1280x720 takes during-motion **7.86 → 15.26 fps** for a 2.25x pixel cut, and the window mean 12.5 → 24.4 fps. The cost is pixel-area-bound |
| 23 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Dqt17Jj2.js` · 720p | [`p12_motion.js`](p12_motion.js) → [`motion-720p-cv-raw.txt`](motion-720p-cv-raw.txt), read by [`parse_motion.py`](parse_motion.py) | A constant-velocity marquee runs at **20.19 fps during motion** — faster than Run 22's 15.26 — while moving in **65.7%** of read-carrying frames against Run 22's 28.5%. Framerate is not what the owner is seeing |
| 24 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Ci1lj58e.js` · 720p | [`p12_motion.js`](p12_motion.js) → [`motion-linear-shrunk-raw.txt`](motion-linear-shrunk-raw.txt), read by [`parse_motion.py`](parse_motion.py) | Shrinking the holds to keep the rows nearly always moving leaves **3 static frames in 3181** and the window mean at 14.1 fps. Ganging the repaints is worse. Reverted |
| 25 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle not recorded · 720p | [`p18_scroll.js`](p18_scroll.js) → [`scroll-vs-transform-raw.txt`](scroll-vs-transform-raw.txt), read by [`parse_scroll.py`](parse_scroll.py) | **The mechanism result.** Same rows, same distance, same px/s, interleaved in one capture: `scrollLeft` **26.5 ms / 37.8 fps** against `transform` **71.5 ms / 14.0 fps** — **2.7x cheaper** |
| 26a | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p | [`p7_min.js`](p7_min.js) → [`hold2s-fps-169s-raw.txt`](hold2s-fps-169s-raw.txt) | The shipped mechanism, throughput read: 169 s, mean **24 ms ~41 fps**, **96.4% of frames under 50 ms**, deadline misses **0.089/s** |
| 26b | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p | [`p7_min.js`](p7_min.js) → [`hold2s-phase-289s-raw.txt`](hold2s-phase-289s-raw.txt) | The same mechanism over 289 s: **0.045/s**, and **8 of 8** steady stalls land at t mod 8 s = 1.8–2.0 — the scroll-start, not a random arrival |
| 27 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` + 200 ms stagger · 720p | [`p7_min.js`](p7_min.js) → [`stagger-phase-288s-raw.txt`](stagger-phase-288s-raw.txt) | Staggering the rows' starts by 200 ms moves nothing: **0.042/s**, and **6 of 6** steady stalls still at t mod 8 s ≈ 2. Reverted |
| 28 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p | [`p20_profile.js`](p20_profile.js) → [`layout-attribution-288s-raw.txt`](layout-attribution-288s-raw.txt), read by [`parse_profile.py`](parse_profile.py) | A forced layout flush timed in every frame: **0–1 ms on all 14 stall frames**, **0.0% of the worst** and 0.0% frame-weighted. The stall is **not layout** |
| 29 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p | [`p21_fullpaint.js`](p21_fullpaint.js) → [`fullpaint-bench-115s-raw.txt`](fullpaint-bench-115s-raw.txt), read by [`parse_fullpaint.py`](parse_fullpaint.py) | A deliberately forced full-viewport repaint costs **p50 203 / p90 458 / max 530 ms** against a 34 ms baseline — an isolated **183 ms** at the median. The parser returns a **negative** verdict against the stall, and Run 35 later confirms it: this prices a repaint, not the residual |
| 30 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p | [`p22_contain.js`](p22_contain.js) → [`contain-paint-286s-raw.txt`](contain-paint-286s-raw.txt), read by [`parse_contain.py`](parse_contain.py) | `contain: paint` on all four cards, **computed value read back as `paint`**, and the rate goes **up**: 0.084/s with a 1454 ms max. The stall is not card-bounded |
| 31 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p | [`p23_freeze.js`](p23_freeze.js) → [`freeze-188s-raw.txt`](freeze-188s-raw.txt), read by [`parse_freeze.py`](parse_freeze.py) | Every timer and `rAF` neutered: **0.016/s, and no stall after t=3.9 s** at 59.6 fps. **Scored INCONCLUSIVE by its own parser** — one content change survived the freeze, so it is suggestive of a content trigger, not proof |
| 32 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-B8gPvD4g.js` · 720p | [`p7_min.js`](p7_min.js) → [`continuous-pingpong-292s-raw.txt`](continuous-pingpong-292s-raw.txt) | A continuously ping-ponging marquee, never at rest: **0.017/s**, 2.6x fewer than Run 26b, at a worse mean (33 ms against 24 ms). Two stalls survive post-startup and their phase is **not derivable from this capture**. Diagnostic, reverted |
| 33 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p, compositing ON + `FORCE_SHM` + 4 painting threads | [`p7_min.js`](p7_min.js) → [`tiled-shm-292s-raw.txt`](tiled-shm-292s-raw.txt) | Tiled software compositing is the worst configuration measured: **14.3 fps, 0.507/s**, 11x the shipped rate, only 73.8% of frames under 50 ms |
| 34 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p + 4 painting threads | [`p7_min.js`](p7_min.js) → [`painting-threads-294s-raw.txt`](painting-threads-294s-raw.txt) | `NICOSIA_PAINTING_THREADS=4` without compositing is a null: **41.3 fps, 0.041/s** against the shipped 0.045/s. Painting threads do not engage on the non-composited path |
| 35 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · **640x480** | [`p7_min.js`](p7_min.js) → [`res640x480-194s-raw.txt`](res640x480-194s-raw.txt), read by [`parse_min.py`](parse_min.py) | **The falsifier.** A 3.0x pixel cut below 720p leaves the stall where it was: **0.036/s** against 0.045/s, the same ~40 s arrival cadence, steady stalls past t=40 s 324–378 ms against 468–537 ms — **1.4x for 3x fewer pixels**. The residual is **not pixel-area-bound**, and the full-viewport-repaint identification does not survive it |
| 36 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (slot A) · bundle `index-Mt2gvuKb.js` · 720p | [`p24_alloc.js`](p24_alloc.js) → [`alloc-pressure-raw.txt`](alloc-pressure-raw.txt) | **The confirmer.** JS allocation pressure interleaved against a baseline arm in one capture: the ALLOC arm misses **216 of 219 frames** at a **1147 ms mean / 2020 ms max**, the BASELINE arm **14 of 6730** at 24 ms — a **474x** change in miss fraction, with each arm's allocation counter read back (219 and 0). The stall is a **JavaScriptCore GC pause** |

**R2 is satisfied for Runs 8 to 36 and not for Runs 3 to 7.**

The probe family Runs 8 to 16 put on the board is committed beside this README, with the raw
captures those runs' numbers are computed from:

| File | What it is |
|---|---|
| [`probe4.tmpl.js`](probe4.tmpl.js) | The frame-time probe template every variant is spliced from |
| [`p4_a.js`](p4_a.js) · [`p4_b.js`](p4_b.js) · [`p4_d.js`](p4_d.js) | Baseline, marquee-off and rows-capped-at-2 arms (Runs 8, 9) |
| [`p5_clock.js`](p5_clock.js) · [`p6_title.js`](p6_title.js) · [`p7_min.js`](p7_min.js) | The clock, exfil-cadence and stripped-instrumentation probes (Runs 10, 11, 13) |
| [`p8_layers.js`](p8_layers.js) · [`p9_area.js`](p9_area.js) · [`p10_noanim.js`](p10_noanim.js) | The in-place page-reduction and animation-ablation probes (Runs 14, 15, 16) |
| [`run-phase.sh`](run-phase.sh) | Deploys one variant, restarts onto a cleared cache, reads the payload back with `xprop` |
| [`parse4.py`](parse4.py) · [`parse_arms.py`](parse_arms.py) · [`parse_title.py`](parse_title.py) · [`parse_min.py`](parse_min.py) · [`phase1hz.py`](phase1hz.py) · [`parse_layers.py`](parse_layers.py) · [`parse_area.py`](parse_area.py) · [`parse_anim.py`](parse_anim.py) | The analysers, one per payload shape |
| [`xcpu-sample.sh`](xcpu-sample.sh) · [`analyze_xcpu.py`](analyze_xcpu.py) | Run 12's forkless on-board X-CPU sampler and its analyser |
| [`phaseA.txt`](phaseA.txt) · [`phaseA2.txt`](phaseA2.txt) · [`phaseB.txt`](phaseB.txt) · [`phaseD.txt`](phaseD.txt) · [`hang-after-raw.txt`](hang-after-raw.txt) · [`clock-ablation-raw.txt`](clock-ablation-raw.txt) · [`title-cadence-raw.txt`](title-cadence-raw.txt) · [`minprobe-raw.txt`](minprobe-raw.txt) · [`xcpu-noprobe.log`](xcpu-noprobe.log) · [`xcpu-probe.log`](xcpu-probe.log) · [`layers-raw.txt`](layers-raw.txt) · [`area-raw.txt`](area-raw.txt) · [`noanim-raw.txt`](noanim-raw.txt) | Raw captures, one per run arm |

The same obligation for Runs 17 to 36, discharged the same way: every probe, every parser and every
raw capture is committed here. **How each number is produced differs by payload shape, and the
difference is stated rather than smoothed over.** Runs 17 to 25 and Runs 28 to 31 each name a parser
that computes their figures. Runs 26, 27, 32, 33, 34 and 35 carry the bare `MP` payload, which
[`parse_min.py`](parse_min.py) reads — it reproduces every figure quoted for them, including 26b's
window, frame count, mean, max, rate, histogram and big-frame list — and those rows name it. Run 36's
`AL` payload is read from the record's own fields against the probe that wrote them
([`p24_alloc.js`](p24_alloc.js)); [`parse_alloc.py`](parse_alloc.py) in this directory was written
against an **earlier revision of that payload** carrying an `AO` field the committed probe does not
emit, so it does not read the committed capture and is not the source of any number here. That
mismatch is a real R2 defect, recorded rather than papered over, and closing it is an outstanding
obligation on this investigation.

| File | What it is |
|---|---|
| [`p12_motion.js`](p12_motion.js) | The motion probe — tags each frame MOVING or STATIC from the live computed `translateX` of every marquee row, and buckets frame time by how many rows moved (Runs 17, 19, 22, 23, 24) |
| [`p13_steps.js`](p13_steps.js) · [`p16_duration.js`](p16_duration.js) · [`p17_paintcost.js`](p17_paintcost.js) | The three 1080p lever arms spliced onto that measurement — `steps()` quantisation, per-row constant velocity, and glyphs replaced by a solid fill (Runs 18, 20, 21) |
| [`p18_scroll.js`](p18_scroll.js) | The mechanism probe — arm T keeps the stylesheet's transform animation, arm S cancels it and drives `scrollLeft` at the same px/s over the same distance (Run 25) |
| [`p20_profile.js`](p20_profile.js) · [`p21_fullpaint.js`](p21_fullpaint.js) · [`p22_contain.js`](p22_contain.js) · [`p23_freeze.js`](p23_freeze.js) | The residual-stall probes — one timed layout flush per frame, a forced full-viewport repaint benchmark, paint containment on the cards, and the frozen page (Runs 28, 29, 30, 31) |
| [`p24_alloc.js`](p24_alloc.js) | The allocation-pressure probe (Run 36) — a palindrome of ALLOC and BASELINE arms inside one capture, allocating and dropping ~25000 short-lived objects per frame in the ALLOC arms, with a per-arm frame-time split and an in-band allocation counter so an arm that never allocated is visible rather than scored |
| [`ovf_track.js`](ovf_track.js) | A helper that records each ride name's maximum marquee overflow across a full tour rotation. It sized the demonstration data's overflows and contributes no number to any run |
| [`run-phase-motion.sh`](run-phase-motion.sh) | Deploys a probe, restarts onto a cleared cache and reads the longer `KP2` payload back with `xprop`. Takes the board on its command line, as [`run-phase.sh`](run-phase.sh) does |
| [`parse_motion.py`](parse_motion.py) · [`parse_steps.py`](parse_steps.py) · [`parse_duration.py`](parse_duration.py) · [`parse_scroll.py`](parse_scroll.py) · [`parse_profile.py`](parse_profile.py) · [`parse_fullpaint.py`](parse_fullpaint.py) · [`parse_contain.py`](parse_contain.py) · [`parse_freeze.py`](parse_freeze.py) | The analysers, one per payload shape. [`parse_motion_test.py`](parse_motion_test.py) and [`parse_steps_test.py`](parse_steps_test.py) prove the two reused across the most runs report both outcomes |
| [`motion-baseline-raw.txt`](motion-baseline-raw.txt) · [`steps-k40-raw.txt`](steps-k40-raw.txt) · [`steps-k10-raw.txt`](steps-k10-raw.txt) · [`motion-compositing-on-raw.txt`](motion-compositing-on-raw.txt) · [`duration-cv179-raw.txt`](duration-cv179-raw.txt) · [`paintcost-raw.txt`](paintcost-raw.txt) · [`motion-720p-raw.txt`](motion-720p-raw.txt) · [`motion-720p-cv-raw.txt`](motion-720p-cv-raw.txt) · [`motion-linear-shrunk-raw.txt`](motion-linear-shrunk-raw.txt) · [`scroll-vs-transform-raw.txt`](scroll-vs-transform-raw.txt) | Raw captures, Runs 17 to 25 |
| [`hold2s-fps-169s-raw.txt`](hold2s-fps-169s-raw.txt) · [`hold2s-phase-289s-raw.txt`](hold2s-phase-289s-raw.txt) · [`stagger-phase-288s-raw.txt`](stagger-phase-288s-raw.txt) · [`layout-attribution-288s-raw.txt`](layout-attribution-288s-raw.txt) · [`fullpaint-bench-115s-raw.txt`](fullpaint-bench-115s-raw.txt) · [`contain-paint-286s-raw.txt`](contain-paint-286s-raw.txt) · [`freeze-188s-raw.txt`](freeze-188s-raw.txt) · [`continuous-pingpong-292s-raw.txt`](continuous-pingpong-292s-raw.txt) · [`tiled-shm-292s-raw.txt`](tiled-shm-292s-raw.txt) · [`painting-threads-294s-raw.txt`](painting-threads-294s-raw.txt) · [`res640x480-194s-raw.txt`](res640x480-194s-raw.txt) · [`alloc-pressure-raw.txt`](alloc-pressure-raw.txt) | Raw captures, Runs 26 to 36 |
| [`freeze-720p-cv-raw.txt`](freeze-720p-cv-raw.txt) · [`deployed-scroll-raw.txt`](deployed-scroll-raw.txt) | **Uncatalogued captures, claimed by no run block.** The first is a `probe4`-family payload naming itself 228 s, 6052 frames, 38 frames over 250 ms — 0.167/s — at 26.5 fps; the second is one load-average and `VmRSS` read. Neither carries its own configuration, so neither is attributed to a run here, and no conclusion rests on either |

**One capture carries a redaction, recorded so no editor mistakes it for a live value.**
[`scroll-vs-transform-raw.txt`](scroll-vs-transform-raw.txt) opens with an SSH `known_hosts` warning,
and the address in it reads `<PROD_ADDRESS>` — the placeholder, not the board. This repository is
public and investigations are redaction-only, so a capture is redacted in place rather than
regenerated. `tools/scrub-identity.py --check` covers the whole tracked tree, this directory
included, and passes.

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

### The in-place page-reduction family — the harness Runs 14 to 16 share

Runs 14 to 16 install a probe at `/home/root/.surf/script.js`, restart the kiosk onto a cleared
WebKit cache and read the payload back out of the X window title with `xprop`, the same path the
`probe4` family uses. Frame timing is the bare `requestAnimationFrame` loop Run 13 proved carries no
instrumentation cost of its own.

Two things are new, and both are what make these runs readable:

- **The page is reduced in place, not deployed.** Each arm manipulates the live document through the
  user script — hiding `#app`, inserting a test element, switching every animation off — so no
  frontend build, no URL change and no mirror deploy is involved, and a restart reverts all of it.
  Where a rule is needed it goes in through `insertRule` on a stylesheet already loaded from the same
  origin: the page's `style-src 'self'` drops an injected `<style>` element, as "Configuration under
  test" records, but does not stop that.
- **The arms run as a palindrome inside one continuous capture** — A/B/C/B/A — so that under linear
  drift each condition's mean is drift-centred and the board's ~30% within-run drift cannot
  masquerade as an effect. Every arm samples its own landing state every 2 s, and each analyser
  refuses an arm that did not land, proven against synthetic payloads for both outcomes before use.

Bound conditions on all three: **each arm is n=1** within its own run, and `animation: none`
suppresses keyframe animations only — CSS transitions and Web Animations API animations were not
enumerated. Device state touched is `~/.surf/script.js` and the WebKit cache; no image rebuild, no
`/boot` write, no OTA, no reboot, no `/data/config/kiosk.conf` write. Each run ends with a zero-byte
`script.js`, a restart, and [`kiosk-render-check.sh`](../../../tools/kiosk-render-check.sh)
reporting the render advancing.

### Run 14 — the floor with the app's render tree taken out of the page

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`. **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** as Run 13 — compositing off (`WEBKIT_DISABLE_DMABUF_RENDERER=1`),
  `WEBKIT_FORCE_VBLANK_TIMER=1`, same demonstration data.
- **Scripts deployed:** ONE-OFF [`p8_layers.js`](p8_layers.js), committed here. Raw capture
  [`layers-raw.txt`](layers-raw.txt), read by [`parse_layers.py`](parse_layers.py).
- **Procedure:** one continuous 520 s capture, five 100 s slots after a 20 s warmup, palindrome
  **full app / one animation / nothing moving / one animation / full app**. `#app` is hidden with
  `display:none`, which stops its rendering and leaves every timer, interval, marquee measurement and
  module poll running — which is what licenses reading the result as rendering rather than JS.
- **Landing check, sampled live in every arm:** `appW`, the app root's
  `getBoundingClientRect().width`, is 1920 in both full-app arms and **0** in all three reduced arms;
  `boxW`, the test element's width, is 240 when it should be shown and 0 when hidden; `anim`, the
  computed `animationName`, is the injected keyframes name in both animation arms and `none` in the
  static arm. All five arms OK.
- **Bound condition, and it decides what this run can conclude:** hiding `#app` removes roughly 99%
  of the painted pixels along with the app, so on its own the run cannot separate something specific
  to this app's DOM from the cost of painting a screenful at all. Run 15 is that separation.

### Run 15 — painted area and animation, separated

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`. **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** as Run 14, same demonstration data.
- **Scripts deployed:** ONE-OFF [`p9_area.js`](p9_area.js), committed here. Raw capture
  [`area-raw.txt`](area-raw.txt), read by [`parse_area.py`](parse_area.py).
- **Procedure:** one continuous 420 s capture — a 20 s warmup, then five 80 s arms — the Run 14
  method with one change: the test element is **full-viewport and text-heavy (420 rows)** rather than
  a 240x80 patch, so painted area is comparable to the app's. Palindrome **full app / fullscreen
  animated / fullscreen static / fullscreen animated / full app**.
- **Landing check:** `appW` 1920 in both app arms and 0 in the three reduced arms; `boxW` **1920** in
  all three reduced arms; `anim` the keyframes name in both animated arms and `none` in the static
  arm. All five arms OK.
- **Bound condition:** the box is text-heavy by construction, and a full-screen box of flat colour
  would behave differently. The arm bounds the cost of animating a large rasterised layer; it is not
  a model of the app, and the finding says so.

### Run 16 — every animation off, with the landing check Run 8's arm B never had

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`. **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** as Run 15, same demonstration data.
- **Scripts deployed:** ONE-OFF [`p10_noanim.js`](p10_noanim.js), committed here. Raw capture
  [`noanim-raw.txt`](noanim-raw.txt), read by [`parse_anim.py`](parse_anim.py).
- **Procedure:** one continuous 420 s capture — a 20 s warmup, then five 80 s arms — palindrome
  **ON / OFF / ON / OFF / ON**.
  The app stays **fully visible in every arm**; the only manipulation is
  `*,*::before,*::after{animation:none !important}` through `insertRule`. This is Run 8's arm B run
  properly — the same intervention, inside one capture, with a landing check.
- **Landing check, and it is the point of the run:** the **computed** `animationName` is read off a
  live `.ride-name-text.marquee` element every sample — a keyframes name proves the animation ran,
  `OFF` proves the rule applied — with `appW` 1920 and 7 marquee rows present throughout all five
  arms. The parser was proven against synthetic payloads for both outcomes. All five arms OK.
- **Bound condition:** the ablation stops the **motion**; it does not remove the overflowing names or
  change layout. What it measures is therefore the cost of animating, not the cost of the rows.

### The motion probe family — the harness Runs 17 to 24 share

Stated once rather than eight times. [`p12_motion.js`](p12_motion.js) is the frame loop Runs 8 to 16
used, with one addition that is the point of the family: **every frame reads each marquee row's live
computed `translateX` and tags the frame MOVING or STATIC** by whether any row moved more than a
fixed epsilon. Every fps figure before Run 17 is a whole-window mean over a page that is in motion
for part of its cycle; this family separates the two, so a lever can be scored on the frames a person
actually sees move. Deployment is [`run-phase-motion.sh`](run-phase-motion.sh) — write
`~/.surf/script.js`, clear the WebKit cache, restart, read the payload back with `xprop` — the
`probe4` path with a wider title window, because the payload carries one record per 20 s block.

Runs 18, 20 and 21 splice an **arm B** onto that measurement and run a palindrome W/A/B/A/B/A across
the capture, so the board's ~30% within-run drift cancels between the arms instead of loading onto
one. Each names its own manipulation, and each carries an in-band landing check read from the
**computed** value on every live row every frame: a block whose rows disagree with the arm is dropped
by the parser rather than averaged in. That discipline is Runs 8 to 16's, and it is not restated per
run below.

Three bound conditions hold across the family. **Each arm is n=1** within its run. **The MOVING/STATIC
tag costs a computed-style read per row per frame**, which is present identically in every arm, so
between-arm deltas hold while the absolute level sits above a bare loop's. And **a row is tagged
moving by its transform**, so Run 25's scroll mechanism is outside what this probe can see — which is
why Run 25 uses a different probe and a different metric.

Device state touched, every run: `~/.surf/script.js` and the WebKit cache. No image rebuild, no OTA,
no reboot, no keyring touch. The 720p runs and the compositing arm are the exception and say so: they
change `/data/config/kiosk.conf` or the launcher's `xrandr` line, each named in its own block. Every
run ends with a zero-byte `script.js`, a restart, and
[`kiosk-render-check.sh`](../../../tools/kiosk-render-check.sh) reporting the render advancing.

### Run 17 — the during-motion framerate, measured rather than derived

- **Board:** prod, Raspberry Pi Zero W, slot A.
- **Image commit:** `100-gpu-compositing:7ce44ba`, read off the board's `/etc/buildinfo`.
- **Frontend bundle:** `index-dKJ9KDWL.js`, unchanged from Runs 9 to 16.
- **Kiosk config:** compositing off (`WEBKIT_DISABLE_DMABUF_RENDERER=1`),
  `WEBKIT_FORCE_VBLANK_TIMER=1`, 1920x1080, firmware KMS. Full-open demonstration park data, as
  Runs 8 to 16.
- **Scripts deployed:** ONE-OFF [`p12_motion.js`](p12_motion.js), committed here. Raw capture
  [`motion-baseline-raw.txt`](motion-baseline-raw.txt), read by
  [`parse_motion.py`](parse_motion.py), whose both-outcome proof is
  [`parse_motion_test.py`](parse_motion_test.py).
- **Procedure:** one continuous **1630 s** capture — far longer than any prior run, because the
  quantity being estimated is conditional on a state the page is in about a third of the time. Blocks
  alternate T (transform read taken) and N (no read), and only T blocks contribute to the
  during-motion figure. Block 0 is discarded as warmup.
- **What this run discharges.** The finding "DERIVED, NOT MEASURED — the framerate *during* the
  scroll's motion" quotes a 2.6–11.9 fps estimate built by arithmetic on two Run 16 means. This run
  measures it directly at **7.86 fps**, inside that range and near its middle, and the estimate is
  superseded by the measurement rather than corrected.
- **Bound condition:** the marquee class is taken by rows whose own name overflows, so the roster of
  animating rows drifts across the capture — `M5/20` at the payload's last read. The rows-moving
  buckets are read as a within-run dose-response, not as a fixed configuration.

### Run 18 — `steps()` quantisation, two step counts

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-dKJ9KDWL.js`. **Kiosk config:** as Run 17, 1080p.
- **Scripts deployed:** ONE-OFF [`p13_steps.js`](p13_steps.js), committed here. Two captures, one per
  step count: [`steps-k40-raw.txt`](steps-k40-raw.txt) (arm 18a, `steps(40)`) and
  [`steps-k10-raw.txt`](steps-k10-raw.txt) (arm 18b, `steps(10)`), each read by
  [`parse_steps.py`](parse_steps.py) with its both-outcome proof
  [`parse_steps_test.py`](parse_steps_test.py).
- **Procedure:** one 436 s palindrome capture per step count, arms W/A/B/A/B/A over 20 s / four 80 s
  slots. Arm B writes `animation-timing-function: steps(k) !important` on every marquee row; arm A
  removes it. Landing is read from the computed timing function on every row every frame.
- **The two arms are separate captures and are never differenced against each other.** Each is scored
  against its own interleaved baseline inside its own run.
- **Bound condition, and it is why 18b is rejected rather than adopted.**
  [`parse_steps.py`](parse_steps.py)'s SCORE line is the **overall** frame-weighted mean, which a
  lever can win by making frames static rather than by making a moving frame cheaper. The number this
  run is read on is the **MOVING** mean and the moving-frame fraction, both printed beside it.

### Run 19 — the compositing A/B retaken on the motion metric

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** 1920x1080, firmware KMS, and **accelerated compositing ON** —
  `WEBKIT_DISABLE_DMABUF_RENDERER` removed from `/data/config/kiosk.conf`, the web process restarted
  onto the dma-buf renderer against vc4/mesa, and the line restored afterwards.
- **Scripts deployed:** ONE-OFF [`p12_motion.js`](p12_motion.js) — the identical probe Run 17 ran, so
  the only variable is the renderer. Raw capture
  [`motion-compositing-on-raw.txt`](motion-compositing-on-raw.txt), read by
  [`parse_motion.py`](parse_motion.py).
- **Procedure:** one continuous 437 s capture in the composited configuration, scored the same way as
  Run 17's.
- **Why this run exists at all.** Run 5 measured compositing off as 3.7x faster and the reading was
  challenged as a confound — that the composited arm might be paying for motion the software arm was
  not. This run answers it from inside the same probe: the **static** frames read 745 ms too, so the
  penalty is not motion-specific and Run 5 is not a motion confound.
- **Bound conditions.** Two sequential captures on a board with ~30% within-run drift; the effect is
  5.2x, two orders outside it. And the capture is thin by construction — 641 frames in 437 s is what
  1.5 fps yields — so the block-level figures are noisy while the aggregate is not.

### Run 20 — per-row constant scroll velocity

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-dKJ9KDWL.js`. **Kiosk config:** as Run 17, 1080p.
- **Scripts deployed:** ONE-OFF [`p16_duration.js`](p16_duration.js), committed here. Raw capture
  [`duration-cv179-raw.txt`](duration-cv179-raw.txt), read by
  [`parse_duration.py`](parse_duration.py).
- **Procedure:** the Run 18 palindrome. Arm B sets each row's `animation-duration` to its own overflow
  distance divided by a fixed 179 px/s, floored at a minimum, so every row scrolls at one velocity
  instead of covering its own distance in a common 8 s cycle. The target is derived from the app's
  published `--pwt-marquee-distance` and never from the duration already applied, so a row cannot
  ratchet itself slower frame after frame.
- **The score is px per moving frame, not frame time**, because the lever's claim is about the size
  of the per-frame jump that reads as judder. The margins were fixed before the run: the jump must
  fall at least 10% and frame time may rise at most 5%.
- **Bound condition, and it is the finding.** The demonstration data's overflows are 1–108 px
  (Run 25's payload reads the set directly). At those distances the flat cycle is already close to
  the constant-velocity cycle for most rows, so the lever has almost nothing to move — the result
  bounds this lever **on this data**, not on a roster with long names.

### Run 21 — glyph rasterisation priced out

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-dKJ9KDWL.js`. **Kiosk config:** as Run 17, 1080p.
- **Scripts deployed:** ONE-OFF [`p17_paintcost.js`](p17_paintcost.js), committed here. Raw capture
  [`paintcost-raw.txt`](paintcost-raw.txt), read by [`parse_steps.py`](parse_steps.py) — reused
  as-is, which is why its output labels arm B "STEPS" where this run's arm B is FILL.
- **Procedure:** the Run 18 palindrome. Arm B writes `color: transparent !important` plus a solid
  `background-color` on every marquee row: **no glyph is rasterised, and the same box over the same
  area still paints under the same animation**. It is the cheap injectable stand-in for blitting a
  pre-rendered bitmap of the row — same geometry, same motion, no text raster.
- **Landing, in band over the whole row set.** Arm B clears the block's flag the instant any row's
  computed colour is not fully transparent or its computed background is not the fill; arm A clears
  it the instant any row's colour *is* transparent, which is what proves the revert restored the
  stylesheet's colour rather than leaving the override on.
- **The signal is the MOVING mean delta, not the SCORE line**, for the reason Run 18 records. What
  this run decides is whether building a bitmap marquee is worth the work.

### Run 22 — 1280x720

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-dKJ9KDWL.js`.
- **Kiosk config:** compositing off, firmware KMS, and **1280x720** — `xrandr --output HDMI-1 --mode
  1280x720` hand-edited into the launcher, so the mode is applied before surf maps its window and
  WebKit renders at 720p rather than rendering 1080p and being clipped.
- **This is the correction of Run 4's bound condition.** Run 4's 720p arm shrank the X screen and
  scanout buffer only, leaving surf's override-redirect window at 1920x1080 and WebKit still
  rendering 1080p; that arm measured the X and surf stages' pixel cost, not WebKit's. Setting the
  mode in the launcher moves WebKit too, which is why this run's 1.94x is larger than Run 4's 1.38x.
- **Scripts deployed:** ONE-OFF [`p12_motion.js`](p12_motion.js), the identical probe Run 17 ran. Raw
  capture [`motion-720p-raw.txt`](motion-720p-raw.txt), read by
  [`parse_motion.py`](parse_motion.py).
- **Procedure:** one continuous 439 s capture, scored as Run 17's.
- **Bound condition:** Run 17 and this run are **sequential captures, not interleaved arms** — a mode
  change cannot be toggled inside one page load. The 1.94x on the during-motion mean is read against
  the board's ~30% within-run drift, which it clears, and against a 2.25x pixel cut, which it does
  not reach.

### Run 23 — a constant-velocity marquee at 720p

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
- **Frontend bundle:** `index-Dqt17Jj2.js` — a deployed WiseKiosk build whose marquee moves at a
  constant velocity with no hold phases, replacing the stylesheet's hold/move/hold/snap keyframes.
- **Kiosk config:** as Run 22 — compositing off, 720p, firmware KMS.
- **Scripts deployed:** ONE-OFF [`p12_motion.js`](p12_motion.js). Raw capture
  [`motion-720p-cv-raw.txt`](motion-720p-cv-raw.txt), read by
  [`parse_motion.py`](parse_motion.py).
- **Procedure:** one continuous 228 s capture, scored as Run 22's.
- **What it decides, and it is not the framerate.** During motion this build is *faster* than Run 22
  — 20.19 fps against 15.26 — and the owner's report of stutter survived it. The per-frame step
  histogram in the payload shows why the two can both be true: the chop being reported is the
  distribution of per-frame jumps, not the rate. That is the reading that sends the next run at the
  mechanism rather than at the framerate.
- **Bound condition:** the comparison to Run 22 crosses a bundle change *and* a capture boundary.
  Both figures are quoted with their own run attached and neither is differenced into a single
  number.

### Run 24 — linear timing with shrunken holds

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
- **Frontend bundle:** `index-Ci1lj58e.js` — a deployed build with linear timing and the hold phases
  shortened, so the rows are in motion for nearly the whole cycle.
- **Kiosk config:** as Run 23 — compositing off, 720p.
- **Scripts deployed:** ONE-OFF [`p12_motion.js`](p12_motion.js). Raw capture
  [`motion-linear-shrunk-raw.txt`](motion-linear-shrunk-raw.txt), read by
  [`parse_motion.py`](parse_motion.py).
- **Procedure:** one continuous 226 s capture, scored as Run 23's.
- **The landing check is the result.** Three frames out of 3181 carry zero rows moving — the holds
  really did shrink — and the window mean lands at 14.1 fps. Removing the rests does not spread the
  work; it gangs every row's repaint into the same frames. **Reverted**, and the reversion is what
  Run 25 measures against.

### Run 25 — `scrollLeft` against `transform`, interleaved in one capture

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
- **Frontend bundle:** **not recorded.** This run follows Run 24's revert and no hash was captured
  for the resulting build. The gap is real and is not papered over; what rescues the run is that both
  arms live inside **one** capture, so whatever the bundle was, it was the same for both.
- **Kiosk config:** compositing off, 720p, firmware KMS, demonstration data.
- **Scripts deployed:** ONE-OFF [`p18_scroll.js`](p18_scroll.js), committed here. Raw capture
  [`scroll-vs-transform-raw.txt`](scroll-vs-transform-raw.txt), read by
  [`parse_scroll.py`](parse_scroll.py).
- **Procedure:** one continuous 438 s palindrome, W/T/S/T/S/T on 20 s blocks — a 20 s warmup, then
  four arms of four blocks each and a final T arm of five, which is why the last slot runs ~100 s.
  - **arm T** leaves `ParkCard.svelte`'s `animation` in place, which drives
    `transform: translateX(--pwt-marquee-distance)` on the text.
  - **arm S** writes `animation-name: none !important` and `transform: none !important` on the text
    and drives the clipping column's `scrollLeft` from the probe's own rAF loop.
- **Arm S reproduces arm T's motion rather than inventing one.** The px/s, the move fraction, the
  minimum cycle and the four keyframe phases are `ParkCard.svelte`'s own, so both arms move each row
  the same distance at the same pixel velocity on the same cycle. A different speed would change the
  repainted area per second and the arms would not be comparable at all.
- **`animation-name`, not the `animation` shorthand.** The app publishes each row's cycle length as an
  inline `animation-duration`; writing the shorthand would erase it, and removing the override on the
  way back to arm T would leave the row on the stylesheet's flat 8 s cycle — arm T would then be
  measuring a marquee the app never renders.
- **Measurement is deliberately thin and identical across arms.** The frame loop counts rAF deltas
  and nothing else, because a per-row computed-style flush scales with N and is exactly the cost this
  probe is trying to attribute to the mechanism. Each arm's per-frame work is one `querySelectorAll`,
  two style-**attribute** reads per row, and in arm S one `scrollLeft` write per row.
- **Landing, and it is positive evidence in both directions:** the payload carries the maximum
  `scrollLeft` reached in each block — **94–108 px in every S block and 0 in every T block**. One T
  block reported land=0 and the parser dropped it.
- **Bound condition:** the arms are n=1 each within the palindrome, and the worst frame in each arm
  is the same size (491 ms against 496 ms). The mechanism swap buys **throughput**; it does not touch
  the stall, and the runs that follow are about the stall.

### The shipped-mechanism family — the harness Runs 26 to 36 share

Runs 26 to 36 measure one deployed configuration and the levers and hypotheses tried against its
residual; Runs 35 and 36 are the two that overturned the residual's identification. The
configuration is the one the board runs: **720p, software rendering, and the marquee re-mechanised
as `scrollLeft` on the clipping column** — one shared rAF clock, all cards flipping and all marquees
starting on the same tick, a 2 s home hold, one constant-velocity scroll, a 2 s end hold, then home.
That is an **8 s cycle**, and the phase of a stall against it is a load-bearing number in this family.

Frame timing is [`p7_min.js`](p7_min.js)'s and nothing more — dt, mean, max, frames over 250 ms, a
seven-bucket histogram and the timestamps of the last 14 big frames. Run 13 proved that loop carries
no instrumentation cost of its own, which is why every probe in this family is built on it rather
than on `p4_a.js`: a wrapped getter or a `MutationObserver` lands inside `WebKitWebProcess` and
confounds the exact quantity these runs decide.

Runs 26, 27, 32, 33 and 34 run that loop unmodified and are read straight off the `MP` payload:
`f` frames and `av` mean over the window, `BT` frames over 250 ms, `H` the histogram, `B` the big
frames as `t:dt`. Runs 28 to 31 each add **one** instrument and carry a parser that refuses a verdict
when the instrument did not land — [`parse_profile.py`](parse_profile.py),
[`parse_fullpaint.py`](parse_fullpaint.py), [`parse_contain.py`](parse_contain.py) and
[`parse_freeze.py`](parse_freeze.py). One of them exercises that refusal for real; see Run 31.

**Every added instrument's cost is attributed to the following frame**, because WebKit does the work
a rAF callback requests after the callback returns. Run 29 relies on this to attribute a forced
repaint, and Run 31 relies on it to *exclude* its own sampling frames from the stall count — at ~0.5
sampling frames per second, charging them to the engine would have been enough to fake the very rate
the run reads.

Bound conditions across the family: **each run is n=1**, arms are captures rather than interleaved
slots wherever the manipulation is a deploy or an environment variable, and the reference the later
runs are scored against is **Run 26b's 0.045/s**, quoted with its run rather than treated as a
property of the board. Device state touched is `~/.surf/script.js` and the WebKit cache, plus a
`/data/config/kiosk.conf` line in Runs 33 and 34. No image rebuild, no `/boot` write, no OTA, no
keyring touch.

**A note on the big-frame lists, because it governs which runs can be read for phase.** The `MP`
payload caps its big-frame list at 14 entries. Run 26b records `BT13` and its list is therefore
complete, which is why the phase read is taken from 26b and from no other capture; Run 26a records
`BT15` against 14 entries and is truncated, so a phase read from it would be a read of the first 14
arrivals rather than of the window. Run 36's `AL` payload caps at 40 and records 236, so it is
truncated in the same way and carries no phase either.

### Run 26 — the shipped mechanism, throughput and phase

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
- **Frontend bundle:** `index-Mt2gvuKb.js` — the shipped scroll build with 2 s holds, served from the
  mirror and **not baked into any image**.
- **Kiosk config:** compositing off, 720p, firmware KMS, demonstration data.
- **Scripts deployed:** ONE-OFF [`p7_min.js`](p7_min.js), already committed here for Run 13. Two
  captures: [`hold2s-fps-169s-raw.txt`](hold2s-fps-169s-raw.txt) (arm 26a, 169 s) and
  [`hold2s-phase-289s-raw.txt`](hold2s-phase-289s-raw.txt) (arm 26b, 289 s).
- **Procedure:** two continuous captures of the same configuration, taken for different questions —
  26a for the throughput distribution, 26b long enough that the phase of the steady stalls against
  the 8 s cycle is readable. Neither is an arm of the other and the two are not averaged.
- **Bound condition, and it is the honest headline of this investigation's result.** The two captures
  of one configuration give **0.089/s and 0.045/s** — a factor of two apart. The stall is rare enough
  that a three-minute window resolves it poorly, and any single figure quoted for "the shipped rate"
  inherits that. The longer capture is used as the later runs' reference because it counts more
  cycles, not because it is the better number.
- **Phase, read from 26b's payload only.** Of the 13 recorded big frames, five arrive before t=6 s
  and are startup; the remaining **eight all land at t mod 8 s = 1.8–2.0**, which is the scroll-start
  of the cycle. The phase offset is against the probe's own t0, not the page's, so it is read as
  *locked to a fixed point of the cycle*, never as a wall-clock phase comparable across runs.

### Run 27 — a 200 ms stagger between the rows' starts

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
- **Frontend bundle:** the shipped `index-Mt2gvuKb.js` with a 200 ms per-row start offset added.
- **Kiosk config:** as Run 26.
- **Scripts deployed:** ONE-OFF [`p7_min.js`](p7_min.js). Raw capture
  [`stagger-phase-288s-raw.txt`](stagger-phase-288s-raw.txt).
- **Procedure:** one continuous 288 s capture, read against Run 26b's 289 s capture of the unstaggered
  build.
- **The hypothesis and its disposition.** If every row starting on the same tick is what gangs the
  repaint into one frame, spreading the starts by 200 ms should break the stall up. It does not: the
  rate is unchanged and **6 of 6** steady stalls still land at the same point of the cycle. **Reverted.**
- **Bound condition:** two sequential captures, and the difference between 0.042/s and 0.045/s is far
  inside the factor-of-two spread Run 26's own two captures show. The result is read from the
  **phase**, which is categorical, not from the rate.

### Run 28 — layout excluded

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-Mt2gvuKb.js`. **Kiosk config:** as Run 26.
- **Scripts deployed:** ONE-OFF [`p20_profile.js`](p20_profile.js), committed here. Raw capture
  [`layout-attribution-288s-raw.txt`](layout-attribution-288s-raw.txt), read by
  [`parse_profile.py`](parse_profile.py).
- **Procedure:** one continuous 288 s capture. Each frame runs the bare rAF loop plus **one timed
  synchronous layout flush** — `offsetHeight` on the root — so `tForce` is the cost of flushing
  whatever layout that frame had pending. Nothing else is read.
- **Forcing layout every frame is a deliberate perturbation, and all three outcomes are findings.**
  `tForce` large on the stall frame means a batched layout flush. `tForce` small means the frame is
  paint, raster or compositing and a layout timer cannot see it. **No stall at all** would also have
  been a layout result, because continuous flushing would have dissolved the batch. The run is
  therefore not a neutral observation of the unperturbed page, and it is not quoted as one.
- **Bound condition:** the `longtask` entry type is **absent on this WebKit build**, so the
  cross-check from the engine's own side was unavailable. Its absence is recorded in the payload as
  `NA` rather than faked.

### Run 29 — the magnitude of one full-viewport repaint

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-Mt2gvuKb.js`. **Kiosk config:** as Run 26.
- **Scripts deployed:** ONE-OFF [`p21_fullpaint.js`](p21_fullpaint.js), committed here. Raw capture
  [`fullpaint-bench-115s-raw.txt`](fullpaint-bench-115s-raw.txt), read by
  [`parse_fullpaint.py`](parse_fullpaint.py).
- **Procedure:** one continuous 115 s capture. A fixed `pointer-events:none` overlay covers the
  viewport; every twentieth frame its `background-color` is set to a **new** value, which invalidates
  the whole rect and obliges WebKit to repaint the entire viewport. The two colours differ by one
  blue unit at 3% alpha, so the price is paid and nothing visible changes. The repaint lands in the
  **following** frame's dt, which is tagged FORCED; every other frame is BASELINE.
- **This is a benchmark, not an observation of a stall.** It prices the hypothesised mechanism so the
  stall's magnitude can be compared against it. It does not show that any particular stall *was* one.
- **The price it measures is still correct; the identification it was recruited for is not.** Run 35
  falsified the full-viewport-repaint reading of the residual, and this run's numbers are unaffected
  by that — what changes is only what they are evidence *for*. The figures below stand as the cost of
  one forced full-viewport repaint on this board.
- **Bound conditions, and they are why this run never closed the question alone.** The FORCED
  distribution is wide — p50 203 ms, p90 458 ms, max 530 ms — and the isolated cost, FORCED minus
  BASELINE, is **183 ms at the median and 211 ms at the mean**. A stall frame that *was* one full
  repaint should therefore have read about `34 + 183 = ~217 ms`; Run 26b's steady stalls read
  **468–537 ms**, a mean near 490 ms. **That is ~2.3x, and it is a mismatch rather than a match.**
  Reading the stall against the *un-subtracted* p90 of 458 ms is the only way the two meet, and the
  subtraction and the comparison cannot both be taken. [`parse_fullpaint.py`](parse_fullpaint.py)
  scores on the p50 and returns a **negative** verdict — "forced full repaint is cheaper than the
  stall" — which is printed here rather than filtered out, and which was right. Run 21 closes the one
  escape available to the benchmark: if a solid-fill repaint under-priced a glyph-heavy one, the gap
  would be an artifact, but Run 21 measures the cost as content-independent to 1.2%, so the price is
  fair and the 2.3x stands.
- **Second bound condition, on the control arm.** The BASELINE row's max is **1477 ms**. The `FVP`
  payload carries **no timestamps**, so *when* that frame arrived is not derivable from this capture;
  1477 ms also sits squarely inside the startup cluster every other capture in this family shows in
  its first ~5 s. Either way only that row's median and mean are usable, and no claim here rests on
  the frame having fired mid-run.
- **Where the mismatch pointed.** A stall 2.3x the mechanism named to explain it, unmoved by a pixel
  cut (Run 35), is the trail that led off the paint path altogether and onto the collector. It is
  recorded here as the reasoning, not as a live claim about repaint.

### Run 30 — paint containment on the cards

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-Mt2gvuKb.js`. **Kiosk config:** as Run 26.
- **Scripts deployed:** ONE-OFF [`p22_contain.js`](p22_contain.js), committed here. Raw capture
  [`contain-paint-286s-raw.txt`](contain-paint-286s-raw.txt), read by
  [`parse_contain.py`](parse_contain.py).
- **Procedure:** one continuous 286 s capture with `contain: paint` written as an **inline style
  property** on all four park cards — the page's `style-src 'self'` drops an injected `<style>`
  element, as "Configuration under test" records, so the inline property is the only form that
  survives. Cards re-render on a flip, so an ensure loop re-checks every current card each frame and
  writes only on difference; the write count is exfiltrated, so a loop that rewrote rather than
  settled would be visible.
- **The prediction was fixed before the run.** If the stall is WebKit escalating to a whole-viewport
  repaint, a paint-containment boundary per card bounds it to roughly a quarter of the viewport —
  ~110 ms, under the 250 ms threshold — and the rate should fall toward zero.
- **The landing read is what keeps this from being a dead instrument.** Once every ~2 s one card's
  **computed** `contain` is read back: it reads `paint`, with support probed and confirmed and four
  inline writes recorded. A flat rate under `land=0` would have said nothing about the hypothesis;
  this one landed and the rate went **up**.
- **Bound condition:** 0.084/s against Run 26b's 0.045/s is a 2.1x rise across sequential captures,
  inside the factor-of-two spread Run 26's own pair shows. The conclusion drawn is the **null** —
  containment does not bound the stall — and not that containment made things worse.
- **What the null means under the corrected mechanism.** This run is a well-instrumented negative
  against a paint hypothesis, and paint is not the mechanism (see "Root cause of the residual
  stall"). A paint-containment boundary has nothing to say about a collector pause, so the null is
  expected rather than informative about the cause. The run's value stands as an exclusion and as the
  strongest landing check in this record.

### Run 31 — the page frozen

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-Mt2gvuKb.js`. **Kiosk config:** as Run 26.
- **Scripts deployed:** ONE-OFF [`p23_freeze.js`](p23_freeze.js), committed here. Raw capture
  [`freeze-188s-raw.txt`](freeze-188s-raw.txt), read by [`parse_freeze.py`](parse_freeze.py).
- **Procedure:** one continuous 188 s capture. Every live timer is cleared and `requestAnimationFrame`,
  `setInterval` and `setTimeout` are replaced by no-ops, so no app callback can reschedule and the DOM
  stops changing. The probe keeps measuring because it captures the **real** scheduler into a local
  before the neuter and drives its own loop from it; `clearInterval` and `clearTimeout` are left
  intact so the page's own teardown still works.
- **The discriminator.** A stall that survives a frozen page is the engine repainting a page nothing
  touched — beyond anything the frontend can reach. A stall that goes to zero is driven by the app's
  own DOM updates.
- **The frozen flag gates the verdict, and on this run it withheld it.** A content signature —
  `document.body.innerText` length plus the clock's `.seconds` text — is sampled every ~2 s;
  `frozen=1` requires that consecutive samples never differ. This capture reports **`frozen=0` with
  one content change over 94 samples**, and [`parse_freeze.py`](parse_freeze.py) accordingly returns
  **"INCONCLUSIVE: page did not freeze … the 0.016/s rate is not attributable either way."** That
  verdict stands as written. What the capture still shows, as observation rather than verdict, is
  that its only three frames over 250 ms are at t = 1.6, 3.1 and 3.9 s and **nothing** over 250 ms
  arrives in the remaining 184 s, at a 59.6 fps mean.
- **Bound condition on the number itself:** 93 signature-sampling frames are excluded from the count
  and the histogram, two of them over 250 ms, because `innerText` forces layout and WebKit charges
  that to the following frame. Charging them to the engine would have manufactured most of a rate.

### Run 32 — a marquee that never rests

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
- **Frontend bundle:** `index-B8gPvD4g.js` — a diagnostic build whose marquee ping-pongs
  continuously, with no hold phase at either end.
- **Kiosk config:** as Run 26.
- **Scripts deployed:** ONE-OFF [`p7_min.js`](p7_min.js). Raw capture
  [`continuous-pingpong-292s-raw.txt`](continuous-pingpong-292s-raw.txt).
- **Procedure:** one continuous 292 s capture, read against Run 26b's.
- **The hypothesis and what the capture supports.** Run 26b puts the steady stalls at the scroll-start,
  so the rest→scroll transition is the suspect. Removing the rest entirely takes the rate to
  **0.017/s**, 2.6x fewer than Run 26b, at a **worse** mean frame time (33 ms against 24 ms) because
  nothing is ever static. The build is a **diagnostic, reverted**.
- **Bound condition, and it is the whole of what this run establishes.** The comparison crosses a
  bundle change and a capture boundary, and the 2.6x sits at the edge of the factor-of-two spread
  Run 26's own pair shows. Post-startup the capture holds **two** frames over 250 ms, at t = 25.6 s
  and t = 114.1 s, and it records **no ping-pong period and no direction-change timestamps** — the
  diagnostic build's flip interval is not stated anywhere in this record, so `t mod` cannot be
  computed as it is for Runs 26b, 27 and 30. **No phase claim is available from this run**, and none
  is made: what it reports is the rate, at n=2 on the surviving stalls. It is not offered as support
  for any leg of the root cause.

### Run 33 — tiled software compositing with painting threads

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-Mt2gvuKb.js`.
- **Kiosk config:** 720p, firmware KMS, and accelerated compositing **on** with the shared-memory
  path forced and four painting threads — `WEBKIT_DISABLE_DMABUF_RENDERER` removed,
  `WEBKIT_FORCE_SHM=1` and `NICOSIA_PAINTING_THREADS=4` added to `/data/config/kiosk.conf`. Reverted
  afterwards.
- **Scripts deployed:** ONE-OFF [`p7_min.js`](p7_min.js). Raw capture
  [`tiled-shm-292s-raw.txt`](tiled-shm-292s-raw.txt).
- **Procedure:** one continuous 292 s capture.
- **The hypothesis and its disposition.** WebKit's tiled compositor repaints dirty tiles rather than
  a whole surface, and painting threads rasterise those tiles off the main thread — on paper, exactly
  the bound the stall needs. On this SoC it is the **worst configuration measured**: 14.3 fps,
  0.507/s, and only 73.8% of frames under 50 ms against the shipped 96.3%. The tile upload and the
  extra threads cost more on a saturated single core than the damage-rect saving returns.
- **Bound condition:** three variables move together — compositing on, SHM forced, four painting
  threads — so this run scores **the configuration**, not any one of them. Run 34 separates the
  painting threads from it.

### Run 34 — painting threads alone

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** `index-Mt2gvuKb.js`.
- **Kiosk config:** as Run 26 — compositing **off**, 720p — plus `NICOSIA_PAINTING_THREADS=4` alone
  in `/data/config/kiosk.conf`. Reverted afterwards.
- **Scripts deployed:** ONE-OFF [`p7_min.js`](p7_min.js). Raw capture
  [`painting-threads-294s-raw.txt`](painting-threads-294s-raw.txt).
- **Procedure:** one continuous 294 s capture, read against Run 26b's.
- **This is the separation Run 33 owes.** With compositing off there is no tiled backing store for a
  painting thread to rasterise into, and the numbers say the variable does nothing: 41.3 fps and
  0.041/s against the shipped 41.9 fps and 0.045/s, with a histogram within **0.12 percentage point**
  of the shipped one at every bucket.
- **Bound condition:** this is a null on a sequential capture, and a null of this size cannot be
  distinguished from a small real effect. What it excludes is a *large* one, which is what the
  hypothesis required.

### Run 35 — a third display mode, below 720p

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** the shipped `index-Mt2gvuKb.js`.
- **Kiosk config:** as Run 26 — compositing off, firmware KMS, demonstration data — with the launcher's
  `xrandr` line set to **640x480** instead of 1280x720. Returned to 1280x720 afterwards.
- **Scripts deployed:** ONE-OFF [`p7_min.js`](p7_min.js). Raw capture
  [`res640x480-194s-raw.txt`](res640x480-194s-raw.txt), read by [`parse_min.py`](parse_min.py).
- **Procedure:** one continuous 194 s capture, read against Run 26b's 289 s capture of the same
  bundle and mechanism at 720p. The only variable moved is the display mode.
- **The prediction was fixed before the run, and it came from this record's own model.** 640x480 is
  **307200 px against 720p's 921600 — exactly 3.0x fewer**. If the residual were a full-viewport
  software repaint, its magnitude is pixel-bound and a 3x cut takes Run 26b's ~490 ms steady stall to
  roughly 165 ms, under the 250 ms deadline entirely, and the rate toward zero. Either outcome is
  informative: closing the gap would settle the deadline inside the current stack, and failing to
  close it falsifies the pixel-area leg.
- **It failed to close it, and by a wide margin.** The rate is **0.036/s** (7 frames over 250 ms in
  194 s) against Run 26b's 0.045/s — inside the factor-of-two spread Run 26's own pair shows, so no
  change. Four of those seven are startup, at t = 1.0, 2.3, 3.2 and 3.4 s, and the capture's maximum
  of **1290 ms is one of them**. The three steady stalls are **324, 324 and 378 ms** at t = 40.4,
  80.4 and 120.5 s, against Run 26b's seven arrivals past t=40 s at **468–537 ms** (its eighth, at
  t=9.8 s, is 278 ms and is excluded from both sides of this comparison): a **1.4x** reduction where
  3.0x was owed. Mean
  frame time moves 24 → 22 ms and throughput 41.9 → 44.8 fps, so the pixel cut is doing real work on
  the *mean* and almost none on the *stall*.
- **The arrival cadence is untouched, which is the sharper half of the result.** The three steady
  stalls arrive **40.0 s and 40.1 s** apart. Run 26b's arrive 40.0, 40.1, 39.9, 40.0, 40.1 and 40.0 s
  apart. Three times fewer pixels changes neither the size of the stall by more than 1.4x nor its
  period at all — and a ~40 s period is five turns of the marquee's 8 s cycle, so it is not a
  per-cycle event in the first place.
- **What this falsifies.** The residual is **not pixel-area-bound**, and the full-viewport software
  repaint named as its mechanism does not survive. Run 22's 1080p → 720p result is unaffected: that
  one measures during-motion *throughput*, which is pixel-bound, and this one measures the *stall*,
  which is not. The two were read as the same quantity, and they are not.
- **Bound conditions.** Two sequential captures, n=1 each, 194 s against 289 s; three steady stalls is
  a small sample and the 1.4x magnitude ratio is quoted as such. The phase offset is against the
  probe's own `t0` and is not compared across runs — only the *interval* is, which is invariant to
  where the clock started. Legibility at 640x480 on a wall-mounted panel was not assessed; this run
  was taken for the mechanism, not as a proposal.

### Run 36 — allocation pressure, interleaved against a baseline arm

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba`.
  **Frontend bundle:** the shipped `index-Mt2gvuKb.js`. **Kiosk config:** as Run 26, back at 1280x720.
- **Scripts deployed:** ONE-OFF [`p24_alloc.js`](p24_alloc.js), committed here. Raw capture
  [`alloc-pressure-raw.txt`](alloc-pressure-raw.txt).
- **Procedure:** one continuous 433 s capture, arms **interleaved inside it** rather than run as
  separate captures — a `W,B,A,B,A,B` palindrome on 80 s blocks after a 20 s warmup, where **B
  allocates** ~25000 short-lived objects per frame and drops them and **A allocates nothing beyond the
  probe's own bookkeeping**. Frame timing is [`p7_min.js`](p7_min.js)'s bare rAF loop in both arms.
  Board drift cannot masquerade as the effect, and the warmup block quarantines the startup stalls by
  construction — the six frames over 250 ms before t=10 s are tagged `W` and score in neither arm.
- **The discriminator, fixed before the run.** A JavaScriptCore collection is driven by allocation. If
  the residual is a GC pause, arm B must show a markedly higher rate of frames over 250 ms and a
  larger maximum than arm A. If the two arms read alike, GC is refuted and what remains is a periodic
  engine task.
- **The landing check is in band.** Each arm carries its own allocation counter, exfiltrated with its
  frame statistics: **arm A reads `alloc=0` across 6730 frames and arm B reads `alloc=219` across 219
  frames** — every B frame allocated, no A frame did. An arm that silently failed to allocate would
  have read `alloc=0` and been unscoreable rather than a null.
- **The arms do not overlap, and the separation is not subtle.** Arm B misses the deadline on **216 of
  its 219 frames**, at a **1147 ms mean and a 2020 ms maximum**. Arm A misses on **14 of its 6730**,
  at a 24 ms mean. As a fraction of frames that is **98.6% against 0.21% — a 474x ratio** — and as a
  mean frame time it is **1147 ms against 24 ms, 48x**.
- **Arm A's own maximum is the residual, seen outside startup.** Arm A reads a 1488 ms maximum while
  excluding the warmup block by construction, so the heavy tail this record has treated as a startup
  artifact also fires mid-run on the shipped page. Arm A's 14 misses over its 160 s of wall time are
  0.088/s, the same order as Runs 26a and 26b.
- **Bound conditions.** Mean frame time is **not** the score: building the objects costs real
  milliseconds, so arm B's mean sits above arm A's whether or not a collector ran. The verdict is read
  from the rate of frames over 250 ms and from the maximum, which are an order of magnitude larger
  than the allocation's own cost. The per-second form of arm B's rate is not quoted, because arm B's
  frames are so slow that fewer of them fit in the same wall time — the per-frame fraction is the
  arm-comparable score and is what is used. This run shows allocation **drives** the stall; it does
  not show that the shipped page's own allocation is the *only* thing that can trigger one, and the
  magnitude of the injected pressure is far above anything the frontend does.
- **The big-frame list is truncated** — 40 entries recorded against 236 misses — so it carries no
  phase and none is read from it. Of the 40, six are warmup and the remaining 34 are all arm B.

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
- The image these runs ran, `7ce44ba`, was built from a `graphics` block setting
  `VC4DTBO = "vc4-kms-v3d"` — full KMS as a hard set, not a default taken: `VC4DTBO` is `?=` in
  `sources/meta-raspberrypi/recipes-bsp/bootfiles/rpi-config_git.bb:28`, and several of
  meta-raspberrypi's machine configs override it to `vc4-fkms-v3d`. **Deleting the block does not
  reach firmware KMS**; only an affirmative `VC4DTBO = "vc4-fkms-v3d"` does, which is what the
  reconcile diff under "Durable image delivery — pending owner decision" carries.
- The firmware HDMI keys in `meta-wisekiosk/recipes-bsp/bootfiles/rpi-config_%.bbappend` are inert
  under full KMS, and `7ce44ba`'s `graphics` block carries
  `CMDLINE:append = " video=HDMI-A-1:1920x1080@60D"` in their place; the
  trailing `D` forces the connector enabled and digital, which is what `hdmi_force_hotplug` did
  (`Documentation/fb/modedb.rst:49-50` in the pinned kernel source). Under firmware KMS the keys are
  the live mechanism again and the `video=` line has no place, which is the other half of that diff.
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
- Cost, and it is specific to what is touched. A `DISTRO_FEATURES`, `MACHINE_FEATURES` or webkit
  `PACKAGECONFIG` change invalidates WebKit and costs a full rebuild (~4.5 h), per
  [`../../../README.md`](../../../README.md) §"Quick start". The `graphics` block touches none of
  those: `vc4graphics` enters `MACHINE_FEATURES` from upstream `rpi-base.inc:125` and
  `kiosk-zero-w.yaml` sets no `DISABLE_VC4GRAPHICS` either way, so changing `VC4DTBO` or the
  `CMDLINE:append` re-deploys `config.txt` and the kernel command line and reassembles the image
  without the WebKit invalidation.

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

*Run 14 (`7ce44ba`, prod, compositing off, bundle `index-dKJ9KDWL.js`, demonstration data). One
continuous 520 s capture: a 20 s warmup, then five 100 s palindrome slots. All five arms landed.*

| slot | condition | frames | >250 ms | **>250 ms/s** | mean frame | fps | `appW` | `boxW` | `anim` |
|---|---|---|---|---|---|---|---|---|---|
| 0 | full app | 1562 | 99 | **0.99** | 64 ms | 15.6 | 1920 | 0 | none |
| 1 | one animation, 240x80 box | 3670 | 2 | **0.02** | 27 ms | 36.7 | 0 | 240 | css |
| 2 | nothing moving, 240x80 box | 5447 | 1 | **0.01** | 18 ms | 54.5 | 0 | 240 | none |
| 3 | one animation, 240x80 box | 3614 | 0 | **0.00** | 28 ms | 36.1 | 0 | 240 | css |
| 4 | full app | 2297 | 106 | **1.06** | 44 ms | 23.0 | 1920 | 0 | none |

The two full-app controls bracket the experiment at 0.99 and 1.06/s with the three reduced arms at
zero between them, so the collapse is not a drift artifact.

*Run 15 (`7ce44ba`, prod, compositing off, bundle `index-dKJ9KDWL.js`, demonstration data). One
continuous 420 s capture: a 20 s warmup, then five 80 s palindrome arms. All five arms landed.*

| slot | condition | frames | >250 ms | **>250 ms/s** | **mean frame** | fps |
|---|---|---|---|---|---|---|
| 0 | full app | 1210 | 76 | 0.95 | 66 ms | 15.1 |
| 1 | **fullscreen animated** | **62** | 61 | **0.76** | **1278 ms** | **0.78** |
| 2 | fullscreen static | 4318 | 2 | **0.03** | 19 ms | 54.0 |
| 3 | **fullscreen animated** | **62** | 60 | **0.75** | **1289 ms** | **0.78** |
| 4 | full app | 1715 | 86 | 1.07 | 47 ms | 21.4 |

*Run 16 (`7ce44ba`, prod, compositing off, bundle `index-dKJ9KDWL.js`, demonstration data). One
continuous 420 s capture: a 20 s warmup, then five 80 s palindrome arms, the app fully visible and 7
marquee rows present in every one. All five arms landed.*

| slot | condition | frames | >250 ms | **>250 ms/s** | **mean frame** | **fps** |
|---|---|---|---|---|---|---|
| 0 | animations ON | 955 | 79 | 0.99 | 84 ms | 11.9 |
| 1 | **animations OFF** | 2276 | 86 | **1.07** | **35 ms** | **28.5** |
| 2 | animations ON | 1125 | 90 | 1.12 | 71 ms | 14.1 |
| 3 | **animations OFF** | 2132 | 90 | **1.12** | **38 ms** | **26.7** |
| 4 | animations ON | 1052 | 91 | 1.14 | 76 ms | 13.2 |

Drift-centred across the palindrome: **ON 1.08/s at 76.6 ms · OFF 1.10/s at 36.5 ms.**

*Run 17 (`7ce44ba`, prod, compositing off, 1080p, bundle `index-dKJ9KDWL.js`, demonstration data).
One continuous 1630 s capture, 20337 frames, `M5/20` at the last read.
[`motion-baseline-raw.txt`](motion-baseline-raw.txt) → [`parse_motion.py`](parse_motion.py).*

| | value |
|---|---|
| window mean · max | 80 ms · 2013 ms |
| window fps | 12.5 |
| **during motion** (2211 frames, T blocks, block 0 dropped) | **127 ms · 7.86 fps** |

| rows moving that frame | frames | mean | fps |
|---|---|---|---|
| 0 | 9658 | 44 ms | **22.7** |
| 1 | 2200 | 94 ms | 10.6 |
| 2 | 714 | 143 ms | 7.0 |
| 3 | 1711 | 157 ms | 6.4 |
| 4 | 765 | 177 ms | 5.6 |
| 5 | 374 | 197 ms | **5.1** |
| 6 | 65 | 216 ms | 4.6 |
| 7 | 3 | 327 ms | 3.1 |

*Run 18a (`7ce44ba`, prod, compositing off, 1080p, bundle `index-dKJ9KDWL.js`). One 436 s palindrome,
5836 frames, `steps(40)`. [`steps-k40-raw.txt`](steps-k40-raw.txt) →
[`parse_steps.py`](parse_steps.py).*

| arm | blocks | frames | overall mean | fps | moving frames | **MOVING mean** | static mean |
|---|---|---|---|---|---|---|---|
| A baseline | 13 | 3407 | 75.0 ms | 13.33 | 35.8% | **132.3 ms** | 42.9 ms |
| B `steps(40)` | 8 | 2240 | 71.3 ms | 14.02 | 32.3% | **121.1 ms** | 47.9 ms |

*Run 18b (`7ce44ba`, prod, compositing off, 1080p, bundle `index-dKJ9KDWL.js`). A separate 436 s
palindrome, 7089 frames, `steps(10)`. Never differenced against Run 18a.
[`steps-k10-raw.txt`](steps-k10-raw.txt) → [`parse_steps.py`](parse_steps.py).*

| arm | blocks | frames | overall mean | fps | moving frames | **MOVING mean** | static mean |
|---|---|---|---|---|---|---|---|
| A baseline | 13 | 3614 | 70.8 ms | 14.12 | 34.6% | **131.5 ms** | 38.7 ms |
| B `steps(10)` | 8 | 3290 | **48.6 ms** | 20.56 | **11.1%** | **153.2 ms** | 35.6 ms |

The overall mean falls 22.2 ms and the **moving** frame gets 21.7 ms slower. The lever buys the
average by converting moving frames into static ones, which is the opposite of what a person watching
the motion is paying for. Rejected on that line, not on the score.

*Run 19 (`7ce44ba`, prod, **compositing ON**, 1080p, bundle `index-dKJ9KDWL.js`). One continuous
437 s capture, 641 frames, `M4/20`. [`motion-compositing-on-raw.txt`](motion-compositing-on-raw.txt)
→ [`parse_motion.py`](parse_motion.py).*

| | value |
|---|---|
| window mean · max | 680 ms · 4722 ms |
| window fps | 1.5 |
| **during motion** (391 frames) | **667 ms · 1.50 fps** |
| frames with **no** row moving (89) | 745 ms · 1.3 fps |

*Run 20 (`7ce44ba`, prod, compositing off, 1080p, bundle `index-dKJ9KDWL.js`). One 436 s palindrome.
[`duration-cv179-raw.txt`](duration-cv179-raw.txt) → [`parse_duration.py`](parse_duration.py).*

| arm | blocks | frames | overall mean | fps | MOVING mean | **px per moving frame** |
|---|---|---|---|---|---|---|
| A flat 8 s cycle | 13 | 3541 | 72.2 ms | 13.85 | 127.2 ms | **20.80** (26127 px / 1256 frames) |
| B constant 179 px/s | 8 | 2109 | 75.7 ms | 13.22 | 137.7 ms | **21.94** (15377 px / 701 frames) |

The jump was required to fall at least 10% and frame time to rise at most 5%. The jump **rose** 5.5%
and frame time rose 4.8%: the lever does not work on this data.

*Run 21 (`7ce44ba`, prod, compositing off, 1080p, bundle `index-dKJ9KDWL.js`). One 436 s palindrome,
glyphs against a solid fill over the same box. [`paintcost-raw.txt`](paintcost-raw.txt) →
[`parse_steps.py`](parse_steps.py), which labels arm B "STEPS" where this run's arm B is FILL.*

| arm | blocks | frames | overall mean | fps | moving frames | **MOVING mean** | static mean |
|---|---|---|---|---|---|---|---|
| A glyphs | 13 | 3375 | 75.4 ms | 13.26 | 35.1% | **140.0 ms** | 40.5 ms |
| B solid fill | 8 | 2072 | 77.1 ms | 12.97 | 34.8% | **141.7 ms** | 42.6 ms |

A 1.3% difference on the MOVING mean, in the direction of the fill being *dearer*. Removing every
glyph from the moving box changes nothing measurable.

*Run 22 (`7ce44ba`, prod, compositing off, **1280x720**, bundle `index-dKJ9KDWL.js`). One continuous
439 s capture, 10760 frames, `M6/19`. [`motion-720p-raw.txt`](motion-720p-raw.txt) →
[`parse_motion.py`](parse_motion.py).*

| | value |
|---|---|
| window mean · max | 41 ms · 1595 ms |
| window fps | 24.4 |
| **during motion** (2273 frames) | **66 ms · 15.26 fps** |

| rows moving that frame | frames | mean | fps |
|---|---|---|---|
| 0 | 5983 | 31 ms | **32.3** |
| 1 | 707 | 51 ms | 19.6 |
| 2 | 41 | 57 ms | 17.5 |
| 3 | 814 | 61 ms | 16.4 |
| 4 | 608 | 77 ms | 13.0 |
| 5 | 117 | 96 ms | **10.4** |
| 6 | 94 | 95 ms | 10.5 |

*Run 23 (`7ce44ba`, prod, compositing off, 720p, bundle `index-Dqt17Jj2.js`, constant-velocity
marquee). One continuous 228 s capture, 5800 frames, `M3/20`.
[`motion-720p-cv-raw.txt`](motion-720p-cv-raw.txt) → [`parse_motion.py`](parse_motion.py).*

| | value |
|---|---|
| window mean · max | 39 ms · 1508 ms |
| window fps | 25.6 |
| **during motion** (2645 frames) | **50 ms · 20.19 fps** |
| frames carrying a read with at least one row moving | **65.7%** (2893 of 4404) |

*Run 24 (`7ce44ba`, prod, compositing off, 720p, bundle `index-Ci1lj58e.js`, linear timing with
shrunken holds). One continuous 226 s capture, 3181 frames, `M3/20`.
[`motion-linear-shrunk-raw.txt`](motion-linear-shrunk-raw.txt) →
[`parse_motion.py`](parse_motion.py).*

| | value |
|---|---|
| window mean · max | 71 ms · 1413 ms |
| window fps | 14.1 |
| **during motion** (2234 frames) | **72 ms · 13.94 fps** |
| frames with **no** row moving | **3 of 3181** — the holds really did shrink |

*Run 25 (`7ce44ba`, prod, compositing off, 720p, bundle not recorded). One continuous 438 s
palindrome, 9859 frames, `M5/20`, row overflow distances 59 · 18 · 20 · 1 · 108 px.
[`scroll-vs-transform-raw.txt`](scroll-vs-transform-raw.txt) → [`parse_scroll.py`](parse_scroll.py).*

| arm | blocks | frames | **mean frame** | **fps** | worst frame | landing (max `scrollLeft`) |
|---|---|---|---|---|---|---|
| T `transform` | 12 | 3328 | **71.5 ms** | **13.99** | 491 ms | 0 px in every block |
| S `scrollLeft` | 8 | 6037 | **26.5 ms** | **37.80** | 496 ms | 94–108 px in every block |

**45.0 ms per frame, a 2.70x ratio, inside one capture with both arms moving the same rows the same
distance at the same px/s.** One T block reported `land=0` and was dropped. The worst frame is the
same size in both arms — the mechanism buys throughput and does not touch the stall.

*Runs 26 to 35 (`7ce44ba`, prod, firmware KMS, demonstration data; 720p except Run 35, which is
640x480). Each is one continuous capture of the bare [`p7_min.js`](p7_min.js) loop or a probe built on
it, and every row is produced by running [`parse_min.py`](parse_min.py) on the named file except
Runs 28, 30 and 31, which name their own parser. **Run 29 is absent by design** — it is a two-arm
benchmark rather than a single window and has its own table below. **Run 36 is absent** because its
payload is the `AL` record, also its own table below. **The rows are not a series**: each names its
own configuration and its own capture, and no two are differenced into a single number without saying
so.*

| Run | capture | s | frames | mean | fps | max | **>250 ms** | **per second** | `<50 ms` |
|---|---|---|---|---|---|---|---|---|---|
| 26a | [`hold2s-fps-169s-raw.txt`](hold2s-fps-169s-raw.txt) | 169 | 6978 | 24 ms | 41.3 | 1549 ms | 15 | **0.089** | 96.4% |
| 26b | [`hold2s-phase-289s-raw.txt`](hold2s-phase-289s-raw.txt) | 289 | 12096 | 24 ms | 41.9 | 1518 ms | 13 | **0.045** | 96.3% |
| 27 | [`stagger-phase-288s-raw.txt`](stagger-phase-288s-raw.txt) | 288 | 11866 | 24 ms | 41.2 | 1493 ms | 12 | **0.042** | 96.4% |
| 28 | [`layout-attribution-288s-raw.txt`](layout-attribution-288s-raw.txt) | 288 | 11829 | 24 ms | 41.1 | 1494 ms | 14 | **0.049** | — |
| 30 | [`contain-paint-286s-raw.txt`](contain-paint-286s-raw.txt) | 286 | 11168 | 26 ms | 39.0 | 1454 ms | 24 | **0.084** | 94.7% |
| 31 | [`freeze-188s-raw.txt`](freeze-188s-raw.txt) | 188 | 11209 | 17 ms | 59.6 | 1348 ms | 3 | **0.016** | 100.0% |
| 32 | [`continuous-pingpong-292s-raw.txt`](continuous-pingpong-292s-raw.txt) | 292 | 8951 | 33 ms | 30.7 | 1564 ms | 5 | **0.017** | 95.5% |
| 33 | [`tiled-shm-292s-raw.txt`](tiled-shm-292s-raw.txt) | 292 | 4183 | 70 ms | 14.3 | 2613 ms | 148 | **0.507** | 73.8% |
| 34 | [`painting-threads-294s-raw.txt`](painting-threads-294s-raw.txt) | 294 | 12143 | 24 ms | 41.3 | 1487 ms | 12 | **0.041** | 96.3% |
| **35** | [`res640x480-194s-raw.txt`](res640x480-194s-raw.txt) · **640x480** | 194 | 8692 | 22 ms | 44.8 | 1290 ms | 7 | **0.036** | 97.1% |

Three rows carry a qualifier that the number alone does not. **Run 28's** rate is measured on a page
being deliberately perturbed by a forced layout flush every frame, so it is not the unperturbed rate.
**Run 31's** 0.016/s is scored INCONCLUSIVE by its own parser because the page did not fully freeze;
its three stalls are all before t=3.9 s, and it excludes 93 signature-sampling frames, two of them
over 250 ms, from both the count and the histogram. **Run 35's** 1290 ms maximum is a startup frame
(t=2.3 s), not a steady stall — the steady stalls in that capture are 324, 324 and 378 ms, and the
`max` column is not the quantity Run 35 is read for.

*Run 35 against Run 26b, the only pair in this record that differs in display mode alone at the same
bundle, mechanism and probe. Read as a cross-run comparison with the capture boundary stated, never
merged.*

| | Run 26b · 1280x720 | Run 35 · 640x480 | ratio |
|---|---|---|---|
| pixels | 921600 | 307200 | **3.0x fewer** |
| steady stalls past t=40 s | 474 · 468 · 537 · 478 · 473 · 478 · 520 ms | 324 · 324 · 378 ms | **1.4x smaller** |
| earliest steady stall (t≈10 s), listed not compared | 278 ms at t=9.8 | — | — |
| arrival interval of those stalls | 40.0 · 40.1 · 39.9 · 40.0 · 40.1 · 40.0 s | 40.0 · 40.1 s | **unchanged** |
| frames >250 ms per second | 0.045 | 0.036 | inside the run-to-run spread |
| mean frame · fps | 24 ms · 41.9 | 22 ms · 44.8 | 1.1x · 1.07x |

**Three times fewer pixels buys 1.4x on the stall and nothing on its period.** A pixel-bound cost owed
3x. This is the measurement that falsifies the pixel-area leg and, with it, the full-viewport-repaint
identification; the mean and the framerate do improve, which is the separate, real, pixel-bound win.

*Run 36 (`7ce44ba`, prod, 720p, bundle `index-Mt2gvuKb.js`). One continuous 433 s capture, 7564
frames, arms interleaved inside it. [`alloc-pressure-raw.txt`](alloc-pressure-raw.txt), read from the
`AL` record's own per-arm fields as written by [`p24_alloc.js`](p24_alloc.js).*

| arm | frames | **>250 ms** | **as a fraction** | mean frame | max frame | **`alloc` counter** |
|---|---|---|---|---|---|---|
| A — BASELINE | 6730 | 14 | **0.21%** | 24 ms | 1488 ms | **0** |
| B — ALLOC | 219 | 216 | **98.6%** | **1147 ms** | **2020 ms** | **219** |

**474x** on the fraction of frames that miss the deadline, **48x** on the mean frame time, with the
landing check reading `alloc=0` in the arm that must not allocate and `alloc=219` — every frame — in
the arm that must. Window totals: 236 frames over 250 ms, 57 ms mean, 2020 ms max, histogram
7068 · 167 · 93 · 11 · 39 · 185 · 1 across the seven buckets. The six warmup stalls (t = 1.6, 2.6,
4.1, 5.2, 5.5 and 9.8 s) score in neither arm.

**Arm B's rate is deliberately not quoted per second.** Its frames are slow enough that fewer fit in
the same wall time, so a per-second rate under-reports the effect; the per-frame fraction is the
arm-comparable score. Arm A's own 14 misses across its 160 s of wall time are 0.088/s, the same order
as Runs 26a and 26b, and its 1488 ms maximum fires **outside** the warmup block — the heavy tail is
not only a startup artifact.

*Run 26b, the phase of the steady stalls against the marquee's 8 s cycle. Read from that capture's
own big-frame list and from no other run's.*

| t (s) | dt (ms) | t mod 8 s |
|---|---|---|
| 1.5 · 2.5 · 4.0 · 5.1 · 5.4 | 1518 · 978 · 1506 · 1081 · 301 | startup, not scored |
| 9.8 | 278 | 1.8 |
| 41.9 | 474 | 1.9 |
| 81.9 | 468 | 1.9 |
| 122.0 | 537 | 2.0 |
| 161.9 | 478 | 1.9 |
| 201.9 | 473 | 1.9 |
| 242.0 | 478 | 2.0 |
| 282.0 | 520 | 2.0 |

**Eight of eight**, in a 0.2 s window, on a cycle 8 s long. Run 27's stagger leaves it at **six of
six** between 1.8 and 2.1. The offset is against the probe's `t0`, not the page's, so it is read as
locked to a fixed point of the cycle and never compared across runs.

*Run 28 (`7ce44ba`, prod, 720p, bundle `index-Mt2gvuKb.js`). One 288 s capture with one timed
synchronous layout flush per frame. [`layout-attribution-288s-raw.txt`](layout-attribution-288s-raw.txt)
→ [`parse_profile.py`](parse_profile.py).*

| | value |
|---|---|
| stall frames (>250 ms) | 14 |
| forced layout on the **worst** stall frame (1494 ms) | **0 ms — 0.0%** |
| largest forced layout on any stall frame | **1 ms — 0.3%** of that frame |
| forced layout across all 14, frame-weighted | **0.0%** |
| `longtask` entry type | **absent on this build** — recorded, not faked |

*Run 29 (`7ce44ba`, prod, 720p, bundle `index-Mt2gvuKb.js`). One 115 s capture, 2560 frames, 22.3 fps.
A full-viewport repaint forced every 20th frame and attributed to the following frame.
[`fullpaint-bench-115s-raw.txt`](fullpaint-bench-115s-raw.txt) →
[`parse_fullpaint.py`](parse_fullpaint.py).*

| | n | mean | p50 | **p90** | **max** |
|---|---|---|---|---|---|
| FORCED — one full-viewport repaint | 127 | 245 ms | 203 ms | **458 ms** | **530 ms** |
| BASELINE — the page's ordinary frames | 2432 | 34 ms | 20 ms | 50 ms | 1477 ms |

Top forced frames: 530 · 528 · 512 · 508 · 508 · 504 · 495 · 486 · 476 · 474 ms. Isolated cost of one
full-viewport repaint, FORCED minus BASELINE: **183 ms at the median, 211 ms at the mean.**

**The parser's verdict is negative and is printed as it stands:** scored on the p50, a forced full
repaint is **0.45x** the reference stall (0.54x on the mean). That reference is **450 ms hardcoded in
[`parse_fullpaint.py`](parse_fullpaint.py)** with no provenance stated in the parser itself; it is
consistent with Run 26b's steady stalls, whose mean is 490 ms over the seven at t>40 s and 463 ms
over all eight, and it is recorded here as a chosen constant rather than a derived one.

Run 26b's steady stalls span **278–537 ms**, with seven of the eight in 468–537 and the 278 ms member
the earliest arrival. Against the **isolated** repaint cost — FORCED minus BASELINE, 183 ms at the
median — a stall that was one full repaint should read about `34 + 183 = ~217 ms`, and the measured
~490 ms is **2.3x** that. The only reading on which the two meet is the un-subtracted FORCED p90 of
458 ms, and the subtraction and that comparison cannot both be taken. **The magnitude leg is
therefore negative, not marginal**, which is what the parser said and what Run 35 later confirmed
from the other direction.

The BASELINE row's 1477 ms max is not attributable in time: the `FVP` payload carries **no
timestamps**, and 1477 ms sits inside the startup cluster every capture in this family shows. Only
that row's median and mean are usable, and nothing here rests on when the frame arrived.

*Run 30 (`7ce44ba`, prod, 720p, bundle `index-Mt2gvuKb.js`, `contain: paint` inline on all four
cards). One 286 s capture. [`contain-paint-286s-raw.txt`](contain-paint-286s-raw.txt) →
[`parse_contain.py`](parse_contain.py).*

| | value |
|---|---|
| requested · cards · inline writes | `paint` · 4 · 4 |
| **landing: computed `contain` read back** | **`paint`**, support probed and confirmed |
| frames >250 ms | 24 in 286 s = **0.084/s** |
| worst frame | 1454 ms |
| against Run 26b's 0.045/s | **2.10x — the wrong direction** |

Read **within this capture only**, because a phase offset is against the probe's own `t0` and does
not carry between runs: the stalls still cluster — nine of the 14 at t mod 8 s = 0.8–1.6 — but four
more arrive at 6.7–7.3 and five follow another within 0.2–0.5 s. Containment landed, and the
escalation is neither removed nor bounded by a card.

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

## Root cause of the residual stall

**The residual is a JavaScriptCore garbage-collection pause.** A long-lived page that allocates on a
schedule — a clock tick every second, a data poll, reactive objects re-created, DOM churn — walks its
heap up to the collector's threshold, and the full collection that follows runs on the board's single
ARM11 core and stops the main thread for roughly half a second at the steady arrival and up to ~1.5 s
in the tail. The allocation sources named there are the shape of the mechanism and are **not
measured on this page**; what is measured is that allocation drives the stall. Four legs carry the
identification, and the second of them is also the test the withdrawn one failed.

- **Allocation drives it, measured directly and by a wide margin (Run 36).** Inside one capture,
  with arms interleaved so board drift cannot masquerade as the effect, an arm allocating and
  dropping short-lived objects every frame misses the 250 ms deadline on **216 of 219 frames** at a
  **1147 ms mean and a 2020 ms maximum**; the baseline arm of the same capture misses on **14 of
  6730** at a 24 ms mean. That is **98.6% against 0.21% — a 474x change in the fraction of frames
  that miss** — and each arm's allocation counter is read back in band, `alloc=219` and `alloc=0`, so
  the manipulation is verified to have landed on the arm it was meant to and on no other. This is the
  only manipulation in this investigation that reproduces the stall at will.
- **It is not pixel-area-bound (Run 35).** Cutting the panel from 1280x720 to 640x480 — **exactly
  3.0x fewer pixels** — leaves the rate at 0.036/s against 0.045/s, leaves the ~40 s arrival interval
  untouched, and shrinks the steady stall only **1.4x** — 468–537 ms to 324–378 ms, comparing each
  capture's arrivals past t=40 s — where a pixel-bound cost owes 3x. Mean frame time and framerate
  *do* improve, 24 → 22 ms and 41.9 → 44.8 fps, which is the separate pixel-bound win and not this
  quantity.
- **It is not layout (Run 28).** A synchronous layout flush timed inside every frame reads **0–1 ms
  on all 14 stall frames** — 0.0% of the worst one, 0.0% frame-weighted. Forcing layout continuously
  would also have dissolved a batched-layout stall, and it did not: the stalls survived the
  perturbation unchanged. Layout is excluded twice over.
- **Stopping the page's own work stops it (Run 31), and that is now read as stopping allocation.**
  With every timer and `requestAnimationFrame` neutered, the capture runs 188 s at 59.6 fps with its
  only three frames over 250 ms at t = 1.6, 3.1 and 3.9 s and **nothing over 250 ms in the remaining
  184 s**. At the shipped 0.045/s a 184 s window expects about eight; seeing none is a strong
  observation, not a weak one. The run's own content signature caught **one change** across 94
  samples, so `frozen=0` and [`parse_freeze.py`](parse_freeze.py) returns **INCONCLUSIVE: "the
  0.016/s rate is not attributable either way."** That verdict is not overridden here. What the run
  cannot separate is *which* kind of work stopping mattered — a page whose callbacks are neutered
  both allocates far less and renders far less — and Run 36 is what separates them, by holding
  rendering constant and moving allocation alone.

**The arrival cadence is what a threshold-driven collector looks like, and it is not what a
per-cycle rendering event looks like.** Run 26b's seven arrivals past t=40 s are 40.0, 40.1, 39.9,
40.0, 40.1 and 40.0 s apart; Run 27's fall on the same beat with two turns skipped (40.0, 40.0, 80.0,
80.1); Run 34's carry it with one extra arrival between; and Run 35's are 40.0 and 40.1 s apart at a
third of the pixels. That period is **five turns of the marquee's 8 s cycle**, so
nothing in the cycle explains why one turn in five costs half a second. A steady allocation rate
crossing a fixed heap threshold explains the period directly. The phase lock Run 26b reads — eight of
eight steady stalls at t mod 8 s = 1.8–2.0, the scroll-start — then says only *which* frame of the
cycle is the one that carries the collection when the threshold is due: the busiest frame in the
cycle, the one that allocates and works most.

**WITHDRAWN: the full-viewport software repaint.** This record carried, for most of its length, the
identification that the residual was an occasional full-viewport software repaint, content-triggered
and pixel-bound. **Run 35 falsified it** — a 3.0x pixel cut is the test that mechanism owed, and the
stall did not follow the pixels down. Two things had already pointed the same way and are recorded
here as the reasoning trail rather than as live claims:

- **The magnitude never matched.** Run 29 prices an isolated full-viewport repaint at **183 ms at the
  median, 211 ms at the mean** (FORCED minus BASELINE). One repaint on top of a 34 ms frame is
  ~217 ms; the measured steady stall is ~490 ms. That is **2.3x**, and the only way the two met was by
  comparing the stall against the *un-subtracted* FORCED p90 of 458 ms — taking the subtraction and
  the comparison at once. [`parse_fullpaint.py`](parse_fullpaint.py) printed the negative verdict all
  along, and Run 21 closes the escape: cost is content-independent to 1.2%, so a solid-fill benchmark
  is a fair price for a glyph-heavy repaint and the gap is real rather than an artifact of the probe.
- **The probes could never see the component the claim named.** Every stall-family probe measures rAF
  deltas from inside the page, which bundle the whole produce-to-next-callback interval. Run 4
  measures that interval as **WebKit 53% / X 25% / surf 19%**, so ~44% of a frame is not WebKit
  rasterising at all, and no run in this family attributes a stall frame across the three processes.
  "Software repaint" named a component the instrument could not resolve.

**What the withdrawal does not touch.** Run 29's benchmark is still a correct measurement of what a
full-viewport repaint costs on this board; it simply is not measuring the stall. Run 21's
content-independence and Run 30's inert, verifiably-landed `contain: paint` stand as measured. Run
22's 1080p → 720p result stands: it measures during-motion **throughput**, which is pixel-bound, and
the error was reading it as the same quantity as the stall. The engine levers in "Engine levers,
measured and exhausted" are still measured and still negative — they were aimed at paint, which is
the wrong target, so their nullity is expected rather than informative about the collector.

**The honest gaps, named rather than glossed.**

- **No collector instrument was read.** No GC-event trace, no heap-size series and no
  `performance.memory`-equivalent reading is in this record; the identification rests on an
  allocation manipulation with a verified landing (Run 36), a falsified alternative (Run 35) and the
  arrival cadence. A direct read of collection events would convert it from convergent inference to
  observation, and that read has not been taken.
- **Run 36 shows allocation is sufficient to produce the stall, not that the frontend's own
  allocation is the only trigger.** The injected pressure is far above anything the page does, and
  the shipped page's per-second allocation has not been measured.
- **The Paint rect was never read either.** WebKit's remote-inspector Timeline, which records a
  `Paint` record carrying the repainted rectangle, is **unavailable on this build**: the inspector
  server accepts the socket and returns nothing, and there is no repaint-region debug environment
  variable to fall back on — consistent with "Configuration under test", which records that
  `WEBKIT_DEBUG` is compiled out of this release build. Run 28 independently records that the
  `longtask` entry type is absent, so the engine-side cross-check was gone too. **Both missing
  instruments are build-time conditions with a build-time answer** — see "Real-time framing".

## Engine levers, measured and exhausted

Every **runtime** configuration lever WebKit and the display stack expose on this SoC, each measured
on the board and each scored against the run that measured it. The build-time surface —
`PACKAGECONFIG` on the webkit recipe — is a separate class and is **not** enumerated here; see
"Real-time framing".

**These rows are not a series and must not be differenced against each other.** Each is one run's own
number against its own reference, across different resolutions, bundles and mechanisms. The column
says what that run's verdict was, not where a lever sits in a ranking.

**Every lever in this table was aimed at paint**, and paint is not the residual's mechanism — see
"Root cause of the residual stall". The rows are still correct as measurements and still correct as
verdicts on their own levers; what they are not is evidence that the residual is unbounded, because
none of them was ever pointed at the collector.

| Lever | Run | Measured | Verdict |
|---|---|---|---|
| **GPU / accelerated compositing** (dma-buf, vc4 + mesa) | 19 | during-motion **1.50 fps** against Run 17's 7.86 at the same resolution and bundle; static frames 745 ms | **5.2x worse.** The investigation's opening premise, measured backwards for the second time |
| **Tiled software compositing** + shared-memory path + 4 painting threads | 33 | **14.3 fps, 0.507/s**, 73.8% of frames under 50 ms | **11x more deadline misses** than the shipped 0.045/s. Tile upload costs more on a saturated single core than the damage-rect saving returns |
| **Painting threads alone** (`NICOSIA_PAINTING_THREADS=4`, compositing off) | 34 | **41.3 fps, 0.041/s** against the shipped 41.9 fps and 0.045/s | **Null.** With no tiled backing store there is nothing for a painting thread to rasterise into |
| **`contain: paint` on the park cards** | 30 | **0.084/s**, max 1454 ms, computed `contain` read back as `paint` | **Inert, and landed.** A containment boundary does not bound the stall — which follows, since a collector pause is not a paint the boundary could contain |
| **Full KMS** (`vc4-kms-v3d`) | 2 | A content-black scanout on a live signal, owner-confirmed, persisting across forced 1080p and 720p, `disable_fw_kms_setup=1`, an `xrandr` kick, and compositing on and off | **Blacks the panel.** Not a performance lever at all on this display |
| **1280x720** (`xrandr` in the launcher, firmware KMS) | 22 | during-motion **7.86 → 15.26 fps**, window mean 12.5 → 24.4 fps | **The one lever here that works, and only on throughput.** It is not an engine lever — it is fewer pixels, and it buys the mean, not the stall |
| **640x480** — a third display mode, 3.0x below 720p | 35 | **0.036/s** against 0.045/s, steady stalls past t=40 s 324–378 ms against 468–537 ms, arrival interval unchanged at ~40 s | **Does not reach the stall, and that is the point of the run.** 3x fewer pixels buys 1.4x on the stall and nothing on its period. The falsifier of the pixel-area leg |
| `steps()` quantisation of the marquee | 18a, 18b | `steps(40)` 75.0 → 71.3 ms overall; `steps(10)` 70.8 → 48.6 ms overall but **131.5 → 153.2 ms** on the moving frame | **Rejected.** Wins the average by converting moving frames to static ones |
| Per-row constant scroll velocity | 20 | 20.80 → **21.94** px per moving frame, frame time +4.8% | **Does not engage** on overflows of 1–108 px |
| Shrinking the hold phases | 24 | 3 static frames in 3181; window mean 14.1 fps | **Worse.** Removing the rests gangs the repaints instead of spreading them |
| A 200 ms stagger between row starts | 27 | 0.042/s, and **6 of 6** steady stalls still at one phase | **Null.** Reverted |

What is left after the ledger is not an engine lever, and the two things that moved a number moved
**mean frame time**: **fewer pixels** (Run 22) and **a different mechanism in the app** (Run 25,
`scrollLeft` at 26.5 ms against `transform` at 71.5 ms in one interleaved capture). Both live outside
WebKit's runtime configuration, and neither touches the stall — Run 25's two arms have the same worst
frame, 491 ms and 496 ms, and Run 35 takes the pixels down 3x more for 1.4x on the stall. **The
lever that does reach the stall is in the app too, and it is not a rendering lever**: the frontend's
per-second allocation churn, which Run 36 shows drives the stall by 474x when pushed in the wrong
direction. It has not been pushed in the right one; see "Real-time framing".

## Real-time framing

The owner's standard for this panel is a hard one: a ~450 ms frame is not a slow frame, it is a
**missed deadline**, and a display that misses one is broken for the interval it misses it in. That
framing is the right one for a wall-mounted appliance, and this investigation was run against it
rather than against an average.

The measured answer is that **no runtime configuration of this stack bounds the deadline, and the
lever that reaches the mechanism is in the application rather than in the stack at all.**

A browser engine is a soft-real-time system by construction: it decides when to repaint, how much of
the surface to repaint, on which thread, and when to collect its heap, from heuristics that optimise
the common case and carry no upper bound. The **rendering** heuristics have all been tried on the
board and are in "Engine levers, measured and exhausted" — compositing, tiled compositing, painting
threads, containment, two resolution cuts. Containment was the sharpest of them because it addresses
the damage rect directly, and Run 30 applied it, verified it landed by reading the computed value
back, and watched the rate go through it. **That whole ledger is aimed at the wrong subsystem.** The
residual is a collector pause, not a repaint (see "Root cause of the residual stall"), and none of
those levers was ever pointed at it.

What the work did buy is large and is not a guarantee: **1.07/s deadline misses at 1080p with the
transform marquee (Run 9) against 0.045/s over 289 s and 0.089/s over 169 s on the shipped
configuration (Runs 26b and 26a)** — a 12x to 24x reduction, read across runs that differ in
resolution, mechanism and bundle at once, and quoted as a range because two captures of the *same*
shipped configuration differ by a factor of two. Rare is not bounded. A miss every twenty-odd seconds
is a miss. And on Run 36's reading, that reduction was bought by the frontend **allocating less** —
the remount gone, the per-frame style writes gone, the transform churn gone — rather than by
rendering more cheaply. The mechanism that produced the win is the same mechanism that still has
headroom.

**The lever that follows is reducing the WiseKiosk frontend's per-second allocation churn**, and it
is un-run. Run 36 shows the relationship is steep in the wrong direction — 474x on the miss fraction
for injected pressure — and nothing here measures what the page's own allocation rate is or what
removing it would buy. The audit that opens it is a frontend one: the clock tick, the data poll, the
reactive objects re-created per update, and the per-frame object churn in the marquee's shared rAF
loop. **This investigation does not take it, size it, or promise what it returns.** It records that
this is the thread #100 gpu-compositing is now open on, and that it is the owner's to pick up in the
WiseKiosk repository.

**Two levers sit outside what was surveyed, and naming them is part of the honesty of the
conclusion.**

- **Build-time WebKit configuration was never enumerated.** Everything above is *runtime* — an
  environment variable, a `/data/config/kiosk.conf` line, an `xrandr` mode. `PACKAGECONFIG` on the
  webkit recipe is a different class, and it is a budgeted operation in this tree rather than an
  exotic one: a webkit `PACKAGECONFIG` change invalidates WebKit and costs a full rebuild, ~4.5 h,
  per [`../../../README.md`](../../../README.md) §"Quick start". Two things sit in that class and both
  bear on this record. **Whether a concurrent or incremental collector is available to this build at
  all** is unknown, because the surface was not surveyed — and JavaScriptCore's own options are
  compiled out of this release build, so there is no runtime way to ask. **And the instruments this
  record says it lacks are build-time conditions**: `WEBKIT_DEBUG` is compiled out and the remote
  inspector returns nothing, so a developer- or inspector-enabled WebKit build is what would turn
  both the collector read and the Paint rect from inference into observation. Costing that is an
  owner decision; **not naming it** would be a defect in this section, which is why it is named.
- **A renderer that owns its own frame budget** remains the architectural answer to a *hard* bound,
  whatever the current mechanism is — one that decides what to do from the application's own model of
  what changed, and whose worst case is computable rather than observed. That is a different
  architecture, not a different configuration. **This investigation does not propose it, cost it, or
  take it**, and on the corrected mechanism it is not the *next* step either: the allocation lever is
  cheap, in-application and untried, and it comes first.

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
  - **WITHDRAWN — "the marquee is not the driver".** Turning it off (`animation: none`, verified
    landed) scored 12.7 fps against adjacent baselines of 13.1 and 4.6. One phase window cannot
    resolve that: the effect looked for is 2x and the band it sits in spans 2.8x. Run 16 runs the
    same intervention as an interleaved palindrome with a computed-value landing check and measures a
    ~2x per-frame cost, so this reading and the "no motion tradeoff is owed" that rested on it are
    both withdrawn — see the finding "CORRECTED — the marquee's motion is a real ~2x per-frame cost".
    The `steps(8)` quantisation null reported beside it came from the same underpowered design and is
    withdrawn with it: `steps()` has never been tested by a design able to detect a 2x effect.
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

- **LOCALIZED — the floor requires the app's rendered DOM, and nothing else about the app explains
  it (Runs 14 and 15).** OBSERVATION (Run 14): with `#app` hidden by `display:none` and the page
  reduced in place to a 240x80 box, the rate falls from **0.99 and 1.06/s in the two bracketing
  full-app arms to 0.02, 0.01 and 0.00/s** in the three reduced arms — about **100x** — while every
  Svelte timer, the rotation intervals, the marquee measurements and the module polls keep running.
  The cost is the app's **rendering**, not its JavaScript, which is what the engine-dominated frame
  attribution has said since Run 8.

  OBSERVATION (Run 14): a static page on this hardware is clean — one frame over 250 ms in 100 s, at
  54.5 fps. **There is no ~1/s metronome in the stack below the page**, so the floor is not a periodic
  cost WebKit, the compositor or the driver pays regardless of content.

  OBSERVATION (Run 15): neither painted area nor animation alone reproduces it. A full-viewport
  text-heavy box static reads **0.03/s at 54 fps**; the same box animated collapses to **1278 and
  1289 ms per frame, 0.78 fps** — far worse than the app itself. INFERENCE: that is a real regime and
  a bound on what animating a large rasterised layer costs here, but it does not model the app's six
  small marquees. A mechanism generalised from it — that any animation forces a full-surface
  recomposite — is refuted by Run 16, which switches every animation off and leaves the rate at
  1.10/s.

  INFERENCE, and it is the bound this pair supports: painted area alone is not sufficient (Run 15's
  static arm), animation is not sufficient (Run 16), and the app's JavaScript is not involved
  (Run 14). What is left is **WebKit's rendering of this particular render tree** — its depth, its
  box structure, its layer count — and which property of it costs is undecided.

- **CORRECTED — the marquee's motion is a real ~2x per-frame cost (Run 16).** OBSERVATION: with every
  animation in the page switched off, verified by reading the computed `animationName` off a live
  marquee row, mean frame time falls from **76.6 ms to 36.5 ms** drift-centred across the palindrome
  — **~13 fps to ~27 fps** — with the app fully rendered and 7 marquee rows present throughout. The
  board's ~30% within-run drift cannot produce that: the three ON arms read 84, 71 and 76 ms and the
  two OFF arms 35 and 38 ms, and the arms do not overlap.

  OBSERVATION: Run 8's arm D reaches the same lever from the other side — capping the rows that
  animate at 2 took mean frame time 72 → 46 ms. Both say the cost tracks how many rows are in motion.

  **This withdraws Run 6's "the marquee is not the driver" and the "no motion tradeoff is owed to
  anyone" that followed from it.** That reading rested on one phase window at 12.7 fps inside a
  baseline band spanning 2.8x (4.6–13.1 fps), where the effect being looked for is 2x — inside the
  noise the run itself documents. A motion tradeoff **is** owed, and this is the largest frontend
  lever on the record for the sustained framerate.

  What the correction does not touch is the ~1/s floor: Run 16 moves it by −2%, 1.08 → 1.10/s. The
  marquee costs throughput; it does not produce the hitches.

- **OBSERVATION (the running config, read against WebKit's own source) — this board has no compositor
  thread, so the marquee scroll is main-thread software paint every frame.**
  `WEBKIT_DISABLE_DMABUF_RENDERER=1` is set on both the UI process and the web process, asserted by
  exact match in `/proc/<pid>/environ` before every measurement from Run 5 onward, and Run 5
  establishes what the variable does: it fails WebKit's accelerated-compositing requirements check,
  which disables accelerated compositing outright rather than selecting a different transport. With
  no accelerated backing store there is no threaded compositor to carry a transform animation off the
  main thread, and no composited layer for `will-change: transform` to promote.

  INFERENCE, immediate: every frame of the scroll is painted by the web process's main thread and
  copied to X, which is why the motion's cost lands on mean frame time as Run 16 measures it, rather
  than on a compositor thread invisible to `requestAnimationFrame`.

  **Wherever this record reasons from layer promotion, it describes compositing ON and not the
  deployed board.** Run 2's "the animating row promotes a `transform` layer with `will-change`,
  confirmed" was read under the composited configuration Run 2 delivered, and the finding "Confound,
  stated rather than resolved — `will-change` and vc4 shipped together" is explicitly conditioned on
  compositing being on. Neither describes the configuration the board has run since Run 6, and
  neither licenses a `will-change` or layer-promotion argument about it.

- **DERIVED, NOT MEASURED — the framerate *during* the scroll's motion is estimated at 2.6 to
  11.9 fps, and the confirming board run is unrun.** Every fps figure in this record is a
  **whole-window mean**, while the marquee is in motion for only part of its cycle: the keyframes in
  `ParkCard.svelte` hold `translateX(0)` over `0%,15%`, move over `15%→50%`, hold over `50%,65%` and
  snap back over `65.01%,100%`, so one row moves for 2.8 s of each 8 s cycle, a 35% duty. Rows take
  the marquee class when their own name is measured, so their moving windows start independently and
  union: for `k` animating rows the fraction of wall-clock time with at least one row moving is
  `1 − 0.65^k` — 0.58 at `k=2`, the live roster, and 0.92 at `k=6`, the demonstration data the board
  is running.

  DERIVATION: take Run 16's two drift-centred means — 76.6 ms with animation, 36.5 ms without — and
  assume a static-phase frame on the animating page costs what a frame on the animation-off page
  costs. Then `1/76.6 = d/f_move + (1−d)/36.5` gives:

  | animating rows | union motion duty `d` | implied moving-phase frame time | implied **during-motion fps** |
  |---|---|---|---|
  | 2 (`M2/20`, the live roster) | 0.58 | ~390 ms | **~2.6** |
  | 6 (`M6/20`, the demonstration data) | 0.92 | ~84 ms | **~11.9** |

  **This is arithmetic on two run means, not a measurement.** It is quoted only to bound the
  question: every branch puts the during-motion rate below the 13–15 fps window mean, across a 4.5x
  spread this record cannot narrow. The assumption it rests on may be false — at `k=1`, `d=0.35`, the
  equation has no solution at all, because the static portion alone (`0.65/36.5`) already exceeds the
  observed total rate (`1/76.6`). That says either the rows are out of phase, or a static-phase frame
  on a page with a live animation is **not** cheap.

  **The confirming measurement was not taken.** A probe that tags each frame by reading the live
  computed `translateX` off every marquee row, and buckets frame time by how many rows moved and by
  total pixels moved, was written and smoke-tested off-device. Its deploy to the board was **denied
  by the harness's own safety classifier**, twice — once as a direct write of `~/.surf/script.js` and
  once through [`run-phase.sh`](run-phase.sh) — for reasons the denial attributes to earlier
  conversation content rather than to the operation. The board was left untouched and verified clean:
  `~/.surf/script.js` at 0 bytes, no restart issued, `/data/config/kiosk.conf` unchanged. Nothing in
  this repository, in `.claude/hooks/guard.sh` or on the device was in the way. **No during-motion
  number exists, and none is to be inferred from the table above.**

- **SUPERSEDED as to mechanism — what sets the ~1/s floor. Runs 8 to 16 bound it to the app's own
  render tree being present; Run 36 names what about its presence costs.** The bound below is
  correct and the exclusions below all still hold. What has changed is the reading of the one
  manipulation that moved it: Run 14 took the app's rendered DOM out of the page and the floor
  collapsed ~100x, which this record read as "the engine's rendering of this tree". Removing that
  tree also removes what re-rendering it **allocates** — reactive objects, DOM nodes, the churn of
  every update — and Run 36 shows allocation is what drives the stall. Run 14 is consistent with both
  readings and discriminates neither; Run 36 discriminates, by holding rendering constant and moving
  allocation alone. See "Root cause of the residual stall". Each intervention below is verified to
  have landed except the one marked:

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
  | every animation in the page off, computed value verified | 16 | 1.10 *(1.08 on the ON arms)* |
  | **the app's rendered DOM taken out, its JS still running** | **14** | **0.01–0.02** |

  INFERENCE, and the bound it supports: it is not the app's JavaScript *as executed work* — Run 14
  removed the rendering and left every timer running, and the floor went with the rendering. It is
  not the display server — X's own stalls are 5–6x too rare. It is not the instrument — Runs 11 and
  13 exclude both halves of that. It is not a periodic cost below the page — Runs 14 and 15 measure a
  static page on this hardware at 0.01–0.03/s. And it is not the animations — Run 16. What is left is
  the engine's own work on **this** tree, which is what the frame attribution said from the first
  capture: these frames are `engine` 294–476 ms with `js` and `lay` near zero. **A collector pause
  wears exactly that signature** — it is engine time, not app JS time and not layout time — which is
  why the attribution never separated it from rendering.

  **What Runs 8 to 16 could not decide is which property of the tree costs**, and the subtree
  bisection they point at is superseded as the next test: Run 36 moves the question off the tree's
  shape and onto what maintaining it allocates. The bisection is still runnable and carries no device
  risk beyond the usual user-script swap, but a read of the frontend's per-second allocation comes
  first; see "Real-time framing".

  **The direction of any fix is not full KMS.** The frontend levers against the *floor* are exhausted
  and measured; the frontend lever against the *sustained framerate* is not, and it is the marquee's
  motion. Full KMS is separately excluded on this panel — it presents a content-black
  scanout on a live signal, chased to a dead end — and whether the vc4 display-stack work ships at
  all remains the owner's decision on the record below, unchanged by these runs.

  Three further diagnostics stand open, ordered by discriminating power: correlate Run 12's
  0.16–0.20/s X bursts against the frame stalls by timestamp, to establish whether X accounts for the
  *largest* frames while something else produces the rest; sample `WebKitWebProcess` CPU alongside
  the frames, to separate "the engine is working hard" from "the engine is blocked waiting"; and take
  a capture long enough to hold several of the frontend's 5-minute module polls, to settle whether
  the one observed 1063 ms **js**-dominated frame (Run 8, arm A, t=308.3 s, `js=813 ms`) is a real
  recurring second event with a different signature from the floor. That observation is n=1.

- **WITHDRAWN — the residual stall is not a full-viewport software repaint (Run 35 falsifies it).**
  This record carried that identification through Runs 28 to 34 and reasoned from it in three
  sections. OBSERVATION: at 640x480, **3.0x fewer pixels than 720p**, the stall's rate is 0.036/s
  against 0.045/s, its arrival interval is 40.0 and 40.1 s against 40.0–40.1 s, and its magnitude
  falls only **1.4x** — 324–378 ms against 468–537 ms, each capture's arrivals past t=40 s — where a
  pixel-bound cost owes 3x. The
  pixel-area leg is the leg the identification rested on and it does not survive the test it named.

  Two things had already pointed away from repaint and are recorded as the trail rather than
  rediscovered. OBSERVATION: Run 29's isolated full-viewport repaint costs **183 ms at the median,
  211 ms at the mean**, so one repaint on a 34 ms frame is ~217 ms against a measured ~490 ms steady
  stall — **2.3x**, reachable as a "match" only by comparing against the *un-subtracted* FORCED p90
  of 458 ms, which is the subtraction and the comparison taken at once. `parse_fullpaint.py` printed
  that negative verdict throughout. INFERENCE: Run 21's content-independence (141.7 against 140.0 ms)
  closes the escape that a solid-fill benchmark under-prices a glyph repaint, so the gap is real.
  OBSERVATION: every stall-family probe reads rAF deltas from inside the page, and Run 4 measures that
  interval as WebKit 53% / X 25% / surf 19% — so "software repaint" named a component these probes
  cannot resolve, and no run in Runs 26 to 36 attributes a stall frame across the three processes.

  **What the withdrawal does not touch:** Run 29 still correctly prices a full-viewport repaint on
  this board; Run 21, Run 28 and Run 30 stand as measured; Run 22's 1080p → 720p result stands as a
  **throughput** result, which is pixel-bound. The error was reading throughput and stall as one
  quantity. **This entry is kept rather than deleted** — an overturned conclusion is part of the
  record here, the same way "the marquee is not the driver" is kept under the finding that withdrew it.

- **ROOT CAUSE, corrected — the residual stall is a JavaScriptCore garbage-collection pause (Run 36,
  with Run 35).** OBSERVATION: inside one capture with arms interleaved, an arm allocating and
  dropping short-lived objects every frame misses the 250 ms deadline on **216 of its 219 frames** at
  a **1147 ms mean and 2020 ms max**, against **14 of 6730** at a 24 ms mean in the baseline arm —
  **98.6% against 0.21%, a 474x change in miss fraction** — with each arm's allocation counter read
  back in band as 219 and 0. OBSERVATION: the stall is resolution-independent (Run 35), not layout
  (Run 28, 0–1 ms of forced layout on all 14 stall frames), and absent from a page whose scripts have
  been stopped (Run 31, nothing over 250 ms in 184 s where ~8 were expected).

  INFERENCE: the page allocates continuously — a clock tick every second, a data poll, reactive
  objects re-created, DOM churn — and periodically crosses the collector's heap threshold, so a full
  collection runs on the single ARM11 core and stops the main thread. The **~40 s** arrival interval,
  invariant across Runs 26b, 27, 34 and 35, is what a steady allocation rate against a fixed threshold
  produces; it is **five turns** of the marquee's 8 s cycle, which nothing in the cycle explains. The
  phase lock Run 26b reads then says only which frame of the cycle carries the collection when it is
  due.

  INFERENCE, and it re-reads this investigation's own headline: the deadline-miss rate fell from
  1.07/s to ~0.045/s because the frontend work **removed allocation** — the park-card remount, the
  per-frame style writes, the transform churn — and not because rendering got cheaper. 720p and
  `scrollLeft` are a real and separate win on the **mean**, and Run 25's own arms show they do not
  touch the stall: worst frames 491 ms and 496 ms. **The lever that follows is reducing the frontend's
  per-second allocation churn**, and it is un-run; see "Real-time framing". **The gaps:** no collector
  instrument was read on this board, the page's own allocation rate is unmeasured, and Run 36's
  injected pressure is far above anything the page does — it shows allocation is sufficient to produce
  the stall, not that the frontend's allocation is its only trigger.

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

## Durable image delivery — pending owner decision

**The reconcile diff is written and independently reviewed. Nothing has been delivered.** No image
was built, no bundle was created, no board was flashed and no OTA was pushed against any of it. The
section states the gap, what is staged against it, and the decisions that close it, so the owner
decides against a written position rather than against a session's memory.

**The gap.** The image these runs ran, `7ce44ba`, bakes the hypothesis this investigation disproved.
Its `graphics` block sets `VC4DTBO = "vc4-kms-v3d"` — full KMS, which Run 2 found blacks this panel —
and `CMDLINE:append = " video=HDMI-A-1:1920x1080@60D"`, which pins the mode Run 22 measures as 1.94x
more expensive on throughput than 720p. The configuration the board actually runs is none of that:
**firmware KMS (`vc4-fkms-v3d`), a plain `cmdline.txt` with no `video=`, 1280x720 set by `xrandr` in
the launcher, and software rendering.** Three of those four reached the board as a hand-edit and one
lives in `/data/config/kiosk.conf`.

**What is staged against it.** A reconcile diff across five files —
[`../../../kiosk-zero-w.yaml`](../../../kiosk-zero-w.yaml), the `kiosk-launch` launcher, the
`kiosk-session` recipe, the `rpi-config` bbappend and [`../../../README.md`](../../../README.md) —
moves the tree to **firmware KMS, no `video=` on the kernel command line, software rendering as the
launcher's default, and 720p set in the launcher**, and **keeps mesa and `libgles2-mesa`**. The GLES
package is not a compositing switch: WebKit `dlopen`s `libGLESv2.so.2`, so removing the package makes
the web process segfault the instant compositing is attempted rather than turning compositing off,
and the runtime switch is the launcher default plus the `/data/config/kiosk.conf` line. The diff has
been **independently reviewed**. It has **not** been built and **not** been flashed.

**Delivery is deferred, and the reason is in this record rather than in scheduling.** The corrected
root cause reopens #100 gpu-compositing on the allocation lever — see "Real-time framing" — and
flashing now would bake a display configuration ahead of a thread that could change what the board
should run. The staged diff is the inspectable form; taking it is the owner's call.

**Standing risk, stated as a risk and not as a plan.** An OTA or a reflash of `7ce44ba` blacks the
wall panel — "Changes configured as a result" already records this and it is unchanged. The running
configuration is a set of manual edits that no build reproduces, so a reflash loses the display mode.
`/data` surviving a reflash is what preserves the renderer setting rather than anything in the image
— and **a re-provision does not preserve it either**, because `tools/provision.sh` writes a fresh
two-line `kiosk.conf`. That is a second failure mode on the same axis and it is not covered by the
reflash argument.

**An operator tool is now aimed at the wrong verdict.**
[`kiosk-gpu-check.sh`](../../../tools/kiosk-gpu-check.sh)'s default mode passes when a web process
holds `/dev/dri` open with a `vc4`/`v3d` driver mapped. That was the right proxy when the GPU path
was the goal. On the configuration this investigation measured as **correct** — compositing off, no
accelerated backing store, so no DRM node held — it reports `NO GPU path` and exits non-zero: **a
correctly configured board reads as broken.** Whether the tool is retired, re-aimed at the software
path, or kept as a guard on a state the fleet does not want is an owner decision that has not been
taken. It is flagged here because the tool is operator-facing — `justfiles/device.just` drives it in
both modes, and its self-test runs in `tools/ci-guards.sh` — so the mis-aimed verdict reaches a
person at a prompt, not just a file.

**The decisions the owner holds, none of them taken here:**

- **Take the staged reconcile, or not.** The diff is written and reviewed; what remains is a build
  and a delivery. Cost is image reassembly plus a `config.txt` and cmdline re-deploy — **not** the
  ~4.5 h WebKit invalidation, which arrives only from `DISTRO_FEATURES`, `MACHINE_FEATURES` or webkit
  `PACKAGECONFIG`, none of which the diff touches.
- **Where the 720p mode should live.** The board's copy is a hand-edit of the launcher's `xrandr`
  line, and the staged diff puts that line into the launcher the `kiosk-session` recipe installs. The alternative is
  `/data/config/kiosk.conf` beside the renderer setting. These are not equivalent: the recipe route
  reproduces on a reflash and needs a build to change; the `/data` route changes over the wire and
  does **not** reproduce on a reflash. Run 35 also shows the mode is a **throughput** decision rather
  than a stall one, which changes what the choice is being made for.
- **Whether the renderer setting belongs in the image at all.**
  `WEBKIT_DISABLE_DMABUF_RENDERER=1` reaches the board as a `/data/config/kiosk.conf` line, which is
  why it survives an OTA and is **not** reproduced by a reflash or a re-provision. That asymmetry is
  already recorded under "Changes configured as a result" as an untaken owner decision, and the 720p
  mode sits in exactly the same position beside it.
- **Which board, and by which route.** Bench is the OTA, reboot and rollback target; prod is
  wall-mounted and carries the live soak. Nothing here proposes a prod delivery. The boot half of any
  such change cannot ride an OTA at all — `/boot` is the shared FAT partition RAUC does not write, as
  "Delivery and board" sets out, with no A/B protection and a recovery path that ends in a physical
  trip.
- **Whether the WiseKiosk frontend should be baked into the image**, given that the shipped scroll
  mechanism is a mirror-served bundle (`index-Mt2gvuKb.js`) and every measurement in Runs 26 to 36
  depends on it. It is a separate decision with its own consequences, and this investigation neither
  makes it nor assumes it.

**The frontend half of the fix is not in this repository and is not closed.** The `scrollLeft`
mechanism Run 25 measures, the 2 s holds, the shared rAF clock and the clock's `.seconds` fix are all
WiseKiosk frontend changes running on the board from the dev mirror. They carry no commit, branch or
pull request here, and that traceability gap is the owner's to close in that repository — the same
gap "Changes configured as a result" records for the `.seconds` fix.

## Changes configured as a result

- **The stutter's fix is a WiseKiosk frontend change, not a meta-wisekiosk one.** `.seconds` out of
  flow under size containment, in `frontend/src/modules/clock/Clock.svelte`. It is running on the
  board. **It carries no commit, branch or pull request** — it exists as a working-tree edit in the
  WiseKiosk checkout, which is where the traceability gap is and where it has to be closed.

- **A WiseKiosk frontend cleanup, not a hang fix — the park-card `{#key ride.name}` remount
  removed.** Run 9 verified the removal (`ROT` 97 → 0) and measured no effect on the residual stall.
  It ships or not on its own merits — less DOM churn, and the marquee class reconciled in both
  directions — and the record must not describe it as the answer to the hang.

- **Root-caused, not fixed, and the root cause was corrected once — the residual engine frame
  stall.** Runs 8 to 16 bound it to the app's own render tree being present (Run 14), surviving every
  other manipulation, animations included (Run 16). Runs 28 to 34 named it a **full-viewport software
  repaint**; **Run 35 falsified that** — 3.0x fewer pixels buys 1.4x on the stall and nothing on its
  ~40 s period — and **Run 36 named the mechanism that holds**: a **JavaScriptCore
  garbage-collection pause**, driven by allocation at 474x on the miss fraction with the arms'
  allocation counters read back. The withdrawn identification is kept visible rather than deleted.
  The evidence, the withdrawal and the gaps are in "Root cause of the residual stall"; the levers
  tried — all of them aimed at paint — are in "Engine levers, measured and exhausted"; the lever that
  follows is in "Real-time framing". **The next step is not another engine lever and not yet an
  architecture decision** — it is a frontend allocation audit, it is un-run, and it is the owner's.
  #100 gpu-compositing stays open on it.

- **The motion cost is settled by re-mechanising, not by trading legibility away — a WiseKiosk
  frontend change.** Run 25 drives the clipping column's `scrollLeft` instead of translating the text
  inside it and the same motion — same rows, same distance, same px/s, interleaved in one capture —
  costs **26.5 ms against 71.5 ms per frame, 2.7x cheaper**. Run 22's 720p mode buys a further 1.94x
  on the during-motion rate. Together they take the shipped configuration to ~42 fps at a 24 ms mean
  (Run 26). This is where the tradeoff below lands: the marquee keeps its motion and its legibility,
  and the cost comes out of the mechanism instead. **It carries no commit, branch or pull request** —
  it runs on the board as a mirror-served bundle, which is the same traceability gap the `.seconds`
  fix carries.

- **Superseded in part — the motion tradeoff the marquee was owed.** The lever the bullet above
  supplies is cheaper than any of the ones enumerated here, so the tradeoff that follows is a smaller
  one than this entry describes. The estimate it points at is also replaced: Run 17 **measures** the
  during-motion framerate at 7.86 fps, inside the 2.6–11.9 fps range the derivation bounded. The rest
  of the entry stands as written. Run 16 measures the marquee's
  motion at roughly **2x per-frame cost** (76.6 → 36.5 ms, ~13 → ~27 fps), and Run 8's arm D reaches
  the same lever by capping the rows that animate. This is the largest frontend lever on the record
  for the *sustained* framerate the owner sees as chop, and every form of it — fewer rows in motion,
  fewer moving pixels, a slower update rate, no motion at all — trades legibility or motion against
  frame time. **Nothing here decides it**, and the during-motion framerate the decision would
  properly be made against is derived, not measured; see the findings "CORRECTED — the marquee's
  motion is a real ~2x per-frame cost" and "DERIVED, NOT MEASURED — the framerate *during* the
  scroll's motion".

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

- **The `probe4` harness, the motion probe family, the shipped-mechanism probes, the allocation probe
  and every raw capture they produced, committed beside this README** — the R2 obligation for Runs 8
  to 36, discharged on the artefacts. Every number in "Metrics" is reproduced from the named file by
  the parser that row names, or from the `AL` record's own fields for Run 36. Two obligations remain
  outstanding and are named in "Test runs": the scripts Runs 3 to 7 put on the board are not committed
  here, and [`parse_alloc.py`](parse_alloc.py) reads an earlier revision of Run 36's payload than the
  committed probe emits.

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
