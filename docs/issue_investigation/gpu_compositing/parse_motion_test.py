#!/usr/bin/env python3
"""Prove parse_motion reports BOTH outcomes before any board number is trusted.

A discriminator that cannot come out both ways discriminates nothing. Three
synthetic KP2| payloads exercise the landed case and the two did-not-land cases
(no marquee rows; marquee rows but zero moving frames). Run: python3 parse_motion_test.py
"""
import parse_motion as pm

# --- Landed: marquee rows seen, T blocks with moving frames, motion slower than static
LANDED = (
    'KP2|500|f8000|av90|mx1200|M6/20'
    '|R3000:38.600:95.500:140.300:200.200:260.0:0.0:0.0:0.0:0'
    '|P3000:38.900:120.600:180.300:240.100:300.0:0.0:0'
    '|B0T,700,45,300,84,400,20,12000;1T,650,90,250,180,400,35,9000;'
    '2T,640,88,240,175,400,34,8800;3N,600,42,0,0,0,0,0;'
    '4T,660,86,255,170,405,33,9100'
)

# --- Did not land: no marquee rows on the page (M0/20)
NO_ROWS = (
    'KP2|500|f8000|av40|mx900|M0/20'
    '|R8000:40.0:0.0:0.0:0.0:0.0:0.0:0.0:0.0:0'
    '|P8000:40.0:0.0:0.0:0.0:0.0:0.0:0'
    '|B0T,700,40,0,0,700,40,0;1T,650,40,0,0,650,40,0;3N,600,42,0,0,0,0,0'
)

# --- Did not land: rows present but nothing ever moved (animation not running)
NO_MOTION = (
    'KP2|500|f8000|av44|mx900|M6/20'
    '|R8000:44.0:0.0:0.0:0.0:0.0:0.0:0.0:0.0:0'
    '|P8000:44.0:0.0:0.0:0.0:0.0:0.0:0'
    '|B0T,700,44,0,0,700,44,0;1T,650,44,0,0,650,44,0;3N,600,42,0,0,0,0,0'
)

fails = 0


def check(name, payload, want_ok, want_reason_sub=None):
    global fails
    d = pm.parse(payload)
    assert d is not None, f"{name}: payload did not parse at all"
    ok, reason = pm.validate(d)
    status = "PASS" if ok == want_ok else "FAIL"
    if ok != want_ok:
        fails += 1
    print(f"[{status}] {name}: validate -> ok={ok} ({reason})")
    if want_reason_sub and want_reason_sub not in reason:
        fails += 1
        print(f"       FAIL: expected reason to mention {want_reason_sub!r}")


check("LANDED", LANDED, True)
check("NO_ROWS", NO_ROWS, False, "no marquee rows")
check("NO_MOTION", NO_MOTION, False, "no moving frames")

# Sanity: the landed payload's during-motion fps is well below its overall mean.
d = pm.parse(LANDED)
tblocks = [b for b in d["blocks"] if b["ty"] == "T" and b["i"] > 0 and b["mn"] > 0]
mov_ms = sum(b["mmov"] * b["mn"] for b in tblocks) / sum(b["mn"] for b in tblocks)
mov_fps = pm.fps(mov_ms)
overall_fps = pm.fps(d["avg"])
print(f"\nLANDED during-motion mean {mov_ms:.0f}ms (~{mov_fps:.2f} fps) "
      f"vs overall ~{overall_fps:.1f} fps")
if not (mov_fps < overall_fps):
    fails += 1
    print("       FAIL: during-motion fps should be below the overall mean")

print("\n--- full report on the LANDED payload ---")
pm.report(d, "LANDED sample")

print()
if fails:
    raise SystemExit(f"{fails} check(s) FAILED")
print("all checks passed")
