# JSC GC levers for the ~500 ms full-GC STW on armv6 / WebKit 2.44.3

> **SUPERSEDED IN PART — read this first (2026-09-23).** This document was written **before Run 45
> and Run 47** and its recommendations were overtaken by them. Three things in it are no longer live
> advice, and each is marked in place below rather than deleted:
>
> - **"The only runtime lever is frequency — and it is a real one"** and **"The single best first
>   thing to try"**. Run 45 ran that lever at ÷16 and **the period did not move at all**. The
>   `T = sqrt(L/(g·P))` model this document derives predicts ~4x; the measurement is ~1x. The model
>   does not describe this board's cadence, and neither the timer nor the growth path is the binding
>   constraint.
> - **The "Reconciling with the Run-42 evidence" verdict** — *"the growth trigger was never the
>   binding constraint; the timer was"* — is falsified by Run 45 in the same stroke.
> - **The "Fallback: compile-time" recommendation to persist the environment option** via a systemd
>   `Environment=` drop-in is a recommendation to ship a tuned constant to a wall-mounted unit for an
>   effect Run 45 measured as zero. **Do not.**
>
> What this document still gets right, and what the README leans on it for, is the **source reading**:
> the `useConcurrentGC` gating and the initialize/override/recompute ordering, the synchronous
> scheduler, the absence of a sweeper option's slice control, and which options are dead code on this
> build. Those were re-derived independently in the extracted tree, file and line, and hold.
> Three wording errors found in that pass are corrected in place below.
>
> The standing conclusion is in the README's "Runs 37-48 — the GC lever, and where it is driven
> from", and it moved again on 2026-09-23: **no JSC lever reaches the trigger, but a frontend one
> does.** Run 48 varies the application's `rotation_interval_seconds` and the beat follows it at
> **5 x the rotation tick** (40.0 s at 8 s, 60.0 s at 12 s), so the collection's *frequency* is set
> by the frontend's rotation cadence rather than by anything in this document's subject matter. What
> this file's analysis still owns is the other half — the **pause**, which armv6 cannot chunk.

All source claims below were read from the **`webkitgtk-2.44.3` tag of `WebKit/WebKit`**, not from
main and not from a newer release. Every file cited is also present in the tree this image was built
from, under
`build/tmp-raspberrypi0-wifi/work/arm1176jzfshf-vfp-poky-linux-gnueabi/webkitgtk3/2.44.3/webkitgtk-2.44.3/`,
which is where a reader should check them — the same path the README's JSC-source subsection uses.

## Headline: the two top candidates are dead on this device, by construction

`Source/JavaScriptCore/runtime/Options.cpp`, in `notifyOptionsChanged()`:

```c++
#if !CPU(X86_64) && !CPU(ARM64)
    Options::useConcurrentGC() = false;
    Options::forceUnlinkedDFG() = false;
    Options::useWebAssemblySIMD() = false;
```

and, 120 lines further down in the same function:

```c++
    if (!Options::useConcurrentGC())
        Options::collectContinuously() = false;
```

armv6 is `CPU(ARM)` — neither `X86_64` nor `ARM64`. So **`useConcurrentGC` is forced off and
`collectContinuously` is forced off with it.**

This is not avoidable from the environment. `Options::initialize()` runs in a fixed order:

1. defaults from `OptionsList.h`
2. `overrideDefaults()`
3. **`JSC_*` environment overrides** (`overrideOptionWithHeuristic`, the non-`PLATFORM(COCOA)` path)
4. **`notifyOptionsChanged()`** — the block above

Step 4 runs *after* step 3 and unconditionally assigns. `JSC_useConcurrentGC=true` and
`JSC_collectContinuously=true` are parsed, applied, and then silently overwritten. They will produce
no warning and no effect.

### What that forces downstream — `Heap.cpp` ~line 393

```c++
    if (Options::useConcurrentGC()) {
        ... StochasticSpaceTimeMutatorScheduler / SpaceTimeMutatorScheduler
    } else {
        // We simulate turning off concurrent GC by making the scheduler say that the world
        // should always be stopped when the collector is running.
        m_scheduler = makeUnique<SynchronousStopTheWorldMutatorScheduler>();
    }
```

and `SynchronousStopTheWorldMutatorScheduler::timeToResume()`
(`heap/SynchronousStopTheWorldMutatorScheduler.cpp:59-62`) returns `now()` when the state is `Normal`
and `MonotonicTime::infinity()` otherwise — so it returns infinity **conditionally**, in the
`Stopped` state, not unconditionally. `Heap::runFixpointPhase` calls
`visitor.drainInParallel(m_scheduler->timeToResume())` — with an infinite deadline, **the mark drains
to completion in one unbroken stop-the-world.** There is no resume point inside it.

