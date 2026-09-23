# What makes the kiosk panel stutter, and does GPU compositing fix it?

| | |
|---|---|
| **Issue** | #100 gpu-compositing |
| **Status** | **open, and closing on a located cause rather than on a fix.** The compositing premise is **disproven**; the clock relayout is found and fixed in the WiseKiosk frontend; the marquee's motion cost is settled by re-mechanising it from `transform` to `scrollLeft` (Run 25). The residual stall is root-caused as a **JavaScriptCore garbage-collection pause** (Runs 35 and 36) — the identification this record previously carried, an intermittent full-viewport software repaint, is **withdrawn and kept visible below**. The lever that followed from that mechanism — **reducing the WiseKiosk frontend's per-second allocation churn** — is **run and withdrawn**, and Run 48 then found the lever that does work. **The residual has two halves and they belong to different owners.** The **per-event ~450 ms pause cannot be chunked on this board**: armv6 compiles concurrent marking out, so a full collection is one unbroken stop-the-world block — which bounds how the cost is paid, not how large it is. But the **frequency is not a floor at all — it is frontend-driven.** Run 48 varies the application's own `rotation_interval_seconds` across three same-bundle arms, each interval landing-verified in band, and under one uniform membership rule **all three carry a beat at 5 x the rotation tick**: 30.0 s at 6 s, 40.0 s at 8 s, 60.0 s at 12 s. (The 6 s arm is the low-quality point — 58% of its grid slots carry no arrival and its landing check caps out — consistent with the law rather than carrying it.) **Why the count is five is BOUNDED and not established**: the "five ticks of promotion cross the old-generation threshold" model is the one Run 42 falsified, and Run 48 sharpens that exclusion rather than rescuing it. What accumulates over five ticks is unidentified, alongside what the ~450 ms is spent on. **That locates the residual as WiseKiosk's — not the image's and not the hardware's.** It also reconciles the nulls: Runs 37, 43 and 46 removed *individual* allocations and moved nothing because the promotion is spread across the whole per-tick update, while the *number of ticks* per collection stays fixed. **SUPERSEDED and kept visible below**: this record read the residual until 2026-09-23 as "a floor no lever this investigation could reach moves", and before that as "promotion-triggered" — Run 48 refutes the first, Runs 42, 45 and 47 the second. **Production stays at the schema default 8 s** (owner, 2026-09-23): Run 48 is a diagnostic that locates the cause, not a cadence change. What the ~450 ms is *spent on* remains unidentified. What **was** fixed is the marquee **stutter** and the clock relayout. The **fix** is not in this repository: it spans a WiseKiosk frontend change the owner holds and a durable image change not yet taken |
| **Opened / last updated** | 2026-09-19 / 2026-09-23 |

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
which part of it is the open question. #100 gpu-compositing stays open on that. **SUPERSEDED by
"Runs 37-48 — the GC lever, and where it is driven from"**: the residual is a collector pause rather than a
rendering one, and what #100 gpu-compositing stays open on is stated there, not here. The sentence is
kept because it is the question the runs below were asked.

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

**The lever this record was left open on is now closed, and closed against itself.** "Reduce the
frontend's per-second allocation churn" was the right *mechanism* and the wrong *lever*, and Runs 37
to 47 separate the two. Allocation does drive the collection — Run 36 stands, on injected pressure
far above anything the page does. But removing the page's *own* allocation reaches nothing: not the
marquee's per-frame transients (Run 37), not the clock and `matchMedia` reductions of Fix 1
(Run 43), not the reactive render itself (Run 46). Freezing the rotation tick takes the stall to zero
(Run 39) and is not shippable, because a rotation that does not rotate is not the product. Everything
short of that leaves the ~40 s beat where it was, to within the 0.1 s the probe resolves — and so
does every engine lever the runs could reach, the heap and growth budget (Run 42), the full-GC timer
(Run 45) and WebKit's memory-pressure handler (Run 47). **Run 48 is where it turns.** Varying the
application's own `rotation_interval_seconds` across three same-bundle arms moves the beat with it —
**5 x the rotation tick** — 30.0 s at 6 s, 40.0 s at 8 s, 60.0 s at 12 s under one uniform
membership rule — so the frequency was never a floor: it is the frontend's rotation cadence. That
reconciles every null above, because no single contributor to the per-tick update is removable enough
to matter while the tick *count* per collection stays fixed. **Why the count is five is not
established** — the promotion-threshold reading is the one Run 42 falsified — and **the per-event
~450 ms pause cannot be chunked** on armv6, with what it is spent on still unidentified. The sentence above it, that the lever is un-run, is superseded and kept
visible; the runs, the reasoning and what remains open are in "Runs 37-48 — the GC lever, and where it is
driven from".

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

**Runs 37 to 48 keep the same discipline, and one part of it is weaker than for Runs 17 to 36,
stated rather than smoothed over.** Every one ran on **prod**. **No capture in this range carries the
image commit** and no run in it re-read `/etc/buildinfo`, so `100-gpu-compositing:7ce44ba` is carried
by continuity from Run 36 — the runs are consecutive on one board with no OTA, reflash or rebuild
between them, but the basis is a deploy record rather than a board read, and it is the weakest R1
basis in this document. **The frontend bundle is named for every run in the range, and where the name
comes from differs.** Runs 38, 43, 44 and 46 have it in their capture's own header —
`index-Mt2gvuKb.js`, `index-BhI9T8Rb.js`, `index-Mt2gvuKb.js` and `index-DJUeJLKg.js` — while Runs
37, 39, 40, 41, 42 and 45 take it from the deploy record, which is this record's claim and not the
board's: Run 37 on the instrumented `index-CDzciXkW.js`, Run 39 on `index-CqqUlNUO.js`, Run 40 on
`index-BM3R3o7e.js`, Runs 41 and 42 on the shipped `index-Mt2gvuKb.js`, Run 45 on
`index-Csf9V8Vf.js`. **Run 47's bundle is not recorded at all** — no hash was read off the board or
carried in its output — which is the same gap Run 25 carries and is stated rather than guessed; its
two arms ran back-to-back on one board, one build and one bundle, so the comparison inside the run is
unaffected by it. **Display mode is not recorded in any capture in this range** and is carried by
continuity at 1280x720 from Run 36. Runs 42, 45 and 47 each add environment variables and say which,
and Run 44 sets two `/data/config/kiosk.conf` lines for its window and restores them after. **Run 48
is the one run in this range whose manipulation is neither an environment variable nor a bundle**: it
varies the application's own `rotation_interval_seconds` across three arms on **one** bundle,
`index-DJUeJLKg.js`, named in each capture's own header, and each arm's interval is read back in band
from the capture's `R[]` series.

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
| 37 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · instrumented bundle `index-CDzciXkW.js` · 720p | [`p25_mqtoggle.js`](p25_mqtoggle.js) → [`mq-toggle-496s-raw.txt`](mq-toggle-496s-raw.txt), read by [`parse_mqtoggle.py`](parse_mqtoggle.py) | **The first withdrawal.** The marquee's per-frame transient allocation toggled inside one capture under byte-identical motion, landing counters read back (12963 of 12965 and 2 of 6696): ALLOC **5 of 12965 = 0.039%**, CLEAN **7 of 6696 = 0.105%**. Removing the churn does not lower the stall. **The mechanism offered for that — it dies in the nursery and is never promoted — is INFERENCE and BOUNDED (Runs 42, 45, 47)**: it names a promotion trigger no lever reaches, and Run 44 read zero eden collections in 85 s. The *bound* does not depend on it |
| 38 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle `index-Mt2gvuKb.js` | [`cap-probe.js`](cap-probe.js) · [`p26_gc.js`](p26_gc.js) → [`cap-probe-raw.txt`](cap-probe-raw.txt) | The page cannot instrument its own collector on this build: `performance.memory` absent, `window.gc` undefined, `FinalizationRegistry` present but its callbacks **never fire** on a saturated core (`fin0`, an empty `G[]`), `WeakRef.deref` keeps its target alive for the rest of the turn so observing prevents the collection observed. A null instrument, not a null result. **The `JSC_logGC` reading this row once carried — "substantially compiled out" — is WITHDRAWN (Run 47): the option is `Availability::Normal` and honoured; the empty trace was a capture-routing bug** |
| 39 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · instrumented bundle `index-CqqUlNUO.js` · 720p | [`p28_ablate.js`](p28_ablate.js) → [`ablate-475s-raw.txt`](ablate-475s-raw.txt), read by [`parse_ablate.py`](parse_ablate.py) | **The relocation.** Three conditions interleaved, skip counters read back: none **10 of 6109 = 0.164%**, rotation-off **0 of 6737 = 0.000%** with a 218 ms maximum, clock-off **5 of 6132 = 0.082%**. Freezing the rotation tick takes the stall to **zero** (p = 0.0006); the clock arm is noise (p = 0.21) and its parser verdict is **not adopted**. The driver is the per-tick **reactive update**, not the allocation inside it |
| 40 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · instrumented bundle `index-BM3R3o7e.js` · 720p | [`p29_split.js`](p29_split.js) → [`split-475s-raw.txt`](split-475s-raw.txt), read by [`parse_split.py`](parse_split.py) | **SCORED UNMEASURED, not null.** `matchMedia` cached against the derived recompute: 1, 3 and 1 stalls per arm over 463 s — Poisson noise, and the known-zero control read **one**. The parser's confident verdict is **not adopted**. Superseded by Run 43, which ships both reductions and can score |
| 41 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle `index-Mt2gvuKb.js` · 720p | [`p30_baseline.js`](p30_baseline.js) → [`baseline-588s-raw.txt`](baseline-588s-raw.txt), read by [`parse_baseline.py`](parse_baseline.py) | **The reference.** 588 s, 23969 frames, 25 ms mean: **27 frames over 250 ms = 0.046/s**, and fourteen of them on a **metronome** — 40.5 s to 561.0 s at intervals of **39.9–40.1 s**, 475–531 ms each |
| 42 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle `index-Mt2gvuKb.js` · 720p + `JSC_forceRAMSize=32MB`, growth factors 1.05, `collectContinuously` | [`p30_baseline.js`](p30_baseline.js) → [`eager-gc-616s-raw.txt`](eager-gc-616s-raw.txt), read by [`parse_baseline.py`](parse_baseline.py) | **Inert on the cadence.** `forceRAMSize` landed — `VmRSS` reads **89984 kB**, against **106380 kB** in **Run 37's** capture, which is a different bundle and a different probe; no same-configuration baseline was taken, so the check is indicative rather than controlled — and the beat runs 40.5 s to 401.0 s at **39.9–40.3 s**, Run 41's period. **`collectContinuously` never applied**: `Options.cpp:832-833` clears it whenever `useConcurrentGC` is false, which armv6 forces. Rate reads 0.029/s and **is not scored**: the beat, not the count, is the comparable quantity |
| 43 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle `index-BhI9T8Rb.js` · 720p, clean config | [`p30_baseline.js`](p30_baseline.js) → [`fix1-benchmark-600s-raw.txt`](fix1-benchmark-600s-raw.txt), read by [`parse_baseline.py`](parse_baseline.py) | **The lever, built and null.** Clock granularity split + `matchMedia` cache, both real allocation reductions: 608 s, **26 frames over 250 ms = 0.043/s**, beat 40.5 s to 561.0 s at **40.0–40.1 s** at 470–525 ms, plus a 600.5/601.2 pair after a 39.5 s interval at 433 and 532 ms. **Reducing app-level allocation does not move the stall** |
| 44 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle `index-Mt2gvuKb.js` · `WEBKIT_INSPECTOR_HTTP_SERVER`, restored after | [`webkit-inspector` skill](../../../.claude/skills/webkit-inspector/SKILL.md) (`cd5cf9e`) → [`inspector-gc-census-raw.txt`](inspector-gc-census-raw.txt) | **The ground truth, and the withdrawal of "the inspector is unreachable on this build".** The launcher wires the **WS-only** variable; the HTTP variant works over the wire with no rebuild. `Heap.startTracking` types the tracked collection as **full**, not eden — **n = 1**, and the same window reports zero eden collections over 85 s, which is not credible, so the sample is not treated as representative. The forcing census diff over 30 s is reported in the capture as **no retained growth**, but **no number was banked for it** — an unrecorded session claim, not a datum of this record. The *experiment* is re-runnable: the committed `webkit-inspect.mjs` implements the same forced-GC census diff as its `diff` mode |
| 45 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle `index-Csf9V8Vf.js` · 720p + `percentCPUPerMBForFullTimer` / 16 | [`p30_baseline.js`](p30_baseline.js) → [`freq-lever-P16-535s-raw.txt`](freq-lever-P16-535s-raw.txt), read by [`parse_baseline.py`](parse_baseline.py) | **The frequency lever, inert.** A 16x less eager full-collection timer: 535 s, **29 frames over 250 ms = 0.054/s**, beat 42.0 s to 522.5 s at **40.0–40.2 s**, 472–527 ms. Phase shifts ~1.5 s, **period does not move**. The collection is not timer-triggered. **The "therefore promotion-triggered" reading is WITHDRAWN** — Run 42 is itself a promotion-path lever and was equally inert (see "Runs 37-48 — the GC lever, and where it is driven from"). Ten off-beat arrivals are enumerated in the run block, including a 593 ms one at 302.4 s |
| 46 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle `index-DJUeJLKg.js` · 720p, clean config | [`p30_baseline.js`](p30_baseline.js) → [`imperative-tour-587s-raw.txt`](imperative-tour-587s-raw.txt), read by [`parse_baseline.py`](parse_baseline.py) | **The sharpest form of the lever, also null.** Tour rows rendered once and filled imperatively, bypassing the reactive `{#each}`, with a two-screenshot landing check that shows the right rows in the right places but **has no oracle** and cannot resolve a wrong-value fill: 587 s, **25 frames over 250 ms = 0.043/s**, beat at **39.9–40.1 s** across a hand-curated on-beat set. Mean frame time **22 ms against Run 41's 25 ms** and 298 frames in the 50–100 ms bucket against 682 — **consistent with a throughput win, not measured as one**: the comparison is cross-capture against the slowest of five, and the run carries no control arm |
| 47 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle **not recorded** · 720p by continuity | [`p30_baseline.js`](p30_baseline.js), two arms differing only in `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR`. **No capture file is committed** — the arrival series is transcribed into the run block | **The memory-pressure falsifier.** The complete kill switch for WebKit's memory-pressure handler, run back-to-back against a baseline arm on one board and one build, **with its landing verified in the UI process that reads it** (`WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR` found in surf's own `/proc/<pid>/environ` under the identical `kiosk.conf` mechanism, on a supplementary restart): the beat holds at **40.0 s** in **both** arms. The switch skips `install()` outright, so the arms close the **whole handler**; separately, reaching the monitor's **≥90%** would need `MemAvailable` to fall from ~263 MB to ~43.5 MB of 435, a ~220 MB excursion against a web process of ~90–106 MB, which closes the **polled path** on headroom. **The memory-pressure handler is not the driver.** `JSC_logGC` reached the WebProcess and its trace was still not captured — the sandbox blocked the file redirect |
| 48 | prod · Pi Zero W | `100-gpu-compositing:7ce44ba` (by continuity) · bundle `index-DJUeJLKg.js`, **the same in all three arms** · 720p | [`p31_rotcheck.js`](p31_rotcheck.js) → [`rotation-6s-588s-raw.txt`](rotation-6s-588s-raw.txt) · [`rotation-8s-589s-raw.txt`](rotation-8s-589s-raw.txt) · [`rotation-12s-586s-raw.txt`](rotation-12s-586s-raw.txt) | **The lever that moves the beat, and it is the frontend's.** The app's `rotation_interval_seconds` varied across three same-bundle arms, each interval read back in band (`R[]` medians 6.000 / 8.000 / 12.000 s): under one uniform >=250 ms membership rule, **all three arms carry a beat at 5 x the rotation tick** — **30.0 s** (8 of 9 arrivals on-grid, 58% dropout, `R[]` capped), **40.0 s** (14 of 15, 0% dropout) and **60.0 s**. **The frequency is frontend-driven, not a hardware or engine floor.** *Why* five ticks is **unidentified** — the promotion-threshold model Run 42 falsified is not reinstated. The 6 s arm is the low-quality point, not a counter-example; its 167 s silent tail is unexplained. Diagnostic only — production stays at 8 s |

**R2 is satisfied for Runs 8 to 46 and 48 except Run 36's analyser and Run 44's census-diff
numbers, is not satisfied for Run 47, and is not satisfied for Runs 3 to 7.** Each exception is named
where it bites, below.

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

The same obligation for Runs 37 to 48, **discharged for ten of the twelve, and the two exceptions
are named here rather than in a footnote.** Every probe, every analyser and every raw capture for
Runs 37 to 46 is committed here, the inspector session's output included, and Run 46's landing-check
screenshots with it; **Run 48's probe and all three of its captures are committed too**, which makes
it the cleanest discharge in this range. The two that are not:

- **Run 44's census diff banked no numbers.** The capture names `profile-churn.mjs`, which is
  committed nowhere in this repository — but the committed
  [`webkit-inspect.mjs`](../../../.claude/skills/webkit-inspector/webkit-inspect.mjs) implements the
  same experiment as its `diff <seconds>` mode, two snapshots N seconds apart with a forced
  collection before each. **So the obligation is to bank the numbers, not to commit a missing
  tool**: the specific run is not re-derivable because nothing numeric was recorded, while the
  experiment itself is re-runnable today — see the Run 44 block.
