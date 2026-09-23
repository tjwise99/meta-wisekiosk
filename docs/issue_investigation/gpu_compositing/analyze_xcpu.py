#!/usr/bin/env python3
"""Test B: find sustained X-server CPU bursts from the no-probe sampler log.

Input lines: "<uptime_s> <jiffies>". On a single core X can use at most one jiffy of CPU
per 10 ms of wall time, so a burst of X pegged at ~100% shows as consecutive samples whose
jiffy delta ~= the wall delta in centiseconds.
"""
import sys

BUSY = 0.80          # fraction of a core that counts as "pegged"
MIN_MS = 200         # a burst must last at least this long to matter

rows = []
meta = []
for ln in open(sys.argv[1]):
    ln = ln.strip()
    if not ln:
        continue
    p = ln.split()
    if len(p) != 2:
        meta.append(ln); continue
    try:
        rows.append((float(p[0]), int(p[1])))
    except ValueError:
        meta.append(ln)

for m in meta:
    print(f"  {m}")
if len(rows) < 10:
    sys.exit(f"only {len(rows)} samples -- nothing to analyse")

t0 = rows[0][0]
span = rows[-1][0] - t0
ivals = [b[0] - a[0] for a, b in zip(rows, rows[1:])]
ivals.sort()
print(f"\nsamples {len(rows)} over {span:.1f}s  "
      f"median interval {ivals[len(ivals)//2]*1000:.0f} ms")

# per-sample utilisation as a fraction of one core
util = []
for (ta, ja), (tb, jb) in zip(rows, rows[1:]):
    dt = tb - ta
    if dt <= 0:
        continue
    util.append((ta - t0, dt, (jb - ja) / 100.0 / dt))

tot_cpu = (rows[-1][1] - rows[0][1]) / 100.0
print(f"X total CPU over the window: {tot_cpu:.1f}s = {100*tot_cpu/span:.1f}% of one core")

# maximal runs at/over BUSY
bursts, cur = [], None
for t, dt, u in util:
    if u >= BUSY:
        if cur is None:
            cur = [t, t + dt, u, 1]
        else:
            cur[1] = t + dt; cur[2] = max(cur[2], u); cur[3] += 1
    else:
        if cur is not None:
            bursts.append(cur); cur = None
if cur is not None:
    bursts.append(cur)

long = [b for b in bursts if (b[1] - b[0]) * 1000 >= MIN_MS]
print(f"\nruns with X >= {BUSY:.0%} of a core: {len(bursts)} total, "
      f"{len(long)} lasting >= {MIN_MS} ms")
print(f"rate of >= {MIN_MS} ms X bursts: {len(long)/span:.2f}/s")
if long:
    print(f"\n{'start_s':>9}{'dur_ms':>9}{'peak_util':>11}{'samples':>9}")
    for b in long[:25]:
        print(f"{b[0]:>9.1f}{(b[1]-b[0])*1000:>9.0f}{b[2]:>11.2f}{b[3]:>9d}")
    gaps = [b[0] - a[0] for a, b in zip(long, long[1:])]
    if gaps:
        gaps_s = sorted(gaps)
        print(f"\ninter-burst gap: median {gaps_s[len(gaps_s)//2]:.2f}s  "
              f"min {min(gaps):.2f}s  max {max(gaps):.2f}s")

hi = sorted(util, key=lambda x: -x[2])[:10]
print("\nbusiest single sample windows (util as fraction of one core):")
for t, dt, u in hi:
    print(f"  t={t:7.1f}s  window {dt*1000:5.0f} ms  util {u:.2f}")
