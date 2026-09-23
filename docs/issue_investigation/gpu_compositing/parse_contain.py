#!/usr/bin/env python3
"""Render the paint-containment probe's KC| window-title payload as a report.

p22_contain.js sets an inline `contain` property on every `[data-pwt-card]` and
measures p7_min.js's frame-time distribution underneath it. The hypothesis is
that the ~450ms stall is a whole-viewport software repaint; if each card is a
paint-containment boundary, the escalation is bounded to roughly a quarter of
the viewport (~110ms), under the 250ms visible-stall threshold, so the frames
>250ms rate should fall toward zero.

The verdict is on that rate against a reference -- the rate measured without
containment, default 0.04/s -- and it is gated on the landing flag. land=0 means
the computed `contain` never reflected the requested value, and a flat rate
under land=0 measures nothing at all.

Usage: parse_contain.py <raw.txt> [reference-rate] [label]
The second and third arguments may be given in either order: a token that parses
as a number is the reference >250ms rate in frames/s, any other token is the
report label (default the filename), matching the sibling parsers' argv[2].

The MP|/PF|/FVP| parsers do not read this payload and must not be pointed at it:
the tag is KC| and the record carries the containment landing state.
"""
import re
import sys

PAT = (r"KC\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|BT(\d+)\|RT([\d.]+)"
       r"\|C(\d+)\.(\d+)\|L(\d)\.(\d)\|CV([A-Za-z+]*)\|CN([A-Za-z+]+)"
       r"\|H([\d.]+)\|B(.*)")

BUCKETS = ["<50", "50-100", "100-250", "250-500", "500-1k", "1k-2k", ">=2k"]

REF_DEFAULT = 0.04       # frames >250ms per second, without containment
REDUCE_FACTOR = 0.25     # at or below this share of the reference: bounded
NULL_FACTOR = 0.75       # at or above this share: unchanged
FLIP_PERIOD = 8.0        # card flip cycle, seconds -- big frames are read mod this

V_REDUCE = "CONTAINMENT REDUCES/DEFEATS THE STALL"
V_PARTIAL = ("partial -- the rate fell, but not to the <=0.25x a card-bounded "
             "escalation predicts")
V_NULL = ("containment does NOT reduce the stall (escalation is not "
          "card-bounded)")


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    big = []
    for e in g[13].split(","):
        if ":" in e:
            t, dt = e.split(":", 1)
            try:
                big.append((float(t), int(dt)))
            except ValueError:
                pass
    return dict(
        sec=int(g[0]), frames=int(g[1]), mean=int(g[2]), mx=int(g[3]),
        big250=int(g[4]), rate_probe=float(g[5]),
        cards=int(g[6]), writes=int(g[7]),
        land=int(g[8]), support=int(g[9]),
        computed=g[10].replace("+", " "), contain=g[11].replace("+", " "),
        hist=[int(x) for x in g[12].split(".")],
        big=big,
    )


def validate(d):
    """Return (ok, reason). A run with no payload or no frames measured nothing."""
    if d is None:
        return False, "no KC| payload -- the probe never wrote a title"
    if d["frames"] == 0:
        return False, "zero frames -- the rAF loop never ran"
    return True, "ok"


def rate(d):
    return d["big250"] / max(d["sec"], 1)


def verdict(d, ref):
    """(verdict, rate/reference) from the >250ms rate, gated on the landing flag."""
    r = rate(d)
    ratio = r / ref if ref else 0.0
    if not d["land"]:
        extra = ""
        if not d["support"]:
            extra = " (the engine has no `contain` property)"
        elif d["cards"] == 0:
            extra = " (no [data-pwt-card] elements were present)"
        return ("UNMEASURED: contain:%s did not apply%s -- do not read as a null"
                % (d["contain"], extra)), ratio
    if r == 0.0 or ratio <= REDUCE_FACTOR:
        return V_REDUCE, ratio
    if ratio < NULL_FACTOR:
        return V_PARTIAL, ratio
    return V_NULL, ratio


def report(d, label, ref):
    print(f"===== {label} =====")
    ok, reason = validate(d)
    if not ok:
        print(f"\n*** UNMEASURED: {reason} -- do NOT read this as a null ***")
        return False

    r = rate(d)
    print(f"window {d['sec']}s  frames {d['frames']}  "
          f"~{d['frames']/max(d['sec'],1):.1f} fps  "
          f"mean {d['mean']}ms  max {d['mx']}ms")
    print(f"requested contain: {d['contain']}   cards {d['cards']}   "
          f"inline writes {d['writes']}")
    print(f"landing: land={d['land']} support={d['support']} "
          f"computed contain = {d['computed'] or '(empty)'}")
    if d["writes"] > d["frames"]:
        print("  NOTE: writes exceed frames -- the ensure loop is rewriting "
              "rather than settling, so the run is self-perturbed")
    print(f"frames >250ms: {d['big250']}  = {r:.3f}/s  "
          f"(probe reported {d['rate_probe']:.3f}/s)  "
          f"reference {ref:.3f}/s")

    tot = sum(d["hist"]) or 1
    print("\n  frame-time histogram:")
    for k, v in zip(BUCKETS, d["hist"]):
        print(f"    {k:>8}  {v:6d}  {100*v/tot:5.1f}%  {'#'*int(50*v/tot)}")

    print(f"\n  last {len(d['big'])} frames >250ms "
          f"(t, dt, t mod {FLIP_PERIOD:.0f}s):")
    if not d["big"]:
        print("    (none)")
    for t, dt in d["big"]:
        print(f"    {t:8.1f}s  {dt:5d}ms   mod {t % FLIP_PERIOD:5.1f}s")
    if len(d["big"]) > 1:
        ia = [round(b[0] - a[0], 1) for a, b in zip(d["big"], d["big"][1:])]
        print(f"  inter-arrival: {ia}")

    v, ratio = verdict(d, ref)
    if not d["land"]:
        print(f"\nVERDICT: {v}. The {r:.3f}/s above is a rate measured WITHOUT "
              f"containment in effect; it is not evidence either way.")
    else:
        print(f"\nVERDICT: {v} -- {r:.3f}/s is {ratio:.2f}x the {ref:.3f}/s "
              f"reference.")
    return True


if __name__ == "__main__":
    ref, label = REF_DEFAULT, None
    for a in sys.argv[2:]:
        try:
            ref = float(a)
        except ValueError:
            label = a
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "KC|" in l]
    if not lines:
        sys.exit("no KC| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if d is None:
        sys.exit("KC| did not match:\n" + lines[-1][:400])
    report(d, label or sys.argv[1], ref)
