#!/usr/bin/env python3
"""Interleaved title-write-cadence arms: does frames>250ms track the exfil poke rate?"""
import re, sys
import parse4

A = r'f(\d+):b(\d+):tw(\d+):m(\d+)'
PAT = r'KA\|arm(-?\d+)\|FAST1_' + A + r'\|SLOW_' + A + r'\|FAST2_' + A

txt = open(sys.argv[1]).read().replace('"', '')
lines = [l for l in txt.splitlines() if 'KA|' in l]
if not lines:
    sys.exit("no KA| payload in " + sys.argv[1])
m = re.search(PAT, lines[-1])
if not m:
    sys.exit("KA| did not match:\n" + lines[-1][:300])
g = [int(x) for x in m.groups()]
arms = [g[1:5], g[5:9], g[9:13]]
names = ["FAST1 (title 1000ms)", "SLOW  (title 4000ms)", "FAST2 (title 1000ms)"]
want_tw = [120, 30, 120]          # 120 s arms at 1/s, 0.25/s, 1/s
DUR = 120.0

print(f"{'arm':<24}{'frames':>8}{'>250ms':>8}{'big/s':>8}{'titlewrites':>13}{'tw/s':>7}{'mean':>7}")
for n, a, w in zip(names, arms, want_tw):
    f, b, tw, mean = a
    print(f"{n:<24}{f:>8}{b:>8}{b/DUR:>8.2f}{tw:>13}{tw/DUR:>7.2f}{mean:>6}ms")

print("\ncadence landing check (did the arm's write rate actually change?):")
ok = True
for n, a, w in zip(names, arms, want_tw):
    tw = a[2]
    good = abs(tw - w) <= max(6, 0.15 * w)
    ok &= good
    print(f"  {n:<24} wrote {tw:>4} titles, expected ~{w:<4} -> {'OK' if good else '*** MISMATCH ***'}")
if not ok:
    print("  *** CADENCE DID NOT APPLY AS INTENDED -- treat arms as UNMEASURED ***")

# drift control: interpolate the two FAST arms to the SLOW arm's midpoint
f1, sl, f2 = arms[0][1] / DUR, arms[1][1] / DUR, arms[2][1] / DUR
pred = f1 + (f2 - f1) * 0.5
tw_ratio = (arms[0][2] + arms[2][2]) / 2.0 / max(arms[1][2], 1)
print(f"\ndrift control: FAST1={f1:.2f}/s FAST2={f2:.2f}/s -> predicted at SLOW midpoint {pred:.2f}/s")
print(f"               SLOW measured {sl:.2f}/s   (delta {sl-pred:+.2f}/s, {100*(sl-pred)/pred:+.0f}%)")
print(f"\ntitle-write rate ratio FAST:SLOW = {tw_ratio:.1f}x")
print(f"big-frame rate ratio   FAST:SLOW = {pred/max(sl,1e-9):.2f}x")
print("\nIf the floor were the exfil artifact, the two ratios would match "
      f"(~{tw_ratio:.0f}x). If independent, the big-frame ratio is ~1.0x.")

d = parse4.parse(lines[-1])
if d:
    print(f"\nwhole run: {d['sec']}s {d['frames']} frames mean {d['avg']}ms M{d['marquee']}/{d['rows']} "
          f"ROT{d['rotn']} big {d['bigtot']} ({d['bigtot']/max(d['sec'],1):.2f}/s)")