- **Run 47 has no committed capture at all.** Its two arms' arrival series are transcribed into its
  run block from the session's own task output rather than read from a raw file in this directory.
  The run is reported with that stated at its head.

Both are outstanding R2 obligations on this investigation, alongside the two already named above.
**Run 48 carries neither defect**: its probe, its three raw captures and every figure quoted from
them are in this directory, and the figures in its block were re-derived from those files rather than
transcribed.

| File | What it is |
|---|---|
| [`p25_mqtoggle.js`](p25_mqtoggle.js) | The marquee-allocation toggle probe (Run 37) — an ALLOC/CLEAN palindrome inside one page load, selecting the `Map`-destructuring loop body or an allocation-free indexed one per frame **from the arm schedule then in force**, so the motion is byte-identical and only the garbage differs, with a per-arm path counter so an arm that ran the wrong body is visible rather than scored. **Its `EDGE` array does not terminate `ARMS`**, so the final arm runs to the end of the capture rather than for one block — see the Run 37 block |
| [`cap-probe.js`](cap-probe.js) · [`p26_gc.js`](p26_gc.js) | Run 38's in-page GC instruments — a capability probe for `performance.memory` / `FinalizationRegistry` / `WeakRef` / `window.gc`, and a full-GC detector built on promoted sentinels and finalizer bursts. The detector returned nothing because finalizer callbacks never fire on this core, and **that null instrument is Run 38's result** rather than a failed run |
| [`p28_ablate.js`](p28_ablate.js) · [`p29_split.js`](p29_split.js) | The subsystem-ablation and rotation-driver-split probes (Runs 39, 40) — three conditions interleaved in one capture on 50 s arms cycled three times, each reading the app's own skip counters back per condition as the landing check |
| [`p30_baseline.js`](p30_baseline.js) | The long-baseline probe (Runs 41, 42, 43, 45, 46) — a bare rAF loop with no arms and no ablation, recording every frame over 250 ms with its timestamp so the **arrival cadence** is readable, plus a seven-bucket histogram that reproduces the stall count independently. It is the one probe in this record whose output is the period rather than a rate |
| [`p31_rotcheck.js`](p31_rotcheck.js) | The rotation-interval probe (Run 48) — Run 41's `>250 ms` stall detector with an in-band **rotation landing check** added: `R[]` records the wall-clock time of every tour-row text change, so the interval the app actually ran is re-derivable from the capture instead of being taken on trust from the config that was written |
| [`parse_mqtoggle.py`](parse_mqtoggle.py) · [`parse_ablate.py`](parse_ablate.py) · [`parse_split.py`](parse_split.py) | The analysers for Runs 37, 39 and 40, each with a test — [`parse_mqtoggle_test.py`](parse_mqtoggle_test.py), [`parse_ablate_test.py`](parse_ablate_test.py), [`parse_split_test.py`](parse_split_test.py) — proving it reports both outcomes. **Each prints a VERDICT line and two of those verdicts are rejected in the run blocks above** (Run 39's clock arm and Run 40's whole capture, both on counts too small to score). The parsers reproduce the counts faithfully; the significance reasoning is in the run blocks, not in the parsers. **None of the three carries an event-count guard**, so each prints a confident VERDICT on counts that cannot separate anything — including, demonstrably, a capture with zero stalls in every arm. Closing that is an outstanding obligation; until it is, a verdict read off these parsers without the matching run block is not a result |
| [`parse_rotation.py`](parse_rotation.py) | The rotation analyser (Run 48) — reads the `R[]` rotation series and the `S[]` stall series from one capture, applies **one uniform membership rule to every arm** (post-startup arrivals at or above the probe's own 250 ms cutoff, companion pairs clustered to one event), and reports the gap series, the `5 x tick` grid fit and the dropout rate. It also **detects the `R[]` cap** and says so, which is how the 6 s arm's blind final 100 s became visible. [`parse_rotation_test.py`](parse_rotation_test.py) proves it reports both outcomes — a beat that scales with the tick and one that does not — plus the cap case and the 250 ms boundary |
| [`parse_baseline.py`](parse_baseline.py) | The `BL` analyser (Runs 41, 42, 43, 45, 46) — window, frame count, mean, max, rate, the seven-bucket histogram checked against the stall list, and the on-beat arrival series with its intervals. Every figure quoted for those five runs is reproduced by it. **It carries no test**, unlike the three analysers above, so the both-outcomes discipline this record states for Runs 8 to 16 is not met for it; what stands in place of a test is that each capture's histogram reproduces its own stall count independently of the stall list. **That substitute check validates the stall *count*, and every conclusion in "Runs 37-48 — the GC lever, and where it is driven from" rests on the on-beat *interval series*, which nothing tests** — which is where two mis-statements in this document were found. The analyser also **presumes the period it is used to read**: it cuts steady state at 40.0 s and folds arrivals modulo 40.0 s within ±3.0 s, a window that accepts 15% of the timeline by chance. No conclusion here depends on the fold — the run blocks quote the raw consecutive arrivals, which are self-evidently 40 s apart — but a period-free read is what the tool should do |
| [`mq-toggle-496s-raw.txt`](mq-toggle-496s-raw.txt) · [`ablate-475s-raw.txt`](ablate-475s-raw.txt) · [`split-475s-raw.txt`](split-475s-raw.txt) · [`cap-probe-raw.txt`](cap-probe-raw.txt) | Raw captures, Runs 37, 39, 40 and 38 |
| [`baseline-588s-raw.txt`](baseline-588s-raw.txt) · [`eager-gc-616s-raw.txt`](eager-gc-616s-raw.txt) · [`fix1-benchmark-600s-raw.txt`](fix1-benchmark-600s-raw.txt) · [`freq-lever-P16-535s-raw.txt`](freq-lever-P16-535s-raw.txt) · [`imperative-tour-587s-raw.txt`](imperative-tour-587s-raw.txt) | Raw captures, Runs 41, 42, 43, 45, 46 — all `BL` payloads from [`p30_baseline.js`](p30_baseline.js). The histogram reproduces each capture's stall count independently of the stall list, and every list is complete rather than truncated at the probe's 120-entry cap |
| [`rotation-6s-588s-raw.txt`](rotation-6s-588s-raw.txt) · [`rotation-8s-589s-raw.txt`](rotation-8s-589s-raw.txt) · [`rotation-12s-586s-raw.txt`](rotation-12s-586s-raw.txt) | Raw captures, Run 48's three arms — all `BL` payloads from [`p31_rotcheck.js`](p31_rotcheck.js), each carrying its own `R[]` rotation series, its `LOAD` line and its `MemAvailable` read. One bundle across all three, named in each header. Read by [`parse_rotation.py`](parse_rotation.py), which reproduces every figure quoted for Run 48 |
| [`fix1-600s-raw.txt`](fix1-600s-raw.txt) | An **earlier Fix-1 capture on the same bundle**, 801 s and 30 frames over 250 ms (0.037/s), superseded by [`fix1-benchmark-600s-raw.txt`](fix1-benchmark-600s-raw.txt) and **contributing no number to any run**. It carries only four on-beat arrivals and a large off-beat cluster between 150 s and 211 s, so its arrival cadence is not readable. Catalogued so it is not an uncatalogued capture, not because a conclusion rests on it |
| [`inspector-gc-census-raw.txt`](inspector-gc-census-raw.txt) | Run 44's inspector output — the `Heap.startTracking` collection-type read, the `Heap.snapshot` census by class, and the 30 s forcing diff. It carries its own bound condition in the file: tracking quiesces the collector, so the read is of the collection **type** and not of the cadence. **The diff section of the file is a header with no numbers under it**, so nothing numeric from the diff is readable here; the tool it names, `profile-churn.mjs`, is not committed, though the committed `webkit-inspect.mjs` implements the same diff. The census above it does carry real per-class figures and they re-derive |
| [`imperative-tour-render-shot1.png`](imperative-tour-render-shot1.png) · [`imperative-tour-render-shot2-rotated.png`](imperative-tour-render-shot2-rotated.png) | Run 46's landing check — the imperatively-filled tour before and after a rotation, the evidence that the bundle whose capture reads as a clean null was drawing the right rows. **The check has no oracle**: there is no matching pair from the reactive bundle at the same data state and no written expectation of which rows should appear after a rotation, so it establishes that rows were drawn in the right places, not that each cell carried the right value |
| [`jsc-gc-findings.md`](jsc-gc-findings.md) | The JavaScriptCore source analysis behind "The JSC source: why the pause cannot be chunked on this board" — the option gating, the scheduler, the frequency lever and the ranked shortlist Run 45 was chosen from, with its own confirmed/not-confirmed split and its upstream sources |
| [`webkit-inspect.mjs`](../../../.claude/skills/webkit-inspector/webkit-inspect.mjs) | Run 44's inspector client, banked as a **skill** rather than beside this investigation because it is reusable on any future board question — `.claude/skills/webkit-inspector/`, committed at `cd5cf9e`. It runs on the workstation through an `ssh -L` forward; the board has no node |

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

### Run 37 — the marquee's per-frame allocation, toggled inside one capture

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by
  continuity). **Frontend bundle:** the instrumented `index-CDzciXkW.js`, carrying both loop bodies.
  **Kiosk config:** as Run 36, 1280x720.
- **Scripts deployed:** ONE-OFF [`p25_mqtoggle.js`](p25_mqtoggle.js), committed here. Raw capture
  [`mq-toggle-496s-raw.txt`](mq-toggle-496s-raw.txt), read by
  [`parse_mqtoggle.py`](parse_mqtoggle.py) with [`parse_mqtoggle_test.py`](parse_mqtoggle_test.py)
  proving it reports both outcomes.
- **Procedure:** one continuous 496 s capture, arms **interleaved inside it** — a `W,A,C,A,C,A`
  palindrome after a 20 s warmup. Arm A runs the current `Map`-destructuring loop; arm C runs an
  indexed-array loop that allocates nothing. **The motion is byte-identical** — both paths compute
  and write the same scroll offsets — so the only difference between arms is garbage.
- **The schedule that ran is not the one the probe was written to run, and the correction weakens the
  drift argument rather than the result.** [`p25_mqtoggle.js`](p25_mqtoggle.js) declares seven edges
  for six arms and its `armAt()` scans from the last *arm* index, so the final edge is never read and
  **the trailing A arm runs from t=340 s to the end of the capture — 156 s, not 80 s.** The executed
  schedule is `W 20, A 80, C 80, A 80, C 80, A 156`: **A 316 s against C 160 s**, not the equal blocks
  the palindrome's own header claims. The capture's frame counts say so without needing the board —
  12965 against 6696 is a ratio of **1.94**, where three equal A blocks against two C blocks would
  give 1.5. Every CLEAN arm is still bracketed by ALLOC arms, so the null is not destroyed; but the
  stated basis for trusting it — symmetric, equal-weight blocks cancelling the board's ~30% within-run
  drift — is **not what ran**, and a trailing double-length arm pushes A's time-centroid late. The
  bias runs against the hypothesis this run rejected, so the bound survives; it survives by luck
  rather than by design, and **no probe in this family terminates its final arm and no parser checks
  a capture's length against its schedule.**
- **The discriminator, fixed before the run.** If the marquee's transient allocation paces the
  collection, arm A must carry a markedly higher fraction of frames over 250 ms than arm C.
- **The landing check is in band.** Each arm carries its own path counter: **arm A reads 12963
  allocating frames of 12965 and arm C reads 2 of 6696** — each arm ran the body it was meant to.

| Arm | Frames | >250 ms | fraction | mean | max |
|---|---|---|---|---|---|
| A ALLOC (`Map` destructuring) | 12965 | 5 | 0.039% | 24 ms | 479 ms |
| C CLEAN (indexed, no allocation) | 6696 | 7 | 0.105% | 24 ms | 531 ms |

