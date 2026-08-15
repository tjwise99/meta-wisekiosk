# Reading the soak log — why a fitted slope reported a leak that was not there

A 22.8 h window of `surf`/WebKit RSS read as a steady climb of +127.8 kB/h and was not a leak. This
records the three estimators that were compared, which of them the data supports, and what the valid
comparison is.

## Configuration under test

The live kiosk's browser family RSS, sampled by
[`kiosk-soak.sh`](../../../meta-wisekiosk/recipes-core/kiosk-soak/files/kiosk-soak.sh) every five
minutes into `/data/kiosk-soak.log`. `rss_total` — the whole `surf` + WebKit process family, not
just the launcher — is the series in question; the renderer is a separate process and holds most of
the memory. Two windows: a 6.5 h window and the 22.8 h window of 2026-08-08.

## How the test was performed

Three estimators were computed over the same samples and compared against each other:

- the **endpoint delta**, last sample minus first;
- a **least-squares slope over all samples**;
- the same slope **excluding hour 0**, on the argument that warm-up is not a leak.

The window was then segmented by eye against the hourly means, and the page content at each segment
boundary was compared by screenshot. Finally, `rss_total` was compared between two windows in the
same page state 24 h apart.

## Metrics

Estimators over the 6.5 h window:

| Estimator | Reading |
|---|---|
| endpoint delta | +192.6 kB/h — 4.6 MB/day, indistinguishable from a slow leak |
| fitted slope, all samples | +21.4 kB/h |
| fitted slope, excluding hour 0 | −15.8 kB/h |

The first sample merely happened to be the lowest in the series.

The 22.8 h window read +127.8 kB/h excluding hour 0, with near-monotonic hourly means. Segmented:

| Segment | Slope |
|---|---|
| first eight hours | +24.9 kB/h |
| two-hour step, 1.4 MB | +438.2 kB/h |
| final six hours | +34.4 kB/h |

One line through a step function reports the step as a rate. **A leak does not hold still for eight
hours and then hold still again at a new level** — flat stretches either side of a step are what
distinguish a working-set expansion from accumulation, and the fitted rate cannot.

The step's cause was outside the browser: every wait-time row on the page went from `Closed` to a
live value between 08:00 and 10:00, which is more DOM and more text. Identifying it explains the
step's timing and settles nothing about recurrence — when the rows returned to `Closed`, `rss_total`
stayed **1.66 MB above** the matched closed-state window 24 h earlier. The allocator keeps the pages
rather than returning them.

A healthy window on this image: hourly means inside a ~±150 kB band on a ~165 MB working set, with a
slope whose sign is not stable between windows.

## Changes configured as a result

`kiosk-soak.sh --summary` prints the endpoint delta labelled `NOT a rate`, next to the fit, because
seeing the two together is what makes the difference legible; it also notes that `load1` includes
the sampler's own wake-up. Both are in
[`kiosk-soak.sh`](../../../meta-wisekiosk/recipes-core/kiosk-soak/files/kiosk-soak.sh).

Two guards this investigation calls for are not implemented: a two-point series must report `n/a`
rather than a slope, and gaps in `ts` (consecutive differences should be ~301 s) must be detected
rather than silently fitted across. Both are tracked by issue #27 kiosk-soak --summary: guard the
two-point series and detect gaps in ts.

The valid leak comparison is matched content states 24 h apart — closed-state against closed-state —
never before-and-after a content change, which guarantees a difference and answers a question nobody
asked. None of this detects a frozen page: every field would look identical if the display had been
showing a stale render for hours, which is what
[`screenshot_capture_fbgrab`](../screenshot_capture_fbgrab/README.md) covers.
