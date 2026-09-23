#!/usr/bin/env python3
"""Prove parse_mqtoggle.py reports BOTH outcomes and refuses to score an unlanded capture.

A discriminator that cannot come out both ways discriminates nothing (measure-first discipline).
Run: python3 parse_mqtoggle_test.py  -- exits 0 only if every case matches.
"""
import io
from contextlib import redirect_stdout

import parse_mqtoggle as P


def run(title):
    d = P.parse(title)
    assert d is not None, "payload did not parse: " + title
    buf = io.StringIO()
    with redirect_stdout(buf):
        P.report(d, "test")
    return buf.getvalue()


def mq(A, C, N=6, sec=420, frames=6700, big=84):
    # A / C are (n, big, mean, mx, aran) tuples
    def a(t):
        return ".".join(str(x) for x in t)
    return (f"MQ|{sec}|f{frames}|av120|mx2000|BT{big}|N{N}"
            f"|A:{a(A)}|C:{a(C)}|H1000.2000.3000.500.100.50.50|B")


CASES = [
    # (label, title, must-contain, must-NOT-contain)
    ("confirm: ALLOC misses far more than CLEAN",
     mq(A=(200, 80, 400, 2000, 200), C=(200, 4, 25, 300, 0)),
     "STALL TRACKS THE MARQUEE ALLOCATION", "does NOT track"),
    ("null: ALLOC and CLEAN miss the same",
     mq(A=(200, 6, 30, 300, 200), C=(200, 5, 29, 300, 0)),
     "does NOT track the marquee allocation", "STALL TRACKS"),
    ("unmeasured: no marquee columns (N=0)",
     mq(A=(200, 80, 400, 2000, 200), C=(200, 4, 25, 300, 0), N=0),
     "UNMEASURED", "VERDICT"),
    ("unmeasured: ALLOC path never ran in ALLOC arm (toggle did not land)",
     mq(A=(200, 80, 400, 2000, 10), C=(200, 4, 25, 300, 0)),
     "toggle did not land", "VERDICT"),
    ("unmeasured: CLEAN arm ran the alloc path a lot (toggle leaked)",
     mq(A=(200, 80, 400, 2000, 200), C=(200, 4, 25, 300, 40)),
     "toggle leaked", "VERDICT"),
    ("landed: a few CLEAN-arm boundary frames are tolerated",
     mq(A=(200, 6, 30, 300, 200), C=(200, 5, 29, 300, 3)),
     "does NOT track the marquee allocation", "UNMEASURED"),
    ("unmeasured: an arm captured no frames",
     mq(A=(0, 0, 0, 0, 0), C=(200, 4, 25, 300, 0)),
     "interleave did not run", "VERDICT"),
]

ok = True
for label, title, must, mustnot in CASES:
    out = run(title)
    if must not in out:
        print(f"FAIL [{label}]: expected {must!r} in output\n---\n{out}")
        ok = False
    elif mustnot in out:
        print(f"FAIL [{label}]: did NOT expect {mustnot!r} in output\n---\n{out}")
        ok = False
    else:
        print(f"ok   [{label}]")

raise SystemExit(0 if ok else 1)
