#!/usr/bin/env python3
"""Interleaved page-reduction arms: which layer owns the ~1/s WebKit render stall?"""
import re, sys

S = r'f(\d+):b(\d+):m(\d+):aw(-?\d+):tw(-?\d+):an(\w+)'
PAT = (r'FL\|slot(-?\d+)\|mech(\w+)'
       r'\|S0_' + S + r'\|S1_' + S + r'\|S2_' + S + r'\|S3_' + S + r'\|S4_' + S)
COND = [0, 1, 2, 1, 0]
NAME = {0: 'full app', 1: 'one animation', 2: 'nothing moving'}
DUR = 100.0

txt = open(sys.argv[1]).read().replace('"', '')
lines = [l for l in txt.splitlines() if 'FL|' in l]
if not lines:
    sys.exit("no FL| payload in " + sys.argv[1])
m = re.search(PAT, lines[-1])
if not m:
    sys.exit("FL| did not match:\n" + lines[-1][:400])
g = m.groups()
cur, mech = int(g[0]), g[1]
slots = []
for i in range(5):
    f, b, mn, aw, tw, an = g[2 + i*6 : 8 + i*6]
    slots.append(dict(f=int(f), b=int(b), mean=int(mn), aw=int(aw), tw=int(tw), an=an))

print(f"slot at read: {cur}   animation mechanism: {mech}\n")
print(f"{'slot':<6}{'condition':<17}{'frames':>8}{'>250ms':>8}{'big/s':>8}{'mean':>7}"
      f"{'appW':>7}{'boxW':>7}{'anim':>7}")
for i, s in enumerate(slots):
    print(f"{i:<6}{NAME[COND[i]]:<17}{s['f']:>8}{s['b']:>8}{s['b']/DUR:>8.2f}"
          f"{s['mean']:>6}ms{s['aw']:>7}{s['tw']:>7}{s['an']:>7}")

print("\nlanding check per slot (did the page state actually change?):")
ok = True
for i, s in enumerate(slots):
    c = COND[i]
    prob = []
    if c == 0:
        if s['aw'] <= 0: prob.append("app NOT visible")
        if s['tw'] > 0: prob.append("test box visible when it should be hidden")
    else:
        if s['aw'] > 0: prob.append(f"app STILL VISIBLE (w={s['aw']})")
        if s['tw'] <= 0: prob.append("test box NOT visible")
        if c == 1 and s['an'] in ('none', 'wa0', 'x'): prob.append(f"animation NOT running (an={s['an']})")
        if c == 2 and s['an'] not in ('none', 'wa0'): prob.append(f"animation STILL running (an={s['an']})")
    ok &= not prob
    print(f"  slot {i} ({NAME[c]:<15}): " + ("OK" if not prob else "*** " + "; ".join(prob) + " ***"))
if not ok:
    print("  *** AT LEAST ONE ARM DID NOT LAND -- treat those arms as UNMEASURED ***")

print("\ncondition means, drift-centred by the palindrome (slots 0,4 = full app; 1,3 = one anim):")
def agg(idxs):
    b = sum(slots[i]['b'] for i in idxs); f = sum(slots[i]['f'] for i in idxs)
    ms = sum(slots[i]['mean']*slots[i]['f'] for i in idxs)
    return b/(DUR*len(idxs)), (ms/f if f else 0), f
for c, idxs in ((0, [0,4]), (1, [1,3]), (2, [2])):
    rate, mean, f = agg(idxs)
    print(f"  {NAME[c]:<17} {rate:>5.2f}/s   mean {mean:>5.1f}ms   ({f} frames, slots {idxs})")

r0 = agg([0,4])[0]; r1 = agg([1,3])[0]; r2 = agg([2])[0]
print(f"\nreadout:")
print(f"  nothing moving  = {r2:.2f}/s")
print(f"  one animation   = {r1:.2f}/s")
print(f"  full app        = {r0:.2f}/s")
if r2 >= 0.6 * r0:
    print("  => (a) periodic WebKit/compositor/driver work, independent of page content")
elif r1 >= 0.6 * r0:
    print("  => (b) cost of compositing ANY animation on this hardware")
else:
    print("  => (c) something app-specific remains")
