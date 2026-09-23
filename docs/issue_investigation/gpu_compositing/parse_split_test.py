#!/usr/bin/env python3
"""Prove parse_split.py reports every outcome and refuses an unlanded capture."""
import io
from contextlib import redirect_stdout
import parse_split as P


def run(title):
    d = P.parse(title); assert d is not None, "did not parse: " + title
    buf = io.StringIO()
    with redirect_stdout(buf):
        P.report(d, "test")
    return buf.getvalue()


def sp(N, M, R):
    def c(t): return ".".join(str(x) for x in t)
    return f"SP|470|f18000|big30|N:{c(N)}|M:{c(M)}|R:{c(R)}|B"


# (n, big, mean, mx, mmReal, rotSkip)
CASES = [
    ("matchMedia is the dominant fix",
     sp(N=(5000, 60, 30, 1400, 300, 0), M=(5000, 4, 23, 300, 0, 0), R=(5000, 0, 22, 210, 0, 18)),
     ["matchMedia caching is the (dominant) fix"], ["UNMEASURED"]),
    ("matchMedia is NOT the driver (derived recompute is)",
     sp(N=(5000, 60, 30, 1400, 300, 0), M=(5000, 58, 30, 1400, 0, 0), R=(5000, 0, 22, 210, 0, 18)),
     ["matchMedia is NOT the driver", "derived recompute"], ["UNMEASURED"]),
    ("matchMedia is a partial contributor",
     sp(N=(5000, 60, 30, 1400, 300, 0), M=(5000, 30, 27, 800, 0, 0), R=(5000, 0, 22, 210, 0, 18)),
     ["PARTIAL contributor"], ["UNMEASURED"]),
    ("unmeasured: cache toggle did not land",
     sp(N=(5000, 60, 30, 1400, 300, 0), M=(5000, 4, 23, 300, 250, 0), R=(5000, 0, 22, 210, 0, 18)),
     ["UNMEASURED", "cache toggle did not land"], ["VERDICT"]),
    ("unmeasured: rotation toggle did not land",
     sp(N=(5000, 60, 30, 1400, 300, 0), M=(5000, 4, 23, 300, 0, 0), R=(5000, 0, 22, 210, 0, 0)),
     ["UNMEASURED", "rotation toggle did not land"], ["VERDICT"]),
    ("unmeasured: N never called matchMedia",
     sp(N=(5000, 60, 30, 1400, 0, 0), M=(5000, 4, 23, 300, 0, 0), R=(5000, 0, 22, 210, 0, 18)),
     ["UNMEASURED", "no uncached matchMedia"], ["VERDICT"]),
]
ok = True
for label, title, musts, mustnots in CASES:
    out = run(title)
    for m in musts:
        if m not in out: print(f"FAIL [{label}]: want {m!r}\n{out}"); ok = False
    for mn in mustnots:
        if mn in out: print(f"FAIL [{label}]: unwanted {mn!r}\n{out}"); ok = False
    if ok: print(f"ok   [{label}]")
raise SystemExit(0 if ok else 1)
