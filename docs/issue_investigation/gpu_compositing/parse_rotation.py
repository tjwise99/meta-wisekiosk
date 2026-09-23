"""Parse a Run 48 rotation-interval capture (p31_rotcheck.js output). An AID, not the verdict: the run
block does the careful reasoning, as every parser in this investigation does. It extracts, under a
UNIFORM >=250ms threshold (the probe's own stall cutoff -- NOT an amplitude cut that would demote one
arm's weaker-but-on-grid stalls), the rotation interval actually driven (R[] median, with a CAP flag
because p31 caps R[] at 80), the >=250ms beat arrivals and their gaps, and how well those arrivals fit
a 5x-tick grid (fraction within +/-3s of a 5*rotation multiple, and the dropout). A capped R[] is
flagged, not read as a measurement; a beat that did not scale reads as a low grid-fit, not forced."""
import re, sys, statistics

STRONG_MS = 250      # the probe's own >250ms stall cutoff -- uniform across arms, declared here
STARTUP_S = 15.0     # exclude the mount/first-paint cluster
CLUSTER_S = 2.0      # two frames of one collection within ~2s -> one event
GRID_TOL = 3.0       # +/-3s of a 5*rotation multiple counts as on-grid (the record's on-beat window)
ROTS_CAP = 80        # p31_rotcheck.js caps rots.length < 80

def parse(path):
    txt = open(path).read()
    m = re.search(r'BL\|(\d+)\|f(\d+)\|big(\d+)\|mx(\d+)\|S\[([^\]]*)\]\|R\[([^\]]*)\]', txt)
    if not m:
        raise ValueError(f'{path}: no p31 (BL|...|S[...]|R[...]) payload found')
    el, fr, big, mx = (int(m.group(i)) for i in range(1, 5))
    stalls = [(float(t), int(d)) for t, d in (e.split(':') for e in m.group(5).split(',') if e)]
    rots = [float(x) for x in m.group(6).split(',') if x]
    return dict(path=path, el=el, fr=fr, big=big, mx=mx, stalls=stalls, rots=rots)

def analyse(r):
    rg = sorted(round(r['rots'][i + 1] - r['rots'][i], 1) for i in range(len(r['rots']) - 1))
    rot_med = round(statistics.median(rg), 2) if rg else None
    rots_capped = len(r['rots']) >= ROTS_CAP and (r['rots'][-1] < r['el'] - rot_med if rot_med else False)
    # beat arrivals: >=250ms, post-startup, clustered
    ev = []
    for t in sorted(t for t, d in r['stalls'] if d >= STRONG_MS and t >= STARTUP_S):
        if not ev or t - ev[-1] > CLUSTER_S:
            ev.append(t)
    gaps = [round(ev[i + 1] - ev[i], 1) for i in range(len(ev) - 1)]
    # 5x-tick grid fit: how many arrivals sit within GRID_TOL of a 5*rotation multiple (from t0)
    grid = 5 * rot_med if rot_med else None
    on = off = drop = None
    if grid:
        on = sum(1 for t in ev if abs(t - round(t / grid) * grid) <= GRID_TOL)
        off = len(ev) - on
        pts = [k * grid for k in range(1, int((r['el'] - STARTUP_S) / grid) + 1)]
        hitpts = sum(1 for p in pts if any(abs(t - p) <= GRID_TOL for t in ev))
        drop = round(100 * (1 - hitpts / len(pts))) if pts else None
    last_stall = max((t for t, _ in r['stalls']), default=0)
    return dict(rot_med=rot_med, rots_n=len(r['rots']), rots_last=r['rots'][-1] if r['rots'] else None,
                rots_capped=rots_capped, events=ev, gaps=gaps, grid=grid, on=on, off=off, drop=drop,
                fps=round(r['fr'] / r['el'], 1) if r['el'] else None, worst=r['mx'], last_stall=last_stall)

def report(path):
    r = parse(path); a = analyse(r)
    print('=' * 72); print(path)
    print(f"  window {r['el']}s  frames {r['fr']}  fps {a['fps']}  worst {a['worst']}ms  last stall {a['last_stall']}s")
    cap = f"  *** R[] CAPPED at {ROTS_CAP} (last event {a['rots_last']}s of {r['el']}s) ***" if a['rots_capped'] else ""
    print(f"  rotation R[] median = {a['rot_med']}s  ({a['rots_n']} events){cap}")
    print(f"  beat arrivals (>= {STRONG_MS}ms, t>= {STARTUP_S}s, clustered): {a['events']}")
    print(f"  gaps {a['gaps']}")
    if a['grid']:
        print(f"  5x-tick grid = {a['grid']}s: {a['on']}/{len(a['events'])} arrivals on-grid (+/-{GRID_TOL}s), "
              f"{a['off']} off, {a['drop']}% of grid points dropped")
    return a

if __name__ == '__main__':
    for p in sys.argv[1:]:
        report(p)
