# WiFi instability — the routes that were ruled out, and how the fault was captured

For two days the working hypothesis was that the SDIO bus, the brcmfmac driver, or the WiFi firmware
was defective. All three variants are dead: the board corrupts memory at its top CPU OPP under
sustained load, and the fix is the frequency cap shipped by
[`kiosk-cpufreq`](../../../meta-wisekiosk/recipes-core/kiosk-cpufreq/kiosk-cpufreq_1.0.bb), which
carries the dose-response evidence and the reason it ships as a unit rather than as `config.txt`.
This page is the residue: the negative results, the instrumentation lessons, the fault analysis
underneath that two-line summary, and the raw captures.

## Configuration under test

Pi Zero W, BCM43430A1 over SDIO with brcmfmac, kernel 6.6.63, under sustained network receive and
transmit — the load an OTA bundle transfer produces. Arms across the campaign varied burst size,
average rate, WiFi power save, firmware build, kernel patch set and CPU governor, one variable at a
time, against a transfer large enough to kill the board reliably.

Fault capture ran on the same board with `ramoops`/`pstore` reserved across the reset, and with
`slub_debug=FZPU` armed on one arm.

## How the test was performed

**The wedge model.** Sustained receive and sustained transmit could each hang the board; dose-response
across burst size and average rate produced apparent thresholds (~0.9 MB/s, later revised to a
burst-size effect) that looked like a receiver limit. Under-voltage was ruled out — `get_throttled`
stayed `0` through every death — and plain CPU starvation was ruled out, because the board still
hung at 12 % idle over plain HTTP, which has no crypto to blame. Two firmware builds, swapped at
runtime through `/sys/module/firmware_class/parameters/path`, crashed identically. Every one of
these was a real measurement of a real device death, and every one was measuring the true cause at
one remove: a higher receive rate drives more CPU demand, which drives `ondemand` to its top OPP.
The evidence for the wedge model is recorded in issue #5 sustained SDIO traffic wedges the board.

**The kernel-bump chase.** `slub_debug=FZPU` found no redzone or poison violation, ruling out a
simple buffer overrun. A review of brcmfmac's upstream history found two real fixes missing from the
pinned tree, but the scatterlist table-size bug was measured on the device to be nowhere near
triggered at safe rates — mean glom depth 4.8 against a 35-entry table — and the null-guard fix has
never been backported to any 6.6.y stable branch. Neither is the cause, so a kernel version bump
would not have fixed this regardless of which fix it delivered. Both patches ship anyway; the
reasoning is at
[`linux-raspberrypi_%.bbappend`](../../../meta-wisekiosk/recipes-kernel/linux/linux-raspberrypi_%.bbappend).

**The sender-starvation lesson.** `mmc1` interrupts falling to the idle rate during a stall looked
like proof the firmware had stopped delivering frames. Sampling the *sender's* TCP state (`ss -ti`)
during the same window showed `unacked: 0` and `lastsnd: 3552ms` — nothing was outstanding because
the sender had nothing to send. The pacing loop was a fork-per-chunk `dd` plus `sleep 0.1`, running
on a host at load average 28 under a WebKit build, and measured independently at 29 KB/s against a
requested 640 KB/s. **A receiver-only instrument cannot see a sender-side stall.** Every later arm
sampled the sender too, and counted a device stall only when the sender was demonstrably pushing —
`unacked > 0` and `lastsnd` small while the device's byte counter stayed flat. An arm built to that
rule did show a genuine device-side collapse: `cwnd` fell to 1 with seven backed-off retransmits,
none acknowledged.

**Panic recovery, proven by making it fire.** `echo c > /proc/sysrq-trigger`, twice, after
`rauc-mark-good` had already run so the test could not consume a boot attempt.

**ramoops feasibility.** The question was whether a persistent RAM store could capture a hard-lockup
panic across a reboot, and which zone to rely on.

## Metrics

**OTA blocked at 64 MB of 130 MB.** The chunk-and-pause shape that had moved 133 MB with zero hangs
stopped converging once the destination passed ~60 MB. Each attempt landed one chunk, the board
hung, and the unsynced append was lost on reboot, so the file rolled back:

| Run | chunks landed | transfer failures |
|---|---|---|
| 1 | 14 | 2 |
| 2 | 0 | 1 |
| 3 | 2 | 1 |
| 4 | 0 | 3 |
| 5 | 1 | 1 |