## Verdict on "can a runtime option bound the pause?" — No

Every option the brief nominated for bounding per-increment mutator time is reachable only through
the concurrent path, which does not exist here:

| Option | Where it is consumed | Live on this build? |
|---|---|---|
| `minimumGCPauseMS`, `gcPauseScale` | `StochasticSpaceTimeMutatorScheduler` ctor only | **No** — scheduler never constructed |
| `maximumMutatorUtilization`, `minimumMutatorUtilization`, `epsilonMutatorUtilization` | both SpaceTime schedulers only | **No** |
| `concurrentGCPeriodMS`, `concurrentGCMaxHeadroom` | both SpaceTime schedulers only | **No** |
| `gcIncrementBytes`, `gcIncrementMaxBytes`, `gcIncrementScale` | `Heap::performIncrement`, which opens with `if (!m_objectSpace.isMarking()) return;` | **No** — the mutator never runs while marking |
| `collectContinuously`, `collectContinuouslyPeriodMS` | forced off (above) | **No** |
| `useConcurrentGC` | forced off (above) | **No** |

Note `overrideDefaults()` already sets `useStochasticMutatorScheduler() = false`,
`minimumGCPauseMS() = 1`, `maximumMutatorUtilization() = 0.6` and `gcIncrementScale() = 1` on
`numberOfProcessorCores() <= 1`. Those assignments happen and are then irrelevant — an easy trap if
you read `overrideDefaults()` and stop there.

**`useIncrementalSweeper` and `sweepMaxDuration` do not exist in 2.44.** ~~There is no sweeper option
in `OptionsList.h` at all.~~ **CORRECTED:** that second sentence is false. `sweepSynchronously`
**does** exist, at `OptionsList.h:378`, consumed at `Heap.cpp:2597-2600`. It does not tune the slice,
and setting it true *lengthens* the pause, so the verdict below survives unchanged — but the
statement did not. The sweeper's slicing is hardcoded in `heap/IncrementalSweeper.cpp`:

```c++
static constexpr Seconds sweepTimeSlice = 10_ms;
static constexpr double sweepTimeTotal = .10;
```

Sweeping is therefore *already* incremental at 10 ms slices and is **not** part of the 500 ms pause.
The pause is mark + constraint solving.

## So the only runtime lever is frequency — and it is a real one

> **SUPERSEDED by Run 45 (2026-09-23).** It is not a real one. `percentCPUPerMBForFullTimer` was run
> at ÷16 on the board and the period moved by **nothing** — 40.0 s before and after, phase shifted
> ~1.5 s. The heading's claim and the model below it are kept as the reasoning that chose the
> experiment, not as advice. **The ~40 s cadence is not the full-GC activity timer**, and Run 47 then
> excluded WebKit's memory-pressure path as well, so what does set it is unidentified.

The ~40 s cadence is the full-GC activity timer, exactly as suspected. `heap/GCActivityCallback.cpp`:

```c++
void GCActivityCallback::didAllocate(JSC::Heap& heap, size_t bytes)
{
    double bytesExpectedToReclaim = static_cast<double>(bytes) * deathRate(heap);
    Seconds newDelay = lastGCLength(heap) / gcTimeSlice(bytesExpectedToReclaim);
    scheduleTimer(newDelay);
}
```

with `FullGCActivityCallback::gcTimeSlice`:

```c++
    return std::min((static_cast<double>(bytes) / MB) * Options::percentCPUPerMBForFullTimer(),
                    Options::collectionTimerMaxPercentCPU());
```

Defaults: `percentCPUPerMBForFullTimer = 0.0003125` (`OptionsList.h:367`),
`collectionTimerMaxPercentCPU = 0.05` (`OptionsList.h:369`).

**`collectionTimerMaxPercentCPU` is a no-op here — *at its default*.** The `min()` only bites at
`bytesExpectedToReclaim = 0.05 / 0.0003125 = 160 MB`, which this heap never reaches, so raising it
does nothing. **CORRECTED:** *lowering* it is not a no-op. `gcTimeSlice` returns a `min()`, so
`delay >= lastGCLength / C` always holds; drive `C` down far enough and it becomes the binding term
and imposes a hard linear cadence floor. What kills it as a lever is a different fact:
`EdenGCActivityCallback.cpp:68` shares the same cap, so lowering it stretches eden collections too
and the two cannot be decoupled.