- **The result is the absence of a reduction, and the ratio is not the result.** The clean arm's
  fraction is 2.7x *higher*, which at 5 and 7 events is noise in the other direction (a binomial test
  against the arms' frame counts gives p = 0.12; nothing here separates the arms). What the run
  establishes is a **bound**: removing the marquee's transient allocation entirely does not lower the
  stall fraction, and a lever that cannot be shown to help at 19661 frames is not the lever. The
  capture's overall figures are 20281 frames, 24 ms mean, 1569 ms max, 18 frames over 250 ms.
- **The mechanism this implies, and it is INFERENCE.** A per-frame transient dies in the nursery and
  is reclaimed by an eden collection, which is cheap; it is never promoted, so it never raises the
  old generation toward the threshold that triggers the full collection. This is consistent with
  Run 36 — which injected ~25000 objects per frame, far above anything the page does, and *did* drive
  promotion — and it is why Run 36's result does not transfer to the page's own churn.
  **BOUNDED (Runs 42, 45, 47):** this mechanism assumes a promotion-triggered collection, and that
  trigger is not identified — see "Runs 37-48 — the GC lever, and where it is driven from". It also sits
  unreconciled against Run 44's one direct read of the collector, which reported **zero eden
  collections in 85 s**. The *bound* the run establishes — removing the transient allocation does not
  lower the stall fraction — does not depend on either.

### Run 38 — the in-page GC instruments, and why there are none

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** `index-Mt2gvuKb.js`, named in the capture's own header.
- **Scripts deployed:** ONE-OFF [`cap-probe.js`](cap-probe.js) and [`p26_gc.js`](p26_gc.js),
  committed here. Raw capture [`cap-probe-raw.txt`](cap-probe-raw.txt), carrying both the `CAP`
  capability line and the `GC2` detector payload.
- **What it establishes**, each read off that capture:
  - **`performance.memory` is absent** (`pm:NONE`) and **`window.gc` is undefined**. There is no
    heap-size series to read, and no way to watch the heap approach a threshold from inside the page
    or to force a collection at a known moment.
  - **`FinalizationRegistry` is present and its callbacks never fire.** `p26_gc.js` was built on it:
    hold sentinels long enough to be promoted, drop them, and time the finalizer bursts as full-GC
    events. Finalizers are delivered on an idle turn, and this core has none, so the payload reads
    `fin0` with an empty `G[]` over 118 s and 4864 frames — a null instrument, not a null result.
  - **`WeakRef.deref` cannot be used to observe collection** — calling it keeps a still-live target
    alive for the remainder of the turn, so the act of measuring prevents the thing measured. (It
    does not *resurrect*: `deref` returns `undefined` for an already-collected target. The
    consequence is the same; the earlier mechanism sentence was wrong.)
- **One further bullet, and it is NOT read off this capture.** `cap-probe-raw.txt` carries no
  `JSC_logGC` content at all. **Run 45's** capture carries a `JSC_logGC` block with three lines over
  535 s, none with a pause at or above 100 ms, and this record read that as the option being
  "substantially compiled out". **That reading is WITHDRAWN (Run 47).** `logGC` is declared
  `Availability::Normal` at `OptionsList.h:381`, which `overrideOptionWithHeuristic` short-circuits
  the availability test for, so it is honoured in this release build; its emission sites in `heap/`
  carry no `#if` guard. What is compiled out is `dataLogLnIf` under a `constexpr bool verbose =
  false`, which is a different thing. The empty trace was a **capture-routing bug**: `dataLog` writes
  to the **WebProcess's** stderr, which neither the journal nor the surf log captures. Run 47 set
  `WTF_DATA_LOG_FILENAME` to redirect it and the WebProcess sandbox denied the path, so the trace is
  *still* uncaptured — but it is uncaptured for a reason with a named fix, not because the instrument
  does not exist. **That block's last two values, `0.696` and `9.76`, are not self-describing and no
  conclusion is quoted from them**, and the "one incidental line" figure this bullet once carried
  appears in no capture in this directory and is dropped.
- **The conclusion is about instruments, not about the collector.** The page cannot instrument its own
  collector on this build. Run 44 is what leaves the page, and the `webkit-inspector` skill is what
  makes that possible.

### Run 39 — the periodic subsystems, ablated three ways inside one capture

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** the instrumented `index-CqqUlNUO.js`, gating each subsystem behind
  `window.__abl`. **Kiosk config:** 1280x720.
- **Scripts deployed:** ONE-OFF [`p28_ablate.js`](p28_ablate.js), committed here. Raw capture
  [`ablate-475s-raw.txt`](ablate-475s-raw.txt), read by [`parse_ablate.py`](parse_ablate.py) with
  [`parse_ablate_test.py`](parse_ablate_test.py).
- **Procedure:** one continuous 462 s capture; after a 20 s warmup, 50 s arms cycling `N,R,C` three
  times, so each condition is sampled early, mid and late and drift cancels. **N** ablates nothing;
  **R** skips the 8 s rotation tick's derived recompute, leaving the marquee's own animation cycle
  untouched; **C** skips the 1 s clock re-read and re-format.
- **The landing check is in band.** The app's own skip counters are exfiltrated per condition: **R
  reads 18 rotation skips and 0 clock skips; C reads 138 clock skips and 0 rotation skips; N reads
  0 and 0.** Every arm is verified to have ablated what it claimed and nothing else.

| Condition | Frames | >250 ms | fraction | mean | max | rot skips | clock skips |
|---|---|---|---|---|---|---|---|
| N none | 6109 | 10 | 0.164% | 25 ms | 525 ms | 0 | 0 |
| R rotation off | 6737 | **0** | **0.000%** | 22 ms | 218 ms | 18 | 0 |
| C clock off | 6132 | 5 | 0.082% | 23 ms | 530 ms | 0 | 138 |

- **The rotation result is strong and the clock result is not, and the parser over-reads the second
  one.** Arm R records **zero** frames over 250 ms in 6737, where N's rate predicts about eleven — a
  binomial test against the arms' frame counts gives p = 0.0006, and R's maximum frame is **218 ms**,
  below the threshold entirely, so the arm contains no near-miss either. That is a real effect.
  Arm C's 5 against N's 10 is **p = 0.21 — indistinguishable from noise**, and
  [`parse_ablate.py`](parse_ablate.py) nonetheless prints "VERDICT clock: … this subsystem drives the
  residual" from the raw 2.0x ratio. **That verdict is not adopted here.** The parser reproduces the
  counts faithfully and its significance reasoning is absent rather than wrong; the counts are in the
  table and the reading is taken from them.
- **What the run relocates.** Run 37 has already shown the allocation *inside* the per-frame loop is
  not the driver. Run 39 shows the per-tick **reactive update** is. Those are compatible only if what
  matters is allocation that **survives** the tick — promoted into the old generation — rather than
  allocation that is merely made. **BOUNDED (Runs 42, 45, 47):** that reconciliation names promotion
  as the trigger, and no lever aimed at promotion moves the beat, so it is not the record's finding —
  see "Runs 37-48 — the GC lever, and where it is driven from". What arm R establishes without it is narrower and
  unaffected: **the tick is what makes the cost become due**, whatever the cost is.
- **Bound conditions.** Arm R is **not a shippable configuration**: a rotation tick that does not
  recompute is a display that does not advance. The run measures **that the tick is upstream of the
  stall**; it does not propose freezing it, and it does not name what the tick does that matters. And
  it does not separate *which part* of the tick — that is Run 40's question, which Run 40 could not
  answer.

### Run 40 — `matchMedia` against the derived recompute, and the capture that was too quiet

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** the instrumented `index-BM3R3o7e.js`. **Kiosk config:** 1280x720.
- **Scripts deployed:** ONE-OFF [`p29_split.js`](p29_split.js), committed here. Raw capture
  [`split-475s-raw.txt`](split-475s-raw.txt), read by [`parse_split.py`](parse_split.py) with
  [`parse_split_test.py`](parse_split_test.py).
- **Procedure:** the Run 39 schedule with the middle condition changed — 463 s, 20 s warmup, 50 s arms
  cycling `N,M,R`. **M** caches `window.matchMedia` so the marquee's re-registration stops creating a
  document-retained `MediaQueryList` per tick; **R** is Run 39's zero control.
- **The landing check is in band and it landed:** N reads **18** real `matchMedia` calls, M reads
  **0**, R reads 3 with 18 rotation skips.

| Condition | Frames | >250 ms | fraction | mean | max | real `matchMedia` | rot skips |
|---|---|---|---|---|---|---|---|
| N none | 6347 | 1 | 0.016% | 24 ms | 474 ms | 18 | 0 |
| M `matchMedia` cached | 6233 | 3 | 0.048% | 24 ms | 451 ms | 0 | 0 |
| R rotation off | 6293 | 1 | 0.016% | 23 ms | 313 ms | 3 | 18 |

- **SCORED UNMEASURED, not null.** One, three and one events per arm cannot separate anything: N
  against M is p = 0.37 and N against R is p = 1.0. The zero control that read a clean zero in
  Run 39's 6737 frames reads **one** stall here, which is the clearest statement that the capture as a
  whole was too quiet to score — the arm that is known to be zero did not read zero.
  [`parse_split.py`](parse_split.py) prints a confident verdict ("the per-tick derived recompute is
  the source; the fix must reduce that") and **that verdict is not adopted.** The run contributes no
  finding; it is recorded because it was taken, because its harness is committed, and because a
  reader who finds the parser's verdict elsewhere is entitled to know it was rejected here.
- **Why it was not re-run.** Run 43 supersedes the question it asked. Fix 1 ships **both** candidate
  reductions — the clock granularity split and the `matchMedia` cache — and measures them together
  over 608 s against a clean 588 s reference, at counts that can score. The answer there is that
  neither matters, which makes splitting them moot.

### Run 41 — the clean baseline, and the ~40 s metronome

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** the shipped `index-Mt2gvuKb.js`. **Kiosk config:** clean, 1280x720.
- **Scripts deployed:** ONE-OFF [`p30_baseline.js`](p30_baseline.js), committed here. Raw capture
  [`baseline-588s-raw.txt`](baseline-588s-raw.txt), read by
  [`parse_baseline.py`](parse_baseline.py). The probe is a bare rAF loop with no ablation and no
  arms.
- **The capture:** 588 s, **23969 frames**, mean **25 ms**, max **1512 ms**, **27 frames over 250 ms
  = 0.046/s**. The payload's own histogram is 22917 / 682 / 343 / 21 / 3 / 3 / 0 across the
  `<50 / 50-100 / 100-250 / 250-500 / 500-1000 / 1000-2000 / >=2000` ms buckets, and its 21 + 3 + 3
  reproduces the stall count exactly; the stall list is complete, 27 of 27, below the probe's 120-entry
  cap.
- **The beat, which is the point of the run.** Fourteen of the twenty-seven arrivals fall on one
  period:

| t (s) | 40.5 | 80.5 | 120.6 | 160.5 | 200.6 | 240.6 | 280.7 | 320.7 | 360.8 | 400.8 | 440.9 | 480.9 | 520.9 | 561.0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| duration (ms) | 477 | 476 | 531 | 484 | 475 | 480 | 527 | 488 | 486 | 477 | 525 | 489 | 481 | 490 |

  The thirteen intervals are **40.0, 40.1, 39.9, 40.1, 40.0, 40.1, 40.0, 40.1, 40.0, 40.1, 40.0, 40.0,
  40.1 s** — a spread of 0.2 s over nine and a half minutes, at the 0.1 s the probe resolves. Durations
  run **475 to 531 ms**, mean 492 ms.
- **What is not on the beat, and the accounting closes.** **Five** arrivals are startup — 1.2, 2.7,
  3.8, 4.1 and 8.4 s, up to 1512 ms. **One further early arrival at 24.2 s (271 ms)** is on neither
  the beat nor the startup cluster. Seven are off-beat: 144.7, 144.9, 264.7, 265.0, 300.7, 301.0 and
  393.0 s, at 257 to 450 ms — noticeably shorter than the on-beat arrivals and clustered in pairs.
  14 + 5 + 1 + 7 = 27, the capture's whole stall list. They are recorded and no conclusion rests on
  them.
- **This is the reference every run below is read against, and only its beat is read across captures.**
  Rate is not comparable between captures in this record — Runs 26a and 26b differ by a factor of two
  on the *same* configuration — so a run that changes the rate and not the period has changed nothing
  this section is measuring.

### Run 42 — the JSC eager-collection environment, with its landing verified

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** the shipped `index-Mt2gvuKb.js`. **Kiosk config:** as Run 41 **plus**
  `JSC_forceRAMSize=32MB`, the eden and old-generation growth factors set to 1.05, and
  `collectContinuously` enabled.
- **Scripts deployed:** [`p30_baseline.js`](p30_baseline.js), unchanged from Run 41. Raw capture
  [`eager-gc-616s-raw.txt`](eager-gc-616s-raw.txt), read by [`parse_baseline.py`](parse_baseline.py).
- **The landing check is out of band, and it covers one of the three options rather than all of
  them.** The options are read at process start and cannot be confirmed from inside the page, so the
  check is the process's own footprint: **`VmRSS` reads 89984 kB**, about 89 MB. **`JSC_forceRAMSize`
  was honoured**; an environment variable the engine ignored would have left the footprint alone. The
  growth factors have no such witness and are assumed to have landed.
- **The comparator for that check is not this run's baseline, and the record said it was.** The
  106380 kB figure comes from [`mq-toggle-496s-raw.txt`](mq-toggle-496s-raw.txt) — **Run 37's**
  capture, a different probe and the instrumented `index-CDzciXkW.js` rather than the shipped bundle.
  Run 41's own capture carries no `VmRSS` line at all, so the "against Run 41's 106380 kB" this
  record previously wrote here, in the summary table and in the section is **wrong attribution and is
  corrected**. **No same-configuration `VmRSS` baseline was taken.** A 16 MB drop against a 32 MB cap
  is a large enough margin that the landing is probably real, but the check is **indicative rather
  than controlled**, and reading it as a controlled one puts two runs' numbers in one comparison —
  which is the thing R3 forbids.
- **`collectContinuously` did NOT land, and the source says why.**
  `Source/JavaScriptCore/runtime/Options.cpp:832-833` reads
  `if (!Options::useConcurrentGC()) Options::collectContinuously() = false;` — and
  `useConcurrentGC` is already forced false on this architecture at `Options.cpp:707-708`. **The
  engine silently disabled the third option before the page ever ran.** This is recorded rather than
  quietly dropped: one of the three levers this run believed it was testing was never applied, the
  run cannot speak to it, and the `VmRSS` check that proved `forceRAMSize` landed says nothing about
  it. It does not change the run's verdict — the two options that *did* land moved the period by
  nothing — but a reader is entitled to know the arm was narrower than its description.
- **The capture:** 616 s, **26296 frames**, mean **23 ms**, max **1500 ms**, **18 frames over 250 ms
  = 0.029/s**, histogram 25328 / 592 / 358 / 12 / 3 / 3 / 0.
- **The beat, unchanged:** 40.5, 80.5, 120.6, 160.6, 200.6, 240.7, 280.7, 321.0, 361.1, 401.0 s —
  intervals of **40.0, 40.1, 40.0, 40.0, 40.1, 40.0, 40.3, 40.1, 39.9 s** — at 477, 470, 542, 482,
  470, 484, 525, 477, 299 and 268 ms. **The period is Run 41's period.** Two off-beat arrivals at
  300.4 and 301.2 s, and one late arrival at 600.5 s after a 199 s gap in which the beat does not
  appear.
- **Bound conditions, and the rate is deliberately not the verdict.** This capture's 0.029/s is lower
  than Run 41's 0.046/s, and **that difference is not read as an effect.** The beat is present at the
  same period throughout the first 400 s and then stops for 199 s; a capture whose beat is
  intermittent is exactly the kind of capture this record has already seen differ 2x between two runs
  of one configuration (Runs 26a, 26b). **What the run scores is the period, and the period did not
  move.** Shrinking the heap the collector will grow into, and making it grow in 5% steps, changes
  neither when the full collection is due nor what it costs.

### Run 43 — Fix 1 benchmarked against the clean baseline

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** `index-BhI9T8Rb.js`, named in the capture's own header. **Kiosk config:**
  clean, as Run 41 — none of Run 42's JSC options.
- **Scripts deployed:** [`p30_baseline.js`](p30_baseline.js), unchanged. Raw capture
  [`fix1-benchmark-600s-raw.txt`](fix1-benchmark-600s-raw.txt), read by
  [`parse_baseline.py`](parse_baseline.py).
- **What Fix 1 changes in the frontend.** Two allocation reductions, both aimed by Runs 39 and 40:
  the clock's granularity is **split** so the 1 s path no longer re-runs the `Intl` formatting that
  only changes on a coarser boundary, and `window.matchMedia` is **cached** so the marquee's
  re-registration stops constructing a document-retained `MediaQueryList` on every rotation tick.
  Both reduce allocation the page genuinely made.
- **The capture:** 608 s, **26487 frames**, mean **23 ms**, max **1415 ms**, **26 frames over 250 ms
  = 0.043/s**, histogram 25632 / 502 / 327 / 18 / 6 / 2 / 0.
- **The beat, unchanged:** 40.5, 80.5, 120.6, 160.6, 200.6, 240.6, 280.7, 320.7, 360.8, 400.8, 440.9,
  480.9, 521.0, 561.0, 600.5 s — intervals of **40.0, 40.1, 40.0, 40.0, 40.0, 40.1, 40.0, 40.1, 40.0,
  40.1, 40.0, 40.1, 40.0, 39.5 s** — at 433 to 532 ms, mean 486 ms across the sixteen on-beat
  arrivals, the sixteenth a 601.2 s companion to the 600.5 s one. Three off-beat arrivals, at 300.7,
  301.0 and 537.0 s.
- **The verdict: a null on the stall, and it is the run that withdraws the lever.** 0.043/s against
  Run 41's 0.046/s is inside the capture-to-capture spread this record has already measured, and the
  beat is identical to 0.1 s across fourteen consecutive intervals. **Reducing the application's own
  allocation does not reduce the frequency of the collection.** Taken with Run 37 (transient churn
  removed, no effect) and Run 46 (the reactive render removed, no effect), the allocation lever
  "Real-time framing" left open is closed.
- **A second Fix-1 capture exists and is not the benchmark.**
  [`fix1-600s-raw.txt`](fix1-600s-raw.txt) is the same bundle over 801 s reading 30 frames over
  250 ms (0.037/s), but it carries only four on-beat arrivals and a large off-beat cluster between
  150 s and 211 s, so its beat is not readable and it is not the run's number. It is catalogued in
  "Test runs" so no reader finds an uncatalogued capture in the directory.

### Run 44 — the remote inspector, and the first direct read of the collector

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** `index-Mt2gvuKb.js`, named in the capture's own header. **Kiosk config:**
  `KIOSK_INSPECTOR=0` and `WEBKIT_INSPECTOR_HTTP_SERVER=127.0.0.1:2999` set in
  `/data/config/kiosk.conf` for the duration and **restored afterward** — the inspector is a listening
  server and a perturbation, not a thing left running on prod. Reached from the workstation over an
  `ssh -L` forward.
- **Tooling:** the **`webkit-inspector` skill** —
  [`.claude/skills/webkit-inspector/SKILL.md`](../../../.claude/skills/webkit-inspector/SKILL.md) and
  its client [`webkit-inspect.mjs`](../../../.claude/skills/webkit-inspector/webkit-inspect.mjs),
  committed at `cd5cf9e`. The client runs on the workstation; the board has no node. Raw output
  [`inspector-gc-census-raw.txt`](inspector-gc-census-raw.txt).
- **What unlocked it, and it withdraws a claim this record carried.** "Root cause of the residual
  stall" records that "the inspector server accepts the socket and returns nothing" and files it under
  build-time conditions with a build-time answer. **That is withdrawn.** There are two server
  variables and they are not interchangeable: `WEBKIT_INSPECTOR_SERVER` — which
  `meta-wisekiosk/recipes-core/kiosk-session/files/kiosk-launch` wires `KIOSK_INSPECTOR=1` to — is **WebSocket-only**
  and answers a plain `GET /` by connecting and then hanging with zero bytes forever, which is
  precisely the symptom recorded. `WEBKIT_INSPECTOR_HTTP_SERVER` serves the target-list page an HTTP
  client can drive. **No rebuild was needed**; the instrument was reachable over the wire the whole
  time, on the other variable.
- **What it read, and what the read is bounded to.** `Heap.startTracking` over an 85 s window
  reports **one** collection and types it **full**, with **zero** eden collections. The capture
  carries its own bound condition: **under tracking the collector is quiesced, so the cadence inside
  that window is not the untracked cadence** — the read establishes the collection **type** and says
  nothing about frequency. A **census** — `Heap.snapshot`, 20866 nodes — is dominated by code and
  structure objects (`UnlinkedFunctionCodeBlock` 247882 B, `Object` 187938 B, `Function` 129285 B),
  and those per-class figures re-derive from the capture.
- **The type read is n = 1, and the record over-read it. DOWNGRADED.** One collection is the whole
  sample, and this record previously called it "the direct observation the identification was making
  by convergent inference". It is not that. Three things sit against it, none of which were stated:
  **the "quiesced" clause is cited to nothing** — neither the capture nor the
  [`webkit-inspector` skill](../../../.claude/skills/webkit-inspector/SKILL.md) sources it, and if
  quiescing perturbs *when* collections happen there is no argument for why it leaves *which kind*
  intact; **`eden:0` over 85 s is not credible** against this record's own stated mechanism, in which
  transients die in the nursery under cheap eden passes (Run 37), so either the eden passes are not
  happening or the `Heap.garbageCollected` event stream is under-delivering — and the skill's own
  note that `startTime`/`endTime` read 0 on this build says the plumbing is partly broken here;
  and **`fullTimes:[7.08]` sits beside the claim undisclosed** — it is an arrival wall-clock in
  seconds, not a duration, and a reader who took it for milliseconds would read it as contradicting
  ~500 ms. The honest statement is: **one collection was observed and typed full; the same window
  reported zero edens, which is not credible, so the sample is not treated as representative.**
- **The census diff is the right experiment and its result was never banked. RESTATED.** The capture's
  diff section reads, in full, `--- diff (profile-churn.mjs) over 30s: NO retained growth (transient
  churn, no leak) ---` — a header with no before/after byte count, no node count, no per-class delta
  and no threshold under it. So "no retained growth" is **a claim the session made and did not
  record**: nothing numeric survives, so *this run's* result is not re-derivable and is not a datum
  of this record. **The experiment itself is not lost.** The tool the capture names,
  `profile-churn.mjs`, is committed nowhere here — but
  [`webkit-inspect.mjs`](../../../.claude/skills/webkit-inspector/webkit-inspect.mjs), which **is**
  committed and catalogued, implements the same design as its `diff <seconds>` mode: two class
  censuses N seconds apart, each forcing a collection first so that a survivor is genuinely promoted
  growth. So the R2 obligation here is **bank the numbers**, not **commit a missing tool**, and a
  re-run is available today. The design is right — which is why the result is worth re-taking rather
  than abandoning — but nothing downstream may rest on the unrecorded claim, and this record's
  earlier "the heap is not leaking, it is churning, building and promoting and releasing the same
  volume every cycle" was **INFERENCE on an unrecorded claim**, not an observation. **Nothing in this
  record measures a promotion rate, an allocation rate or a per-cycle volume**; the page's own
  allocation rate remains unmeasured, exactly as "Root cause of the residual stall" says.
- **What the run still establishes.** The inspector is reachable on this build over the HTTP server
  variable, with no rebuild — that withdrawal stands and is the run's durable result. The heap census
  is real and small: 20866 nodes, top classes summing to roughly 1.07 MB. That figure is load-bearing
  in the other direction, and against this record's own earlier reading: **500 ms over 20866 nodes is
  ~24 µs per node**, on the order of 17,000 ARM11 cycles to mark one object, which is two to three
  orders of magnitude off any plausible mark rate. So the census does not confirm the pause is
  marking — it argues the pause is *not* mark-dominated, and which phase it is dominated by is
  unidentified.

### Run 45 — the frequency lever, the one the JSC source leaves nominally open

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** `index-Csf9V8Vf.js`. **Kiosk config:** as Run 41 plus
  `percentCPUPerMBForFullTimer` divided by 16 — the full-collection timer made 16x less eager.
- **Scripts deployed:** [`p30_baseline.js`](p30_baseline.js), unchanged. Raw capture
  [`freq-lever-P16-535s-raw.txt`](freq-lever-P16-535s-raw.txt), read by
  [`parse_baseline.py`](parse_baseline.py).
- **Why this lever and no other.** The JSC source analysis below establishes that the *pause* cannot
  be chunked on this architecture. `percentCPUPerMBForFullTimer` is the one remaining nominal control
  over the *frequency* — it paces the timer that schedules a full collection against heap size. If
  the collection is timer-driven, a 16x less eager timer must move the period.
- **The capture:** 535 s, **23382 frames**, mean **23 ms**, max **1587 ms**, **29 frames over 250 ms
  = 0.054/s**, histogram 22612 / 457 / 284 / 21 / 5 / 3 / 0.
- **The beat, unchanged in period and shifted in phase:** 42.0, 82.0, 122.0, 162.0, 202.0, 242.0,
  282.1, 322.3, 362.3, 402.4, 442.4, 482.4, 522.5 s — twelve intervals of **40.0, 40.0, 40.0, 40.0,
  40.0, 40.1, 40.2, 40.0, 40.1, 40.0, 40.0, 40.1 s** — at **472 to 527 ms**, mean 489 ms. The first
  arrival is 1.5 s later than Run 41's and every one after it tracks that offset; the **period is
  identical**.
- **What is not on the beat, and this run omitted it where its siblings do not.** Ten off-beat
  arrivals: 114.1, 114.4, 210.0, 210.5, 210.8, 302.4, 474.6, 474.8, 512.1 and 512.5 s — **the largest
  off-beat cluster in this record**, and the 302.4 s arrival at **593 ms** is longer than any on-beat
  arrival in the capture. This capture also carries the **highest rate of the five `BL` captures,
  0.054/s**, above the clean baseline's 0.046/s. Neither is read as an effect — rate is not the
  comparable quantity here, and the run block is stating both rather than leaving a reader to find
  them, which is what Runs 41, 42, 43 and 46 do and this block previously did not.
- **The verdict — and half of it is withdrawn.** A 16x change in the timer's eagerness moves the
  period by **nothing**. **That stands**: the collection is not timer-triggered. What this record
  wrote next does not: *"it is what a **promotion-driven** one looks like — the collection fires when
  the eden-to-old-generation ratio crosses its threshold"*, and *"the engine's frequency lever is
  inert for the same reason its heap-size lever is (Run 42): neither reaches promotion."* **Both
  sentences are WITHDRAWN and kept visible here.** Run 42 **is** a promotion-path lever — the
  eden-to-old-generation ratio is `m_maxEdenSize / m_maxHeapSize`, and `forceRAMSize` and the growth
  factors are precisely what set `m_maxHeapSize`. Run 42 aimed at promotion and found it inert; this
  run aimed at the timer and found it inert. Each concluded "it must be the other one", and both
  cannot be right. Sharper still: `JSC_forceRAMSize=32MB` drives `minHeapSize` from 32 MB to 8 MB, a
  **4x cut** to the promotion budget, and a promotion-paced cadence owes a roughly 4x shorter period
  for it. The period did not move. That is a **falsification** of the promotion model, not a null,
  and it leaves the trigger **unidentified** — see "Runs 37-48 — the GC lever, and where it is driven from".
- **The capture also carries a `JSC_logGC` block** — three lines over the whole 535 s, none with a
  pause at or above 100 ms. This record read that as the option being substantially compiled out of
  this build. **That reading is WITHDRAWN (Run 47):** the option is honoured in this build and the
  near-empty trace is a capture-routing artefact, because `dataLog` writes to the WebProcess's stderr
  rather than to anything this capture was reading — see the Run 38 block. **Two trailing values in
  that block, `0.696` and `9.76`, are not self-describing and nothing here is read from them.**

### Run 46 — the tour rendered imperatively, bypassing the reactive graph

- **Board:** prod, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by continuity).
  **Frontend bundle:** `index-DJUeJLKg.js`, named in the capture's own header. **Kiosk config:**
  clean, as Run 41.
- **Scripts deployed:** [`p30_baseline.js`](p30_baseline.js), unchanged. Raw capture
  [`imperative-tour-587s-raw.txt`](imperative-tour-587s-raw.txt), read by
  [`parse_baseline.py`](parse_baseline.py).
- **What the bundle changes.** Run 39 named the per-tick reactive update as the driver, and Run 43
  showed that reducing the allocation *inside* it does nothing. This is the sharpest remaining form
  of the lever: the tour rows are **rendered once** and thereafter **filled imperatively** — direct
  DOM writes — so advancing the rotation no longer re-executes the `{#each}` block, its snippet, or
  the component instances under it.
- **The landing check is visual, it is the right *kind* of check, and it has no oracle.** An
  imperative render that silently drew the wrong rows would read as a clean null, which is why a
  display check belongs here at all. Two screenshots were taken before the capture was scored:
  [`imperative-tour-render-shot1.png`](imperative-tour-render-shot1.png) and
  [`imperative-tour-render-shot2-rotated.png`](imperative-tour-render-shot2-rotated.png), committed
  here. **But "validated pixel-correct" is stronger than two frames 64 s apart can support**, and the
  phrase is withdrawn. There is no matching pair from the *reactive* bundle at the same data state,
  so "pixel-correct" names no comparison; and no written expectation of which rows should appear
  after a rotation, so the verdict cannot be re-derived by a reader. Read adversarially the pair is
  not self-evidently correct: two of the four cards advanced their toured tail across the gap and two
  are identical in both shots, which may well be right and which nothing here says how to decide.
  What the check establishes is that **rows were drawn in the right places**; it cannot resolve a
  cell drawn with the wrong value or the wrong class. The in-band form — walk the rendered rows,
  compare against the rows the data model says are due, and exfil a mismatch count through the same
  channel as the rest of the payload — is what Runs 37 and 39 do and what this run should have done.
- **The capture:** 587 s, **26577 frames**, mean **22 ms**, max **1542 ms**, **25 frames over 250 ms
  = 0.043/s**, histogram 25942 / 298 / 312 / 21 / 1 / 3 / 0.
- **The beat, unchanged, and the on-beat set is hand-curated.** 40.5, 80.5, 120.5, 160.5, 200.4,
  240.5, 321.4, 361.4, 401.5, 441.5, 481.5, 521.5, 561.6 s, at intervals of **39.9 to 40.1 s**
  (`160.5 → 200.4` is the 39.9), with one skipped turn between 241 and 321 s. Durations run 445 to
  474 ms on the clean arrivals, with a 294 ms and a 645 ms pair at 240.5 and 241.1 s. Five off-beat
  arrivals, at 300.6, 301.1, 541.3, 541.7 and 542.0 s. **[`parse_baseline.py`](parse_baseline.py)'s
  own on-beat set is fifteen, not thirteen**: it also folds in `200.9` at 450 ms, which this list
  excludes as the second of a pair with the 200.4 arrival, on the same reading that keeps the
  240.5/241.1 pair as one turn. Saying so is the point — curating a beat by hand is defensible, doing
  it silently in the run that carries the strongest form of the lever is not. The accounting closes:
  13 on-beat turns + the 241.1 companion + the excluded 200.9 + 5 off-beat + 5 startup (1.2, 2.8,
  3.8, 4.1, 8.4 s) = the capture's 25.
- **The rate reads the same as Run 43's to the two figures this record uses.** 25 over 587 s is
  0.0426/s and 26 over 608 s is 0.0428/s — both 0.043/s. The two runs are not being differenced; the
  point is that the sharpest available form of the lever lands on the same number as the mildest.
- **The throughput claim is BOUNDED, not withdrawn, and it is a cross-capture comparison.** Mean
  frame time reads **22 ms** and the 50–100 ms bucket holds **298 frames** where Run 41's held 682.
  Both numbers are real. The comparator is not neutral: across the five `BL` captures, all on
  [`p30_baseline.js`](p30_baseline.js),

  | Run | configuration | mean | 50–100 ms bucket | rate |
  |---|---|---|---|---|
  | 41 | clean baseline | **25 ms** | **682** | 0.046/s |
  | 42 | JSC heap options, same bundle as 41 | 23 ms | 592 | 0.029/s |
  | 43 | Fix 1 | 23 ms | 502 | 0.043/s |
  | 45 | JSC timer option | 23 ms | 457 | 0.054/s |
  | 46 | imperative render | 22 ms | 298 | 0.043/s |

  **Run 41 is the outlier on both columns and is the capture Run 46 is differenced against.** Against
  the nearest comparable capture the mean delta is **1 ms**, and Run 45 — which changed nothing in the
  application, only a JSC timer constant — moved the same bucket 682 → 457, more than half the
  distance the imperative render is credited with. This section's own rule is that captures are not
  comparable to each other and only the beat may be read across them; mean frame time and a histogram
  bucket are no more capture-stable than rate, as the table shows. **Run 46 also carries no
  interleaved control arm**, unlike Runs 36, 37, 39 and 40, so nothing inside the run isolates the
  effect. The defensible statement is **"consistent with a throughput win, not measured as one"**.
  The comparison to Run 22 and Run 25 is dropped with it: both of those were interleaved or
  same-capture measurements, which makes the analogy flattering rather than apt.
- **The inference, stated as inference — and SUPERSEDED in its mechanism.** This record wrote:
  *"Removing the reactive render does not move the beat because the promotion is **spread across the
  reactive graph** rather than concentrated in the render."* The observation stands; **the mechanism
  does not**, because it names promotion, and Runs 42, 45 and 47 leave the trigger unidentified — see
  "Runs 37-48 — the GC lever, and where it is driven from". What survives without the mechanism is the shape:
  Run 39's *whole-tick* freeze reaches zero and every partial removal reaches nothing.
- **And Run 39 and this run do not ablate the same thing, which bounds what "sharpest form" means.**
  Run 39 arm R skips the rotation tick's **derived recompute**; this run removes the reactive
  **render** under it. The tick is still `$state`, the page and slice are still deriveds, and the
  imperative effect still reads them, so the derived spine Run 39 ablated is still executing every
  tick here. The configuration that would separate "spread across the graph" from "concentrated in
  the deriveds" — advancing the tour from a plain interval with no signal on the rotation path at all
  — **was never built**, and this record does not claim it was.

### Run 47 — the memory-pressure kill switch, and the hypothesis it falsifies

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by
  continuity). **Frontend bundle: not recorded** — the page was served from the dev mirror as in every
  run above and no hash was read off the board or carried in the run's output. Both arms ran
  back-to-back on one board, one build and one bundle, so the comparison inside the run is unaffected;
  the hash is a gap, stated rather than guessed, and it is the same gap Run 25 carries. **Kiosk
  config:** as Run 41, plus `JSC_logGC=1` and `WTF_DATA_LOG_FILENAME` in both arms, plus arm 2's one
  variable. Restored afterwards to the four-line baseline and the panel confirmed rendering — not
  blank — by a screenshot with the device clock legible in it. **That screenshot sits in the
  gitignored `local/` tree and is not citable from here**, unlike Run 46's two committed panel
  images; the restore landing check is the right check and a reader cannot currently verify it.
