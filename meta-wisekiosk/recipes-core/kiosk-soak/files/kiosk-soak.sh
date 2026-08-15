#!/bin/sh
# Kiosk soak sampler, ported from the Raspbian-era kiosk's sampler for the
# Yocto image.
#
#   kiosk-soak.sh              take one sample
#   kiosk-soak.sh --summary [N]   report over the last N samples (default: all)
#
# Differences from the Raspbian original, all forced by the target:
#   * LOG lives on /data, which survives an A/B update. The Raspbian log sat on
#     the rootfs; here that would be destroyed by the first OTA.
#   * busybox has no `ps -eo`, no `df --output`, and its `free -m` reports KB
#     regardless of the flag. Memory is divided to MB explicitly so the line
#     format stays byte-comparable with the old log.
#   * the launcher runs a bare `surf`, not an absolute path, so the browser is
#     resolved with command -v rather than by grepping for a path. The principle
#     is unchanged: ask the launcher, never hardcode. A sampler that names one
#     browser records zeros for the other and calls it data.
#
# The fields that are not self-evident from the printf below:
#   boot       first 8 of boot_id. A change means the device rebooted, and the
#              samples either side are not one series
#   pid        main browser pid. A change means the browser restarted; `none`
#              means it was not running at that sample
#   nproc      processes in the browser family (surf plus its WebKit children)
#   rss_total  RSS across that whole family, and the memory number that matters
#              -- the renderer is a separate process and holds most of it
#   thr        vcgencmd get_throttled. Anything but 0x0 means it throttled at
#              some point SINCE BOOT, not that it is throttling now
#   ent        entropy pool. Low is expected; rngd is deliberately off for surf
#
# Read a --summary in this order, weakest evidence last:
#   1. reboots and browser restarts. Non-zero means the memory series is really
#      two series, and no rate fitted across it means anything
#   2. samples w/o browser. Non-zero means the kiosk was down at those samples
#   3. the shape of rss_total across the window, before any slope. This port
#      prints no hourly mean, so that read is manual against the log
#   4. the slope, last
#
# Why the order is that way, and why the endpoint delta is labelled NOT a rate:
# docs/issue_investigation/surf_memory_soak/README.md.
set -u
LOG=${KIOSK_SOAK_LOG:-/data/kiosk-soak.log}
LAUNCHER=${KIOSK_LAUNCHER:-/usr/bin/kiosk-launch}
MAXLINES=${KIOSK_SOAK_MAXLINES:-20000}

if [ "${1:-}" = "--summary" ]; then
  N=${2:-0}
  [ "$N" -gt 0 ] 2>/dev/null && SRC=$(tail -n "$N" "$LOG") || SRC=$(cat "$LOG")
  printf '%s\n' "$SRC" | awk '
    { for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
      n++
      if (first == "") { first = v["ts"]; frss = v["rss_total"]; fboot = v["boot"] }
      last = v["ts"]; lrss = v["rss_total"]
      if (v["boot"] != fboot && !seen[v["boot"]]++) reboots++
      if (v["pid"] == "none") down++
      else { if (prevpid != "" && v["pid"] != prevpid) restarts++; prevpid = v["pid"] }
      if (v["rss_total"] + 0 > maxrss || maxrss == 0) maxrss = v["rss_total"] + 0
      if (minrss == 0 || v["rss_total"] + 0 < minrss) minrss = v["rss_total"] + 0
      if (v["load1"] + 0 > maxload) maxload = v["load1"] + 0
      if (v["temp"] + 0 > maxtemp) maxtemp = v["temp"] + 0
      if (v["thr"] != "0x0") thr++
    }
    END {
      hours = (last - first) / 3600
      printf "  samples          %d over %.1f h\n", n, hours
      printf "  reboots          %d\n", reboots + 0
      printf "  browser restarts %d\n", restarts + 0
      printf "  samples w/o browser  %d %s\n", down + 0, (down > 0 ? "<-- kiosk was down" : "")
      printf "  rss_total range  %d .. %d kB\n", minrss, maxrss
      printf "  rss_total ends   %d -> %d kB (endpoint delta %+d -- NOT a rate)\n", frss, lrss, lrss - frss
      if (hours > 0.5) printf "  slope            %+.1f kB/h  (n=%d)\n", (lrss - frss) / hours, n
      printf "  peak temp        %.1f C\n", maxtemp
      printf "  peak load1       %.2f  (includes the sampler wake-up itself)\n", maxload
      printf "  throttled        %d sample(s) with thr != 0x0\n", thr + 0
    }'
  exit 0
fi

# ----------------------------------------------------------------- sample mode
# Ask the launcher which browser this is. It invokes a bare command name, so
# resolve it on PATH rather than looking for an absolute path.
CMD=$(grep -oE '^[[:space:]]*exec[[:space:]]+[A-Za-z0-9._-]+' "$LAUNCHER" 2>/dev/null \
      | head -n1 | awk '{print $2}')
BIN=$(command -v "${CMD:-surf}" 2>/dev/null)
COMM=$(basename "${BIN:-unknown}" | cut -c1-15)

PID=$(pgrep -x "$COMM" 2>/dev/null | head -n1)

# Renderers are separate processes and hold most of the memory. Count the whole
# family, or a leak in the renderer looks like a flat launcher. busybox has no
# `ps -eo`, so walk /proc directly.
NPROC=0; RSS_TOTAL=0
for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in
    WebKit*|webkit*|"$COMM")
      r=$(awk '/^VmRSS/{print $2}' "$d/status" 2>/dev/null)
      [ -n "$r" ] && { NPROC=$((NPROC + 1)); RSS_TOTAL=$((RSS_TOTAL + r)); } ;;
  esac
done

RSS_MAIN=0
[ -n "$PID" ] && RSS_MAIN=$(awk '/^VmRSS/{print $2}' "/proc/$PID/status" 2>/dev/null)

read -r L1 L5 L15 _ < /proc/loadavg
UP=$(cut -d. -f1 /proc/uptime)
BOOT=$(cut -c1-8 /proc/sys/kernel/random/boot_id)
TEMP=$(awk '{printf "%.1f", $1 / 1000}' /sys/class/thermal/thermal_zone0/temp)
THR=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
ENT=$(cat /proc/sys/kernel/random/entropy_avail)
DISK=$(df / | awk 'NR==2{print $5}' | tr -d ' %')
MU=$(free | awk '/^Mem/{printf "%d", $3 / 1024}')
MA=$(free | awk '/^Mem/{printf "%d", $7 / 1024}')

printf 'ts=%s iso=%s boot=%s up=%s load1=%s load5=%s load15=%s temp=%s thr=%s memused=%s memavail=%s ent=%s disk=%s browser=%s pid=%s nproc=%s rss_main=%s rss_total=%s\n' \
  "$(date +%s)" "$(date +%Y-%m-%dT%H:%M:%S%z)" "$BOOT" "$UP" "$L1" "$L5" "$L15" "$TEMP" "${THR:-unknown}" \
  "$MU" "$MA" "$ENT" "$DISK" "$COMM" "${PID:-none}" "$NPROC" "$RSS_MAIN" "$RSS_TOTAL" \
  >> "$LOG"

# Cap the log so a sampler left running for a year cannot fill the partition.
# temp + mv so a reader never sees a truncated file.
lines=$(wc -l < "$LOG")
if [ "$lines" -gt "$MAXLINES" ]; then
  tail -n "$MAXLINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