`percentCPUPerMBForFullTimer` is the live term. `scheduleTimer` only ever shortens the pending delay,
and the deltas telescope, so the timer fires at the fixed point `T` where `newDelay(T) = T`. With
`b(T) = g·T` (old-gen growth rate `g` in MB/s, already multiplied by `deathRate`):

```
T = L / (g·T·P)   →   T = sqrt( L / (g·P) )
```

`L` = `lastFullGCLength`, `P` = `percentCPUPerMBForFullTimer`. Sanity-check against the observed
numbers: `L = 0.5 s`, `T = 40 s` ⟹ `g = 1.0 MB/s` of old-gen growth. That is a very plausible
floating-garbage rate for Svelte reactive churn, so the model fits the board.

**Consequence: `T ∝ 1/sqrt(P)`, not `1/P`.** Dividing `P` by 16 lengthens the cadence ~4×, not 16×.
Anyone predicting a linear response will call the run a failure.

## Reconciling with the Run-42 evidence

Run-42 set `forceRAMSize=32MB`, `smallHeapGrowthFactor=1.05`, `largeHeapGrowthFactor=1.05` and saw
no cadence change. That is exactly what the code predicts, and it carries a warning for the next run:

- Defaults are `smallHeapGrowthFactor = 2`, `largeHeapGrowthFactor = 1.24`. **1.05 is *tighter* than
  default**, i.e. it makes the growth-based full-GC trigger fire *sooner*. It changed nothing ⟹ the
  growth trigger was never the binding constraint; the timer was. Good, that confirms the diagnosis.

  > **SUPERSEDED by Run 45 (2026-09-23).** The last clause is false: Run 45 changed the timer 16x
  > and the period did not move either, so it was not the timer. The two runs exclude each other's
  > explanation and **the trigger is unidentified**. Stronger still — `forceRAMSize=32MB` drives
  > `minHeapSize` from 32 MB to 8 MB, a **4x cut** to the promotion budget, which a promotion-paced
  > cadence owes a ~4x shorter period for. Run 42 is therefore a **falsification** of the promotion
  > model rather than a null. What survives is the asymmetry: a constraint tightened 4x with no
  > response is slack, so loosening it is correspondingly unlikely to help.
- **But those settings will fight the timer lever.** Once you slow the timer, the growth path becomes
  binding: `Heap.cpp` ~2444, after each eden, `if (edenToOldGenerationRatio < 1.0/3.0)
  m_shouldDoFullCollection = true`, plus `m_maxHeapSize = proportionalHeapSize(currentHeapSize,
  m_ramSize)`. Tight growth factors and a small `forceRAMSize` both pull that trigger in.
- So for the next run: **drop the 1.05 growth factors** (back to default, or higher), and consider
  *raising* `forceRAMSize` rather than lowering it. Keeping Run-42's settings alongside the timer
  lever is the most likely way to get a false negative.

## Ranked shortlist of `JSC_` env options

Spelling is `JSC_` + the exact case-sensitive option name (`overrideOptionWithHeuristic` builds
`"JSC_" #name_`). All options below are `Availability::Normal`, so they are honoured in a release
build — `Options::isAvailable` is not even consulted for `Normal`. `Double` values are parsed with
`sscanf("%lf")`, so scientific notation is accepted.

**This applies to `logGC` too, and the README spent nine runs believing otherwise.** `logGC` is
declared `v(GCLogLevel, logGC, GCLogging::None, Normal, …)` at **`OptionsList.h:381`** — availability
`Normal`, so it is honoured in this release build — and its ~30 emission sites in `heap/` are
ordinary runtime conditions with no `#if` guard. **It is not compiled out.** What *is* compiled out
is `dataLogLnIf(verbose, …)` under a `constexpr bool verbose = false`, which is a different function
and a different thing. The reason a `JSC_logGC=1` run returned three lines is **where the output
goes**: `dataLog` writes to the **WebProcess's own stderr** (`DataLog.cpp:151`), which a capture
reading the UI-process unit's journal never sees. The named fix is `WTF_DATA_LOG_FILENAME`
(`DataLog.cpp:91`, auto-appending `.%pid.txt`) **in the WebProcess environment** — and it must point
somewhere the WebProcess sandbox permits, which `/data` is not: Run 47 tried exactly that and the
open was denied. One successful capture of this prints, per collection, the scope, the heap capacity
in kB, the mark-stack sizes and `p=<pause>ms`, and it is the cheapest unrun experiment in the record.