Net progress across the last four runs was zero, and gentler pause variants (6 s, 8 s) hung the same
way. Nothing was damaged — `BOOT_ORDER=B A`, both slots `good`, kiosk active, no FAT errors — and
every hang self-recovered. The attempt was stopped deliberately rather than ground against the risk
of unclean shutdowns corrupting the FAT partition that holds `uboot.env`. This episode predates the
top-OPP finding; the delivery design it produced is documented at
[`send-bundle-chunked.sh`](../../../tools/send-bundle-chunked.sh).

**Panic recovery bound.** Recovery from `sysrq`-triggered panic to SSH answering was **60 s** — a
10 s `panic=10` delay plus a normal boot — confirmed by a changed `boot_id`, with counters at `3/3`,
both slots `good` and no ext4 errors afterwards. That does not fix the 4.0 s `mmc_rescan` panic; it
bounds an indefinite hang needing a person to a 60-second unattended outage. The mechanism underneath
that panic is unknown.

**The fault.** The oops is an *instruction fetch* abort: the CPU jumps to `PC = 0xc1137c58` and tries
to execute data. That address is **constant across four separate crashes, under two different CPU
governors**, while `LR` — the call site — differs each time. A random corruption gives a random
target, so a constant target reached from different call sites is a deterministic computed jump, not
a scribbled heap. The address resolves to roughly 1.09 MB past the end of the kernel image, in the
region the early allocator uses: not a symbol, not module space, not the vector page.

The oops printed no backtrace, because the frame pointer was garbage. Resolving the raw stack
against `/proc/kallsyms` puts the crash in generic softirq code rather than inside brcmfmac:
`net_rx_action → __napi_poll → process_backlog → __netif_receive_skb_one_core → deliver_skb`'s
indirect call to the registered protocol handler. **brcmfmac is the packet source, not the faulting
code** — the `Workqueue: brcmf_sdio_dataworker` line names where the packet came from, not where the
corruption is.

Raw captures:

- [`oops-brcmf-sdio-dataworker-2026-08-13.txt`](oops-brcmf-sdio-dataworker-2026-08-13.txt) — the
  register and stack dump the analysis above is built on.
- [`oops-2-slub-debug-armed-2026-08-13.txt`](oops-2-slub-debug-armed-2026-08-13.txt) — the
  corroborating capture with `slub_debug=FZPU` armed, carrying the SLUB alloc/free backtraces for
  the faulting skb and netdev.

**ramoops zone choice.** The **dmesg zone** would be empty for this failure shape: it fills only on
a panic or oops path, and a watchdog-driven hard lockup never reaches one. The **console zone** is
the win — it writes the kernel log tail synchronously as each line is printed, with no dependence on
panic, which is exactly the evidence journald loses because it never gets to flush. It needs no
kernel rebuild, only an explicit `console-size=` and the overlay, since the stock overlay ships the
console zone disabled. `pstore/ftrace` would also work with interrupts disabled but needs a kernel
rebuild and carries per-function-call overhead on a 1 GHz single core, and was not pursued. On this
SoC a plain `reboot` and a watchdog reset are the same hardware event, so a passing reboot test is a
passing watchdog-reset test for whether the region survives.

## Changes configured as a result

- The frequency cap that fixes the crash:
  [`kiosk-cpufreq`](../../../meta-wisekiosk/recipes-core/kiosk-cpufreq/kiosk-cpufreq_1.0.bb) and its
  [unit](../../../meta-wisekiosk/recipes-core/kiosk-cpufreq/files/kiosk-cpufreq-cap.service).
- The two brcmfmac SDIO scatter-gather patches, carried as hygiene rather than as the fix:
  [`linux-raspberrypi_%.bbappend`](../../../meta-wisekiosk/recipes-kernel/linux/linux-raspberrypi_%.bbappend).
- `panic=10` on the kernel command line, and the ramoops overlay with an explicit `console-size=`:
  the `panic-reboot` and `kiosk` blocks of [`kiosk-zero-w.yaml`](../../../kiosk-zero-w.yaml).
- Chunked delivery, superseded by the cap above and tracked for removal by issue #29 remove chunked
  bundle delivery: [`send-bundle-chunked.sh`](../../../tools/send-bundle-chunked.sh).

Two threads stay open elsewhere: issue #11 cpufreq cap not in force during the first ~20s of boot
tracks the window before the cap unit runs, and the `mmc_rescan` panic mechanism is tracked as its
own hazard by issue #18 kernel panic at 4.0s in mmc_rescan, rather than by issue #5 sustained SDIO
traffic wedges the board, whose premise is retired.
