---
name: measure-first
description: >-
  Drive a hardware performance problem to ground by measurement instead of inference — pick a
  metric that tracks what a person actually sees, A/B it on the board without the board's own
  drift faking the result, test a hypothesis with a cheap injection before paying for a build,
  and question the mechanism when tuning plateaus. Invoke when the panel stutters or judders,
  when a change has to be proved faster or slower on real hardware, when the numbers say "fine"
  but the owner still sees the fault, when an experiment needs a probe and a parser, or when a
  frontend change has to reach the live board and be measured there.
---

# Measure first, and measure what the eye sees

[`kiosk-debug`](../kiosk-debug/SKILL.md) decides which instrument to reach for. This decides what
counts as an answer once one is in hand, and how to get the next one faster. Every discipline below
is carried, with the run that paid for it, by
[`../../../docs/issue_investigation/gpu_compositing/README.md`](../../../docs/issue_investigation/gpu_compositing/README.md) §"Findings".

## What makes a number an answer

| The tell | The discipline | What skipping it costs |
|---|---|---|
| "That should be smoother — take a look" | Measure the change yourself, then show numbers. The human is a witness, never the instrument. | A judgement nobody can re-run, and a change that ships on an impression. |
| A conclusion reached by arithmetic on other numbers | Label it **DERIVED** or go and measure it. A derivation is a hypothesis with decimal places. | The investigation records one derived framerate explicitly as derived, precisely so nothing rests on it. |
| The mean looks fine; the owner still sees stutter | Wrong metric. Find the one the perception tracks — step size, simultaneity, the freeze tail. | Hours. The holds dominate the mean and hide the whole fault. |
| A metric that does not move when the frontend moves | It is a floor of the board, not of the page. Ablate something you *know* is expensive; if the number holds, the metric is measuring the platform. | `frames>250 ms/s` was board-invariant and was read as a result for several runs. |
| A plain before/after pair | Interleave — `W,A,B,A,B,A`. The board drifts within a single run at flat load (Runs 10 and 11). | A drift-sized effect, in whichever direction the drift went. |
| A clean null | Prove the change landed, **in band**, on the computed value, inside the window that produced the number. | A manipulation the page silently dropped is indistinguishable from one with no effect — the CSP drops a `<style>` element and permits only a style *attribute*. |
| A payload that parsed | Assert it is non-empty. An empty read fails loudly or it reads as a null. | An arm that captured nothing scores as an arm that changed nothing. |
| A parser trusted on its first real payload | Prove it reports **both** outcomes on synthetic payloads first — landed and not-landed. See [`parse_motion_test.py`](../../../docs/issue_investigation/gpu_compositing/parse_motion_test.py). | A discriminator that cannot come out both ways discriminates nothing. |
| A probe that reads computed style per element per frame | Use a minimal rAF counter for absolute fps, and do identical work in every arm. | The probe's own cost scales with N and lands on the arm with more elements — the exact quantity under test. |
| The first block after a restart | Discard it. Page load is not steady state. | A warm-up window averaged into the arm it happened to start. |

Reach for the cheapest experiment that can *fail*. An injection costs minutes; a mirror rebuild
costs a deploy cycle; an image rebuild costs ~4.5 h per
[`../../../CONTRIBUTING.md`](../../../CONTRIBUTING.md) §"Before you change anything".

## Choosing the metric

The metric is the whole game. It must satisfy two things at once: it **moves when the thing under
test moves**, and it **tracks what a person perceives**. One without the other is a number that
argues with the room.

- Judder is **step distance**, and step = velocity ÷ fps. Anything that lowers fps enlarges the
  step, which is why raising move-time backfires and why the mean hides it.
- Simultaneity is a variable, not a constant: cost is per moving element, so a metric read over a
  frame where two things move is not comparable to one where six do. Bucket by it.
- Freezes live in the tail. A mean over a bimodal distribution describes neither mode.

When the numbers say "fine" and the owner still sees the fault, stop tuning and change the metric.

## Cheap injectable proxy before the expensive build

Test the hypothesis with a style-attribute or JS injection *before* committing to a refactor or a
build.

