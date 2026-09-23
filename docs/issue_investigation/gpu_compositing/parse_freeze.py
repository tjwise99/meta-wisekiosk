#!/usr/bin/env python3
"""Render the frozen-page probe's FZ| window-title payload as a report.

p23_freeze.js stops every app timer and rAF and then measures frame times with
a scheduler it captured before the neuter. A stall that survives on a page whose
DOM cannot change is the engine repainting unasked; a rate that collapses to
zero is driven by the app's own updates.

THE VERDICT IS GATED ON `frozen`. The probe samples a content signature every
~2s; if it ever changes, the page did not freeze and the stall rate says nothing
either way. A zero rate is gated too: at the ~0.04/s baseline a short window
expects no stalls at all, so zero over such a window is not a null result.

Usage: parse_freeze.py <raw.txt> [baseline-rate] [label]
The second and third arguments may be given in either order: a token that parses
as a number is the baseline frames>250ms rate (default 0.04/s), any other token
is the report label (default the filename), matching the sibling parsers' argv[2].

The MP|/FVP|/KC| parsers do not read this payload and must not be pointed at it:
the tag is FZ| and the record carries a freeze-verification flag.
"""
import re
import sys

BUCKETS = ["<50", "50-100", "100-250", "250-500", "500-1k", "1k-2k", ">=2k"]

PAT = (r"FZ\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|BT(\d+)\|RT([\d.]+)"
       r"\|Z(\d)\.(\d+)\.(\d+)\|S(\d+)\.(\d+)\|H([\d.]+)\|B(.*)")

BASELINE_DEFAULT = 0.04  # frames>250ms per second on the unfrozen page
ZERO_RATE = 0.01         # below this the frozen page is not stalling
NEAR_FACTOR = 0.5        # at or above this share of baseline the rate persists
MIN_EXPECTED = 3.0       # stalls the baseline must predict for a zero to mean anything
MIN_SAMPLES = 3          # signature samples, i.e. >=2 comparisons

V_CONTENT = "STALL IS CONTENT-TRIGGERED (a frozen page does not stall)"
V_ENGINE = ("STALL IS A WEBKIT ENGINE PERIODIC FULL-REPAINT (fires on a static "
            "page -- not fixable in the frontend)")
V_MIXED = ("NO RULING -- the frozen page stalls, but far below baseline. The "
           "rate is neither zero nor the baseline, so neither verdict holds; "
           "extend the window and re-run before reading it either way")


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    return dict(
        sec=int(g[0]), frames=int(g[1]), mean=int(g[2]), mx=int(g[3]),
        big=int(g[4]), rt=float(g[5]),
        frozen=int(g[6]), changes=int(g[7]), samples=int(g[8]),
        sig_big=int(g[9]), sig_frames=int(g[10]),
        hist=[int(v) for v in g[11].split(".")],
        stamps=[e for e in g[12].split(",") if ":" in e],
    )


def rate(d):
    return d["big"] / max(d["sec"], 1)


def validate(d, baseline):
    """Return (ok, reason). Whether this run measured anything at all."""
    if d is None:
        return False, "no FZ| payload -- the probe never wrote a title"
    if d["frames"] == 0:
        return False, "zero frames -- the rAF loop never ran"
    if d["samples"] < MIN_SAMPLES:
        return False, (f"only {d['samples']} signature samples -- fewer than "
                       f"{MIN_SAMPLES}, so `frozen` rests on under two "
                       f"comparisons and the freeze is unverified")
    expected = baseline * d["sec"]
    if d["big"] == 0 and expected < MIN_EXPECTED:
        return False, (f"window too short for a zero -- at {baseline}/s a "
                       f"{d['sec']}s window expects only {expected:.1f} stalls, "
                       f"so measuring none proves nothing")
    return True, "ok"


def verdict(d, baseline):
    """(verdict, rate) gated on the freeze having actually happened."""
    r = rate(d)
    if not d["frozen"]:
        return (f"INCONCLUSIVE: page did not freeze ({d['changes']} content "
                f"changes) -- the neuter/clear was incomplete"), r
    if r < ZERO_RATE:
        return V_CONTENT, r
    if r >= NEAR_FACTOR * baseline:
        return V_ENGINE, r
    return V_MIXED, r


def report(d, label, baseline):
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  mean {d['mean']}ms  "
          f"max {d['mx']}ms  ~{d['frames']/max(d['sec'],1):.1f} fps")
    print(f"  frames >250ms: {d['big']}  = {rate(d):.3f}/s  "
          f"(probe reported RT{d['rt']})  baseline {baseline}/s")
    print(f"  freeze: frozen={d['frozen']}  content changes {d['changes']} "
          f"over {d['samples']} signature samples")
    print(f"  signature-sampling frames excluded: {d['sig_frames']} "
          f"({d['sig_big']} of them >250ms -- innerText's forced layout, "
          f"charged to the sample and not to the engine)")

    tot = sum(d["hist"]) or 1
    print("\n  frame-time histogram:")
    for k, v in zip(BUCKETS, d["hist"]):
        print(f"    {k:>8}  {v:6d}  {100*v/tot:5.1f}%  {'#'*int(50*v/tot)}")

    ts = [float(e.split(":")[0]) for e in d["stamps"]]
    print(f"\n  last {len(ts)} frames >250ms at t = {ts or '(none)'}")
    if len(ts) > 1:
        print(f"  inter-arrival: {[round(b-a,1) for a,b in zip(ts,ts[1:])]}")

    ok, reason = validate(d, baseline)
    if not ok:
        print(f"\n*** UNMEASURED: {reason} -- do NOT read this as a null ***")
        return False

    v, r = verdict(d, baseline)
    # The rate is only readable once the freeze is established.
    tail = (f" -- {r:.3f}/s is {r/baseline if baseline else 0:.2f}x the "
            f"{baseline}/s baseline." if d["frozen"] else
            f" -- the {r:.3f}/s rate is not attributable either way.")
    print(f"\nVERDICT: {v}{tail}")
    return True


if __name__ == "__main__":
    baseline, label = BASELINE_DEFAULT, None
    for a in sys.argv[2:]:
        try:
            baseline = float(a)
        except ValueError:
            label = a
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "FZ|" in l]
    if not lines:
        sys.exit("no FZ| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if d is None:
        sys.exit("FZ| did not match:\n" + lines[-1][:400])
    report(d, label or sys.argv[1], baseline)
