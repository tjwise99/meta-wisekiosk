#!/usr/bin/env python3
"""Render the constant-speed A/B probe's KP3| window-title payload as a report.

The duration probe (p16_duration.js) interleaves two arms over one run -- A
BASELINE (the stylesheet's flat 8 s cycle on every row) and B CONSTANT
(`animation-duration: D / (PX_PER_S * MOVE_FRACTION)` per row, floored at 8 s) --
in the palindrome W,A,B,A,B,A, and stamps every 20 s block with the arm that was
applied and a landing flag read in band from getComputedStyle().animationDuration
against each row's OWN target.

Blocks are aggregated BY ARM, frame-weighted. Warmup is dropped, and so is any
block whose computed duration disagreed with the arm that was supposed to be
applied -- a block that did not land measured the probe, not the lever.

The score is PX PER MOVING FRAME: total px moved over an arm's landed blocks,
divided by that arm's moving-frame count. That is the size of the jump between
two rendered positions, which is what reads as judder; slowing a long row spreads
the same overflow across more frames and shrinks it. Frame time is the guard rail,
not the score -- the lever only works if the jump falls while the frame rate does
not, so both means are reported and the verdict tests both.

A payload is only trusted when it LANDED: at least one marquee row seen
(M<n>/<n>, n>0) and at least one landed block on EACH arm. Anything else is
reported UNMEASURED, never as a null.
"""
import re
import sys

PAT = (r"KP3\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|M(\d+)/(\d+)"
       r"\|R([\d.:]*)\|B(.*)")

HEAD = re.compile(r"^(\d+)([WAB])([01])$")

# Report margins for the verdict. These are the thresholds the write-up is read
# against, not a measurement: nothing in this record derives them.
CLEAR_DROP = 0.10   # px/moving-frame must fall by at least this fraction
FPS_SLACK = 0.05    # overall mean frame time may rise by at most this fraction


def pairs(s):
    """'2:45.3:60' -> [(2,45),(3,60)] (count, meanMs)."""
    out = []
    for e in filter(None, s.split(".")):
        c, _, m = e.partition(":")
        out.append((int(c), int(m or 0)))
    return out


