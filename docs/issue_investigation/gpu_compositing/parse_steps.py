#!/usr/bin/env python3
"""Render the steps() A/B probe's KP3| window-title payload as a report.

The steps probe (p13_steps.js) interleaves two arms over one run -- A BASELINE
(the stylesheet's ease-in-out timing function) and B STEPS
(`animation-timing-function: steps(K, jump-none)`) -- in the palindrome
W,A,B,A,B,A, and stamps every 20 s block with the arm that was applied and a
landing flag read in band from getComputedStyle().animationTimingFunction.

Blocks are aggregated BY ARM, frame-weighted. Warmup is dropped, and so is any
block whose computed timing function disagreed with the arm that was supposed to
be applied -- a block that did not land measured the probe, not steps().

The score is the OVERALL frame-weighted mean, not the MOVING mean: steps() is
expected to win by turning most frames into cheap static ones, not by making a
moving frame cheaper. Both are reported so a win of the wrong shape is visible.

A payload is only trusted when it LANDED: at least one marquee row seen
(M<n>/<n>, n>0) and at least one landed block on EACH arm. Anything else is
reported UNMEASURED, never as a null. Proven against synthetic landed and
did-not-land payloads in parse_steps_test.py before use.
"""
import re
import sys

PAT = (r"KP3\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|M(\d+)/(\d+)"
       r"\|R([\d.:]*)\|B(.*)")

HEAD = re.compile(r"^(\d+)([WAB])([01])$")


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
    return dict(
        nblocks=len(bs), n=n, mn=mn, sn=sn,
        mean=(sum(b["mean"] * b["n"] for b in bs) / n) if n else 0.0,
        mmov=(sum(b["mmov"] * b["mn"] for b in bs) / mn) if mn else 0.0,
        mstat=(sum(b["mstat"] * b["sn"] for b in bs) / sn) if sn else 0.0,
        movfrac=(mn / n) if n else 0.0,
    )


def validate(d):
    """Return (ok, reason). A payload whose arms did not land is not a null."""
    if d["marquee"] == 0:
        return False, f"no marquee rows seen (M{d['marquee']}/{d['rows']})"
    if not landed(d, "A"):
        return False, ("arm A (baseline) has no landed blocks -- the steps() "
                       "override was never removed, or no A block was captured")
    if not landed(d, "B"):
        return False, ("arm B (steps) has no landed blocks -- the steps() "
                       "override never took on a live marquee row")
    return True, "landed"


def arm_line(tag, a):
    print(f"  {tag}  {a['nblocks']:2d} blocks  {a['n']:6d} frames  "
          f"mean {a['mean']:6.1f}ms  ~{fps(a['mean']):5.2f} fps")
    print(f"       moving {a['movfrac'] * 100:5.1f}% of frames  "
          f"MOVING {a['mmov']:6.1f}ms ~{fps(a['mmov']):5.2f} fps   "
          f"static {a['mstat']:6.1f}ms ~{fps(a['mstat']):5.2f} fps")


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
    arm_line("B STEPS   ", b)

    d_all = b["mean"] - a["mean"]
    d_mov = b["mmov"] - a["mmov"]
    print(f"\nA -> B delta, overall mean: {d_all:+.1f}ms "
          f"({fps(a['mean']):.2f} -> {fps(b['mean']):.2f} fps)")
    print(f"A -> B delta, MOVING mean:  {d_mov:+.1f}ms "
          f"({fps(a['mmov']):.2f} -> {fps(b['mmov']):.2f} fps)")

    if d_all < 0:
        verdict = (f"STEPS IS FASTER than baseline on the overall frame-weighted "
                   f"mean ({b['mean']:.1f}ms vs {a['mean']:.1f}ms)")
    elif d_all > 0:
        verdict = (f"STEPS IS SLOWER than baseline on the overall frame-weighted "
                   f"mean ({b['mean']:.1f}ms vs {a['mean']:.1f}ms)")
    else:
        verdict = (f"STEPS AND BASELINE TIE on the overall frame-weighted mean "
                   f"({b['mean']:.1f}ms)")
    print(f"SCORE: {verdict}.")
    print("       The score is the overall mean -- steps() wins by making most "
          "frames static, not by making a moving frame cheaper.")

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
