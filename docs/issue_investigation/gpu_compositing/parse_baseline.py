import re, sys
def parse(path):
    txt = open(path).read()
    m = re.search(r'BL\|(\d+)\|f(\d+)\|big(\d+)\|av(\d+)\|mx(\d+)\|H([\d.]+)\|S\[([^\]]*)\]', txt)
    el, fr, big, av, mx = (int(m.group(i)) for i in range(1,6))
    hist = [int(x) for x in m.group(6).split('.')]
    stalls = []
    for e in m.group(7).split(','):
        t, d = e.split(':')
        stalls.append((float(t), int(d)))
    return dict(path=path, el=el, fr=fr, big=big, av=av, mx=mx, hist=hist, stalls=stalls)

for p in sys.argv[1:]:
    r = parse(p)
    print('='*72)
    print(r['path'])
    print(f"  window {r['el']}s  frames {r['fr']}  big {r['big']}  mean {r['av']}ms  max {r['mx']}ms")
    print(f"  hist(<50,50-100,100-250,250-500,500-1k,1k-2k,>=2k) {r['hist']}  sum={sum(r['hist'])}")
    print(f"  hist>250 = {sum(r['hist'][3:])}   recorded stalls in S[] = {len(r['stalls'])}")
    print(f"  rate = {r['big']}/{r['el']} = {r['big']/r['el']:.4f}/s")
    st = r['stalls']
    steady = [s for s in st if s[0] >= 40.0]
    print(f"  stalls listed: {[f'{t}:{d}' for t,d in st]}")
    print(f"  --- steady (t>=40s): n={len(steady)}")
    print(f"      durations {[d for t,d in steady]}")
    if steady:
        ds = [d for t,d in steady]
        print(f"      duration min/max {min(ds)}/{max(ds)}  mean {sum(ds)/len(ds):.0f}")
    # metronome: arrivals near multiples of 40
    on = [s for s in steady if abs((s[0] % 40.0)) < 3.0 or abs((s[0] % 40.0) - 40.0) < 3.0]
    print(f"  --- on-beat (t mod 40 within +/-3s), n={len(on)}: {[f'{t}:{d}' for t,d in on]}")
    if len(on) > 1:
        iv = [round(on[i+1][0]-on[i][0],1) for i in range(len(on)-1)]
        print(f"      intervals {iv}")
    off = [s for s in steady if s not in on]
    print(f"  --- off-beat, n={len(off)}: {[f'{t}:{d}' for t,d in off]}")