def blocks(s):
    """One record per 20 s block: i,arm,land,n,meanAll,mn,meanMoving,sn,meanStatic,px."""
    out = []
    for e in filter(None, s.split(";")):
        f = e.split(",")
        if len(f) != 8:
            continue
        h = HEAD.match(f[0])                  # e.g. "5B1"
        if not h:
            continue
        out.append(dict(i=int(h.group(1)), arm=h.group(2), land=int(h.group(3)),
                        n=int(f[1]), mean=int(f[2]),
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
                rbuckets=pairs(g[6]), blocks=blocks(g[7]))


def fps(ms):
    return 1000.0 / ms if ms else 0.0


def landed(d, arm):
    """Blocks on `arm` that landed. Warmup is never an arm."""
    return [b for b in d["blocks"] if b["arm"] == arm and b["land"] == 1]


def aggregate(bs):
    """Frame-weighted roll-up of a list of blocks."""
    n = sum(b["n"] for b in bs)
    mn = sum(b["mn"] for b in bs)
    sn = sum(b["sn"] for b in bs)
    px = sum(b["px"] for b in bs)
    return dict(
        nblocks=len(bs), n=n, mn=mn, sn=sn, px=px,
        mean=(sum(b["mean"] * b["n"] for b in bs) / n) if n else 0.0,
        mmov=(sum(b["mmov"] * b["mn"] for b in bs) / mn) if mn else 0.0,
        mstat=(sum(b["mstat"] * b["sn"] for b in bs) / sn) if sn else 0.0,
        movfrac=(mn / n) if n else 0.0,
        pxpf=(px / mn) if mn else 0.0,
    )


def validate(d):
    """Return (ok, reason). A payload whose arms did not land is not a null."""
    if d["marquee"] == 0:
        return False, f"no marquee rows seen (M{d['marquee']}/{d['rows']})"
    if not landed(d, "A"):
        return False, ("arm A (baseline) has no landed blocks -- the duration "
                       "override was never removed, or no A block was captured")
    if not landed(d, "B"):
        return False, ("arm B (constant speed) has no landed blocks -- the "
                       "per-row duration override never took on a live marquee row")
    return True, "landed"


def arm_line(tag, a):
    print(f"  {tag}  {a['nblocks']:2d} blocks  {a['n']:6d} frames  "
          f"mean {a['mean']:6.1f}ms  ~{fps(a['mean']):5.2f} fps")
    print(f"       moving {a['movfrac'] * 100:5.1f}% of frames  "
          f"MOVING {a['mmov']:6.1f}ms ~{fps(a['mmov']):5.2f} fps   "
          f"static {a['mstat']:6.1f}ms ~{fps(a['mstat']):5.2f} fps")
    print(f"       JUMP   {a['mn']:6d} moving frames  {a['px']:9d} px  "
          f"{a['pxpf']:6.2f} px/moving-frame")


def report(d, label):
    ok, reason = validate(d)
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  overall mean {d['avg']}ms "
          f"max {d['max']}ms  ~{fps(d['avg']):.1f} fps")
    print(f"marquee rows seen {d['marquee']} of {d['rows']} ride rows")

    print("\nper 20s block  (arm, land, then all / MOVING / static):")
    print(f"  {'blk':>6}  {'all':>10}  {'MOVING':>16}  {'static':>16}  {'px':>7}")
    for b in d["blocks"]:
        allc = f"{b['n']:4d}f {b['mean']:4d}ms"
        movc = f"{b['mn']:4d}f {b['mmov']:4d}ms {fps(b['mmov']):4.1f}fps"
        stac = f"{b['sn']:4d}f {b['mstat']:4d}ms {fps(b['mstat']):4.1f}fps"
        mark = "" if (b["land"] and b["arm"] != "W") else "  <- dropped"
        print(f"  {b['i']:>2}{b['arm']}{b['land']}  {allc:>10}  {movc:>16}  "
              f"{stac:>16}  {b['px']:7d}{mark}")

    if not ok:
        print(f"\n*** UNMEASURED: {reason} -- do NOT read this as a null ***")
        return False

    a = aggregate(landed(d, "A"))
    b = aggregate(landed(d, "B"))
    print("\nBY ARM (warmup and land=0 blocks dropped, frame-weighted):")
    arm_line("A BASELINE", a)
    arm_line("B CONSTANT", b)

    d_px = b["pxpf"] - a["pxpf"]
    d_all = b["mean"] - a["mean"]
    d_mov = b["mmov"] - a["mmov"]
    drop = (-d_px / a["pxpf"]) if a["pxpf"] else 0.0
    cost = (d_all / a["mean"]) if a["mean"] else 0.0

    print(f"\nA -> B delta, px/moving-frame: {d_px:+.2f} px "
          f"({a['pxpf']:.2f} -> {b['pxpf']:.2f}, {-drop * 100:+.1f}% jump)")
    print(f"A -> B delta, overall mean:    {d_all:+.1f}ms "
          f"({fps(a['mean']):.2f} -> {fps(b['mean']):.2f} fps, {cost * 100:+.1f}% frame time)")
    print(f"A -> B delta, MOVING mean:     {d_mov:+.1f}ms "
          f"({fps(a['mmov']):.2f} -> {fps(b['mmov']):.2f} fps)")

    smaller = drop >= CLEAR_DROP
    affordable = cost <= FPS_SLACK
    if smaller and affordable:
        verdict = (f"THE LEVER WORKS -- constant speed cuts the jump "
                   f"{drop * 100:.1f}% ({a['pxpf']:.2f} -> {b['pxpf']:.2f} px per "
                   f"moving frame) for {cost * 100:+.1f}% frame time")
    elif smaller:
        verdict = (f"THE LEVER COSTS TOO MUCH -- the jump falls {drop * 100:.1f}% "
                   f"but frame time rises {cost * 100:.1f}%, past the "
                   f"{FPS_SLACK * 100:.0f}% margin")
    else:
        verdict = (f"THE LEVER DOES NOT WORK -- the jump falls {drop * 100:.1f}%, "
                   f"short of the {CLEAR_DROP * 100:.0f}% this report calls clear "
                   f"({a['pxpf']:.2f} -> {b['pxpf']:.2f} px per moving frame)")
    print(f"SCORE: {verdict}.")
    print(f"       The score is px per moving frame -- the lever wins by spreading a "
          f"long name's overflow\n       across more frames, not by making a frame "
          f"cheaper. Margins: jump must fall >= "
          f"{CLEAR_DROP * 100:.0f}%, frame time may rise <= {FPS_SLACK * 100:.0f}%.")

    print("\nframes bucketed by rows moving that frame  (count:meanMs):")
    for i, (c, ms) in enumerate(d["rbuckets"]):
        if c:
            print(f"  {i} rows moving  {c:6d} frames  {ms:5d}ms  ~{fps(ms):4.1f} fps")
    return True


if __name__ == "__main__":
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "KP3|" in l]
    if not lines:
        sys.exit("no KP3| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if not d:
        sys.exit("payload did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
