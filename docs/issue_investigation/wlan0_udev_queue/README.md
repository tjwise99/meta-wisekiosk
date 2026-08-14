# The `wlan0` gate — module load order in udev's queue

The WiFi chip is on the SDIO bus at 4.0 s and `wlan0` does not exist until 32.63 s. Every unit
downstream waits on it. This investigation asks what occupies those 28 seconds, and what removing it
is worth. The baseline it is measured against is
[`boot_cpu_saturation`](../boot_cpu_saturation/README.md).

## Configuration under test

Six arms on the Pi Zero W, n=3 boots each, 2026-08-12, all against the image-default baseline:

| Arm | What it changes |
|---|---|
| baseline | image default |
| 4-module blacklist | `bcm2835_isp`, `bcm2835_codec`, `bcm2835_v4l2`, `snd_bcm2835` |
| 8-module blacklist | the four above plus `vc_sm_cma`, `raspberrypi_gpiomem`, `uio`, `uio_pdrv_genirq` |
| Bluetooth removed | `bthelper@.service` + `bluetooth` + `hciuart` masked |
| stacked | 4-module blacklist and Bluetooth removal together |
| `brcmfmac` preloaded | `/etc/modules-load.d/` entry, no work removed |

The last arm is the control: it moves `wlan0` without removing any CPU work.

## How the test was performed

`kiosk-bootprof` records the first time each module appears in `/proc/modules`, capped at 1 Hz
because `/proc/modules` is a seq_file over every loaded module and costs more than the three
counters it samples alongside. Module loads mostly do not log, so the journal alone cannot say what
udev is doing between 14.5 s and 28 s; the first-seen timeline can.

Each arm's endpoints come from the journal in `-o short-monotonic` and from `measure-surf.sh`. An
arm is treated as a result only where the three-boot ranges do not overlap the baseline's.

Because a module blacklist can break the display, every arm was validated against real pixels: a
framebuffer sample is read and reported as `rgb_min`/`rgb_max`/`rgb_mean`/`distinct`. The probe was
seeded in both directions before it was trusted — a uniform buffer reads `BLANK`, and a failed read
reports `PROBE FAILED` rather than blank.

## Metrics

The journal across the gap on an image-default boot:

```
 4.00 s  mmc1: new high speed SDIO card at address 0001     <- the WiFi chip is on the bus
27.33 s  brcmfmac: F1 signature read @0x18000000            <- the driver first touches it
28.26 s  Firmware: BCM43430/1 wl0: ... version 7.45.98
32.53 s  Found device /sys/subsystem/net/devices/wlan0
```

The last six seconds of that gap, read from the same journal:

```
21.28  rpi-gpiomem            24.02  snd_bcm2835          (audio)
21.58  vc_sm_cma              25.00  videodev             (V4L2)
22.07  mc: media interface    25.41  bcm2835_mmal_vchiq
22.36  vc_sm_cma probe        26.04  bcm2835_isp
22.84->23.34  vc_sm init      26.32  bcm2835_v4l2
                              26.57->27.34  /dev/video10..23,31   (14 nodes)
27.33  brcmfmac starts
```

Module first-seen timeline, image-default boot:

```
17.08  cfg80211, rfkill, uio, uio_pdrv_genirq
21.08  fixed
22.57  mc, raspberrypi_gpiomem, snd
24.07  snd_pcm, snd_timer, vc_sm_cma, videobuf2_common, ecc, ecdh_generic
25.08  brcmutil, snd_bcm2835, videodev
26.59  videobuf2_dma_contig, videobuf2_memops, videobuf2_v4l2, videobuf2_vmalloc
28.07  bcm2835_isp, bcm2835_v4l2, v4l2_mem2mem, brcmfmac
```

`cfg80211`, the module `brcmfmac` depends on, loads at 17.1 s — eleven seconds before the driver
that needs it. Nothing about the WiFi stack is slow.

Four-module blacklist against baseline, n=3:

