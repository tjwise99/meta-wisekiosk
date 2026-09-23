#!/usr/bin/env python3
"""Render the forced-layout profile probe's PF| window-title payload as a report.

p20_profile.js times ONE synchronous layout flush per frame (`tForce`) alongside
the frame time (`dt`). On a stall frame, tForce as a fraction of dt is the
attribution: a large fraction says the frame was spent flushing a batched layout,
a small fraction says the cost is paint/raster/compositing, which a forced-layout
timer cannot see at all.

The probe forces layout every frame, so a run with NO frames over 250ms is not a
null -- continuous flushing dissolving the batch is itself a layout result, and
is reported as such.

The KP*/MP* parsers do not read this payload and must not be pointed at it: the
tag is PF|, and the per-frame record is three fields (t, dt, tForce) rather than
p7_min.js's two.

The `BIG<n>250ms` field embeds its own threshold in the literal, so the count is
matched with the trailing `250ms|` anchored -- `BIG12250ms|` is 12 frames over
250ms, not 12250.
"""
import re
import sys

PAT = (r"PF\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|BIG(\d+)250ms"
       r"\|LT(NA|\d+)/(NA|\d+)\|W(.*)")

LAYOUT_FRACTION = 0.50   # tForce/dt above this attributes the stall to layout
BIG_MS = 250

V_LAYOUT = "STALL IS FORCED-LAYOUT"
V_PAINT = "STALL IS NOT LAYOUT (paint/other) -- needs the inspector timeline"
V_SUPPRESSED = ("STALL SUPPRESSED by forcing layout every frame -- consistent "
                "with a batched-layout flush")


def worst(s):
    """'2.1:455:410,10.2:451:405' -> [{t, dt, force}], biggest dt first."""
    out = []
    for e in filter(None, s.split(",")):
        f = e.split(":")
        if len(f) != 3:
            continue
        try:
            out.append(dict(t=float(f[0]), dt=int(f[1]), force=int(f[2])))
        except ValueError:
            continue
    out.sort(key=lambda e: -e["dt"])
    return out


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    return dict(sec=int(g[0]), frames=int(g[1]), avg=int(g[2]), max=int(g[3]),
                big=int(g[4]),
                lt=None if g[5] == "NA" else int(g[5]),
                ltmax=None if g[6] == "NA" else int(g[6]),
                worst=worst(g[7]))


def validate(d):
    """Return (ok, reason). A run that recorded no frames measured nothing."""
    if d is None:
        return False, "no PF| payload -- the probe never wrote a title"
    if d["frames"] == 0:
        return False, ("zero frames -- the rAF loop never ran, so dt and tForce "
                       "are undefined")
    if d["big"] > 0 and not [e for e in d["worst"] if e["dt"] > BIG_MS]:
        return False, (f"BIG{d['big']} frames over {BIG_MS}ms counted but none "
                       f"retained in W -- the payload was truncated")
    return True, "ok"


def stalls(d):
    """The frames the verdict is drawn from: retained frames over 250ms."""
    return [e for e in d["worst"] if e["dt"] > BIG_MS]


def verdict(d):
    """(verdict, peak share, frame-weighted share) over the frames over 250ms.

    The verdict is driven by the PEAK per-frame share, not the frame-weighted
    one. A forced flush that costs 400ms lengthens the FOLLOWING frame by the
    same 400ms, and that follower is itself over 250ms with a near-zero tForce,
    so aggregating pulls a genuinely layout-dominated run toward 50%. The peak is
    the attribution; the aggregate is printed beside it, and a split between them
    is called out rather than averaged away.
    """
    if d["big"] == 0:
        return V_SUPPRESSED, 0.0, 0.0
    s = stalls(d)
    dt = sum(e["dt"] for e in s)
    peak = max((e["force"] / e["dt"]) for e in s if e["dt"])
    agg = (sum(e["force"] for e in s) / dt) if dt else 0.0
    return (V_LAYOUT if peak > LAYOUT_FRACTION else V_PAINT), peak, agg


def report(d, label):
    print(f"===== {label} =====")
    lt = "unsupported (longtask entryType absent)" if d["lt"] is None \
        else f"{d['lt']} tasks, worst {d['ltmax']}ms"
    print(f"window {d['sec']}s  frames {d['frames']}  mean {d['avg']}ms  "
          f"max {d['max']}ms  ~{d['frames']/max(d['sec'],1):.1f} fps")
    print(f"frames >{BIG_MS}ms: {d['big']}  = {d['big']/max(d['sec'],1):.2f}/s")
    print(f"longtask: {lt}")

    ok, reason = validate(d)

    print("\nbiggest frames (forced layout timed inside each):")
    print(f"  {'t(s)':>7}  {'dt(ms)':>7}  {'tForce(ms)':>11}  {'tForce/dt':>9}")
    for e in d["worst"]:
        pct = 100.0 * e["force"] / e["dt"] if e["dt"] else 0.0
        mark = "  <- stall" if e["dt"] > BIG_MS else ""
        print(f"  {e['t']:7.1f}  {e['dt']:7d}  {e['force']:11d}  "
              f"{pct:8.1f}%{mark}")
    if not d["worst"]:
        print("  (none over 150ms)")

    if not ok:
        print(f"\n*** UNMEASURED: {reason} -- do NOT read this as a null ***")
        return False

    v, peak, agg = verdict(d)
    if d["big"] == 0:
        print(f"\nVERDICT: {v}.")
        return True

    n = len(stalls(d))
    print(f"\nVERDICT: {v} -- forced layout is {100*peak:.1f}% of the worst "
          f"stall frame, {100*agg:.1f}% frame-weighted across {n} stall frame(s).")
    if peak > LAYOUT_FRACTION >= agg:
        print("         The stall frames SPLIT: some are the flush, the rest are "
              "the frame the flush overran into. Read the table, not the mean.")
    return True


if __name__ == "__main__":
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "PF|" in l]
    if not lines:
        sys.exit("no PF| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if d is None:
        sys.exit("PF| did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
