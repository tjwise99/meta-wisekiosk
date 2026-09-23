#!/usr/bin/env python3
"""Render the scrollLeft-vs-transform probe's KP18| window-title payload as a report.

The scroll probe (p18_scroll.js) interleaves two arms over one run -- T TRANSFORM
(the app's own `transform: translateX()` marquee animation) and S SCROLL (the
animation suppressed, the probe driving `.ride-name`'s scrollLeft over the same
cycle at the same speed) -- in the palindrome W,T,S,T,S,T, and stamps every 20 s
block with the arm that was applied and a landing flag read in band.

parse_steps.py does NOT read this payload and must not be pointed at it: the tag
is KP18| rather than KP3|, the arm letters are T/S rather than A/B, and the block
record is six fields rather than eight. There is no MOVING/static split here,
because computing one would mean reading computed transform on every row every
frame -- the per-row style flush the probe exists to keep out of the measurement.

The headline is the frame-weighted MEAN FRAME TIME per arm, and its fps. Each
block carries its frame count and its SUMMED frame time, so the roll-up across
blocks is exact rather than a mean of rounded means.

Blocks are aggregated BY ARM. Warmup is dropped, and so is any block that did not
land -- it measured the probe, not the mechanism. A payload is only trusted when
at least one marquee row was seen and at least one block landed on EACH arm.
Anything else is reported UNMEASURED, never as a null. Proven against synthetic
landed, did-not-land and verdict-flipped payloads before use.
"""
import re
import sys

PAT = (r"KP18\|(\d+)\|f(\d+)\|av(\d+)\|mx(\d+)\|M(\d+)/(\d+)"
       r"\|D([\d.]*)\|B(.*)")

HEAD = re.compile(r"^(\d+)([WTS])([01])$")

ARM_NAME = {"T": "T TRANSFORM", "S": "S SCROLL   "}


def dists(s):
    """'843.612.400' -> [843, 612, 400]; the row overflow distances, px."""
    return [int(e) for e in filter(None, s.split("."))]


def blocks(s):
    """One record per 20 s block: i,arm,land,frames,sumMs,maxMs,samples,maxScrollLeft."""
    out = []
    for e in filter(None, s.split(";")):
        f = e.split(",")
        if len(f) != 6:
            continue
        h = HEAD.match(f[0])                  # e.g. "5S1"
        if not h:
            continue
        n = int(f[1])
        tot = int(f[2])
        out.append(dict(i=int(h.group(1)), arm=h.group(2), land=int(h.group(3)),
                        n=n, tot=tot, mean=(tot / n) if n else 0.0,
                        mx=int(f[3]), smp=int(f[4]), sx=int(f[5])))
    return out


def parse(title):
    m = re.search(PAT, title)
    if not m:
        return None
    g = m.groups()
    return dict(sec=int(g[0]), frames=int(g[1]), avg=int(g[2]), max=int(g[3]),
                marquee=int(g[4]), rows=int(g[5]),
                dists=dists(g[6]), blocks=blocks(g[7]))


def fps(ms):
    return 1000.0 / ms if ms else 0.0


def landed(d, arm):
    """Blocks on `arm` that landed. Warmup is never an arm."""
    return [b for b in d["blocks"] if b["arm"] == arm and b["land"] == 1]


def aggregate(bs):
    """Frame-weighted roll-up, computed from summed frame time, not from means."""
    n = sum(b["n"] for b in bs)
    tot = sum(b["tot"] for b in bs)
    return dict(
        nblocks=len(bs), n=n, tot=tot,
        mean=(tot / n) if n else 0.0,
        mx=max([b["mx"] for b in bs], default=0),
    )


def validate(d):
    """Return (ok, reason). A payload whose arms did not land is not a null."""
    if d["marquee"] == 0:
        return False, f"no marquee rows seen (M{d['marquee']}/{d['rows']})"
    if not landed(d, "T"):
        return False, ("arm T (transform) has no landed blocks -- the scroll "
                       "override was never removed, or no T block was captured")
    if not landed(d, "S"):
        return False, ("arm S (scroll) has no landed blocks -- the override never "
                       "took on a live marquee row, or scrollLeft never moved")
    return True, "landed"


def arm_line(a, arm):
    print(f"  {ARM_NAME[arm]}  {a['nblocks']:2d} blocks  {a['n']:6d} frames  "
          f"mean {a['mean']:6.1f}ms  ~{fps(a['mean']):5.2f} fps   "
          f"worst {a['mx']:5d}ms")


def report(d, label):
    ok, reason = validate(d)
    print(f"===== {label} =====")
    print(f"window {d['sec']}s  frames {d['frames']}  overall mean {d['avg']}ms "
          f"max {d['max']}ms  ~{fps(d['avg']):.1f} fps")
    print(f"marquee rows seen {d['marquee']} of {d['rows']} ride rows; "
          f"overflow distances {d['dists']} px")

    print("\nper 20s block  (arm, land, frames, mean, worst, samples, max scrollLeft):")
    print(f"  {'blk':>6}  {'frames':>7}  {'mean':>10}  {'worst':>7}  "
          f"{'smp':>4}  {'maxSL':>6}")
    for b in d["blocks"]:
        mark = "" if (b["land"] and b["arm"] != "W") else "  <- dropped"
        # A transform arm that sees a live scroll offset is contaminated, not invalid:
        # flag it rather than silently folding it into the mean.
        if b["arm"] == "T" and b["sx"] > 0:
            mark += "  !! scroll leaked into arm T"
        print(f"  {b['i']:>2}{b['arm']}{b['land']}  {b['n']:7d}  "
              f"{b['mean']:7.1f}ms  {b['mx']:5d}ms  {b['smp']:4d}  "
              f"{b['sx']:6d}{mark}")

    if not ok:
        print(f"\n*** UNMEASURED: {reason} -- do NOT read this as a null ***")
        return False

    t = aggregate(landed(d, "T"))
    s = aggregate(landed(d, "S"))
    print("\nBY ARM (warmup and land=0 blocks dropped, frame-weighted):")
    arm_line(t, "T")
    arm_line(s, "S")

    delta = s["mean"] - t["mean"]
    print(f"\nT -> S delta, mean frame time: {delta:+.1f}ms "
          f"({t['mean']:.1f} -> {s['mean']:.1f}ms, "
          f"{fps(t['mean']):.2f} -> {fps(s['mean']):.2f} fps)")

    if delta < 0:
        verdict = (f"SCROLL IS CHEAPER than transform: {s['mean']:.1f}ms vs "
                   f"{t['mean']:.1f}ms per frame "
                   f"({fps(s['mean']):.2f} vs {fps(t['mean']):.2f} fps)")
    elif delta > 0:
        verdict = (f"SCROLL IS DEARER than transform: {s['mean']:.1f}ms vs "
                   f"{t['mean']:.1f}ms per frame "
                   f"({fps(s['mean']):.2f} vs {fps(t['mean']):.2f} fps)")
    else:
        verdict = (f"SCROLL AND TRANSFORM TIE at {s['mean']:.1f}ms per frame "
                   f"({fps(s['mean']):.2f} fps)")
    print(f"SCORE: {verdict}.")
    print("       Both arms move every row the same distance at the same px/s, so the "
          "delta is the mechanism.")
    return True


if __name__ == "__main__":
    text = open(sys.argv[1]).read().replace(chr(34), "")
    lines = [l for l in text.splitlines() if "KP18|" in l]
    if not lines:
        sys.exit("no KP18| payload in " + sys.argv[1])
    d = parse(lines[-1])
    if not d:
        sys.exit("payload did not match:\n" + lines[-1][:400])
    report(d, sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
