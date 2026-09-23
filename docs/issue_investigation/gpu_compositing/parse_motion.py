#!/usr/bin/env python3
"""Render the MOVING-vs-STATIC probe's KP2| window-title payload as a report.

The motion probe (p12_motion.js) tags every rAF frame by how many marquee rows
actually moved that frame and buckets frame time three ways per 20 s block:
all frames, MOVING frames, STATIC frames. The during-MOTION frame time -- the
number the whole investigation is missing -- is the MOVING mean inside a T block.

A payload is only trusted when it LANDED: KP2| present, at least one marquee row
seen (M<n>/<n>, n>0), and at least one T block with moving frames. A capture with
no marquee rows or no moving frames measured nothing and is reported UNMEASURED,
never as a null. Proven against synthetic landed and did-not-land payloads in
parse_motion_test.py before use.
"""
import re
import sys

PAT = (r"KP2\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|M(\d+)/(\d+)"
       r"\|R([\d.:]*)\|P([\d.:]*)\|B(.*)")


def pairs(s):
    """'2:45.3:60' -> [(2,45),(3,60)] (count, meanMs)."""
    out = []
    for e in filter(None, s.split(".")):
        c, _, m = e.partition(":")
        out.append((int(c), int(m or 0)))
    return out


def blocks(s):
    """One record per 20 s block: i,ty,n,meanAll,mn,meanMoving,sn,meanStatic,px."""
    out = []
    for e in filter(None, s.split(";")):
        f = e.split(",")
        if len(f) != 8:
            continue
        head = f[0]                       # e.g. "12T"
        ty = head[-1]
        idx = int(head[:-1])
        out.append(dict(i=idx, ty=ty, n=int(f[1]), mean=int(f[2]),
                        mn=int(f[3]), mmov=int(f[4]),
                        sn=int(f[5]), mstat=int(f[6]), px=int(f[7])))
    return out


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    return dict(sec=int(g[0]), frames=int(g[1]), avg=int(g[2]), max=int(g[3]),
                marquee=int(g[4]), rows=int(g[5]),
                rbuckets=pairs(g[6]), pbuckets=pairs(g[7]), blocks=blocks(g[8]))


def fps(ms):
    return 1000.0 / ms if ms else 0.0


def validate(d):
    """Return (ok, reason). A payload that measured no motion is not a null."""
    if d["marquee"] == 0:
        return False, f"no marquee rows seen (M{d['marquee']}/{d['rows']})"
    tblocks = [b for b in d["blocks"] if b["ty"] == "T" and b["i"] > 0]
    if not tblocks:
        return False, "no T (transform-reading) blocks after block 0"
    if not any(b["mn"] > 0 for b in tblocks):
        return False, "no moving frames captured in any T block"
    return True, "landed"


def report(d, label):
    ok, reason = validate(d)
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  overall mean {d['avg']}ms "
          f"max {d['max']}ms  ~{fps(d['avg']):.1f} fps")
    print(f"marquee rows seen {d['marquee']} of {d['rows']} ride rows")
    if not ok:
        print(f"\n*** UNMEASURED: {reason} -- do NOT read this as a null ***")
        return False

    # Per-block MOVING vs STATIC. Compare only inside one block.
    print("\nper 20s block  (compare MOVING vs STATIC only within a row):")
    print(f"  {'blk':>4}  {'all':>10}  {'MOVING':>16}  {'static':>16}  {'px':>7}")
    mov_ms, mov_n = 0, 0
    for b in d["blocks"]:
        allc = f"{b['n']:4d}f {b['mean']:4d}ms"
        if b["ty"] == "T":
            movc = f"{b['mn']:4d}f {b['mmov']:4d}ms {fps(b['mmov']):4.1f}fps"
            stac = f"{b['sn']:4d}f {b['mstat']:4d}ms {fps(b['mstat']):4.1f}fps"
            if b["i"] > 0 and b["mn"] > 0:
                mov_ms += b["mmov"] * b["mn"]
                mov_n += b["mn"]
        else:
            movc = stac = "  (N: no read)"
        print(f"  {b['i']:>2}{b['ty']}  {allc:>10}  {movc:>16}  {stac:>16}  {b['px']:7d}")

    if mov_n:
        agg = mov_ms / mov_n
        print(f"\nDURING-MOTION (frame-weighted over T blocks, block 0 discarded):")
        print(f"  {mov_n} moving frames, mean {agg:.0f}ms  ~{fps(agg):.2f} fps")

    print("\nframes bucketed by rows moving that frame  (count:meanMs):")
    for i, (c, ms) in enumerate(d["rbuckets"]):
        if c:
            print(f"  {i} rows moving  {c:6d} frames  {ms:5d}ms  ~{fps(ms):4.1f} fps")
    return True


if __name__ == "__main__":
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "KP2|" in l]
    if not lines:
        sys.exit("no KP2| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if not d:
        sys.exit("payload did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