| | baseline | blacklisted | Δ |
|---|---|---|---|
| **`wlan0` exists** | 32.6 / 32.7 / 32.6 → 32.63 s | 29.2 / 29.5 / 29.2 → 29.30 s | **−3.33 s**, ranges do not overlap |
| network online | 36.30 s | 33.90 s | −2.40 s |
| **`surf` exec** | 40.2 / 39.6 / 40.2 → 40.00 s | 38.0 / 37.6 / 38.0 → 37.87 s | **−2.13 s**, ranges do not overlap |
| `load_finished` | 49.80 s | 48.10 s | −1.70 s, ranges overlap — directional only |
| CPU work in boot | 44.27 s | 43.53 s | −0.73 s |

Stacked with the Bluetooth removal, same baseline:

| | baseline | + modules | + modules + Bluetooth |
|---|---|---|---|
| `wlan0` exists | 32.63 s | 29.30 s | 29.10 s |
| network online | 36.30 s | 33.90 s | 33.50 s |
| `surf` exec | 40.00 s | 37.87 s | 36.73 s |
| **`load_finished`** | 48.6 / 49.4 / 51.4 → 49.80 s | 48.10 s | 45.8 / 46.0 / 47.9 → **46.57 s** |
| CPU work in boot | 44.27 s | 43.53 s | 41.47 s |

The two changes stack and the combined `load_finished` ranges do not overlap the baseline's
(45.8–47.9 against 48.6–51.4): **−3.23 s to `load_finished`, −2.80 s of CPU work.** The split
matches what the arms act on — the modules buy the gate, Bluetooth buys CPU after the gate.

Second pass, eight modules against baseline, n=3:

| | baseline | 8-module blacklist |
|---|---|---|
| `wlan0` | 32.3 / 32.4 / 32.2 → 32.30 s | 28.9 / 28.9 / 28.8 → 28.87 s |
| `surf` exec | 39.37 s | 37.33 s |
| `brcmfmac` loads | 28.07 s | 25.97 / 26.49 / 25.98 s |

−3.43 s against −3.33 s for the original four, on a baseline that had already moved 0.33 s from an
unrelated journald fix. The four extra modules are worth roughly 0.1 s. The camera and audio stack
was the entire effect.

**`wlan0`'s timestamp is a proxy for CPU work removed, not the cause of the win.** Preloading
`brcmfmac` moved `wlan0` from 24.82 s to 14.19 s — −10.63 s — and moved `surf` exec by −0.06 s,
well inside run-to-run spread. `wpa_supplicant.service` inherits the implicit
`After=sysinit.target basic.target` and starts only once those are reached, 11.25 s after `wlan0`
already existed on that boot:

```
14.10  Found device .../wlan0
22.14  Reached target System Initialization
23.07  Reached target Basic System
25.35  Starting Bring up wlan0 ... wpa_supplicant
28.51  Reached target Network is Online
```

Association plus DHCP is only ~3.2 s of that 14.4 s wait. Every arm above that moved `wlan0` earlier
also removed CPU work, and it is the CPU removed that moved `surf` exec; the two track together
because both follow total CPU work. Rank a trim by whether it removes CPU work ahead of
`sysinit.target`/`basic.target`, not by whether it moves `wlan0`.

Display validation after the blacklist: `kiosk` active, three `surf` processes, X running, no new
failed units, framebuffer reading `rgb_min=0 rgb_max=255 rgb_mean=2.03 distinct=227` against the
baseline's `mean=1.84 distinct=221`.

## Changes configured as a result

Both blacklist passes and the Bluetooth kernel-module pass ship in
[`kiosk-blacklist.conf`](../../../meta-wisekiosk/recipes-core/kiosk-hardware/files/kiosk-blacklist.conf),
which carries the module list and the reason each entry is safe to remove.

Pursuing the remaining gap as a queue-ordering problem is a closed line: the reorder control above
moved `wlan0` earlier without removing work and bought nothing, and the direct reorder of
`wpa_supplicant` measured in [`boot_cpu_saturation`](../boot_cpu_saturation/README.md) made `surf`
exec 8.74 s worse.