- **Scripts deployed:** [`p30_baseline.js`](p30_baseline.js), unchanged from Run 41.
- **R2 is NOT discharged for this run, in two distinct ways.** **No raw capture file is committed**
  for either arm: the arrival series below are **transcribed** from the arms' `WM_NAME` payload lines
  as reported in this session's own task output, not read from a file in this directory. And
  **no analyser reads this run** — the block names a probe but no parser, where Runs 41, 42, 43, 45
  and 46 are all read by [`parse_baseline.py`](parse_baseline.py). Those are separate gaps and the
  second is the one with teeth: Run 46 volunteers that the parser's on-beat set is fifteen where its
  own hand-curated list is thirteen, so a hand-transcribed beat and the parser's fold are known to
  disagree on this payload. The obligation is therefore **bank the two captures *and* re-derive this
  table through `parse_baseline.py`**, not bank the captures alone — and if the fold disagrees with
  the transcription, as it did for Run 46, that must be visible here.
- **Why the run exists, and it is the record arguing with itself.** An adversarial architecture review
  of this investigation read WebKit's **memory-pressure** subsystem out of this image's own generated
  build configuration and proposed it as the driver the JSC levers kept missing: the UI-process
  `MemoryPressureMonitor` polls `/proc/meminfo` and fires at **≥90%** system memory used, and the
  handler's hold-off is `release duration x 20`, from which a ~2.0 s release window yields a 40 s
  spacing with no 40 s constant anywhere in the tree. It explained Run 42's and Run 45's mutual
  exclusion, the `eden:0` of Run 44 and the off-beat pairs at once. It also came with a **complete
  kill switch that needs no rebuild**: `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR=1` sets
  `shouldSuppressMemoryPressureHandler`, so the WebProcess never installs the handler at all. If the
  hypothesis were right the residual would be a configurable policy rather than a floor.
- **Procedure:** two arms, same board, same build, back-to-back, each a single continuous capture
  under the unmodified baseline probe. **Arm 1** is the baseline with the monitor on. **Arm 2** adds
  `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR=1` and changes nothing else.
- **The discriminator, fixed before the run.** The kill switch is complete. If the memory-pressure
  path paces the beat, arm 2 must lose it.
- **What the kill switch actually does, because the falsification's scope depends on it.** It is read
  in the **UI process**, not the web process.
  `Source/WebKit/UIProcess/linux/MemoryPressureMonitor.cpp:389-397` reads
  `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR` under a `std::call_once` and requires exactly the string
  `"1"`; `Source/WebKit/UIProcess/glib/WebProcessPoolGLib.cpp:122-123` turns that into
  `parameters.shouldSuppressMemoryPressureHandler = true`;
  `Source/WebKit/WebProcess/WebProcess.cpp:439-440` assigns it to `m_suppressMemoryPressureHandler`
  and **skips the whole block that ends in `memoryPressureHandler.install()` at `:492`**; and with
  `m_installed` never set, `Source/WTF/wtf/unix/MemoryPressureHandlerUnix.cpp:66-67` returns
  immediately from `triggerMemoryPressureEvent`. **The switch removes the handler itself, not one of
  its triggers** — every path into memory-pressure response is gone in arm 2, whatever would have
  driven it.
- **The landing check is out of band, and it is verified — on the process that consumes the
  variable.** The check that matters is whether the variable reaches **surf**, and it does: an
  anchored read of `/proc/<pid>/environ` finds it in surf's own environment **and** in the web
  process's. An environment variable that reached the consuming process is one the engine had the
  opportunity to honour, and this record's standing rule about silently-unapplied manipulations is
  satisfied for it.
- **What that check is, stated exactly, because its ordering decides how much it is worth.** It is a
  **supplementary verification run**, and the order was: the arms ran; **the board was then restored
  to the four-line baseline**; and only after that was `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR=1`
  appended and the kiosk restarted for the read. So it is **not arm 2's own `kiosk.conf` re-read, and
  not arm 2's own process** — it establishes that *a* configuration carrying this line delivers it to
  surf through the systemd `EnvironmentFile` mechanism on this board. It is **the same mechanism**,
  not the same file. What makes that sufficient rather than nearly worthless is that the mechanism is
  insensitive to the rest of the file: the variable is delivered identically whether or not the two
  JSC-logging lines arm 2 also carried are present, because none of the three interact — they are
  independent `KEY=VALUE` lines consumed by different processes. The residual failure mode the check
  does **not** close is the one this record has been bitten by three times: that the line never
  entered arm 2's config, or the kiosk was never restarted between arms. Nothing in the run's own
  record suggests either, and an in-band counter exfiltrated inside the capture — which Runs 37
  and 39 have and this run should have had — is what would have closed it outright.

| Arm | env delta | beat arrivals (s) | period | magnitude | stalls > 250 ms | `MemAvailable` |
|---|---|---|---|---|---|---|
| 1 baseline, monitor ON | `JSC_logGC=1` | 41.9, 81.9, 121.9, 162, 202, 242.2, 282.2, 322.6, 362.6, 402.6, 442.6, 482.6 | **40.0–40.4 s** | ~450 ms | 24, not scored | 263 MB / 435 |
| 2 monitor OFF | + `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR=1` | 41.9, 82, 122, 162, 202, 242, 282, 322.1, 362.1, 402.1, 442.2, 482.2, 522.2, 562.2 | **40.0–40.1 s** | ~450 ms | 25, not scored | 264 MB / 435 |

