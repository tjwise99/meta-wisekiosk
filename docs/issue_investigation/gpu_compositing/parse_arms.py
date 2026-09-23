#!/usr/bin/env python3
"""Render the interleaved clock-ablation arms from the KA| title segment."""
import re, sys
import parse4

ARM = r'f(\d+):b(\d+):m(\d+):wmax(-?\d+):wlast(-?\d+):ap(\d+)'
PAT = (r'KA\|arm(-?\d+)\|sel(-?\d+)'
       r'\|ON1_' + ARM + r'\|OFF_' + ARM + r'\|ON2_' + ARM)

txt = open(sys.argv[1]).read().replace('"', '')
lines = [l for l in txt.splitlines() if 'KA|' in l]
if not lines:
    sys.exit("no KA| payload in " + sys.argv[1])
line = lines[-1]
m = re.search(PAT, line)
if not m:
    sys.exit("KA| did not match:\n" + line[:400])
g = [int(x) for x in m.groups()]
cur, sel = g[0], g[1]
arms = [g[2:8], g[8:14], g[14:20]]
names = ["ON1  (clock visible)", "OFF  (seconds hidden)", "ON2  (clock visible)"]

print(f"current arm at read: {cur}   selector '.seconds' found: {'YES' if sel==1 else 'NO'}")
if sel != 1:
    print("  *** ABLATION DID NOT LAND -- selector never resolved. Result is UNMEASURED. ***")
print()
print(f"{'arm':<24}{'frames':>8}{'>250ms':>8}{'>250ms/s':>10}{'mean':>7}"
      f"{'sec width max':>15}{'last':>6}{'applied':>9}")
for n, a in zip(names, arms):
    f, b, mean, wmax, wlast, ap = a
    secs = f / 15.0 if f else 0  # nominal; replaced below by true arm duration
    print(f"{n:<24}{f:>8}{b:>8}{'':>10}{mean:>6}ms{wmax:>15}{wlast:>6}{ap:>9}")

# true arm durations are fixed by the probe's edges: 120 s each
print()
print("frames >250 ms per second, using the probe's fixed 120 s arm windows:")
for n, a in zip(names, arms):
    f, b = a[0], a[1]
    print(f"  {n:<24} {b/120.0:.2f}/s   ({b} frames >250ms in 120 s, {f} frames total)")

print()
print("ablation landing check (width of .seconds during each arm):")
for n, a in zip(names, arms):
    wmax, wlast = a[3], a[4]
    verdict = ("hidden (0 px)" if wmax == 0 else
               f"VISIBLE ({wmax} px)" if wmax > 0 else "not sampled")
    print(f"  {n:<24} max={wmax:>4}  last={wlast:>4}  -> {verdict}")

d = parse4.parse(line)
if d:
    print()
    print(f"whole run: {d['sec']}s {d['frames']} frames mean {d['avg']}ms "
          f"M{d['marquee']}/{d['rows']} ROT{d['rotn']} big {d['bigtot']} "
          f"({d['bigtot']/max(d['sec'],1):.2f}/s)")
