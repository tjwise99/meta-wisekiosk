#!/usr/bin/env python3
"""Prove parse_ablate.py reports every outcome and refuses an unlanded capture."""
import io
from contextlib import redirect_stdout

import parse_ablate as P


def run(title):
    d = P.parse(title)
    assert d is not None, "did not parse: " + title
    buf = io.StringIO()
    with redirect_stdout(buf):
        P.report(d, "test")
    return buf.getvalue()


def ab(N, R, C):
    def c(t):
        return ".".join(str(x) for x in t)
    return f"AB|470|f18000|big40|N:{c(N)}|R:{c(R)}|C:{c(C)}|B"


# (n, big, mean, mx, rotSkip, clkSkip)
CASES = [
    ("rotation is the driver",
     ab(N=(5000, 60, 30, 1400, 0, 0), R=(5000, 6, 24, 300, 18, 0), C=(5000, 58, 30, 1400, 0, 150)),
     ["rotation: ablating it CUTS", "clock: ablating it leaves"], ["UNMEASURED"]),
    ("clock is the driver",
     ab(N=(5000, 60, 30, 1400, 0, 0), R=(5000, 58, 30, 1400, 18, 0), C=(5000, 6, 24, 300, 0, 150)),
     ["clock: ablating it CUTS", "rotation: ablating it leaves"], ["UNMEASURED"]),
    ("neither is the driver",
     ab(N=(5000, 55, 30, 1400, 0, 0), R=(5000, 57, 30, 1400, 18, 0), C=(5000, 54, 30, 1400, 0, 150)),
     ["rotation: ablating it leaves", "clock: ablating it leaves"], ["UNMEASURED", "CUTS"]),
    ("unmeasured: rotation toggle did not land",
     ab(N=(5000, 60, 30, 1400, 0, 0), R=(5000, 6, 24, 300, 0, 0), C=(5000, 6, 24, 300, 0, 150)),
     ["UNMEASURED", "rotation toggle did not land"], ["VERDICT"]),
    ("unmeasured: toggles crossed (R also skipped clock)",
     ab(N=(5000, 60, 30, 1400, 0, 0), R=(5000, 6, 24, 300, 18, 9), C=(5000, 6, 24, 300, 0, 150)),
     ["UNMEASURED", "toggles crossed"], ["VERDICT"]),
    ("unmeasured: N ablated something (leak)",
     ab(N=(5000, 60, 30, 1400, 2, 0), R=(5000, 6, 24, 300, 18, 0), C=(5000, 6, 24, 300, 0, 150)),
     ["UNMEASURED", "leak"], ["VERDICT"]),
]

ok = True
for label, title, musts, mustnots in CASES:
    out = run(title)
    for m in musts:
        if m not in out:
            print(f"FAIL [{label}]: expected {m!r}\n---\n{out}"); ok = False
    for mn in mustnots:
        if mn in out:
            print(f"FAIL [{label}]: did NOT expect {mn!r}\n---\n{out}"); ok = False
    if ok:
        print(f"ok   [{label}]")

raise SystemExit(0 if ok else 1)