- **The intervals, from the arrivals above.** Arm 1: 40.0, 40.0, 40.1, 40.0, 40.2, 40.0, 40.4, 40.0,
  40.0, 40.0, 40.0 s. Arm 2: 40.1, 40.0, 40.0, 40.0, 40.0, 40.0, 40.1, 40.0, 40.0, 40.1, 40.0, 40.0,
  40.0 s. Both arms' first arrival is at 41.9 s, about 1.4 s later than Run 41's — a **phase**
  difference, as Run 45's was, on an unchanged period.
- **The verdict: FALSIFIED.** The kill switch removes the handler entirely, its landing is verified
  on the process that reads it, and **the beat is still there at the same period**: **40.0–40.4 s**
  across arm 1's eleven intervals and **40.0–40.1 s** across arm 2's thirteen. The control arm is the
  noisier of the two, which is the direction that matters least for the verdict and is stated rather
  than left to a reader's subtraction. A null from a manipulation known to
  have reached the engine is a result rather than an absence of one. **The memory-pressure handler is
  not the driver**, and the hypothesis that overturned this record's conclusion overnight is refuted
  by direct measurement rather than by argument.
- **What the verdict is scoped to, and it is narrower than "zero effect".** The discriminator was
  binary — if the memory-pressure path paces the beat, arm 2 must lose it — and that is what the run
  resolves. **A partial change in the pause's magnitude is below this run's recorded resolution**:
  the magnitude is recorded as `~450 ms` for both arms, one significant figure, where every sibling
  run quotes a range (Run 41 475–531 ms, Run 43 470–525, Run 45 472–527, Run 46 445–474). A 10–15%
  shortening would not be visible here. The verdict is "the beat is not removed and its period does
  not move", not "nothing changed at all".
- **The two legs are not the same leg, and the difference is what makes the arms worth having.** The
  arms and the memory reading do **not** corroborate each other symmetrically — the memory reading
  *entails* a null on the polled path, so on that path alone arm 2 could not have shown anything
  whether or not the switch landed. They cover different scopes:
  - **The memory reading closes the polled path specifically.** Reaching the monitor's **≥90%**
    (`MemoryPressureMonitor.cpp:51`) would need `MemAvailable` to fall from ~263 MB to about
    **43.5 MB** of 435 MB — a ~220 MB excursion. This record's own WebProcess `VmRSS` readings are
    **89984 kB** (Run 42) and **106380 kB** (Run 37): **the entire web process is less than half the
    excursion required.** That is a headroom argument and it does not depend on sampling cadence,
    which matters because two point samples cannot establish that a board never spiked.
  - **The arms close the whole handler**, polled path and every other, because the switch skips
    `install()` rather than suppressing a trigger. **For that scope the landing check is the whole of
    the evidence that the manipulation applied** — which is why it is reported above at length rather
    than as a formality.
- **Bound conditions.**
  - **The arms are sequential, not interleaved, and it could not be otherwise.**
    `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR` is read once per process under `std::call_once` at
    WebProcess-spawn time, so it cannot be toggled inside one page load — the same exception Runs 18
    and 20 carry, and the same shape as Runs 19 and 35, which are also two sequential captures.
  - **So the board's within-run drift is NOT cancelled here.** This record measures that drift at
    ~30% within a single run, and Runs 37, 39 and 40 interleave specifically to cancel it. Nothing in
    this run cancels it. What makes the comparison readable anyway is **the quantity being read**:
    the *period*, which this record has five independent draws of at **39.9–40.3 s** across five
    captures on different bundles and different JSC options. The drift that motivates interleaving
    moves **rate over a short window**, and no rate is scored here.
  - **Neither arm's capture window is recorded**, unlike every other `BL` run in this record (588 s,
    616 s, 608 s, 535 s, 587 s). What the transcription bounds is the last arrival — **482.6 s in
    arm 1 against 562.2 s in arm 2** — so arm 2 covered at least ~80 s more. **Consequently no count,
    rate, mean or histogram is compared across the arms**, and the stall counts of 24 and 25 sit in
    the table as per-capture facts marked *not scored*, exactly as Run 42's 0.029/s is. The beat is
    the comparable quantity and it carries the verdict on its own.
  - **n = 1 capture per arm.** **The bundle is not recorded** (see the head of this block), and
    **no analyser reads this run** (see R2, above).
- **A separate line, and it is not new.** Run 35 already cut the panel to 640x480, a 3.0x pixel cut,
  and the ~40 s cadence survived it — so the beat is resolution-independent as well, and is not
  paint.
- **A trap in this subsystem, recorded because it has now caught two independent reviews.** WebKit
  also has a **WebProcess-side periodic** memory monitor, and this build's generated config says it
  is on: `build/.../2.44.3/build/cmakeconfig.h:88` reads `#define ENABLE_PERIODIC_MEMORY_MONITOR 1`,
  defaulted ON for the GTK port. Read that line alone and you conclude a ~30 s footprint-driven timer
  is running — which would be the closest thing to a periodic engine task anyone in this record has
  found, and would make the arms the only evidence covering it. **It is not running.**
  `Source/WTF/wtf/MemoryPressureHandler.cpp:79-85` opens `setShouldUsePeriodicMemoryMonitor` with
  `if (!isFastMallocEnabled()) return;`, this build sets `USE_SYSTEM_MALLOC:BOOL=ON`
  (`build/.../2.44.3/build/CMakeCache.txt:1278`), and under that
  `Source/WTF/wtf/FastMalloc.cpp:168-171` — inside the `#if USE(SYSTEM_MALLOC)` branch opening at
  `:158` — returns `false` unconditionally. **So the flag is 1 and the timer still never installs.**
  Two separate reviews of this investigation reached the opposite conclusion from the `#define`, and
  both were corrected by reading the guard; it is recorded here so a third does not have to.
- **The instrument miss, recorded rather than dropped.** `JSC_logGC=1` with
  `WTF_DATA_LOG_FILENAME` pointed at a `/data` path **did not produce a trace**. The environment
  reached the WebProcess — confirmed by reading `/proc/<pid>/environ` — but no file descriptor opened
  to the target, because the WebProcess sandbox denies that path. `dataLog` therefore went where it
  goes by default, the **WebProcess's own stderr**, which neither the journal nor the surf milestone
  log captures; only surf's own `[GC<addr>: starting Xms]` markers appear there. **So the
  per-collection trace is still uncaptured after forty-seven runs** — not because the option is
  compiled out, which is the reading Run 38 and Run 45 carried and which this run withdraws, but
  because of where its output lands. The follow-up is named and cheap: a sandbox-writable path, or a
  redirect of the WebProcess stderr, or the remote inspector's heap tracking. It is not a bound on the
  falsification, which stands on the stall series and the memory reading alone.

### Run 48 — the rotation interval, and the lever that finally moves the beat

- **Board:** prod, Raspberry Pi Zero W, slot A. **Image commit:** `100-gpu-compositing:7ce44ba` (by
  continuity). **Frontend bundle:** `index-DJUeJLKg.js` — **the same bundle in all three arms**, named
  in each capture's own header, which is what makes them comparable to each other. It is Run 46's
  bundle and **not** Run 41's `index-Mt2gvuKb.js`, so **Run 41's numbers are not blended into this
  comparison** (R3). **Kiosk config:** clean, as Run 41. The manipulation is the app's own
  `rotation_interval_seconds`, served from the mirror's `config.json`.
- **Scripts deployed:** ONE-OFF [`p31_rotcheck.js`](p31_rotcheck.js), committed here — Run 41's
  `>250 ms` stall detector with a **rotation landing check** added: `R[]` records the wall-clock time
  of every tour-row text change. Raw captures [`rotation-6s-588s-raw.txt`](rotation-6s-588s-raw.txt),
  [`rotation-8s-589s-raw.txt`](rotation-8s-589s-raw.txt) and
  [`rotation-12s-586s-raw.txt`](rotation-12s-586s-raw.txt), read by
  [`parse_rotation.py`](parse_rotation.py) with [`parse_rotation_test.py`](parse_rotation_test.py)
  proving it reports both outcomes — a scaled beat and an unscaled one.
- **R2 is discharged for this run, and it is the cleanest discharge in this range.** Probe, analyser,
  analyser test and all three raw captures are committed here, and **every figure below is the
  parser's output**, not a hand reading. Run 47, by contrast, has neither capture nor parser.
- **The membership rule is uniform across the three arms, and it is the probe's own.** An earlier
  draft of this block scored the arms by hand at a 400 ms threshold. **That reading is withdrawn**: it
  admitted a 279 ms arrival in the 8 s arm while demoting 252-312 ms arrivals in the 6 s arm, which is
  the same amplitude band treated two ways, each time in the direction of the hypothesis.
  [`parse_rotation.py`](parse_rotation.py) applies one rule to all three — **every post-startup
  arrival at or above the probe's own 250 ms cutoff, clustered so a companion pair counts once** — and
  the arms are re-derived under it below. It changes the 6 s verdict completely.
- **This is a diagnostic, not a cadence change. Production stays at the schema default 8 s** (owner,
  2026-09-23). The run varies the interval to locate the cause; nothing here proposes shipping 12 s.

| Arm | `R[]` landing | fps / worst frame | beat arrivals (>= 250 ms, clustered) | grid = 5x tick | on-grid | dropout |
|---|---|---|---|---|---|---|
| **6 s** | median **6.000 s**, max gap 7.1 s — **`R[]` CAPPED at 80 events, covering 0-488.1 s of 588 s** | 41.7 fps / 2519 ms | 30.5, 90.5, 120.2, 150.6, 180.4, 240.8, 306.9, 360.6, 420.7 | **30.0 s** | **8 of 9** | **58%** |
| **8 s** (production) | median **8.000 s**, 73 events, uncapped | 45.2 fps / 1570 ms | 41.9, 81.9, 121.9, 161.9, 201.9, 242.0, 282.0, 302.5, 322.3, 362.3, 402.3, 442.4, 482.4, 522.4, 562.4 | **40.0 s** | **14 of 15** | **0%** |
| **12 s** | median **12.000 s**, 48 events, uncapped | 48.4 fps / 1535 ms | 60.5, 84.4, 120.5, 180.6, 240.6, 264.7, 300.5, 325.5, 385.5, 421.4, 445.7, 565.9 | **60.0 s** | 6 of 12 | 33% |

- **All three arms are consistent with beat = 5 x the rotation tick**, which is a stronger result than
  the two-points-and-an-outlier this block first claimed. **8 s → 40.0 s** with **zero** grid points
  dropped and fourteen of fifteen arrivals on-grid. **12 s → 60.0 s**: the gap series carries **60.1,
  60.0, 60.0** and a **120.2 s** double, so the 60 s fundamental is in the intervals; the grid *fit*
  is only 6 of 12 because the series takes a phase reset near 300 s and because several off-grid
  arrivals belong to the ~300 s event below, not because the period is unstable. **6 s → 30.0 s**,
  eight of nine arrivals within 3 s of a 30 s grid, first arrival at **30.5 s**.
- **The 6 s arm is NOT an outlier, and the claim that it broke the linearity is WITHDRAWN.** The
  earlier reading — *"there is none: nothing sits on 30 s"* — was wrong, and self-contradicting: the
  sentence that followed it listed 30.5, 90.5 and 150.6 s, which are exactly the 30 s grid. What the
  hand threshold had done was keep only the larger alternate arrivals, whose spacing is then 60 s.
  Under the uniform rule the 6 s gap series reads **60.0, 29.7, 30.4, 29.8, 60.4, 66.1, 53.7, 60.1 s**
  — a **30 s fundamental with alternate members missing**, the 60 s values being two grid steps. So
  the 6 s arm **confirms** 5 x 6 = 30 rather than contradicting it, at **58% dropout** and with
  amplitude alternating between ~450 ms and ~250-310 ms.
- **What is different about the 6 s arm is completeness, not scaling, and the honest word is
  low-quality rather than outlier.** More than half its grid points carry no arrival at all, its
  amplitudes alternate, and two further problems below bound what it can be asked to support. The
  scaling law rests on the 8 s and 12 s arms; the 6 s arm is a third **consistent** point, not a
  third **clean** one.
- **`R[]` capped, and the number this block once quoted as a measurement is the cap.**
  [`p31_rotcheck.js`](p31_rotcheck.js) stops recording at `rots.length < 80`. The 6 s capture contains
  **exactly 80** entries, the last at **488.1 s** of a 588 s window, so **the landing check is blind
  for the final 100 s of that arm** — and a capped `R[]` and a rotation that stopped are
  byte-identical in this payload. [`parse_rotation.py`](parse_rotation.py) detects and prints the
  condition; the probe should exfil `rots.length` as its own field, the way `big` makes `S[]`
  truncation visible, and that is an outstanding harness obligation. **The per-arm event counts
  (80 / 73 / 48) are therefore not evidence of anything** and are no longer offered as such: 80 is a
  cap, and the other two are just window ÷ interval.
- **The 6 s arm goes silent for its last 167 s, and this record does not know why.** Its final
  arrival of any size is **420.7 s**; nothing over 250 ms occurs in the remaining 28% of the window.
  This is a real absence, not list truncation — the payload's own `big22` matches its 22 listed
  entries. `R[]` independently confirms rotation was still running to at least 488.1 s, so for **at
  least 67 s of confirmed-rotating time the beat was wholly silent**, where a 30 s grid predicts two
  arrivals. A saturated board should produce a noisier tail, not a clean one. The live alternative is
  that something in the page stopped doing per-tick work partway through the arm — **and a page that
  stopped looks identical to a page that got quiet, because `R[]` is this run's only liveness signal
  and it capped out before the quiet window closes.** Stated as unexplained rather than folded into
  the saturation story.
- **Saturation, led by the evidence that is actually monotonic.** Throughput falls monotonically as
  the tick gets faster — **48.4, 45.2 and 41.7 fps** at 12, 8 and 6 s — and the worst frame rises,
  **1535, 1570 and 2519 ms**. Those two are the argument. **Load average is disclosed rather than
  used**: the one-minute triple is 2.19 / 1.75 / **1.97** and the fifteen-minute triple is 1.76 /
  1.83 / **1.51**, and **both are non-monotonic in the interval**; only the five-minute triple
  (1.98 / 1.82 / 1.51) runs the expected way, which is not enough to carry a claim on its own.
  Mechanically, a 6 s tick leaves the marquee about 2 s of travel after its 2 s home and 2 s end
  holds.
- **WITHDRAWN — "ticks are dropped".** This block previously explained the 6 s arm by saying the
  board dropped rotation ticks. **The capture refutes that**: over the span `R[]` covers, the 6 s
  arm's rotation median is **6.000 s** with a maximum gap of **7.1 s** — the tick fired on time
  throughout. What degrades under a faster tick is **rendering and beat completeness**, not the tick
  itself: fps falls, the worst frame doubles, and more than half the grid's collections do not
  produce a recorded stall. The corrected statement is that **the rotation fires reliably and the
  work it triggers does not all complete**, which is also the only form the evidence supports.
- **A ~300 s event sits in all three arms and is not the rotation beat.** At 8 s there is an arrival
  at **302.5 s** carrying **686 ms**, the largest in that capture and off the 40 s grid — it is what
  makes the 8 s gap series read 20.5 and 19.8 either side of it. At 12 s there are arrivals at 300.5
  and 301.0 s, and at 6 s one at 306.9 s, the single off-grid member of that arm. Three arms, three
  different rotation intervals, one event at the same place in each capture's own timeline: **it
  scales with nothing this run varied** and is therefore not a rotation-paced collection. It is named
  here as a separate, unmodelled ~300 s event rather than quoted as a beat point, and nothing in this
  record explains it.
- **What the run establishes, and it is the direct causal result forty-seven runs circled.** **The
  beat scales with the rotation tick** — 30.0, 40.0 and 60.0 s at 6, 8 and 12 s, same board, same
  build, same bundle, each interval landing-verified in band. **A residual set by the hardware or by
  an engine configuration cannot move when a frontend config value moves.** This one does, across
  three settings.
- **Why it is five ticks is NOT established, and the mechanism this block first offered is BOUNDED.**
  An earlier draft wrote that *"five ticks' worth of promotion crosses the old-generation
  threshold"*. **That is the promotion-threshold model Run 42 falsified** — `JSC_forceRAMSize=32MB`
  cut the budget roughly 4x, which that model owes a roughly 4x shorter period, and the period held
  at 40.0 s. Run 48 does not rescue it; **it sharpens the exclusion**, because the beat now demonstrably
  tracks a frontend quantity while remaining immovable by the engine-side budget that the same model
  says sets it. The defensible statement is the measured one: **the beat is 5 x the rotation tick, and
  what accumulates over five ticks — and why the count is five rather than three or eight — is
  unidentified.** That sits beside this record's other open half, what the ~450 ms is spent on.
- **What it does reconcile, and this part does not depend on the mechanism.** Runs 37, 43 and 46 each
  removed one *contributor* to the per-tick update and read a null; Run 39 froze the *whole* tick and
  read zero. Both hold if no single contributor is removable enough to matter while the **number of
  ticks per collection stays fixed**, so the period tracks the interval. Run 48 measures that second
  half directly, where Runs 37 to 46 could only infer it.
- **`MemAvailable` reads 266284, 263372 and 270236 kB** across the three arms — about 40% used, as in
  Run 47, nowhere near the memory-pressure monitor's 90%. The memory-pressure path is absent here too.
