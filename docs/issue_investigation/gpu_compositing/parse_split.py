#!/usr/bin/env python3
"""Render the rotation-driver split probe's SP| payload (p29_split.js).

Conditions: N (baseline), M (matchMedia cached, rotation on), R (rotation frozen, zero control).
If M's >250ms fraction falls to ~R's, the rotation tick's matchMedia churn is the driver and caching
it is the fix. If M stays ~N while R is ~0, the per-tick derived recompute is the driver instead.

Payload: SP|<sec>|f<frames>|big<big>|N:<n.big.mean.mx.mmr.rsk>|M:<...>|R:<...>|B<t:dtArm,...>
Per condition: n frames, big frames>250ms, mean ms, max ms, mmr uncached-matchMedia-calls,
rsk rotation-ticks-skipped.
"""
import re
import sys

PAT = (r"SP\|(\d+)\|f(\d+)\|big(\d+)"
       r"\|N:([\d.]+)\|M:([\d.]+)\|R:([\d.]+)(?:\|B(.*))?")
TOL = 5  # boundary-frame tolerance on landing counters


def cond(s):
    n, big, mean, mx, mmr, rsk = [int(x) for x in s.split(".")]
    return dict(n=n, big=big, mean=mean, mx=mx, mmr=mmr, rsk=rsk)


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    return dict(sec=int(g[0]), frames=int(g[1]), bigtot=int(g[2]),
                N=cond(g[3]), M=cond(g[4]), R=cond(g[5]), big=g[6] or "")


def frac(c):
    return c["big"] / c["n"] if c["n"] else 0.0


def validate(d):
    for k in ("N", "M", "R"):
        if d[k]["n"] == 0:
            return False, f"condition {k} has no frames (interleave did not run)"
    if d["N"]["mmr"] == 0:
        return False, "N made no uncached matchMedia calls (rotation/measure not exercised)"
    if d["M"]["mmr"] > TOL:
        return False, f"M still made {d['M']['mmr']} uncached matchMedia calls (cache toggle did not land)"
    if d["R"]["rsk"] == 0:
        return False, "R skipped no rotation ticks (rotation toggle did not land)"
    if d["N"]["rsk"] != 0 or d["M"]["rsk"] != 0:
        return False, f"rotation ran off in a non-R arm (N.rsk={d['N']['rsk']} M.rsk={d['M']['rsk']})"
    return True, "landed"


def report(d, label):
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  frames>250ms {d['bigtot']}")
    ok, why = validate(d)
    if not ok:
        print(f"\n*** UNMEASURED: {why} -- do NOT read as a null ***")
        return False
    print(f"\n{'condition':>20} {'frames':>7} {'>250ms':>7} {'>250ms frac':>12} "
          f"{'mean':>6} {'max':>6} {'mmReal':>7} {'rotSkip':>7}")
    for name, k in (("N none", "N"), ("M matchmedia-cached", "M"), ("R rotation-off", "R")):
        c = d[k]
        print(f"{name:>20} {c['n']:>7} {c['big']:>7} {frac(c):>11.3%} "
              f"{c['mean']:>6} {c['mx']:>6} {c['mmr']:>7} {c['rsk']:>7}")
    fn, fm, fr = frac(d["N"]), frac(d["M"]), frac(d["R"])
    print()
    # how much of N's stalls does caching matchMedia remove, relative to the full removal R achieves?
    removed = (fn - fm)
    full = (fn - fr)
    share = (removed / full) if full > 0 else 0.0
    if fn >= 1.5 * fm and share >= 0.6:
        print(f"VERDICT: matchMedia caching is the (dominant) fix -- it drops the stall fraction "
              f"{fn:.3%} -> {fm:.3%}, {share:.0%} of the way to the rotation-off floor {fr:.3%}.")
    elif fm >= 0.66 * fn:
        print(f"VERDICT: matchMedia is NOT the driver -- caching it leaves the fraction {fn:.3%} -> "
              f"{fm:.3%} while freezing rotation reaches {fr:.3%}. The per-tick derived recompute is "
              f"the source; the fix must reduce that.")
    else:
        print(f"VERDICT: matchMedia is a PARTIAL contributor -- caching it moves {fn:.3%} -> {fm:.3%} "
              f"({share:.0%} of the way to {fr:.3%}); the derived recompute holds the rest.")
    return True


if __name__ == "__main__":
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "SP|" in l]
    if not lines:
        sys.exit("no SP| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if not d:
        sys.exit("SP| did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
