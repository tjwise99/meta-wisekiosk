# The loop, and what to check before trusting a number

The operational form of [`SKILL.md`](SKILL.md), which holds the reasoning behind each step.

## The loop

1. **State the hypothesis and the metric that can falsify it**, and decide which number ends the
   question — before any capture. A metric chosen after the data is a metric fitted to it.
2. **Author probe and parser off-board** (subagent). Probe: minimal per-frame work, identical in
   every arm, interleaved arms `W,A,B,A,B,A`, an in-band landing check on the computed value, a
   payload emitted through `document.title`.
3. **Prove the parser both ways** on synthetic payloads — landed and not-landed — before it sees a
   board number.
4. **Frontend change?** Edit, then rebuild the mirror detached
   (`docker compose -f compose.dev.yaml up -d --build`, in a subagent) and note the served bundle
   hash. Run `svelte-check` separately; the container build does not type-check.
5. **Deploy the probe** to `~/.surf/script.js`.
6. **Clear `~/.surf/cache`, then restart the kiosk.** In that order — the restart re-fetches.
7. **Verify the intended bundle actually loaded** — grep the board's WebKit cache for the hash —
   before trusting anything the capture produces.
8. **Capture**, long enough that the warm-up block is a discard rather than a fraction of an arm.
9. **Read the payload back with `xprop`** and assert it is non-empty. An empty read fails the run;
   it never scores as a null.
10. **Parse.** Drop every block whose landing check failed; an arm with no landed blocks is
    unmeasured, not unchanged.
11. **Clean the board**: `: > ~/.surf/script.js`, restart, confirm it renders.
12. **Record under R1-R3**: board role, image commit, bundle hash, one board × one build × one
    test per table.

## Before you trust a number

- [ ] Interleaved A/B/A — not a before/after pair?
- [ ] Landing check in band, on the **computed** value, inside the same window as the number?
- [ ] Parser proven to report both outcomes on synthetic payloads?
- [ ] Payload asserted non-empty, with an empty read failing loudly?
- [ ] Probe not confounding — no per-element per-frame computed style, identical work in each arm?
- [ ] Warm-up block discarded?
- [ ] Bundle hash confirmed loaded on the board?
- [ ] Metric moves when the page moves, and tracks what a person sees?
- [ ] Measured, not derived — or labelled **DERIVED** where it is stated?
- [ ] Board left clean, and the run recorded with its board role, image commit and bundle hash?