| # | Env var | Effect | Risk |
|---|---|---|---|
| 1 | `JSC_logGC=1` | **Instrumentation, not a fix.** Prints per collection: `START`, scope (`FullCollection`/`EdenCollection`), heap capacity in kb, mark-stack sizes, and at the end `p=<pause>ms (max <maxpause>), cycle <cycle>ms END]`. This is direct ground truth for the pause, the cadence and the heap capacity. | **CORRECTED:** not "stderr volume into the journal" — `dataLog` writes to the **WebProcess's** stderr, which a capture reading the UI-process unit's journal never sees. That routing is why nine runs of this record read an empty trace; see the note above this table. Run it *with* whatever you test, and capture the WebProcess's stderr or redirect it to a sandbox-writable path. |
| 2 | `JSC_percentCPUPerMBForFullTimer=1.953125e-05` (default `0.0003125`, i.e. ÷16) | ~~The only live cadence lever. Predicted ~40 s → ~160 s (`1/sqrt`).~~ **SUPERSEDED — Run 45 ran exactly this and the period did not move at all.** It is not a live cadence lever; the prediction failed. Does not shorten the pause either. | **Do not spend a run on it — it has been spent.** |
| 3 | Drop `JSC_smallHeapGrowthFactor` / `JSC_largeHeapGrowthFactor` overrides; raise `JSC_forceRAMSize` above 32 MB | Removes the growth-trigger ceiling that would otherwise cancel #2. | RSS rises. Run-42's `VmRSS` reads **89984 kB**; the 106380 kB it is often quoted against is **Run 37's** capture, a different probe and bundle, and no same-configuration baseline was taken — the landing is indicative rather than controlled (the README corrects this in three places). **Still un-run**, and still the lever the README names as enumerated-but-untaken. |
| 4 | `JSC_recordGCPauseTimes=true` | Secondary instrumentation. | None. |
| 5 | `JSC_collectionTimerMaxPercentCPU` | **Predicted no-op *at or above its default*** — the `min()` never selects it at this heap size, so *raising* it does nothing. **CORRECTED:** *lowering* it is not a no-op — `delay >= lastGCLength / C` always holds, so a small enough `C` becomes binding and imposes a hard cadence floor. See the corrected note under "the only runtime lever is frequency". | What kills it as a lever is not inertness: `EdenGCActivityCallback.cpp:68` shares the same cap, so lowering it stretches eden collections too and the two cannot be decoupled. |
| 6 | `JSC_useConcurrentGC`, `JSC_collectContinuously`, `JSC_collectContinuouslyPeriodMS`, `JSC_gcIncrement*`, `JSC_minimumGCPauseMS`, `JSC_maximumMutatorUtilization`, `JSC_concurrentGC*` | **Proven no-ops on armv6** (clobbered or on a dead code path). Do not spend a run on them. | — |
| 5b | `JSC_largeHeapSize` (default 32 MB, `OptionsList.h:204`) | **Missing from this list when it was written, and it is the promotion budget itself.** `minHeapSize` is `min(largeHeapSize, ramSize x smallHeapRAMFraction [0.25, :206])`, the VM is `HeapType::Large`, and on a 512 MB board the 32 MB term binds. This is the lever #3 above should have named. | RSS rises. Unlikely to help — Run 42 tightened the same constraint 4x with no response, so it is slack — but it is one environment variable and one capture, and it is **un-run**. |
| 7 | `JSC_numberOfGCMarkers=2` | Would create one helper visitor. `computeNumberOfWorkerThreads` = `min(cores, max)` = **1** on this board, so today there are **zero** parallel visitors and marking runs entirely on the mutator thread. Forcing 2 only time-slices one core and adds sync overhead; it cannot shorten a pause on a single core. | Likely a regression. Not recommended. |

## The single best first thing to try

> **SUPERSEDED by Run 45 (2026-09-23).** This is Run 45, and its prediction failed: the cadence did
> not move ~4x, it did not move at all. The section's own fallback — *"If instead the cadence barely
> moves, the growth trigger has become binding and lever #3 is the next step"* — was never taken, and
> that is recorded as an open lever in the README rather than closed here. The `JSC_logGC=1` half of
> the recommendation was **right and is still un-cashed**: see the note under the table below.

```
JSC_logGC=1 JSC_percentCPUPerMBForFullTimer=1.953125e-05
```