- **Bound conditions.**
  - **The arms are sequential, not interleaved**, and the board's within-run drift is not cancelled by
    the design. What licenses the comparison is that **the quantity read is the period**, and it moved
    by **50%** between the 8 s and 12 s arms and by **25%** down to the 6 s arm — far outside anything
    drift produces in this record, which moves *rate*, not *beat*. **Arm order is not recorded**, so
    if the arms ran in ascending or descending interval order the fps trend is confounded with time
    on the board; the beat result is not, because drift does not move a period.
  - **The 5x relation rests on three points of unequal quality.** The 8 s and 12 s arms carry it; the
    6 s arm is consistent with it at 58% dropout, a capped landing check and an unexplained silent
    tail. No arm above 12 s was taken, so nothing bounds the relation from above.
  - **The three arms share one bundle and the comparison is confined to them.** Run 41's beat is on a
    different bundle and is not blended in. Run 46 *is* the same bundle at the default interval and
    reads 39.9-40.1 s, which agrees with this run's 8 s arm — a consistency check across captures,
    not a differenced result.
  - **n = 1 capture per arm**, and no arm carries an interleaved control.
  - **`R[]` proves the tick fired, not that the tick's work ran to completion.** It records a
    tour-row text change, which is the rotation's visible output; it does not witness the derived
    recompute, the effects, or the marquee re-measure behind it.
  - **This locates the frequency, not the pause.** What the ~450 ms is spent on is still unidentified
    — see "The JSC source: why the pause cannot be chunked on this board".


### The JSC source: why the pause cannot be chunked on this board

**This subsection is analysis of the WebKit source, not a board run.** It reads the extracted
JavaScriptCore of the same webkitgtk3 2.44.3 these runs ran, under
`build/tmp-raspberrypi0-wifi/work/arm1176jzfshf-vfp-poky-linux-gnueabi/webkitgtk3/2.44.3/webkitgtk-2.44.3/`,
and cites file and line in the form "Configuration under test" already uses. The fuller analysis,
including the option shortlist Run 45's lever was chosen from and its own confirmed/not-confirmed
split, is [`jsc-gc-findings.md`](jsc-gc-findings.md). **Every claim below except the last bullet's
reasoning was read out of that tree and is checkable there.**

- **Concurrent marking is compiled out on this architecture, and no environment variable can reach
  it.** `Source/JavaScriptCore/runtime/Options.cpp:707-708` reads
  `#if !CPU(X86_64) && !CPU(ARM64)` → `Options::useConcurrentGC() = false;`. This board is armv6
  (`arm1176jzfshf`), so the gate fires. **The ordering is the load-bearing part and it is explicit in
  the source:** `Options::initialize()` applies every `JSC_*` environment override first
  (`Options.cpp:971-978`), and the comment immediately after reads *"No more options changes after
  this point. notifyOptionsChanged() will do sanity checks and fix up options as needed"* before
  calling `notifyOptionsChanged()` (`Options.cpp:992-994`) — which is the function containing line
  708. An operator who sets `JSC_useConcurrentGC=1` gets it read, accepted, and then overwritten by
  architecture.
- **What runs instead has no yield point, and WebKit says so in its own comment.**
  `Source/JavaScriptCore/heap/Heap.cpp:398-402` takes the non-concurrent branch with the comment
  *"We simulate turning off concurrent GC by making the scheduler say that the world should always be
  stopped when the collector is running"*, and installs
  `SynchronousStopTheWorldMutatorScheduler`. That scheduler's
  `timeToResume()`
  (`Source/JavaScriptCore/heap/SynchronousStopTheWorldMutatorScheduler.cpp:59-62`) returns
  `MonotonicTime::infinity()` whenever the collector is not in the `Normal` state — the mutator is
  never scheduled to resume mid-collection. **A full collection is one unbroken stop-the-world
  pause**, which is why the measured stall is ~500 ms in a single block rather than a sequence of
  short ones, and why no runtime option chunks it.
- **What the source leaves nominally open is frequency alone.**
  `Source/JavaScriptCore/runtime/OptionsList.h:367` declares
  `percentCPUPerMBForFullTimer` at a default of `0.0003125`, and
  `Source/JavaScriptCore/heap/FullGCActivityCallback.cpp:80` is the only place it is consumed —
  scaling the full-collection timer by heap size, clamped by `collectionTimerMaxPercentCPU`
  (`OptionsList.h:369`). **Run 45 is the measurement of that lever and finds it inert**, so the timer
  is not the binding constraint. **The "because it is promotion-triggered" clause this bullet
  previously carried is WITHDRAWN** — Run 42 pulled the promotion budget 4x in the direction a
  promotion model says should have shortened the period, and the period did not move. What the source
  leaves nominally open is frequency alone; what the measurements say is that neither of the two
  frequency paths the engine exposes is the one in force, and which path is has not been identified.
- **Two levers on this surface were enumerated and never run, and the floor claim is scoped around
  them.** `JSC_largeHeapSize` sits on the promotion budget itself — `minHeapSize` is
  `min(largeHeapSize [32 MB, OptionsList.h:204], ramSize x smallHeapRAMFraction [0.25, :206])`, the VM
  is `HeapType::Large`, and on this board the 32 MB term binds — and **raising** `JSC_forceRAMSize`
  above 32 MB is the same lever from the other side. [`jsc-gc-findings.md`](jsc-gc-findings.md)
  predicted that second one as the next step if the timer lever moved nothing; the timer lever moved
  nothing and it was not taken. Both are cheap — an environment variable and one capture. Neither is
  likely to help, for Run 42's reason: the budget was tightened 4x with no response, so it is slack.
  **That argument is stated here rather than left implicit**, because "we predicted a next step, the
  prediction's trigger fired, and we stopped" is not a closure a reader can check.
- **The gate is a correctness gate, and this bullet is INFERENCE rather than a source read.** On a
  32-bit build a `JSValue` is a two-word tag and payload that cannot be loaded or stored atomically,
  so a marking thread running concurrently with the mutator can observe a torn value and follow it as
  a pointer. **No comment in this tree states that as the reason for the `!X86_64 && !ARM64` gate** —
  the gate is stated without justification at `Options.cpp:707` and groups `useConcurrentGC` with
  `forceUnlinkedDFG` and `useWebAssemblySIMD`. The reasoning, and a record of the same hazard biting
  on 64-bit — a pull request against **Bun's downstream fork** of WebKit, not against upstream
  WebKit, which this record previously mis-described as "the upstream record" — are cited in
  [`jsc-gc-findings.md`](jsc-gc-findings.md); the conclusion it
  supports is the cautious one either way. **This is not a knob that was left in the wrong position,
  and patching it out is not a lever this investigation proposes.**

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

## Runs 37-48 — the GC lever, and where it is driven from

This record spent most of its length open on one lever: **reduce the WiseKiosk frontend's per-second
allocation churn.** Run 36 had shown that injected allocation reproduces the stall at will, 474x on
the miss fraction, so the inference was that removing the page's own allocation would remove it.
Eleven runs test that inference directly. It is **half right, and the half that is wrong is the half
the lever rested on.**

**How these eleven are read, and it is R3 rather than a preference.** Each run's numbers stay inside its
own block in "Test runs"; cross-run comparison appears only here, and only on the **beat**. Two
captures of the same configuration have differed by a factor of two in this record (Runs 26a and
26b), so a rate difference between captures is not a result and is never scored as one.

**Run 37 withdraws the first candidate — the marquee's per-frame transient allocation.** The marquee's
shared rAF step iterates a `Map` with `for (const [column, distance] of columns)`, which builds
roughly three short-lived objects per column per frame. An instrumented bundle carries **both** loop
bodies and selects between them per frame **from the arm schedule then in force**, so the motion is
byte-identical either way and only the allocation differs. Interleaved in one capture, the allocating
arm misses the deadline on **5 of 12965 frames (0.039%)** and the allocation-free arm on **7 of 6696
(0.105%)** — the clean arm is *higher*, and both arms read a 24 ms mean. **Removing the allocation
does not remove the stall**, and the "cut the marquee's churn" lever is withdrawn. (The arms are not
the equal 80 s blocks the probe was written to run: an unterminated edge array leaves the final ALLOC
arm running 156 s, so A carries 316 s against C's 160 s. Every CLEAN arm is still bracketed, so the
null holds; the drift-cancellation argument for trusting it is weaker than stated. See the Run 37
block.) The mechanism this suggested — a transient dies in the nursery, is collected by a cheap eden
pass and is never promoted — is INFERENCE, and Run 44's one direct read of the collector reported
**zero eden collections in 85 s**, which this record does not reconcile.

**Run 38 establishes that the page cannot instrument its own collector on this build**, which is why
the next step had to leave the page. `performance.memory` is absent and `window.gc` is undefined.
`FinalizationRegistry` exists but its callbacks **never fire** on a saturated core — there is no idle
turn to deliver them, so the in-band GC detector Run 38 was built around returns nothing.
`WeakRef.deref` is worse than useless here: calling it keeps a still-live target alive for the rest
of the turn, so the act of observing prevents the collection it is trying to see. This is the "no
collector instrument was read" gap "Root cause of the residual stall" names, confirmed as a build
property rather than a missing idea — **for the in-page instruments only**. The one out-of-page
instrument this record dismissed on the same page, `JSC_logGC`, was dismissed wrongly; see Run 47.

**Run 39 is the run that relocates the mechanism.** Three conditions interleaved in one capture — no
ablation, the 8 s rotation tick's derived recompute skipped, the 1 s clock re-read skipped — each
with the app's own skip counter read back as the landing check. **Freezing the rotation tick takes
the stall to zero: 0 frames over 250 ms in 6737, against 10 in 6109 with nothing ablated.** The clock
arm reads 5 in 6132, which is not a result at these counts (see the run block). So the driver is the
**per-tick reactive update**, and Run 37 has already said it is not the allocation *inside* that
update. What the tick does that the loop body does not is re-execute a graph — deriveds, effects, the
marquee's re-measure and re-registration — whose intermediate values **survive long enough to be
promoted**. **BOUNDED (Runs 42, 45, 47), as the same sentence is in the Run 39 block:** "promoted"
names a trigger, and no lever aimed at promotion moves the beat. What arm R establishes without it is
narrower and unaffected — **the tick is what makes the cost become due**, whatever the cost is.

**Run 40 tried to split that further and could not.** It isolates `window.matchMedia` (each call
makes a document-retained `MediaQueryList`) from the per-tick derived recompute. The capture is
quiet — 1 to 3 stalls per arm — and at those counts the arms are indistinguishable from each other
and from Poisson noise. It is recorded as **UNMEASURED quality, not a null**: it does not license the
conclusion its own parser prints, and the run block says so.

**Run 41 establishes the reference the rest of the section is read against, and it is a metronome.**
A clean 588 s baseline with no ablation: **27 frames over 250 ms, 0.046/s**, and fourteen of them
arrive at 40.5, 80.5, 120.6, 160.5, 200.6, 240.6, 280.7, 320.7, 360.8, 400.8, 440.9, 480.9, 520.9 and
561.0 s — **thirteen consecutive intervals of 39.9 to 40.1 s**, at 475 to 531 ms each. This is not a
rate that happens to average 40 s. It is a beat, and the run block gives it in full. A beat this
stable is what a **threshold-driven** mechanism looks like — something crossing a fixed line at a
steady rate, rather than a rendering event recurring per cycle. **Which threshold is open**: this
record once answered "the eden-to-old-generation ratio, fed by a steady promotion rate", and
Runs 42, 45 and 47 each pulled a lever on that answer and got nothing. After them **no mechanism in
this record predicts the beat**, which is this section's conclusion rather than a gap in it.

**Runs 42 and 45 take the two levers the engine nominally exposes, and both are inert on the beat.**
Run 42 shrinks the heap the collector is willing to grow into — `JSC_forceRAMSize=32MB`, whose
landing is indicated by the process's `VmRSS` reading **89984 kB** against the **106380 kB** of
**Run 37's** capture (a different bundle and a different probe; no same-configuration baseline was
taken, so the check is indicative rather than controlled) — and sets the growth factors to 1.05 with
`collectContinuously`. (The third of those never applied: the engine clears `collectContinuously`
whenever concurrent GC is off, which on armv6 it always is — see the run block and the JSC-source
subsection.) The cadence does not move: the beat runs 40.5, 80.5, 120.6, 160.6, 200.6, 240.7, 280.7,
321.0, 361.1, 401.0, at **39.9 to 40.3 s**. Run 45 then takes the one lever the JSC source says is
nominally available — `percentCPUPerMBForFullTimer`, divided by 16 — and the beat runs 42.0, 82.0,
122.0, 162.0, 202.0, 242.0, 282.1, 322.3, 362.3, 402.4, 442.4, 482.4, 522.5, at **40.0 to 40.2 s**,
at 472 to 527 ms each. The phase shifts by about 1.5 s; the **period does not move at all**.

**SUPERSEDED — what this record concluded from those two runs.** It wrote, here and in Run 45's
block: *"That is the signature of a collection triggered by **promotion** — the eden-to-old-generation
ratio crossing a threshold — rather than by a timer, and a timer lever cannot reach a promotion
trigger."* **That is withdrawn**, and the original sentence is kept above rather than deleted,
because the error is instructive. The two runs exclude each other's explanation: Run 42 says "not
growth, therefore the timer"; Run 45 says "not the timer, therefore growth". The
eden-to-old-generation ratio is `m_maxEdenSize / m_maxHeapSize`, and `forceRAMSize` and the growth
factors are exactly what set `m_maxHeapSize` — **Run 42's lever *is* a promotion-path lever**, so the
second sentence is false on this record's own source reading. It is worse than a stalemate: `JSC_forceRAMSize=32MB`
drives `minHeapSize` from 32 MB to 8 MB, a **4x cut** to the promotion budget, and a promotion-paced
cadence owes a roughly 4x *shorter* period for it. The period held at Run 41's to within the probe's
resolution. **That is a falsification of the promotion model, not a null.** What the two runs
establish together is the weaker and true statement: **neither the heap-size and growth path nor the
full-GC timer moves the period, so the trigger is unidentified.** One asymmetry survives and is worth
keeping — a constraint tightened 4x with no response is a **slack** constraint, so loosening it
further is correspondingly unlikely to help.

**Run 47 removes the strongest remaining candidate, and it was this record's own.** The memory-pressure
hypothesis was raised against this section by an adversarial architecture review, read out of this
image's generated build configuration rather than upstream defaults: WebKit's UI-process
`MemoryPressureMonitor` fires at ≥90% system memory used, and the handler's hold-off is the release
duration x 20, so a ~2.0 s release yields a 40 s spacing with no 40 s constant needed anywhere. It
explained Run 42 and Run 45's mutual exclusion, Run 44's `eden:0` and the off-beat pairs at once — and
it came with a complete, no-rebuild kill switch. Run 47 pulled it, **with the switch's landing
verified in the UI process that consumes it** — `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR` read back
from surf's own `/proc/<pid>/environ` under the identical `kiosk.conf` mechanism the arm ran, so the
null is a result and not an unapplied manipulation. **The beat did not notice: 40.0 s in both arms.**
The switch skips the handler's `install()` rather than suppressing one of its triggers, so the arms
rule out **the whole mechanism**, whatever would have driven it. Separately and on different
evidence, the monitor's **≥90%** trigger is excluded on headroom: it would need `MemAvailable` to
fall from ~263 MB to about 43.5 MB of 435, a ~220 MB excursion, where this record's own web-process
`VmRSS` readings are 90–106 MB. Those two legs are not symmetric corroboration — the headroom
argument *entails* a null on the polled path — they are different scopes, and the arms are the only
line covering the rest of the handler.
**The hypothesis that overturned this section overnight is refuted by direct measurement**, and the
honest reading of it is the one below rather than the confident one it replaced.

**The instrument that made this readable is banked separately.** Every prior session in this record
failed to attach WebKit's remote inspector, and "Root cause of the residual stall" records that
failure as a build-time condition. It is not one. The launcher wires `KIOSK_INSPECTOR=1` to
`WEBKIT_INSPECTOR_SERVER`, which is **WebSocket-only** — a plain `GET /` connects at the TCP layer
and then hangs with zero bytes forever, which is exactly what "the inspector server accepts the
socket and returns nothing" describes. `WEBKIT_INSPECTOR_HTTP_SERVER` serves the target-list page an
HTTP client can drive, it is settable over the wire in `/data/config/kiosk.conf` with no rebuild, and
with it the collector is readable. The procedure, the protocol departures from CDP that cost the
prior attempts, and the client are in the **`webkit-inspector` skill**
([`.claude/skills/webkit-inspector/SKILL.md`](../../../.claude/skills/webkit-inspector/SKILL.md),
committed at `cd5cf9e`). **The gap this closes is the first one "Root cause of the residual stall"
names** — "no collector instrument was read" — and the claim that it was unreachable on this build is
**withdrawn**: it was unreachable on the wrong environment variable.

**Run 44 is what the inspector read, and this record over-read it. BOUNDED.** `Heap.startTracking`
types the collection it sees over an 85 s window as **full**, not eden — **on n = 1**, with the same
window reporting **zero** eden collections, which is not credible against the eden-pass mechanism
Run 37 invokes and which points at an under-delivering event stream on this port rather than at a
finding. The capture's "tracking quiesces the collector" clause, which this record leaned on, is
cited to nothing. The honest form: one collection was observed and typed full, and the sample is not
treated as representative. This section previously wrote that the type read was "the direct
observation the identification was making by convergent inference"; **that is withdrawn.**

