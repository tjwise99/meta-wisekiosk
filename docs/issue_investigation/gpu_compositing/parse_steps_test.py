#!/usr/bin/env python3
"""Prove parse_steps reports BOTH outcomes before any board number is trusted.

A discriminator that cannot come out both ways discriminates nothing. Synthetic
KP3| payloads exercise the landed case and both did-not-land exits (arm B never
took; no marquee rows at all), and a fourth payload flips the verdict so the
SCORE line is proven not to be a constant. Run: python3 parse_steps_test.py
"""
import contextlib
import io

import parse_steps as ps

R = '3000:38.600:95.500:140.300:200.200:260.0:0.0:0.0:0.0:0'

# Arm A BASELINE blocks: ease-in-out, ~54% of frames moving, 90ms overall.
A_OK = ('{i}A1,280,90,150,142,130,30,1800')
# Arm B STEPS blocks: same MOVING cost, far fewer moving frames, 70ms overall.
B_OK = ('{i}B1,283,70,78,142,205,43,1792')
# Arm B blocks whose computed timing function never showed steps().
B_BAD = ('{i}B0,283,89,148,141,135,32,1780')
# Arm B blocks that landed but came out SLOWER than baseline.
B_SLOW = ('{i}B1,240,110,120,180,120,40,1700')

WARMUP = '0W1,260,95,140,145,120,37,1700'


def payload(bblocks, marquee=6, bfmt=B_OK):
    """Assemble a KP3| title from the warmup block, three A segments and two B."""
    bs = [WARMUP]
    for i in (1, 2, 3, 4, 9, 10, 11, 12, 17, 18, 19, 20):
        bs.append(A_OK.format(i=i))
    for i in bblocks:
        bs.append(bfmt.format(i=i))
    bs.sort(key=lambda b: int(b.split(",")[0][:-2]))
    return (f'KP3|420|f8000|av82|mx1200|M{marquee}/20|R{R}|B' + ";".join(bs))


LANDED = payload([5, 6, 7, 8])
B_NEVER_LANDED = payload([5, 6, 7, 8], bfmt=B_BAD)
NO_ROWS = payload([5, 6, 7, 8], marquee=0)
STEPS_SLOWER = payload([5, 6, 7, 8], bfmt=B_SLOW)

fails = 0


def check(name, title, want_ok, want_reason_sub=None):
    global fails
    d = ps.parse(title)
    assert d is not None, f"{name}: payload did not parse at all"
    ok, reason = ps.validate(d)
    status = "PASS" if ok == want_ok else "FAIL"
    if ok != want_ok:
        fails += 1
    print(f"[{status}] {name}: validate -> ok={ok} ({reason})")
    if want_reason_sub and want_reason_sub not in reason:
        fails += 1
        print(f"       FAIL: expected reason to mention {want_reason_sub!r}")
    return d


def verdict_of(title):
    """Run the full report and return its SCORE line."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ps.report(ps.parse(title), "verdict probe")
    for line in buf.getvalue().splitlines():
        if line.startswith("SCORE:"):
            return line
    return "(no SCORE line)"


d_landed = check("LANDED", LANDED, True)
check("B_NEVER_LANDED", B_NEVER_LANDED, False, "arm B")
check("NO_ROWS", NO_ROWS, False, "marquee rows")
check("STEPS_SLOWER", STEPS_SLOWER, True)

# The blocks that did not land must be dropped, not merely flagged.
d_bad = ps.parse(B_NEVER_LANDED)
if ps.landed(d_bad, "B"):
    fails += 1
    print("       FAIL: land=0 arm B blocks were not dropped")

# Warmup is never aggregated into either arm.
if ps.landed(d_landed, "A") and any(b["arm"] == "W" for b in ps.landed(d_landed, "A")):
    fails += 1
    print("       FAIL: a warmup block leaked into arm A")

# The verdict must be able to come out both ways on the same code path.
v_fast = verdict_of(LANDED)
v_slow = verdict_of(STEPS_SLOWER)
print(f"\nLANDED        -> {v_fast}")
print(f"STEPS_SLOWER  -> {v_slow}")
if "STEPS IS FASTER" not in v_fast:
    fails += 1
    print("       FAIL: LANDED payload should report steps as faster")
if "STEPS IS SLOWER" not in v_slow:
    fails += 1
    print("       FAIL: STEPS_SLOWER payload should report steps as slower")

# Sanity: arm B's advantage is in the moving-frame FRACTION, not the moving cost.
a = ps.aggregate(ps.landed(d_landed, "A"))
b = ps.aggregate(ps.landed(d_landed, "B"))
print(f"\nLANDED arm A overall {a['mean']:.1f}ms (moving {a['movfrac'] * 100:.1f}%)  "
      f"vs arm B overall {b['mean']:.1f}ms (moving {b['movfrac'] * 100:.1f}%)")
if not (b["mean"] < a["mean"]):
    fails += 1
    print("       FAIL: arm B overall mean should be below arm A's")
if not (b["movfrac"] < a["movfrac"]):
    fails += 1
    print("       FAIL: arm B should move on fewer frames than arm A")

print("\n--- full report on the LANDED payload ---")
ps.report(d_landed, "LANDED sample")

print("\n--- full report on the B_NEVER_LANDED payload ---")
ps.report(d_bad, "B_NEVER_LANDED sample")

print()
if fails:
    raise SystemExit(f"{fails} check(s) FAILED")
print("all checks passed")
