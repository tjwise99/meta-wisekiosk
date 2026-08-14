# Using the boot profiler

`kiosk-bootprof` samples `/proc/stat`, `/sys/block/mmcblk0/stat`, `/proc/loadavg` and
`/proc/modules` from early boot and writes `/data/boot-cpu-io.<boot_id>.txt` once at the end;
`analyze-boot-cpu-io.py` turns that into per-window CPU and I/O figures. Why the sampler is written
the way it is belongs in `files/kiosk-bootprof.c`'s header, and what ships in the image belongs in
`kiosk-bootprof_1.0.bb`. This file is about *taking* a profile and *reading* one — the parts the
code cannot state about itself.

## Capturing a boot

`just bootprofile <host>` (`justfiles/device.just`) runs the whole cycle: enable the unit, reboot,
wait out the observer window below, pull the samples and the matching journal, run the analyzer,
disable the unit again.

Do **not** `rm` the unit to stop it. It is image content, so a delete is undone by the next OTA and
in the meantime the device disagrees with its own image. `systemctl disable kiosk-bootprofile` is
the off switch.

## Your own SSH session is an instrument, and it costs ~3.34s

An `sshd` per-connection daemon burns **3 340 ms of CPU**, measured from its own `CPUUsageNSec` on
the device. A connection opened at 32.2s during a profiling run landed inside browser startup and
inflated `surf` exec on that boot. **One connection per boot, opened no earlier than 90s after the
reboot** — not a session left attached across the window.

Which figures a contaminated run still supports is worth stating exactly, because it decides what
can be salvaged: this board has no network at all before ~30s, so nothing done from a workstation
can reach `mmc1`, `brcmfmac`, `wlan0` or `Reached target Network is Online`. Those survive on any
boot. Everything from `SURFMS uptime_at_exec` onward does not.

90s clears the latest `surf` exec ever observed here (40.24s, on a deliberately misconfigured arm)
with ~35s of margin. Raise it to 120s when complete display is the endpoint. The wait is latency,
not a measurement parameter: it changes when the journal is read, never what the journal says, so
shortening it does not invalidate comparison against arms measured earlier.

## Limits of the data

- **It does not cover the first ~8.6s.** systemd cannot run a unit before it starts, so the kernel
  and early-systemd window is outside the samples entirely.
- **It counts itself.** The sampler is a runnable process, so `nr_running` includes it — every run
  queue figure from this tool is `nr_running - 1`.
- **`io_ticks` is not populated by this kernel's mmc driver** — 0 at 3 minutes of uptime, 4050 at
  4.8h. It is recorded but unusable over boot-length windows; `iowait %` and `rd_ms`/`wr_ms` are the
  I/O figures to read.
- **No PSI, no `systemd-analyze`.** `/proc/pressure/` does not exist (`CONFIG_PSI` is off) and
  `systemd-analyze` is not on the image, so neither pressure stalls nor `blame`/`critical-chain` is
  available as a cross-check.
- **An instrumented boot runs ~1s longer in wall-clock than an uninstrumented one.** Compare
  profiled boots against profiled boots.