**And the census diff was never banked. RESTATED.** The capture's diff section is a header —
`--- diff (profile-churn.mjs) over 30s: NO retained growth (transient churn, no leak) ---` — with no
before/after count, no per-class delta and no threshold under it. So "no retained growth" is **a
claim this investigation made and did not record**, not a datum of it. The gap is the *numbers*, not
the instrument: the capture names `profile-churn.mjs`, which is uncommitted, but the committed
`webkit-inspect.mjs` implements the same forced-GC census diff and the experiment can be re-run
today, and the sentence this section carried — *"the heap is not
leaking, it is **churning**, building and promoting and releasing the same volume every cycle"* — was
**INFERENCE resting on that unrecorded claim**. It is kept visible here and downgraded. **Nothing in
this record measures a promotion rate, an allocation rate or a per-cycle volume**; the page's own
allocation rate is unmeasured, which "Root cause of the residual stall" already says and which
Runs 37 to 48 did not close.

**What Run 44 does contribute is a number that cuts against the pause explanation too.** The census is
real: **20866 nodes**, top classes summing to roughly **1.07 MB**. Five hundred milliseconds over
20866 nodes is **~24 µs per node**, on the order of 17,000 ARM11 cycles to mark one object — two to
three orders of magnitude off any plausible mark rate. So the 500 ms is very likely **not
mark-dominated**, and which phase it *is* dominated by — per-block work proportional to heap
capacity, or WebCore's output constraints over the page's DOM wrappers — is not identified anywhere
in this record. The wrapper-population lever that the third of those would imply has never been
enumerated, let alone run.

**Run 43 is the app-side lever, built and measured, and it does not move.** Fix 1 splits the clock's
granularity so the per-second path stops re-running the expensive formatting, and caches the
`matchMedia` result so the marquee's re-registration stops making a retained `MediaQueryList` per
tick. Both reduce real allocation. Over 608 s the capture reads **26 frames over 250 ms, 0.043/s**,
with the beat at 40.5, 80.5, 120.6, 160.6, 200.6, 240.6, 280.7, 320.7, 360.8, 400.8, 440.9, 480.9,
521.0, 561.0 s — **40.0 to 40.1 s** across those fourteen, at **470 to 525 ms** — followed by a
600.5 s arrival after a 39.5 s interval and its 601.2 s companion, at 433 and 532 ms. Against
Run 41's 0.046/s and identical beat, **this is a null on the stall.** Reducing the application's
allocation does not reduce the frequency of the collection.

**Run 46 is the strongest form of the lever and it does not move either.** If the driver is the
reactive update, then removing the reactive *render* is the sharpest available test: the tour rows
are rendered once and filled **imperatively**, bypassing the `{#each}` and its snippet entirely, with
a two-screenshot landing check that shows the right rows in the right places. Over 587 s: **25 frames
over 250 ms, 0.043/s** — the same number as Run 43's at the two figures this record uses — beat at
40.5, 80.5, 120.5, 160.5, 200.4, 240.5, **then a skipped turn to** 321.4, 361.4, 401.5, 441.5,
481.5, 521.5, 561.6 s, at **39.9 to 40.1 s** across the turns that arrive — the 240.5 → 321.4 gap is
**80.9 s**, two periods, and sits outside that range by construction. The on-beat set is
hand-curated; the run block says on what basis. **Unchanged.**

Two claims this section made about Run 46 are bounded rather than kept. **The landing check has no
oracle** — no matching pair from the reactive bundle at the same data state, no written expectation
of which rows should appear after a rotation — so "validated pixel-correct" is withdrawn in favour of
"the right rows were drawn in the right places", which is what two frames 64 s apart can carry. And
**the throughput win is a cross-capture comparison against the slowest of five captures**: mean frame
time does read 22 ms against Run 41's 25 ms with 298 frames in the 50–100 ms bucket against 682, but
the same bucket moved 682 → 457 under Run 45, which changed nothing in the application at all. The
run carries no interleaved control arm. **Consistent with a throughput win, not measured as one** —
and the five-capture spread is in the Run 46 block. As for why the null: this section wrote that the
promotion is *"spread across the reactive graph"*. That sentence names promotion, which Runs 42, 45
and 47 leave unidentified, so **the mechanism is superseded and the observation stands**. Note too
that Run 39's ablation and Run 46's removal are not the same node: the derived spine Run 39 froze is
still executing under Run 46's imperative fill, so "sharpest available form of the lever" is bounded
by a configuration that was never built.

**The JSC source closes the third direction: the pause itself cannot be chunked.** JavaScriptCore
gates `useConcurrentGC` on `!X86_64 && !ARM64` in `Options.cpp`, **after** environment overrides are
applied, so on this armv6 build concurrent marking is compiled out and no runtime option can turn it
back on. What runs instead is `SynchronousStopTheWorldMutatorScheduler` with `timeToResume` at
infinity: a full collection is **one unbroken stop-the-world pause**, not an incremental one that
could be chunked under the frame budget. The gate is a **correctness** gate, not a performance
default — on a 32-bit build a `JSValue` is not atomically readable, so a marking thread running
concurrently with the mutator can observe a torn value and corrupt the heap. It is not a knob that
was left in the wrong position; it is a knob that must not be moved. The source reads, cited to file
and line, are in "The JSC source: why the pause cannot be chunked on this board"; the fuller
analysis is [`jsc-gc-findings.md`](jsc-gc-findings.md).

**So what is left, stated as what was measured.**

- **The pause cannot be chunked, and this is the best-evidenced thing in the section.** No
  concurrent or incremental marking exists on armv6, by a correctness gate that cannot be lifted
  safely, and what runs instead has no yield point. **A full collection cannot be chunked on this
  board**, so whatever the collection costs is paid in one block. Every source citation behind that
  leg was re-derived in the extracted tree, file and line. **This bounds how the cost is paid, not
  how large it is** — nothing here says the half-second cannot be made smaller, and the next two
  bullets name the levers that would do exactly that.
- **What the ~500 ms is *spent on* is not identified.** The obvious answer does not survive this
  record's own arithmetic: 500 ms over Run 44's 20866-node census is ~24 µs per node, two to three
  orders of magnitude off a mark rate. Per-block work proportional to heap capacity, and WebCore's
  output constraints over the page's DOM wrappers, are the other candidates and neither was measured.
  **The phase is unpinned, so even the pause leg names a cost without naming its content.**
- **No lever *inside the engine* reaches the trigger, and every one is a measured no-op.** WebKit's
  memory-pressure handler under its complete kill switch (Run 47), the JSC heap and growth budget —
  pulled 4x in the direction a promotion model says should have shortened the period (Run 42) — the
  full-GC timer at 1/16 eagerness (Run 45), and pixel area at a 3x cut (Run 35). Each is null on the
  beat. **The earlier reading "the collection is promotion-triggered" is withdrawn**: Run 42 *is* a
  promotion-path lever and it was inert.
- **A lever *in the application* does reach it, and this is Run 48.** The beat is **5 x the
  park-wait-times rotation interval**: 40.0 s at the shipped 8 s across thirteen intervals of
  40.0-40.3 s, and 60.0 s at 12 s across four of 59.9-60.1 s, on one bundle with each interval read
  back in band. **A residual set by the hardware or by an engine configuration cannot move when a
  frontend config value moves.** Under one uniform membership rule **all three arms carry it**: 30.0,
  40.0 and 60.0 s at 6, 8 and 12 s. **BOUNDED — why the count is five is not established.** The
  reading this section first offered, that five ticks' worth of promotion crosses the old-generation
  threshold, **names the model Run 42 falsified**, and Run 48 sharpens that exclusion rather than
  rescuing it: the beat tracks a frontend quantity while staying immovable by the engine-side budget
  the same model says sets it. What accumulates over five ticks is unidentified. The 6 s arm is the
  low-quality point — 58% dropout, a capped landing check, an unexplained 167 s silent tail — and is
  consistent with the law rather than carrying it.
- **That reconciles the nulls rather than contradicting them.** Runs 37, 43 and 46 each removed one
  *contributor* to the per-tick update and read a null; Run 39 froze the *whole* tick and read zero.
  Both hold if promotion is spread across the entire update — no single contributor is removable
  enough to matter — while the **number of ticks per collection is fixed**, so the period tracks the
  interval. Run 48 measures directly what Runs 37 to 46 could only circle.
- **The beat reaches zero exactly once, and Run 48 explains why.** Freezing the rotation tick takes
  it to zero in 6737 frames (Run 39, p = 0.0006). A display that does not advance is not the display
  — but the tick's *rate* is a configuration value, and that is the finding.

**SUPERSEDED, and kept visible because it was this record's conclusion for a day.** Until Run 48 this
section closed as follows: *"The residual ~500 ms freeze every ~40 s is a full stop-the-world
JavaScriptCore collection that **no lever this investigation could reach moves** … It is **not** the
claim that the residual is provably irreducible: the precise engine mechanism — which collection
phase the half-second is spent in, and what triggers it — is unidentified, and an unidentified
trigger may sit somewhere no lever was pointed at."* The caution was right and the conclusion was
wrong in its first clause: **a lever this investigation could reach does move it**, and it was
reachable all along — it is a value in the application's own configuration. The two engine levers
that paragraph named as enumerated-but-un-run, `JSC_largeHeapSize` and a *raised* `JSC_forceRAMSize`,
are **still un-run** — and they are **frequency** levers, not pause levers: both raise the promotion
budget, which changes how often a collection is due. The page's **DOM-wrapper population** is the
un-run **pause** lever, because it changes how much gets marked. **Neither half is closed.**

**The conclusion, in the two halves the evidence now separates.**

- **The per-event pause is the un-chunkable half.** ~450 ms, paid in one unbroken stop-the-world
  block, because armv6 compiles concurrent marking out by a correctness gate that cannot safely be
  lifted. Nothing in this record shortens it, and **what it is spent on is still unidentified** —
  500 ms over Run 44's 20866-node census is ~24 µs per node, orders off a mark rate, so the phase is
  unpinned.
- **The frequency is not a floor. It is the frontend's rotation cadence**, at five ticks per
  collection across every interval measured — though *why* five is unidentified. That makes the residual's frequency **WiseKiosk's to own, not
  the image's and not the hardware's** — which is the single most useful thing this investigation
  produced, because it moves the question out of a 4.5 h rebuild and into a config value and a
  render path.

**Production is unchanged and this section proposes no cadence change.** The schema default stays at
8 s (owner, 2026-09-23). Run 48 is a diagnostic: it locates the cause. Lengthening the interval would
trade the viewer's refresh rate against stall frequency and is a product decision nobody has taken
here. **The lever "reduce the frontend's per-second allocation churn" stays withdrawn** — it was the
right *subsystem* and the wrong *quantity*; the quantity is the tick rate and the per-tick promotion
volume behind it. The paragraph in "Real-time framing" that opens the allocation lever is superseded
by this section.

**The instrument that would settle it has still not been read, and the reason is no longer the one
this record gave.** `JSC_logGC` prints, per collection, the scope, the heap capacity, the mark-stack
sizes and the pause in milliseconds — one capture of it answers the phase question, the trigger
question and Run 44's `eden:0` at once. This record dismissed it as "substantially compiled out";
**that is refuted** — the option is `Availability::Normal` and honoured in this build. The trace has
gone uncaptured because `dataLog` writes to the **WebProcess's stderr**, and Run 47's attempt to
redirect it was denied by the WebProcess sandbox. A sandbox-writable path, a stderr redirect, or the
inspector's heap tracking would finally read it. **It remains the cheapest unrun experiment in this
record.**

**What was fixed is real and is a different quantity.** The marquee **stutter** is fixed by
re-mechanising to `scrollLeft` (Run 25, 2.7x) and the clock relayout by two CSS properties (Run 7,
~8x on p90). Those are smoothness results and they hold. The allocation reductions Run 43 built —
the clock granularity split, the `matchMedia` cache — are **banked, not discarded**: they reduce real
work and they matter for a future in which the board hosts the application itself rather than
rendering a mirror-served page. They do not move today's floor, and this record does not claim they
do.

**What would move it is a different architecture, not a different configuration**, and naming it is
not proposing it. A renderer that owns its own frame budget, or a display whose content advances
without re-executing a reactive graph, has a computable worst case where this one has an observed
one. "Real-time framing" already says that and already says it is not costed here. **Runs 37 to 48
change only one thing about that paragraph: the cheap in-application step it said came first has now
been taken, and it did not work.**

**What this closes, and what it does not.** The **technical lever** this record was left open on is
closed: it was run, in every form available to it, and it does not move the beat. **The mechanism is
not closed with it.** Which collection phase the ~500 ms is spent in, and what triggers the
collection, are both unidentified, and this section says so rather than naming a trigger the
measurements have falsified. **Closure of #100 gpu-compositing is not asserted here and is the
owner's.** What remains open under it:

- **The mechanism**, and the one cheap experiment that would name it — a `JSC_logGC` capture whose
  output is actually collected off the WebProcess's stderr.
- **Open levers in both halves.** On **frequency**: `JSC_largeHeapSize` and a *raised*
  `JSC_forceRAMSize`, both promotion-budget levers, enumerated and un-run. On the **pause**: the
  page's DOM-wrapper population, never enumerated and un-run.
- **The durable image delivery**, still an untaken owner decision — see "Durable image delivery —
  pending owner decision".
- **Four R2 obligations**, not two: the scripts Runs 3 to 7 put on the board are uncommitted;
  [`parse_alloc.py`](parse_alloc.py) reads an earlier revision of Run 36's payload than the committed
  probe emits; Run 44's census diff **banked no numbers** (its named tool `profile-churn.mjs` is
  uncommitted, though the committed `webkit-inspect.mjs` implements the same experiment, so the
  obligation is the numbers rather than the tool); and **Run 47 has no committed capture at all.**
- **Two harness obligations this record's own reviews surfaced.** The three arm-parsers print a
  confident VERDICT with no event-count guard — a capture with zero stalls in every arm reads as a
  confirmation — and [`parse_baseline.py`](parse_baseline.py), the analyser behind every *adopted*
  conclusion here, has no test, no landing check and the 40 s period baked into its fold.

## Root cause of the residual stall

**The residual is a JavaScriptCore garbage-collection pause.** A long-lived page that allocates on a
schedule — a clock tick every second, a data poll, reactive objects re-created, DOM churn — walks its
heap up to the collector's threshold, and the full collection that follows runs on the board's single
ARM11 core and stops the main thread for roughly half a second at the steady arrival and up to ~1.5 s
in the tail. The allocation sources named there are the shape of the mechanism and are **not
measured on this page**; what is measured is that allocation drives the stall. Four legs carry the
identification, and the second of them is also the test the withdrawn one failed.

**BOUNDED by "Runs 37-48 — the GC lever, and where it is driven from".** That the residual is a full stop-the-world
JavaScriptCore collection stands. The sentence above it — *"walks its heap up to the collector's
threshold"* — names a **trigger**, and Runs 42, 45 and 47 leave the trigger unidentified: the heap
budget was pulled 4x in the direction that model owes a response to, the full-GC timer was changed
16x, and WebKit's memory-pressure handler was killed outright, and the beat did not move for any of
them. Read the threshold clause as the shape of a generational collector, not as this record's
measured finding.

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
crossing a fixed heap threshold explains the period directly. **BOUNDED (Runs 42, 45, 47):** that
sentence names the heap threshold as the mechanism, and the levers that reach a heap threshold — the
budget, the growth factors, the full-GC timer — are each a measured no-op on the period. What
survives is the weaker half: the cadence is *threshold-shaped*, and which threshold is unidentified.
The phase lock Run 26b reads — eight of
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
measured" are still measured and still negative — they were aimed at paint, which is the wrong
target, so their nullity is expected rather than informative about the collector.

**The honest gaps, named rather than glossed.**

- **No collector instrument was read.** No GC-event trace, no heap-size series and no
  `performance.memory`-equivalent reading is in this record; the identification rests on an
  allocation manipulation with a verified landing (Run 36), a falsified alternative (Run 35) and the
  arrival cadence. A direct read of collection events would convert it from convergent inference to
  observation, and that read has not been taken.

  **SUPERSEDED IN PART by "Runs 37-48 — the GC lever, and where it is driven from".** Run 44 took a collector read:
  the remote inspector is reachable on this build over the HTTP-server variable, and it returned a
  heap census and one typed collection. That read is **n = 1 with a partly-broken event stream**, so
  the gap narrows rather than closes. **The GC-event trace is still not captured** after forty-seven
  runs — and the reason this record gave for that, that `JSC_logGC` is substantially compiled out, is
  **wrong** (Run 47): the option is honoured, and its output goes to the WebProcess's stderr, which
  nothing here was collecting.
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

  **SUPERSEDED IN PART by "Runs 37-48 — the GC lever, and where it is driven from".** The inspector is **not**
  unavailable on this build and no rebuild is needed: the launcher wires the WebSocket-only server
  variable, whose silent-socket behaviour is exactly the symptom recorded above, and
  `WEBKIT_INSPECTOR_HTTP_SERVER` works over the wire (Run 44). **"Both missing instruments are
  build-time conditions" is therefore withdrawn.** What is *not* withdrawn is the gap itself: Run 44
  drove `Heap.*`, not `Timeline`, so **the Paint rect is still unread**, and the `longtask` absence
  stands.

## Engine levers, measured

Every **runtime** configuration lever WebKit and the display stack expose on this SoC **that this
investigation measured**, each measured on the board and each scored against the run that measured
it. **This ledger was titled "measured and exhausted" until Run 47, and it was not exhausted** — it
enumerated only rendering levers while a whole memory-management subsystem with its own thresholds,
its own hold-off arithmetic and its own environment variable sat outside it, and two engine levers
named in this record's own source analysis are still un-run (see "Runs 37-48 — the GC lever, and where it is
driven from"). The word is dropped rather than defended. The build-time surface — `PACKAGECONFIG` on the
webkit recipe — is a separate class and is **not** enumerated here; see "Real-time framing".

