#!/usr/bin/env python3
"""Render the forced-full-repaint probe's FVP| window-title payload as a report.

p21_fullpaint.js changes a full-viewport overlay's background-color every
FORCE_EVERY frames and tags the FOLLOWING frame FORCED, because WebKit repaints
after the rAF callback returns. Every other frame is BASELINE. FORCED is then
the price of one deliberate full-viewport repaint plus the page's ordinary cost,
BASELINE is that ordinary cost alone, and the difference isolates the repaint.

The verdict compares the FORCED distribution against a reference stall -- the
residual ~1/s engine-dominated frame stall this investigation is chasing,
measured at 294-476ms. If forcing a whole-viewport repaint costs about what the
stall costs, the stall is consistent with being one; if forcing it is far
cheaper, the stall is something larger than a single viewport repaint.

Usage: parse_fullpaint.py <raw.txt> [reference-ms] [label]
The second and third arguments may be given in either order: a token that parses
as a number is the reference stall (default 450ms), any other token is the
report label (default the filename), matching the sibling parsers' argv[2].

The KP*/MP*/PF| parsers do not read this payload and must not be pointed at it:
the tag is FVP| and the record is two labelled distributions, not a frame list.
"""
import re
import sys

PAT = (r"FVP\|(\d+)\|f(\d+)"
       r"\|FORCED n:(\d+),mean:(\d+),p50:(\d+),p90:(\d+),max:(\d+),top:([\d.]*)"
       r"\|BASE n:(\d+),mean:(\d+),p50:(\d+),p90:(\d+),max:(\d+)")

REF_DEFAULT = 450.0
MATCH_FACTOR = 2.0       # forced within this factor of the reference ~matches it

V_MATCH = "FULL-VIEWPORT REPAINT ~MATCHES THE STALL (mechanism confirmed)"
V_CHEAP = ("forced full repaint is cheaper than the stall -- stall is larger "
           "than one viewport repaint")
V_DEAR = ("forced full repaint is MORE expensive than the stall -- the overlay "
          "repaint is not the stall's mechanism as priced here")


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    top = [int(v) for v in g[7].split(".") if v != ""]
    return dict(
        sec=int(g[0]), frames=int(g[1]),
        forced=dict(n=int(g[2]), mean=int(g[3]), p50=int(g[4]),
                    p90=int(g[5]), max=int(g[6]), top=top),
        base=dict(n=int(g[8]), mean=int(g[9]), p50=int(g[10]),
                  p90=int(g[11]), max=int(g[12])),
    )


def validate(d):
    """Return (ok, reason). A run with no forced frames priced nothing."""
    if d is None:
        return False, "no FVP| payload -- the probe never wrote a title"
    if d["frames"] == 0:
        return False, "zero frames -- the rAF loop never ran"
    if d["forced"]["n"] == 0:
        return False, ("zero FORCED frames -- no repaint was ever forced, so "
                       "there is no full-viewport repaint cost in this run")
    if d["base"]["n"] == 0:
        return False, ("zero BASELINE frames -- nothing to subtract, so the "
                       "forced cost cannot be isolated from the page's own")
    return True, "ok"


def verdict(d, ref):
    """(verdict, forced p50 / reference) from the FORCED p50 against `ref`."""
    p50 = d["forced"]["p50"]
    ratio = p50 / ref if ref else 0.0
    if ratio > MATCH_FACTOR:
        return V_DEAR, ratio
    if ratio < 1.0 / MATCH_FACTOR:
        return V_CHEAP, ratio
    return V_MATCH, ratio


def report(d, label, ref):
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  "
          f"~{d['frames']/max(d['sec'],1):.1f} fps  reference stall {ref:.0f}ms")

    ok, reason = validate(d)

    f, b = d["forced"], d["base"]
    print(f"\n  {'':>8}  {'n':>6}  {'mean':>7}  {'p50':>7}  {'p90':>7}  {'max':>7}")
    for name, s in (("FORCED", f), ("BASELINE", b)):
        print(f"  {name:>8}  {s['n']:6d}  {s['mean']:7d}  {s['p50']:7d}  "
              f"{s['p90']:7d}  {s['max']:7d}")
    print(f"\n  top FORCED frames (ms): "
          f"{', '.join(str(v) for v in f['top']) or '(none)'}")

    if not ok:
        print(f"\n*** UNMEASURED: {reason} -- do NOT read this as a null ***")
        return False

    d50 = f["p50"] - b["p50"]
    dmean = f["mean"] - b["mean"]
    print(f"\nisolated full-viewport repaint cost (forced - baseline): "
          f"{d50}ms at p50, {dmean}ms at the mean")

    v, ratio = verdict(d, ref)
    print(f"VERDICT: {v} -- forced p50 {f['p50']}ms is {ratio:.2f}x the "
          f"{ref:.0f}ms reference stall (mean {f['mean']}ms, "
          f"{f['mean']/ref if ref else 0:.2f}x).")
    return True


if __name__ == "__main__":
    ref, label = REF_DEFAULT, None
    for a in sys.argv[2:]:
        try:
            ref = float(a)
        except ValueError:
            label = a
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "FVP|" in l]
    if not lines:
        sys.exit("no FVP| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if d is None:
        sys.exit("FVP| did not match:\n" + lines[-1][:400])
    report(d, label or sys.argv[1], ref)
