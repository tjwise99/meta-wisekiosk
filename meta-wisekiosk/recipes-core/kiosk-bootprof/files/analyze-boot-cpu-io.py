#!/usr/bin/env python3
"""Turn boot-cpu-io-sample.sh output into per-window CPU and disk-I/O figures.

The question it exists to answer: in each phase of boot, is this single core
busy, idle, or blocked on I/O. Overlapping two phases only helps when the core
is idle during one of them, so that number decides whether parallelising is a
speedup or a queue.

Usage: analyze-boot-cpu-io.py <sample-file> [<sample-file> ...]
"""
import sys
from pathlib import Path

HZ = 100  # confirmed: /proc/stat idle matches /proc/uptime field 2 at HZ=100

FIELDS = ("up user nice sys idle iowait irq softirq "
          "rd_ios rd_ms wr_ios wr_ms inflight io_ticks nrun nproc").split()

# Boot phase edges, keyed on journal milestones. Wall-clock stamps are unusable
# on this image (fake-hwclock jumps mid-boot), so the journal must be read with
# `-o short-monotonic` and the [    7.628196] prefix is the anchor.
MILESTONES = [
    ("t_expect", r"Expecting device /sys/subsystem/net/devices/wlan0"),
    ("t_fs", r"Reached target Local File Systems\."),
    ("t_basic", r"Reached target Basic System\."),
    ("t_wlan", r"Found device /sys/subsystem/net/devices/wlan0\."),
    ("t_online", r"Reached target Network is Online\."),
    ("t_kiosk", r"Started Kiosk browser"),
    ("t_exec", r"SURFMS uptime_at_exec"),
    ("t_loaded", r"SURFMS load_finished"),
]

PHASES = [
    ("kernel + early systemd", None, "t_expect"),
    ("local filesystems", "t_expect", "t_fs"),
    ("sysinit -> basic", "t_fs", "t_basic"),
    ("waiting for wlan0", "t_basic", "t_wlan"),
    ("assoc + DHCP", "t_wlan", "t_online"),
    ("Xorg -> surf exec", "t_kiosk", "t_exec"),
    ("surf -> load_finished", "t_exec", "t_loaded"),
]

DEFAULT_WINDOWS = [
    ("kernel + early systemd", 0.0, 7.7),
    ("local filesystems", 7.7, 20.3),
    ("sysinit -> basic", 20.3, 25.3),
    ("waiting for wlan0", 25.3, 33.8),
    ("assoc + DHCP", 33.8, 36.9),
    ("Xorg -> surf exec", 36.9, 41.4),
    ("surf -> load_finished", 41.4, 53.0),
]


def journal_windows(sample_path):
    """Derive per-boot phase edges from the matching -o short-monotonic journal."""
    jpath = Path(str(sample_path).replace(".txt", ".journal.txt"))
    if not jpath.exists():
        return DEFAULT_WINDOWS, None
    import re
    text = jpath.read_text(errors="replace")
    marks = {}
    for name, pat in MILESTONES:
        m = re.search(r"^\[\s*([0-9.]+)\].*" + pat, text, re.M)
        if m:
            marks[name] = float(m.group(1))
    windows = []
    for label, a, b in PHASES:
        t0 = 0.0 if a is None else marks.get(a)
        t1 = marks.get(b)
        if t0 is None or t1 is None or t1 <= t0:
            continue
        windows.append((label, t0, t1))
    return (windows or DEFAULT_WINDOWS), marks


def load_meta(path):
    """Header key=value pairs. kiosk-bootprof emits its own CPU cost here, so
    the instrument's overhead is always visible rather than inferred."""
    meta = {}
    for line in Path(path).read_text().splitlines():
        if not line.startswith("#"):
            break
        for tok in line.lstrip("#").split():
            if "=" in tok:
                k, _, v = tok.partition("=")
                meta[k] = v
    return meta


def load(path):
    rows = []
    for line in Path(path).read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split()
        if len(parts) != len(FIELDS):
            continue
        r = {}
        for k, v in zip(FIELDS, parts):
            r[k] = float(v) if k == "up" else int(v)
        rows.append(r)
    return rows


def delta(a, b, key):
    return b[key] - a[key]


