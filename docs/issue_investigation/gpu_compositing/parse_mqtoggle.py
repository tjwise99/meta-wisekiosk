#!/usr/bin/env python3
"""Render the marquee-toggle probe's MQ| payload (p25_mqtoggle.js).

Tests whether the residual ~1300ms stall is driven by the marquee loop's per-frame allocation.
The instrumented bundle carries both loop bodies in step(), switched per frame by window.__mqAlloc,
with byte-identical motion. This probe interleaves ALLOC (arm A) and CLEAN (arm C) inside one
capture and reports the >250ms frame fraction per arm. If arm A's fraction is markedly higher AND
the landing check confirms the ALLOC path ran only in arm A, the stall tracks the marquee
allocation -- and removing it (the CLEAN path) is the fix.

Payload shape (from p25_mqtoggle.js):
  MQ|<sec>|f<frames>|av<mean>|mx<max>|BT<big>|N<cols>|A:<n.big.mean.mx.aran>|C:<...>|H<7 buckets>|B<t:dtArm,...>

Per-arm field order in A:/C: is n.big.mean.mx.aran -- frames, frames>250ms, mean ms, max ms, and
`aran` = frames in that arm where the ALLOC code path actually ran (window.__mqAllocFrames delta).
Compare arms by the >250ms FRACTION (big/n): the arms are interleaved and hold different frame
counts, so a fraction is the drift-safe comparable (R3).
"""
import re
import sys

PAT = (r"MQ\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|BT(\d+)\|N(\d+)"
       r"\|A:([\d.]+)\|C:([\d.]+)\|H([\d.]+)(?:\|B(.*))?")
BUCKETS = ["<50", "50-100", "100-250", "250-500", "500-1k", "1k-2k", ">=2k"]


def arm(s):
    n, big, mean, mx, aran = [int(x) for x in s.split(".")]
    return dict(n=n, big=big, mean=mean, mx=mx, aran=aran)


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    return dict(sec=int(g[0]), frames=int(g[1]), avg=int(g[2]), max=int(g[3]),
                bigtot=int(g[4]), N=int(g[5]), A=arm(g[6]), C=arm(g[7]),
                hist=[int(x) for x in g[8].split(".")], big=g[9] or "")


def frac(a):
    return a["big"] / a["n"] if a["n"] else 0.0


def validate(d):
    if d["frames"] == 0:
        return False, "zero frames"
    if d["N"] == 0:
        return False, "no marquee columns registered (N=0) -- nothing was under test"
    if d["A"]["n"] == 0 or d["C"]["n"] == 0:
        return False, "an arm has no frames (interleave did not run)"
    # landing: the ALLOC path must have run through arm A and NOT through arm C. A few CLEAN-arm
    # frames tagged alloc are the expected arm-boundary artifact -- the probe flips __mqAlloc at the
    # top of its own rAF, so the app's step for that same frame can still run the previous arm's path
    # once per A->C transition (two such transitions in the palindrome). Tolerate a handful; a real
    # leak is a large fraction of the arm, not a boundary count.
    BOUNDARY_TOL = 5
    if d["A"]["aran"] < 0.8 * d["A"]["n"]:
        return False, (f"ALLOC arm did not run the alloc path (aran={d['A']['aran']} of "
                       f"n={d['A']['n']}) -- toggle did not land")
    if d["C"]["aran"] > max(BOUNDARY_TOL, 0.01 * d["C"]["n"]):
        return False, (f"CLEAN arm ran the alloc path {d['C']['aran']} times "
                       f"({d['C']['aran'] / d['C']['n']:.1%} of {d['C']['n']}) -- "
                       "the __mqAlloc=false toggle leaked, beyond the boundary artifact")
    return True, f"landed (CLEAN-arm boundary frames: {d['C']['aran']})"


def report(d, label):
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  overall mean {d['avg']}ms  "
          f"max {d['max']}ms  frames>250ms {d['bigtot']}  marquee columns N={d['N']}")
    ok, why = validate(d)
    if not ok:
        print(f"\n*** UNMEASURED: {why} -- do NOT read as a null ***")
        return False

    A, C = d["A"], d["C"]
    print(f"\n{'arm':>12} {'frames':>7} {'>250ms':>7} {'>250ms frac':>12} "
          f"{'mean':>6} {'max':>6} {'allocRan':>9}")
    print(f"{'A ALLOC':>12} {A['n']:>7} {A['big']:>7} {frac(A):>11.3%} "
          f"{A['mean']:>6} {A['mx']:>6} {A['aran']:>9}")
    print(f"{'C CLEAN':>12} {C['n']:>7} {C['big']:>7} {frac(C):>11.3%} "
          f"{C['mean']:>6} {C['mx']:>6} {C['aran']:>9}")

    fa, fc = frac(A), frac(C)
    ratio = (fa / fc) if fc else float("inf")
    print(f"\nALLOC vs CLEAN >250ms fraction: {ratio:.1f}x  "
          f"(ALLOC mean frame {A['mean']}ms vs CLEAN {C['mean']}ms)")
    if fa >= 1.5 * fc:
        print("VERDICT: STALL TRACKS THE MARQUEE ALLOCATION (GC lever confirmed) -- the current "
              "Map-iteration loop misses the deadline far more than the allocation-free loop that "
              "renders the same motion. The source fix is validated.")
    else:
        print("VERDICT: stall does NOT track the marquee allocation -- removing the per-frame "
              "garbage does not lower the >250ms rate; the GC driver is elsewhere.")
    return True


if __name__ == "__main__":
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "MQ|" in l]
    if not lines:
        sys.exit("no MQ| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if not d:
        sys.exit("MQ| did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
