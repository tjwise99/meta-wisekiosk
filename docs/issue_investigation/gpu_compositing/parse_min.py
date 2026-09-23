#!/usr/bin/env python3
"""Parse the minimal probe's MP| payload and compare its floor to the instrumented p4_a.js."""
import re, sys

BUCKETS = ["<50", "50-100", "100-250", "250-500", "500-1k", "1k-2k", ">=2k"]
PAT = r"MP\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|BT(\d+)\|H([\d.]+)\|B(.*)"

txt = open(sys.argv[1]).read().replace('"', '')
lines = [l for l in txt.splitlines() if 'MP|' in l]
if not lines:
    sys.exit("no MP| payload in " + sys.argv[1])
m = re.search(PAT, lines[-1])
if not m:
    sys.exit("MP| did not match:\n" + lines[-1][:300])
sec, frames, avg, mx, bt = (int(m.group(i)) for i in range(1, 6))
hist = [int(x) for x in m.group(6).split('.')]
big = [e for e in m.group(7).split(',') if ':' in e]

print(f"MINIMAL probe (p7_min.js, 1687 B -- no getter wrapping, no MutationObserver, "
      f"no querySelectorAll)")
print(f"  window {sec}s  frames {frames}  mean {avg}ms  max {mx}ms  ~{frames/max(sec,1):.1f} fps")
print(f"  frames >250ms: {bt}  = {bt/max(sec,1):.2f}/s")
tot = sum(hist) or 1
print("\n  frame-time histogram:")
for k, v in zip(BUCKETS, hist):
    print(f"    {k:>8}  {v:6d}  {100*v/tot:5.1f}%  {'#'*int(50*v/tot)}")
ts = [float(e.split(':')[0]) for e in big]
if len(ts) > 1:
    print(f"\n  last {len(ts)} frames >250ms at t = {ts}")
    print(f"  inter-arrival: {[round(b-a,1) for a,b in zip(ts,ts[1:])]}")

print("\n--- comparison, same board / same demo data / same bundle ---")
print(f"{'probe':<34}{'mean':>7}{'fps':>7}{'<50ms':>8}{'>250ms/s':>10}")
inst = dict(mean=67, fps=14.9, lt50=72.5, rate=1.07)
print(f"{'p4_a.js (full instrumentation)':<34}{inst['mean']:>6}ms{inst['fps']:>7.1f}"
      f"{inst['lt50']:>7.1f}%{inst['rate']:>10.2f}")
print(f"{'p7_min.js (bare rAF loop)':<34}{avg:>6}ms{frames/max(sec,1):>7.1f}"
      f"{100*hist[0]/tot:>7.1f}%{bt/max(sec,1):>10.2f}")
