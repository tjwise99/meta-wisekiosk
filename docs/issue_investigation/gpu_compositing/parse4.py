#!/usr/bin/env python3
"""Render the kiosk frame-time probe's window-title payload as a readable report."""
import re
import sys

BUCKETS = ["<50", "50-100", "100-250", "250-500", "500-1k", "1k-2k", ">=2k"]
PAT = (r"KP\|(\d+)\|f(\d+)\|mx(\d+)\|av(\d+)\|M(\d+)/(\d+)\|ROT(\d+)@(-?\d+)"
       r"\|H([\d.]+)\|PM([\d.]+)\|PN([\d.]+)\|PB([\d.]+)\|W([\d.]+)\|BT(\d+)\|T([^|]*)\|B(.*)")


def recs(s):
    out = []
    for e in filter(None, s.split(",")):
        p = e.split(":")
        if len(p) == 6:
            out.append(dict(t=float(p[0]), dt=int(p[1]), js=int(p[2]),
                            lay=int(p[3]), layn=int(p[4]), since=float(p[5])))
    return out


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    ints = lambda s: [int(x) for x in s.split(".")]
    return dict(sec=int(g[0]), frames=int(g[1]), max=int(g[2]), avg=int(g[3]),
                marquee=int(g[4]), rows=int(g[5]), rotn=int(g[6]), rotint=int(g[7]),
                hist=ints(g[8]), pm=ints(g[9]), pn=ints(g[10]), pb=ints(g[11]),
                win=ints(g[12]), bigtot=int(g[13]), top=recs(g[14]), big=recs(g[15]))


def report(d, label):
    fps = d["frames"] / max(d["sec"], 1)
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  mean {d['avg']}ms  "
          f"max {d['max']}ms  ~{fps:.1f} fps")
    print(f"scrolling rows now {d['marquee']} of {d['rows']} ride rows")
    print(f"rotation remounts {d['rotn']}, mean interval {d['rotint']}ms")
    print(f"frames >250ms: {d['bigtot']}  ({d['bigtot']/max(d['sec'],1):.2f}/s)")
    tot = sum(d["hist"]) or 1
    print("\nframe-time histogram:")
    for k, v in zip(BUCKETS, d["hist"]):
        print(f"  {k:>8}  {v:6d}  {100*v/tot:5.1f}%  {'#'*int(60*v/tot)}")
    print("\nmean frame time by phase since last rotation remount:")
    for i, (ms, n, b) in enumerate(zip(d["pm"], d["pn"], d["pb"])):
        lbl = f"{i}-{i+1}s" if i < len(d["pm"]) - 1 else ">=8s/none"
        bar = "#" * int(ms / 4) if ms else ""
        print(f"  {lbl:>10}  mean {ms:5d}ms  frames {n:5d}  >250ms {b:5d}  {bar}")
    print("\nmean frame time per 10s window (absolute):")
    for i in range(0, len(d["win"]), 6):
        chunk = d["win"][i:i+6]
        print(f"  t={i*10:4d}-{(i+len(chunk))*10:4d}s  " +
              "  ".join(f"{v:4d}" for v in chunk))
    print("\nworst frames of the run (t, dt, jsMs, layoutMs, layoutCalls, s-since-rotation):")
    for e in d["top"]:
        print(f"  {e['t']:7.1f}s  {e['dt']:5d}ms  js={e['js']:5d}  lay={e['lay']:4d}"
              f"  n={e['layn']:3d}  since_rot={e['since']:6.1f}s"
              f"  engine={e['dt']-e['js']:5d}ms")
    print("\nlast 14 frames >250ms:")
    for e in d["big"]:
        print(f"  {e['t']:7.1f}s  {e['dt']:5d}ms  js={e['js']:5d}  lay={e['lay']:4d}"
              f"  n={e['layn']:3d}  since_rot={e['since']:6.1f}s"
              f"  engine={e['dt']-e['js']:5d}ms")


if __name__ == "__main__":
    text = open(sys.argv[1]).read()
    text = text.replace(chr(34), "")
    lines = [l for l in text.splitlines() if "KP|" in l]
    if not lines:
        sys.exit("no KP| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if not d:
        sys.exit("payload did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
