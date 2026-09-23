#!/usr/bin/env python3
"""Render the allocation-pressure probe's AL| payload (p24_alloc.js).

Tests whether the residual ~1300ms stall is a JavaScriptCore GC pause: it
interleaves BASELINE (arm A, no extra allocation) with heavy-JS-ALLOC (arm B)
and reports the >250ms frame fraction per arm. If arm B's fraction is far higher
AND the landing check confirms arm B actually allocated while arm A did not, the
stall tracks allocation -- GC-consistent.

Payload shape (from p24_alloc.js):
  AL|<sec>|f<frames>|av<mean>|mx<max>|BT<big>|A:<n.big.mean.mx.alloc>|B:<...>|H<7 buckets>|B<t:dtArm,...>

Per-arm field order in A:/B: is n.big.mean.mx.alloc -- frames, frames>250ms,
mean ms, max ms, count of frames that ran the allocation. Compare arms by the
>250ms FRACTION (big/n), not a per-second rate: the arms are interleaved and each
holds a different frame count, so a fraction is the drift-safe comparable (R3).
"""
import re
import sys

PAT = (r"AL\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|BT(\d+)"
       r"\|A:([\d.]+)\|B:([\d.]+)\|H([\d.]+)(?:\|B(.*))?")
BUCKETS = ["<50", "50-100", "100-250", "250-500", "500-1k", "1k-2k", ">=2k"]


def arm(s):
    n, big, mean, mx, alloc = [int(x) for x in s.split(".")]
    return dict(n=n, big=big, mean=mean, mx=mx, alloc=alloc)


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    return dict(sec=int(g[0]), frames=int(g[1]), avg=int(g[2]), max=int(g[3]),
                bigtot=int(g[4]), A=arm(g[5]), B=arm(g[6]),
                hist=[int(x) for x in g[7].split(".")], big=g[8] or "")


def frac(a):
    return a["big"] / a["n"] if a["n"] else 0.0


def validate(d):
    if d["frames"] == 0:
        return False, "zero frames"
    if d["A"]["n"] == 0 or d["B"]["n"] == 0:
        return False, "an arm has no frames (interleave did not run)"
    # landing: ALLOC arm must have allocated, BASELINE arm must not have
    if d["B"]["alloc"] == 0:
        return False, "ALLOC arm never allocated (alloc=0) -- manipulation did not land"
    if d["A"]["alloc"] != 0:
        return False, f"BASELINE arm allocated (alloc={d['A']['alloc']}) -- arms not clean"
    return True, "landed"


def report(d, label):
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  overall mean {d['avg']}ms  "
          f"max {d['max']}ms  frames>250ms {d['bigtot']}")
    ok, why = validate(d)
    if not ok:
        print(f"\n*** UNMEASURED: {why} -- do NOT read as a null ***")
        return False

    A, B = d["A"], d["B"]
    print(f"\n{'arm':>12} {'frames':>7} {'>250ms':>7} {'>250ms frac':>12} "
          f"{'mean':>6} {'max':>6} {'allocated':>9}")
    print(f"{'A BASELINE':>12} {A['n']:>7} {A['big']:>7} {frac(A):>11.3%} "
          f"{A['mean']:>6} {A['mx']:>6} {A['alloc']:>9}")
    print(f"{'B ALLOC':>12} {B['n']:>7} {B['big']:>7} {frac(B):>11.3%} "
          f"{B['mean']:>6} {B['mx']:>6} {B['alloc']:>9}")

    fa, fb = frac(A), frac(B)
    ratio = (fb / fa) if fa else float("inf")
    print(f"\nALLOC vs BASELINE >250ms fraction: {ratio:.1f}x  "
          f"(ALLOC mean frame {B['mean']}ms vs BASELINE {A['mean']}ms)")
    if fb >= 1.5 * fa and fa >= 0:
        print("VERDICT: STALL TRACKS ALLOCATION (GC-consistent) -- forcing JS "
              "allocation drives the >250ms stalls up sharply.")
    else:
        print("VERDICT: stall does NOT track allocation (not GC / points elsewhere).")
    return True


if __name__ == "__main__":
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "AL|" in l]
    if not lines:
        sys.exit("no AL| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if not d:
        sys.exit("AL| did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
