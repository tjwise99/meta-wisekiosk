#!/usr/bin/env python3
"""Render the subsystem-ablation probe's AB| payload (p28_ablate.js).

Three conditions interleaved in one capture: N (nothing ablated), R (rotation tick's derived
recompute skipped), C (clock re-read/re-format skipped). Compares the >250ms frame fraction of each
against N. A condition whose fraction is markedly below N's means that subsystem's allocation drives
the residual full-GC stall -- and points at the fix. Landing is checked from the app's own skip
counters: R must have skipped rotation ticks and not clock ticks; C the reverse; N neither.

Payload (from p28_ablate.js):
  AB|<sec>|f<frames>|big<big>|N:<n.big.mean.mx.rs.cs>|R:<...>|C:<...>|B<t:dtArm,...>
Per-condition fields: n frames, big frames>250ms, mean ms, max ms, rs rotation-ticks-skipped,
cs clock-ticks-skipped.
"""
import re
import sys

PAT = (r"AB\|(\d+)\|f(\d+)\|big(\d+)"
       r"\|N:([\d.]+)\|R:([\d.]+)\|C:([\d.]+)(?:\|B(.*))?")


def cond(s):
    n, big, mean, mx, rs, cs = [int(x) for x in s.split(".")]
    return dict(n=n, big=big, mean=mean, mx=mx, rs=rs, cs=cs)


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    return dict(sec=int(g[0]), frames=int(g[1]), bigtot=int(g[2]),
                N=cond(g[3]), R=cond(g[4]), C=cond(g[5]), big=g[6] or "")


def frac(c):
    return c["big"] / c["n"] if c["n"] else 0.0


def validate(d):
    for k in ("N", "R", "C"):
        if d[k]["n"] == 0:
            return False, f"condition {k} has no frames (interleave did not run)"
    # landing: R skipped rotation ticks, not clock; C skipped clock, not rotation; N skipped neither.
    if d["R"]["rs"] == 0:
        return False, "R condition skipped no rotation ticks (rotation toggle did not land)"
    if d["C"]["cs"] == 0:
        return False, "C condition skipped no clock ticks (clock toggle did not land)"
    if d["N"]["rs"] != 0 or d["N"]["cs"] != 0:
        return False, f"N condition ablated something (rs={d['N']['rs']} cs={d['N']['cs']}) -- leak"
    if d["R"]["cs"] != 0:
        return False, f"R condition also skipped clock ticks (cs={d['R']['cs']}) -- toggles crossed"
    if d["C"]["rs"] != 0:
        return False, f"C condition also skipped rotation ticks (rs={d['C']['rs']}) -- toggles crossed"
    return True, "landed"


def report(d, label):
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  frames>250ms {d['bigtot']}")
    ok, why = validate(d)
    if not ok:
        print(f"\n*** UNMEASURED: {why} -- do NOT read as a null ***")
        return False

    print(f"\n{'condition':>18} {'frames':>7} {'>250ms':>7} {'>250ms frac':>12} "
          f"{'mean':>6} {'max':>6} {'rotSkip':>8} {'clkSkip':>8}")
    rows = [("N none", "N"), ("R rotation-off", "R"), ("C clock-off", "C")]
    for name, k in rows:
        c = d[k]
        print(f"{name:>18} {c['n']:>7} {c['big']:>7} {frac(c):>11.3%} "
              f"{c['mean']:>6} {c['mx']:>6} {c['rs']:>8} {c['cs']:>8}")

    fn = frac(d["N"])
    print()
    verdicts = []
    for name, k in (("rotation", "R"), ("clock", "C")):
        fk = frac(d[k])
        drop = (fn / fk) if fk else float("inf")
        if fn >= 1.5 * fk:
            verdicts.append(f"{name}: ablating it CUTS the stall fraction {fn:.3%} -> {fk:.3%} "
                            f"({drop:.1f}x lower) -- this subsystem drives the residual.")
        else:
            verdicts.append(f"{name}: ablating it leaves the stall fraction {fn:.3%} -> {fk:.3%} "
                            f"(no material change) -- not the driver.")
    for v in verdicts:
        print("VERDICT " + v)
    return True


if __name__ == "__main__":
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "AB|" in l]
    if not lines:
        sys.exit("no AB| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if not d:
        sys.exit("AB| did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