def summarize(a, b):
    """CPU and I/O between two samples, as fractions of wall time."""
    wall = b["up"] - a["up"]
    if wall <= 0:
        return None
    jiff = {k: delta(a, b, k) for k in
            ("user", "nice", "sys", "idle", "iowait", "irq", "softirq")}
    total = sum(jiff.values())
    if total <= 0:
        return None
    busy = jiff["user"] + jiff["nice"] + jiff["sys"] + jiff["irq"] + jiff["softirq"]
    return {
        "wall": wall,
        "busy_pct": 100.0 * busy / total,
        "idle_pct": 100.0 * jiff["idle"] / total,
        "iowait_pct": 100.0 * jiff["iowait"] / total,
        "user_pct": 100.0 * jiff["user"] / total,
        "sys_pct": 100.0 * jiff["sys"] / total,
        "idle_s": jiff["idle"] / HZ,
        "rd_ios": delta(a, b, "rd_ios"),
        "rd_ms": delta(a, b, "rd_ms"),
        "wr_ios": delta(a, b, "wr_ios"),
        "wr_ms": delta(a, b, "wr_ms"),
    }


def bracket(rows, t0, t1):
    """Samples straddling [t0, t1); None if the window is not covered."""
    lo = max((r for r in rows if r["up"] <= t0), key=lambda r: r["up"], default=None)
    hi = min((r for r in rows if r["up"] >= t1), key=lambda r: r["up"], default=None)
    if lo is None:
        lo = min(rows, key=lambda r: r["up"])
    if hi is None:
        hi = max(rows, key=lambda r: r["up"])
    return (lo, hi) if hi["up"] > lo["up"] else (None, None)


def report(path, rows):
    windows, marks = journal_windows(path)
    src = "journal" if marks else "defaults"
    meta = load_meta(path)
    print(f"\n=== {Path(path).name}   {len(rows)} samples, "
          f"uptime {rows[0]['up']:.1f}-{rows[-1]['up']:.1f}s   (edges from {src})")
    if "self_cpu_us" in meta:
        self_s = int(meta["self_cpu_us"]) / 1e6
        print(f"    instrument: self_cpu={self_s*1000:.1f}ms  "
              f"late_samples={meta.get('late', '?')}  "
              f"first_sample={meta.get('first_sample_s', '?')}s")
    if marks:
        print("    " + "  ".join(f"{k}={v:.1f}" for k, v in sorted(
            marks.items(), key=lambda kv: kv[1])))
    print(f"{'window':<22}{'wall':>7}{'busy%':>8}{'idle%':>8}{'iowait%':>9}"
          f"{'idle_s':>8}{'rd_ios':>8}{'rd_ms':>8}{'wr_ios':>8}")
    for name, t0, t1 in windows:
        a, b = bracket(rows, t0, t1)
        if a is None:
            continue
        s = summarize(a, b)
        if not s:
            continue
        print(f"{name:<22}{s['wall']:>7.1f}{s['busy_pct']:>8.1f}{s['idle_pct']:>8.2f}"
              f"{s['iowait_pct']:>9.2f}{s['idle_s']:>8.2f}"
              f"{s['rd_ios']:>8}{s['rd_ms']:>8}{s['wr_ios']:>8}")

    first, last = rows[0], rows[-1]
    boot_end = min((r for r in rows if r["up"] >= 60.0),
                   key=lambda r: r["up"], default=last)
    s = summarize(first, boot_end)
    print(f"{'-'*77}")
    print(f"{'BOOT (to 60s)':<22}{s['wall']:>7.1f}{s['busy_pct']:>8.1f}"
          f"{s['idle_pct']:>8.2f}{s['iowait_pct']:>9.2f}{s['idle_s']:>8.2f}"
          f"{s['rd_ios']:>8}{s['rd_ms']:>8}{s['wr_ios']:>8}")

    # On one core, reordering work can only reclaim time the core was NOT
    # executing. Idle + iowait over the boot is therefore a hard ceiling on
    # everything scheduling changes can buy -- overlapping two runnable tasks
    # on a single core conserves total CPU time and reclaims nothing.
    headroom = s["idle_s"] + s["iowait_pct"] / 100.0 * s["wall"]
    cpu_work = s["busy_pct"] / 100.0 * s["wall"]
    print(f"\nCPU work in boot: {cpu_work:.1f}s of {s['wall']:.1f}s wall")
    print(f"scheduling headroom (idle + iowait): {headroom:.2f}s "
          f"<- ceiling on any parallelise/reorder change")

    # Run-queue depth. nrun counts the sampler itself, so "others" = nrun - 1.
    boot_rows = [r for r in rows if r["up"] <= 60.0]
    others = [max(0, r["nrun"] - 1) for r in boot_rows]
    deep = sum(1 for o in others if o >= 2)
    print(f"run queue during boot (excluding the sampler): "
          f"max {max(others)}, mean {sum(others)/len(others):.2f}, "
          f"{deep}/{len(others)} samples with >=2 other runnable")


def main():
    for path in sys.argv[1:]:
        rows = load(path)
        if len(rows) < 3:
            print(f"{path}: too few samples", file=sys.stderr)
            continue
        report(path, rows)


if __name__ == "__main__":
    main()