**These rows are not a series and must not be differenced against each other.** Each is one run's own
number against its own reference, across different resolutions, bundles and mechanisms. The column
says what that run's verdict was, not where a lever sits in a ranking.

**Every rendering lever in this table was aimed at paint**, and paint is not the residual's mechanism
— see "Root cause of the residual stall". Those rows are still correct as measurements and still
correct as verdicts on their own levers; what they are not is evidence that the residual is
unbounded, because none of them was ever pointed at the collector. **The last three rows are the
levers that *were*** — two JavaScriptCore options and WebKit's memory-pressure handler — **and they
were absent from this table until Run 47 made the omission conspicuous**: a ledger of "every runtime
lever" that enumerated only rendering ones is how a whole subsystem with its own thresholds, its own
hold-off arithmetic and its own environment variable went unconsidered for nine runs.

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
| `JSC_forceRAMSize=32MB` + growth factors 1.05 — the collector's heap and growth budget | 42 | beat 40.5 s to 401.0 s at **39.9–40.3 s**, Run 41's period; `VmRSS` 89984 kB indicates the landing, against Run 37's capture | **Null on the beat, and the direction matters.** It cut the promotion budget 4x, which a promotion-paced cadence owes a 4x shorter period for. `collectContinuously` never applied |
| `percentCPUPerMBForFullTimer` ÷ 16 — the full-collection timer | 45 | beat 42.0 s to 522.5 s at **40.0–40.2 s**; phase shifts ~1.5 s, period identical | **Null on the beat.** The full-GC timer is not the binding constraint |
| `WEBKIT_DISABLE_MEMORY_PRESSURE_MONITOR=1` — the complete kill switch for WebKit's memory-pressure handler | 47 | **40.0 s in both arms**, with the variable read back from surf's own `/proc/<pid>/environ`; the ≥90% trigger separately excluded on headroom (`MemAvailable` ~263 MB of 435 against the ~43.5 MB the threshold needs) | **Null on the beat, landing verified, and it is the decisive one.** The switch skips `install()`, so the arms rule out the whole handler and not merely its polled trigger |

What is left after the ledger is not an engine lever, and the two things that moved a number moved
**mean frame time**: **fewer pixels** (Run 22) and **a different mechanism in the app** (Run 25,
`scrollLeft` at 26.5 ms against `transform` at 71.5 ms in one interleaved capture). Both live outside
WebKit's runtime configuration, and neither touches the stall — Run 25's two arms have the same worst
frame, 491 ms and 496 ms, and Run 35 takes the pixels down 3x more for 1.4x on the stall. **The
lever that does reach the stall is in the app too, and it is not a rendering lever**: the frontend's
per-second allocation churn, which Run 36 shows drives the stall by 474x when pushed in the wrong
direction. It has not been pushed in the right one; see "Real-time framing".

**SUPERSEDED by "Runs 37-48 — the GC lever, and where it is driven from".** It has now been pushed in the right
one, in three forms — the marquee's transient churn (Run 37), Fix 1's clock split and `matchMedia`
cache (Run 43), and an imperative render that bypasses the reactive `{#each}` (Run 46) — and every
one is a measured null on the beat. **This is not a lever that reaches the stall.** The sentence is
kept because it is what the record believed when it was written.

## Real-time framing

The owner's standard for this panel is a hard one: a ~450 ms frame is not a slow frame, it is a
**missed deadline**, and a display that misses one is broken for the interval it misses it in. That
framing is the right one for a wall-mounted appliance, and this investigation was run against it
rather than against an average.

The measured answer is that **no runtime configuration of this stack bounds the deadline, and the
lever that reaches the mechanism is in the application rather than in the stack at all.**

**CORRECTED IN SCOPE by "Runs 37-48 — the GC lever, and where it is driven from".** The first half is supported for
what was measured — WebKit's rendering levers, JavaScriptCore's options and, since Run 47, WebKit's
memory-pressure handler — and is asserted here about *the stack*, which is wider than what was
enumerated. Read it as scoped to those. **The second half is measured false**: the application-side
lever was taken in three forms and reaches nothing (Runs 37, 43, 46).

A browser engine is a soft-real-time system by construction: it decides when to repaint, how much of
the surface to repaint, on which thread, and when to collect its heap, from heuristics that optimise
the common case and carry no upper bound. The **rendering** heuristics have all been tried on the
board and are in "Engine levers, measured" — compositing, tiled compositing, painting
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

**SUPERSEDED by "Runs 37-48 — the GC lever, and where it is driven from".** The audit was taken, by this
investigation rather than by the owner, and the lever is **withdrawn**: Run 37 removes the marquee's
transient churn, Run 43 ships the clock granularity split and the `matchMedia` cache, Run 46 removes
the reactive render itself, and each is a measured null on the ~40 s beat. **#100 gpu-compositing is
not open on this thread**; what it is open on is stated in "Runs 37-48 — the GC lever, and where it is
driven from", and the un-run part of it is the *mechanism*, not the lever.

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

  **SUPERSEDED on both counts by "Runs 37-48 — the GC lever, and where it is driven from", and kept visible.** The
  first is **answered definitively**: `Options.cpp:707-708` compiles `useConcurrentGC` out on any
  architecture that is neither `X86_64` nor `ARM64`, so no concurrent or incremental collector is
  available to this build, and the gate is a correctness gate rather than a build-configuration
  choice — no `PACKAGECONFIG` reaches it. The second is **wrong twice over**: the remote inspector is
  reachable with no rebuild, on the HTTP-server variable rather than the WebSocket one (Run 44), and
  JavaScriptCore's options are **not** compiled out of this release build — `JSC_logGC` is
  `Availability::Normal` and honoured, and the reason its trace went unread is that `dataLog` writes
  to the WebProcess's stderr (Run 47). The `WEBKIT_DEBUG` half stands, and the Paint rect is still
  unread.
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

  **SUPERSEDED IN PART (Runs 37 to 48), and kept visible.** "The lever that follows is reducing the
  frontend's per-second allocation churn, and it is un-run" is **withdrawn**: it was run in three
  forms and each is a null (Runs 37, 43, 46). Of the three gaps, one narrowed — a collector read was
  taken (Run 44), at n = 1 on a partly-broken event stream — and **two stand unchanged**: the page's
  own allocation rate is still unmeasured, and Run 36's injected pressure is still far above anything
  the page does. The findings that replace this paragraph are the four immediately below.

- **OBSERVATION (Run 39) — freezing the rotation tick is the only manipulation that takes the stall
  to zero.** Three conditions interleaved in one capture with the app's own skip counters read back
  per arm: nothing ablated **10 of 6109 frames over 250 ms**, the rotation tick's derived recompute
  skipped **0 of 6737** with a **218 ms maximum** — no near-miss either — and the clock re-read
  skipped 5 of 6132. A binomial test against the arms' frame counts gives **p = 0.0006** for the
  rotation arm and **p = 0.21** for the clock arm, whose parser verdict is **not adopted**. Arm R is
  not a shippable configuration: a rotation that does not recompute is a display that does not
  advance.

- **WITHDRAWN — "reduce the WiseKiosk frontend's per-second allocation churn" (Runs 37, 43, 46).**
  OBSERVATION: the marquee's per-frame transient allocation toggled inside one capture under
  byte-identical motion, with per-arm path counters read back, gives **5 of 12965 frames (0.039%)**
  allocating against **7 of 6696 (0.105%)** allocation-free — p = 0.12, and the clean arm is the
  higher one (Run 37). OBSERVATION: Fix 1's clock granularity split and `matchMedia` cache read
  **0.043/s** with the beat at 40.0–40.1 s against the clean baseline's 0.046/s and identical beat
  (Run 43). OBSERVATION: an imperative tour render that bypasses the reactive `{#each}` entirely
  reads **0.043/s** with the beat unchanged (Run 46). INFERENCE: the application's own allocation is
  not what paces the collection, and the lever "Real-time framing" was left open on is closed against
  itself. **The mechanism this record offered for the null — that the promotion is spread across the
  reactive graph — is superseded**, because it names a promotion trigger the runs below falsify.

- **WITHDRAWN — "the collection is promotion-triggered" (Runs 42, 45, 47).** This record stated it
  twice as settled. OBSERVATION: `JSC_forceRAMSize=32MB` with growth factors at 1.05 leaves the beat
  at Run 41's period (Run 42); OBSERVATION: `percentCPUPerMBForFullTimer` divided by 16 shifts the
  phase ~1.5 s and leaves the period identical (Run 45); OBSERVATION: the complete kill switch for
  WebKit's memory-pressure handler — which skips `install()` outright rather than suppressing a
  trigger, **with its landing verified by an anchored `/proc/<pid>/environ` read on surf, the UI
  process that consumes it** — leaves the beat at **40.0 s in both arms**; and separately the
  monitor's **≥90%** trigger is excluded on headroom, needing `MemAvailable` to fall from ~263 MB to
  ~43.5 MB of 435 against a web process of 90–106 MB (Run 47). INFERENCE: Run 42's lever **is** a promotion-path lever —
  `forceRAMSize` and the growth factors set `m_maxHeapSize`, and the eden-to-old-generation ratio is
  `m_maxEdenSize / m_maxHeapSize` — and it cut the promotion budget **4x**, which a promotion-paced
  cadence owes a roughly 4x shorter period for. It got nothing. **That is a falsification of the
  promotion model, and the trigger is unidentified.**

- **WITHDRAWN — "`JSC_logGC` is substantially compiled out of this build" (Run 38, Run 45; refuted by
  Run 47).** OBSERVATION: the option is declared `Availability::Normal` at `OptionsList.h:381`, which
  the environment-override path short-circuits the availability test for, and its emission sites in
  `heap/` carry no compile-time guard; what is compiled out is `dataLogLnIf` under a `constexpr bool
  verbose = false`, a different thing. OBSERVATION (Run 47): the option and `WTF_DATA_LOG_FILENAME`
  reached the WebProcess — confirmed in `/proc/<pid>/environ` — and no descriptor opened to the
  target path, which the WebProcess sandbox denies. INFERENCE: the near-empty trace was a
  **capture-routing bug**, not a build property: `dataLog` writes to the WebProcess's own stderr,
  which neither the journal nor the surf log collects. **This is the reading that closed off this
  investigation's best instrument for nine runs**, and the instrument is still unread.

- **WITHDRAWN — "the remote inspector is unavailable on this build" (Run 44).** OBSERVATION: the
  launcher wires `KIOSK_INSPECTOR=1` to `WEBKIT_INSPECTOR_SERVER`, which is WebSocket-only and
  answers a plain `GET /` by connecting and then hanging with zero bytes — precisely the symptom this
  record filed as a build-time condition. `WEBKIT_INSPECTOR_HTTP_SERVER` serves a target list an HTTP
  client can drive, is settable in `/data/config/kiosk.conf` over the wire, and **needs no rebuild**.
  The instrument was reachable the whole time, on the other variable. **The Paint-rect gap is not
  retired by this**: Run 44 drove `Heap.*`, not `Timeline`.

- **OBSERVATION (Run 48) — the beat is 5x the frontend's rotation interval, so its frequency is not
  a floor.** Three arms on **one** bundle (`index-DJUeJLKg.js`), varying only the application's
  `rotation_interval_seconds`, each interval read back in band from the capture's own `R[]` series
  (medians **6.000, 8.000, 12.000 s**). Scored by [`parse_rotation.py`](parse_rotation.py) under
  **one uniform membership rule applied to all three arms** — post-startup arrivals at or above the
  probe's own 250 ms cutoff, companion pairs clustered — **every arm carries a beat at 5 x its
  tick**: **30.0 s** at 6 s (8 of 9 arrivals on-grid, 58% of grid points dropped), **40.0 s** at 8 s
  (14 of 15 on-grid, **0%** dropped), **60.0 s** at 12 s (gap series 60.1, 60.0, 60.0 and a 120.2 s
  double). **A residual set by the hardware or by an engine configuration cannot move when a frontend
  config value moves.**

  OBSERVATION: the 6 s arm is the **low-quality** point, not a counter-example. An earlier reading of
  this run scored the arms by hand at 400 ms, kept a 279 ms arrival in the 8 s arm, demoted 252-312 ms
  arrivals in the 6 s arm, and concluded the 6 s arm "broke the linearity" — **that reading is
  withdrawn**; it was the same amplitude band treated two ways, each time toward the hypothesis. Under
  the uniform rule the 6 s gaps read 60.0, **29.7, 30.4, 29.8**, 60.4, 66.1, 53.7, 60.1 s: a 30 s
  fundamental with alternate members missing. Three further facts bound that arm and are stated
  rather than folded in: its **`R[]` capped at the probe's 80-entry limit**, covering only 0-488.1 s
  of 588 s; its stall stream **goes silent for its final 167 s** with rotation confirmed still
  running, which is unexplained; and a page that stopped doing per-tick work would look identical.

  INFERENCE, and it is narrower than this record first wrote: **no single contributor to the per-tick
  update is removable enough to matter** — which is why Runs 37, 43 and 46 read nulls — **while the
  number of ticks per collection stays fixed**, which is why the period tracks the interval and why
  Run 39's whole-tick freeze reached zero. **It locates the residual's frequency as the frontend's**,
  and therefore the owner's, rather than the image's or the board's. Production stays at the schema
  default 8 s (owner, 2026-09-23); this is a diagnostic that locates the cause, not a cadence change.

- **BOUNDED (Run 42, sharpened by Run 48) — "the collection fires every fifth tick because five
  ticks' worth of promotion crosses the old-generation threshold".** That sentence was written into
  this record when Run 48 landed, and it **reinstates the promotion-threshold model Run 42
  falsified**: `JSC_forceRAMSize=32MB` cut the promotion budget roughly 4x, which the model owes a
  roughly 4x shorter period, and the period held at 40.0 s. Run 48 does not rescue it — **it sharpens
  the exclusion**, because the beat demonstrably tracks a frontend quantity while remaining immovable
  by the engine-side budget the same model says sets it. **What is measured is that the beat is 5 x
  the rotation tick. What accumulates over five ticks, and why the count is five rather than three or
  eight, is unidentified** — and sits beside this record's other open half, what the ~450 ms is spent
  on.

- **SUPERSEDED (Run 48) — "the residual is a floor that no reachable lever moves".** This record
  carried, for one day, the INFERENCE that *"no lever this investigation could reach moves it, and
  the precise engine mechanism — which collection phase the half-second is spent in, and what
  triggers it — is unidentified"*. **Its first clause is refuted**: Run 48's lever is reachable, it
  is a value in the application's own configuration, and it moves the beat by 50%. The entry is kept
  visible because its caution was the right instinct — it refused "provably irreducible" — and
  because the sequence that produced it is the substance of this investigation: **every engine lever
  was null, which is exactly what made the engine look like the floor, and the lever that worked was
  never in the engine at all.**

  **What survives from it, unchanged:** the **pause** leg — armv6 compiles concurrent marking out, so
  a full collection cannot be chunked, every citation re-derived in the extracted tree — and the
  admission that **what the ~450 ms is spent on is still unidentified**, since 500 ms over Run 44's
  20866-node census is ~24 µs per node, orders off a mark rate. **Three levers remain un-run, and
  they do not all bear on the same half** — an earlier draft filed all three under the pause, which
  made the frequency half read as closed when it is not:

  - **Frequency half, still open.** `JSC_largeHeapSize` and a *raised* `JSC_forceRAMSize` are
    **promotion-budget** levers — [`jsc-gc-findings.md`](jsc-gc-findings.md) calls the first "the
    promotion budget itself", and raising either raises the threshold a collection is due at, which
    is a lever on **how often** rather than on how long. Run 42 pulled that budget in the *tightening*
    direction and got nothing; neither has been pulled the other way.
  - **Pause half, still open.** The page's **DOM-wrapper population** is the quantity a
    constraint-solving-dominated pause scales with, so reducing it would shrink **what gets marked**.

  **Both halves therefore have named open levers**, and both are named in "Runs 37-48 — the GC lever,
  and where it is driven from" rather than left implicit.

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
  tried — all of them aimed at paint — are in "Engine levers, measured"; the lever that
  follows is in "Real-time framing". **The next step is not another engine lever and not yet an
  architecture decision** — it is a frontend allocation audit, it is un-run, and it is the owner's.
  #100 gpu-compositing stays open on it.

  **SUPERSEDED by "Runs 37-48 — the GC lever, and where it is driven from".** The frontend allocation
  audit was run, by this investigation and in three forms, and each is a measured null on the ~40 s
  beat (Runs 37, 43, 46). **#100 gpu-compositing does not stay open on it.** Run 48 then found what
  the audit was looking for in the wrong units: the beat is **5 x the park-wait-times rotation
  interval**, so the collection's *frequency* is set by the rotation cadence and the per-tick
  promotion volume behind it — both app-side, both the owner's. **The residual's frequency is located
  in WiseKiosk**, not in the image and not in the hardware; the per-event ~450 ms pause is the
  un-chunkable half and stays with the board. Production keeps the schema default 8 s (owner,
  2026-09-23).

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
  the parser that row names, or from the `AL` record's own fields for Run 36. **Four** obligations
  remain outstanding and are named in "Test runs": the scripts Runs 3 to 7 put on the board are not
  committed here; [`parse_alloc.py`](parse_alloc.py) reads an earlier revision of Run 36's payload
  than the committed probe emits; Run 44's census diff banked no numbers, its named tool
  `profile-churn.mjs` being uncommitted while the committed `webkit-inspect.mjs` implements the same
  experiment; and **Run 47 has no committed capture at
  all**, its arrival series being transcribed into its run block from the session's own output.

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
