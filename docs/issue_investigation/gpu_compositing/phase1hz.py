#!/usr/bin/env python3
"""Do frames >250 ms cluster at a consistent phase within a 1000 ms period?

Probe timestamps are quantised to 0.1 s, so phase is computed in INTEGER tenths
(round(t*10) % 10). Using t % 1.0 in float silently drops values a bin --
274.9 stores as 274.8999... -- which manufactures a fake clustering pattern.

t is relative to probe start, not the wall-clock second, so a genuine 1 Hz lock
would still appear as one dominant bin, just at an arbitrary offset.
"""
import sys
import parse4

def hist(ts):
    h = [0] * 10
    for t in ts:
        h[round(t * 10) % 10] += 1
    return h

def chi2(h):
    n = sum(h)
    e = n / 10
    return (sum((o - e) ** 2 / e for o in h) if n else 0.0), n

for path in sys.argv[1:]:
    txt = open(path).read().replace('"', '')
    line = [l for l in txt.splitlines() if 'KP|' in l][-1]
    d = parse4.parse(line)
    ts = [e['t'] for e in d['big']]
    h = hist(ts)
    c2, n = chi2(h)
    # how many distinct bursts? gap > 1.0 s starts a new one
    bursts = 1 + sum(1 for a, b in zip(ts, ts[1:]) if b - a > 1.0)
    print(f"===== {path} =====")
    print(f"  n={n} retained frames >250ms, in ~{bursts} bursts (independent samples ~= bursts, not n)")
    print("  phase within 1000 ms (bin = 100 ms):")
    for i, v in enumerate(h):
        print(f"    0.{i}-0.{i+1}  {v:2d}  {'#'*v}")
    print(f"  chi2={c2:.2f} df=9  (uniform expects {n/10:.1f}/bin; 5% crit = 16.92)")
    print()
