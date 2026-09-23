#!/usr/bin/env python3
"""Run B done properly: does killing ALL app animation collapse the floor?"""
import re, sys
S = r'f(\d+):b(\d+):m(\d+):aw(-?\d+):mq(-?\d+):an(\w+)'
PAT = (r'AN\|slot(-?\d+)\|sheet(-?\d+)'
       r'\|S0_' + S + r'\|S1_' + S + r'\|S2_' + S + r'\|S3_' + S + r'\|S4_' + S)
COND = [0, 1, 0, 1, 0]
NAME = {0: 'animations ON', 1: 'animations OFF'}
DUR = 80.0

txt = open(sys.argv[1]).read().replace('"', '')
lines = [l for l in txt.splitlines() if 'AN|' in l]
if not lines: sys.exit("no AN| payload in " + sys.argv[1])
m = re.search(PAT, lines[-1])
if not m: sys.exit("AN| did not match:\n" + lines[-1][:300])
g = m.groups()
cur, sheet = int(g[0]), int(g[1])
sl = []
for i in range(5):
    f,b,mn,aw,mq,an = g[2+i*6:8+i*6]
    sl.append(dict(f=int(f),b=int(b),mean=int(mn),aw=int(aw),mq=int(mq),an=an))

print(f"slot at read: {cur}   stylesheet insertRule ok: {sheet}\n")
print(f"{'slot':<6}{'condition':<17}{'frames':>8}{'>250ms':>8}{'big/s':>8}{'mean':>7}"
      f"{'appW':>7}{'marquees':>10}{'anim':>7}")
for i,s in enumerate(sl):
    print(f"{i:<6}{NAME[COND[i]]:<17}{s['f']:>8}{s['b']:>8}{s['b']/DUR:>8.2f}"
          f"{s['mean']:>6}ms{s['aw']:>7}{s['mq']:>10}{s['an']:>7}")

print("\nlanding check (THE thing run B lacked):")
ok = True
for i,s in enumerate(sl):
    c = COND[i]; p=[]
    if s['aw'] <= 0: p.append("app not visible")
    want = 'OFF' if c == 1 else 'ON'
    if s['an'] == 'norow': p.append("no marquee row present to read")
    elif s['an'] != want: p.append(f"computed animationName is {s['an']}, expected {want}")
    ok &= not p
    print(f"  slot {i} ({NAME[c]:<15}): " + ("OK" if not p else "*** " + "; ".join(p) + " ***"))
if not ok: print("  *** ABLATION DID NOT LAND -- UNMEASURED, exactly as run B was ***")

def agg(idx):
    b=sum(sl[i]['b'] for i in idx); f=sum(sl[i]['f'] for i in idx)
    ms=sum(sl[i]['mean']*sl[i]['f'] for i in idx)
    return b/(DUR*len(idx)), (ms/f if f else 0), f
on, off = agg([0,2,4]), agg([1,3])
print(f"\ndrift-centred condition means:")
print(f"  animations ON    {on[0]:.2f}/s   mean {on[1]:.1f}ms   ({on[2]} frames, slots 0,2,4)")
print(f"  animations OFF   {off[0]:.2f}/s  mean {off[1]:.1f}ms   ({off[2]} frames, slots 1,3)")
if on[0] > 0:
    print(f"\n  reduction: {100*(on[0]-off[0])/on[0]:+.0f}% in frames>250ms/s, "
          f"{100*(on[1]-off[1])/on[1]:+.0f}% in mean frame time")