with the Run-42 `smallHeapGrowthFactor` / `largeHeapGrowthFactor=1.05` overrides **removed**.

**Prediction if it works:** the journal shows `FullCollection` lines roughly **4×** further apart
(~40 s → ~150-170 s) while the `p=` value on each stays at ~500 ms — i.e. the freeze becomes rare,
not shorter. If instead the cadence barely moves, the growth trigger has become binding and lever #3
is the next step.

**Be honest about what this buys:** it cannot meet the stated ≤250 ms goal. It converts "a 500 ms
freeze every 40 s" into "a 500 ms freeze every ~2.5 min". Whether that is acceptable is an owner
call, not one I can make from the source.

`JSC_logGC=1` alone is also worth one run on its own merits: `p=` vs `cycle` separates the true
stop-the-world from the whole cycle, and the printed mark-stack sizes and `capacity()` will say
whether 500 ms is really marking ~2 MB of live objects (which would be implausibly slow, ~4 MB/s) or
is dominated by per-block work proportional to heap *capacity* or by WebCore's marking constraints
over DOM wrappers/opaque roots. That distinction changes which lever matters and is cheap to get.

## Concurrent-GC-on-single-core verdict

Two separate findings, worth keeping distinct:

1. **It is not "ineffective on one core" — it is compiled out of the decision entirely.** The gate is
   on *architecture* (`!CPU(X86_64) && !CPU(ARM64)`), not on core count. Even on a 4-core armv7 board
   it would be off. This fully explains the observed behaviour: a pure, unsplittable STW full GC.
2. **Even if it were on, one core would blunt it.** `numberOfGCMarkers = min(cores, 8) = 1` here, so
   there are no helper threads, and the "concurrent" collector thread would time-slice with the
   mutator. The SpaceTime scheduler bounds the *mutator pause* rather than total wall time, so it
   would still help with the freeze — but at a throughput cost on an already-saturated core.

## Fallback: compile-time

**What I do *not* recommend.** The mechanically smallest patch is to exempt `CPU(ARM)` from the
concurrent-GC gate in `Source/JavaScriptCore/runtime/Options.cpp`. **Do not ship this.** The gate is
a correctness bar, not a performance heuristic: on 32-bit, `JSValue` is a two-word tag+payload pair
that cannot be loaded or stored atomically, so a concurrent marker can observe a **torn JSValue** —
a fresh tag against a stale payload — and follow it as a pointer. WebKit has a documented history of
exactly this hazard even on 64-bit, where it required GC-safe `memcpy`/`memmove`/`memset` helpers for
concurrently-scanned storage. Turning this on for armv6 is memory corruption on a wall-mounted unit
with no remote undo. Flagging it only so nobody rediscovers the one-line diff and thinks it is free.

**What I do recommend, and it is not a JSC patch.** Since the only working lever is an environment
option, the compile-time work is *persisting the environment*, not modifying JavaScriptCore — a
`systemd` drop-in / `Environment=` line on the kiosk service, whatever this image's mechanism is.
That keeps the change reversible by OTA and inspectable in the image, instead of burying a tuned
constant inside a 4.5 h WebKit rebuild.

> **SUPERSEDED by Run 45 (2026-09-23) — do not act on the paragraph above.** There is no working
> lever to persist. `percentCPUPerMBForFullTimer` at ÷16 moved the period by nothing, so persisting
> it into the image would ship a tuned constant to a wall-mounted unit for a measured-zero effect.
> The reasoning about *where* a persisted environment option belongs — a `systemd` drop-in rather
> than a recipe patch — is still right, and applies to whatever option a future run does earn.

If a baked default is nonetheless wanted, the equivalent one-line recipe patch is against
`Source/JavaScriptCore/runtime/OptionsList.h` line 367:

```
-    v(Double, percentCPUPerMBForFullTimer, 0.0003125, Normal, nullptr) \
+    v(Double, percentCPUPerMBForFullTimer, 1.953125e-05, Normal, nullptr) \
```

It is strictly worse than the env route — same effect, but it invalidates WebKit and costs the full
rebuild, and it cannot be tuned on the board afterwards. There is no `EXTRA_OECMAKE` define for any
of this; these are runtime options, not build flags.

**No safe compile-time change bounds the pause.** Splitting the STW requires resuming the mutator
mid-mark, which requires the concurrent-GC load/store barrier discipline, which is what the
architecture gate exists to withhold. Making `SynchronousStopTheWorldMutatorScheduler::timeToResume()`
return a deadline would "work" and would corrupt the heap.

