# Boot CPU saturation — is the core busy, waiting, or queued?

A boot window can be long because the core is **doing work**, because it is **waiting**, or because
something is **queued behind unrelated work**. The three have different fixes, and on a single core
the first two have opposite ones: overlapping phases helps only when the core is idle during one of
them. This is the baseline measurement that decides which case this board is in, and it is the
evidence base the other boot investigations here are ranked against.

## Configuration under test

Image-default service configuration on the Pi Zero W, n=3 boots, 2026-08-12. Eleven service masks
from an earlier campaign were reverted before the first boot, so the arm is the image as built: no
module blacklist, no masks, no reordering.

The instrument is the
[`kiosk-bootprof`](../../../meta-wisekiosk/recipes-core/kiosk-bootprof/kiosk-bootprof_1.0.bb)
sampler at 2 Hz, with
[`analyze-boot-cpu-io.py`](../../../meta-wisekiosk/recipes-core/kiosk-bootprof/files/analyze-boot-cpu-io.py)
reducing its samples to per-window figures and
[`measure-surf.sh`](../../../meta-wisekiosk/recipes-core/kiosk-bootprof/files/measure-surf.sh)
timing complete display. The sampler's cost, its blind spots and the SSH-session cost that
contaminates a run are documented at
[the tool](../../../meta-wisekiosk/recipes-core/kiosk-bootprof/README.md); every figure below is
kernel-relative and excludes U-Boot, because `CLOCK_MONOTONIC` and `/proc/uptime` both start at
kernel entry.

## How the test was performed

Window edges are taken from each boot's own journal read with `-o short-monotonic`. Wall-clock
stamps are not comparable on this image — there is no RTC — so monotonic time is the only usable
clock. `kiosk-bootprof` samples `/proc/stat`, `/sys/block/mmcblk0/stat` and `/proc/loadavg` into a
preallocated buffer and writes once at the end, so measuring adds no SD writes to the window being
measured.

Four finish lines are quoted for this image and they are not interchangeable. Any figure compared
against one of them must use the same row:

| Endpoint | What it means |
|---|---|
| SSH reachable | the lifeline answers again |
| `SURFMS uptime_at_exec` | `surf` is exec'd |
| `SURFMS load_finished` | WebKit finished the page load |
| complete display | weather icons rendered — the only endpoint a viewer sees |

Two overlap-based routes were then tested against this baseline: starting Xorg in parallel with the
network wait, evaluated against the idle-time ceiling below, and a `DefaultDependencies=no` drop-in
on `wpa_supplicant.service` so it starts as soon as `wlan0` exists rather than waiting for
`sysinit.target`/`basic.target`. The second was applied to the device and measured n=3.

## Metrics

Aggregate over the 60 s window from boot:

| | boot 1 | boot 2 | boot 3 | mean |
|---|---|---|---|---|
| wall, boot → 60 s window | 52.0 s | 51.5 s | 52.0 s | 51.8 s |
| **CPU busy** | 85.2 % | 84.2 % | 86.8 % | **85.4 %** |
| **idle** | 10.18 % | 10.25 % | 8.44 % | **9.6 %** |
| iowait | 4.60 % | 5.54 % | 4.75 % | 5.0 % |
| total idle, seconds | 5.26 s | 5.25 s | 4.37 s | 4.96 s |
| CPU work in the boot | 44.3 s | 43.4 s | 45.1 s | 44.3 s |
| run queue, excluding the sampler | mean 5.52, max 19 | — | — | ~5.5 runnable |

Milestones over the same three boots:

| Milestone | mean |
|---|---|
| `wlan0` exists | 32.63 s |
| network online | 36.30 s |
| `surf` exec | 40.00 s |
| `load_finished` | 49.80 s |

Per window, same three boots:

| Window | wall | busy % | idle % | iowait % | |
|---|---|---|---|---|---|
| local filesystems | 11.5 s | 99.67 | 0.00 | 0.38 | before the gate |
| sysinit → basic | 5.2 s | 100.00 | 0.00 | 0.00 | before the gate |
| **waiting for `wlan0`** | 8.8 s | **100.00** | **0.00** | **0.00** | **the gate** |
| assoc + DHCP | 4.0 s | 84.77 | 13.97 | 1.25 | after |
| Xorg → `surf` exec | 4.3 s | 76.43 | 5.60 | 17.96 | after |
| `surf` → `load_finished` | 10.2 s | 81.10 | 3.94 | 14.93 | after |

**The idle counter advances by exactly zero jiffies before `wlan0` appears** — across the
local-filesystems, sysinit and `wlan0` windows, on every boot measured. All of the boot's idle and
iowait lies after the gate.

**The scheduling ceiling.** On one core, reordering reclaims only time the core was not executing,
because overlapping two runnable tasks conserves total CPU time:

```
reclaimable by any scheduling change  =  idle + iowait  =  7.65 / 8.10 / 6.84 s   (mean 7.53 s)
CPU work already in the boot          =  44.3 / 43.4 / 45.1 s   (mean 44.3 s)
```

The Xorg-parallel-with-network proposal was valued at 7–11 s. That range spans and exceeds the whole
boot's scheduling budget, and none of the budget lies in the window it targets: `waiting for wlan0`
measures 0.00 % idle and 0.00 % iowait on every boot. There is nothing there to overlap into.
Starting Xorg earlier adds a competing process to a run queue already averaging ~5.5 runnable tasks
on one core.

The `wpa_supplicant` reorder tested that accounting directly, n=3:

| | before | after | Δ |
|---|---|---|---|
| network online | 28.51 s | 22.97 s | −5.55 s |
| `surf` exec | 31.54 s | 40.28 s | **+8.74 s** |

Network online moved earlier exactly as intended; `surf` exec moved 8.74 s later, net 3.2 s worse,
reproducible to the hundredth of a second across three boots (40.24 / 40.28 / 40.34 s).
`kiosk.service` was released 6.8 s earlier into a machine still running dbus, journal flush, RAUC
mark-good, RF-kill and the tail of udev, and took 15.5 s longer to start once released. Releasing
work earlier without removing any of it converts a wait into a queue.

Endpoint values on this configuration:

| Endpoint | Value |
|---|---|
| SSH reachable | 53–56 s (n=8) |
| `SURFMS uptime_at_exec` | 39.67 s (n=3) |
| `SURFMS load_finished` | 51.10 / 48.79 / 50.48 → 50.12 s (n=3) |
| complete display | 53.42 / 54.89 / 52.65 → 53.65 s (n=3) |

**The window between `load_finished` and complete display is large and noisy** — 3.53 s on this
baseline, 6.49 s on a module-blacklist boot. It is the page's own post-load fetching and rendering,
which depends on the backend, so it is not a property of the boot. A complete-display delta smaller
than ~2 s is not a boot result: the baseline's own spread is 2.24 s across three boots, and one
blacklist boot never reached icon render at all within ~165 s despite `load_finished` at 46.80 s.

## Changes configured as a result

None. Both overlap-based routes are closed: the Xorg reorder is excluded by the ceiling above, and
the `wpa_supplicant` drop-in was measured and reverted, leaving no code to carry it.

The lever this baseline points at is removing CPU work ahead of `sysinit.target`/`basic.target`,
which is pursued in [`wlan0_udev_queue`](../wlan0_udev_queue/README.md) and lands at
[`kiosk-blacklist.conf`](../../../meta-wisekiosk/recipes-core/kiosk-hardware/files/kiosk-blacklist.conf).
Timings taken on a slot's first boot after an OTA are not comparable with these — see
[`first_boot_after_ota`](../first_boot_after_ota/README.md).