- A solid-fill swap answers "is the cost the content?" — it was not, which killed a bitmap
  refactor before anyone built it.
- A `scrollLeft`-vs-`transform` A/B answers "is the cost the mechanism?" — it was: 14 → 42 fps,
  the whole fix, found with no rebuild at all. See
  [`p18_scroll.js`](../../../docs/issue_investigation/gpu_compositing/p18_scroll.js).
- The injection must survive the page's CSP: `el.style.setProperty(prop, val, 'important')` is the
  form that applies. A `<style>` element or a constructed stylesheet is dropped without error.

A wrong hypothesis caught by a five-minute injection is a multi-hour build not spent.

## Mechanism beats tuning

The worked case: the marquee's cost is content-independent, proportional to area × update rate and
super-linear in pixels. Every tuning knob — velocity, easing, keyframe hold fractions — fails or
backfires, and the fix is a different **mechanism**: scroll-blit instead of transform-repaint.

Two corollaries:

- **When tuning plateaus, question the mechanism**, not the constant.
- **A mechanism claim is retested, not remembered.** GPU compositing measured *worse*, and the
  first compositing test was confounded by an unfixed relayout elsewhere on the page; the finding
  stands because it was re-run cleanly after the confound was removed.

## When the measurement contradicts someone

- **Your own intuition.** Shrinking the animation's hold fractions is a reasonable idea — more
  move-time, smaller steps — and it measured worse, because it raised simultaneity, which dropped
  fps, which enlarged the step. Counterintuitive and real, caught only because it was measured.
- **The owner's directive.** When a requested change backfires, present the data plainly. No
  defence, no burial, no softening the table.
- **A requirement that cannot physically hold.** A 24 fps floor and "every marquee moves at once"
  are incompatible at that resolution, and the measured per-marquee cost says so. Surface the
  conflict with the cost table and the options; never silently satisfy one side.
- **A false premise in the request.** Measure the premise before acting on it — the "dead space"
  was a fixed reservation in the box model, not an unfilled column. Report that; do not comply,
  and do not guess.

## Driving one live board

**One board owner at a time.** Two agents driving the board clobber each other's `~/.surf/script.js`
and each other's cache, and neither capture means anything. The **main thread executes board
captures**; **subagents do the off-board work** — authoring probes and parsers, the mirror build,
implementation, analysis, review — so the capture context stays clean.

- The mirror build **blocks** as `just run-container`. Run
  `docker compose -f compose.dev.yaml up -d --build` **detached**, in a subagent, and have it
  report the served bundle hash.
- The container build does **not** type-check — its Dockerfile runs `vite build` only. Run
  `svelte-check` as its own step.
- Prod is wall-mounted and carries the soak run; bench is the board to abuse. Roles and addresses
  are in gitignored `local/device-identity.md` — read them, and never name one in a tracked file.

The ordered loop and the pre-trust list are [`CHECKLIST.md`](CHECKLIST.md).

## Gotchas that cost real time

- **The page console does not reach the journal on this image.** Exfiltrate through
  `document.title` and read it back with `xprop`, as
  [`run-phase-motion.sh`](../../../docs/issue_investigation/gpu_compositing/run-phase-motion.sh)
  does.
- **`2>/dev/null` on an ssh to a board is blocked** by `.claude/hooks/guard.sh`. A suppressed probe
  cannot distinguish a broken check from a broken device. Let stderr through, or capture it and
  print it on failure.
- **The mirror serves `index.html` with no `Cache-Control` and no `ETag`.** WebKit reuses the
  document across restarts, its content-hashed assets rotate, and a failed module import is
  terminal — the panel stays white. Clearing `~/.surf/cache` is a precondition of the restart, not
  a tidy-up.
- **Leave the board as you found it**: `: > ~/.surf/script.js`, restart, confirm it renders.
- **Record under R1-R3** —
  [`../../../CONTRIBUTING.md`](../../../CONTRIBUTING.md) §"Documentation conventions". Every run names its
  board role, its image commit and its frontend bundle hash; every probe is committed beside the
  investigation; numbers from different runs never share a table.