## Confidence and caveats

Confirmed by reading the 2.44.3 source directly — high confidence:

- the `useConcurrentGC` / `collectContinuously` gating and the initialize/override/recompute ordering
- `SynchronousStopTheWorldMutatorScheduler::timeToResume()` returning infinity **in the `Stopped`
  state** — **CORRECTED** from the unconditional form this list first carried; it returns `now()`
  when the state is `Normal`. The consequence for an uninterrupted mark is unchanged.
- the hardcoded 10 ms sweep slice — **CORRECTED**: the claim that there is *no* sweeper option is
  false, `sweepSynchronously` exists at `OptionsList.h:378`. It does not tune the slice and setting
  it true lengthens the pause, so the verdict stands and the statement did not.
- which options the SpaceTime schedulers and `Heap::performIncrement` consume, and their guards
- `gcTimeSlice` / `didAllocate` arithmetic and the option defaults
- `logGC` output format and `Normal`-availability env override in release builds

**Not confirmed, flagged as such:**

- The `T = sqrt(L/(g·P))` fixed point is my derivation from `scheduleTimer`'s telescoping deltas. It
  reproduces the observed 40 s from plausible inputs, but it is a model, not a measurement — treat
  the "~4×" as an order-of-magnitude prediction, and let `JSC_logGC=1` settle it.
- `g = 1.0 MB/s` is back-solved from the observed cadence, not measured.
- `Heap::scheduleOpportunisticFullCollection()` and `m_isInOpportunisticTask` exist in 2.44's
  `Heap.h`/`Heap.cpp`, but there is **no** JSC option controlling them and I did not trace whether
  WebCore 2.44 drives them on this port. If it does, some full GCs may be idle-scheduled rather than
  timer-scheduled. It would not change the pause either way — the collection is still fully STW.
- I did not confirm the 500 ms is mark-dominated rather than constraint-solver- or capacity-
  dominated. `JSC_logGC=1` answers this and nothing in the source does.

## Sources

- WebKit source at tag `webkitgtk-2.44.3` (pinned, not main):
  [`runtime/Options.cpp`](https://github.com/WebKit/WebKit/blob/webkitgtk-2.44.3/Source/JavaScriptCore/runtime/Options.cpp),
  [`runtime/OptionsList.h`](https://github.com/WebKit/WebKit/blob/webkitgtk-2.44.3/Source/JavaScriptCore/runtime/OptionsList.h),
  [`heap/Heap.cpp`](https://github.com/WebKit/WebKit/blob/webkitgtk-2.44.3/Source/JavaScriptCore/heap/Heap.cpp),
  [`heap/GCActivityCallback.cpp`](https://github.com/WebKit/WebKit/blob/webkitgtk-2.44.3/Source/JavaScriptCore/heap/GCActivityCallback.cpp),
  [`heap/FullGCActivityCallback.cpp`](https://github.com/WebKit/WebKit/blob/webkitgtk-2.44.3/Source/JavaScriptCore/heap/FullGCActivityCallback.cpp),
  [`heap/IncrementalSweeper.cpp`](https://github.com/WebKit/WebKit/blob/webkitgtk-2.44.3/Source/JavaScriptCore/heap/IncrementalSweeper.cpp),
  [`heap/SynchronousStopTheWorldMutatorScheduler.cpp`](https://github.com/WebKit/WebKit/blob/webkitgtk-2.44.3/Source/JavaScriptCore/heap/SynchronousStopTheWorldMutatorScheduler.cpp),
  [`heap/StochasticSpaceTimeMutatorScheduler.cpp`](https://github.com/WebKit/WebKit/blob/webkitgtk-2.44.3/Source/JavaScriptCore/heap/StochasticSpaceTimeMutatorScheduler.cpp)
- [Understanding Garbage Collection in JavaScriptCore From Scratch — WebKit blog](https://webkit.org/blog/12967/understanding-gc-in-jsc-from-scratch/) (Riptide design: generational, mostly-concurrent, non-compacting)
- [JavaScriptCore CSI: A Crash Site Investigation Story — WebKit blog](https://webkit.org/blog/6411/javascriptcore-csi-a-crash-site-investigation-story/)
- Torn-JSValue-under-concurrent-marking hazard, e.g. [oven-sh/WebKit #564 — `JSArray::setLength` clearing live butterfly slots racing the concurrent marker](https://github.com/oven-sh/WebKit/pull/564)
