"""Self-test for parse_rotation.py. Verifies the EXTRACTION is correct and honest (the scaling verdict
lives in the run block, not here): the uniform >=250ms threshold, the 2s clustering, the R[] cap
detection (a capped series must NOT be read as a full measurement), and that a clean 30s beat shows
~30s gaps while a clean 60s beat shows ~60s gaps -- the discriminator that separates '5x=30 with
dropout' from 'stuck at 60'. Also re-derives the three committed captures."""
import sys, tempfile, os, os.path as op
import parse_rotation as pr

def cap(rot_dt, beat_dt=None, beat_ms=450, extra=(), el=600, rots_n=None):
    n = rots_n if rots_n is not None else int(el / rot_dt)
    rots = [round(rot_dt * (i + 1), 1) for i in range(n)]
    stalls = [(2.0, 1500), (4.0, 1100)]  # startup, always excluded (t<15)
    if beat_dt:
        stalls += [(round(beat_dt * (i + 1), 1), beat_ms) for i in range(1, int((el - 20) / beat_dt) + 1)]
    stalls += list(extra)
    stalls.sort()
    s = ','.join(f'{t}:{d}' for t, d in stalls)
    r = ','.join(str(x) for x in rots)
    return f'x | BL|{el}|f27000|big{len(stalls)}|mx2519|S[{s}]|R[{r}]'

def an(text):
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as f:
        f.write(text); p = f.name
    try:
        return pr.analyse(pr.parse(p))
    finally:
        os.unlink(p)

def check(name, cond):
    print(('  ok  ' if cond else ' FAIL ') + name); return cond

ok = True

# rotation extraction + a clean 5x beat: rot 10 -> 50s gaps
a = an(cap(10.0, 50.0))
ok &= check('rot median = 10', a['rot_med'] == 10.0)
ok &= check('50s beat -> gaps all 50', set(a['gaps']) == {50.0})
ok &= check('50s beat on the 50s grid', a['on'] == len(a['events']) and a['off'] == 0)
ok &= check('not capped when R[] covers the window', a['rots_capped'] is False)

# the DISCRIMINATOR: a clean 30s beat has ~30 gaps; a clean 60s beat has ~60 gaps
a30 = an(cap(6.0, 30.0)); a60 = an(cap(6.0, 60.0))
ok &= check('30s beat -> min gap ~30 (=5x6, scaled)', min(a30['gaps']) == 30.0)
ok &= check('60s beat -> min gap ~60 (would be NOT scaled)', min(a60['gaps']) == 60.0)

# UNIFORM threshold: 260ms counts, 240ms does not
a = an(cap(8.0, beat_dt=None, extra=((100.0, 260), (200.0, 240), (300.0, 260))))
ok &= check('260ms arrivals kept, 240ms dropped', a['events'] == [100.0, 300.0])

# CLUSTERING: two arrivals 0.6s apart are one event
a = an(cap(10.0, 50.0, extra=((100.6, 450),)))
ok &= check('0.6s-apart pair clusters to one event', 100.6 not in a['events'])

# CAP DETECTION: 80 R[] events ending well before the window -> flagged, not read as full
a = an(cap(6.0, 30.0, el=600, rots_n=80))
ok &= check('R[] with exactly 80 events short of window -> rots_capped', a['rots_capped'] is True)

# the three REAL captures re-derive (regression against committed data)
here = op.dirname(op.abspath(__file__))
expect = {
    'rotation-8s-589s-raw.txt':  dict(rot=8.0,  first=41.9, capped=False),
    'rotation-12s-586s-raw.txt': dict(rot=12.0, first=60.5, capped=False),
    'rotation-6s-588s-raw.txt':  dict(rot=6.0,  first=30.5, capped=True),
}
for fn, e in expect.items():
    fp = op.join(here, fn)
    if op.exists(fp):
        a = pr.analyse(pr.parse(fp))
        ok &= check(f'{fn}: rot={e["rot"]}, first arrival {e["first"]}, capped={e["capped"]}',
                    a['rot_med'] == e['rot'] and a['events'][0] == e['first'] and a['rots_capped'] is e['capped'])

print('PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)
