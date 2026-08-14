# ramoops / pstore on the Pi Zero W (BCM2835, Yocto scarthgap, kernel 6.6.63)

Read-only investigation. Nothing was modified; no bitbake; the device was not touched.

Evidence tree:
- kernel source: `/home/tjwise/meta-wisekiosk/build/tmp-raspberrypi0-wifi/work-shared/raspberrypi0-wifi/kernel-source`
- built config: `/home/tjwise/meta-wisekiosk/build/tmp-raspberrypi0-wifi/work-shared/raspberrypi0-wifi/kernel-build-artifacts/.config`
- deploy: `/home/tjwise/meta-wisekiosk/build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi`

Every claim below is tagged **VERIFIED** (read in this tree, path+line given), **INFERRED**
(reasoned from something verified, reasoning stated), or **REPORTED** (third-party, not verified).

---

## BOTTOM LINE FIRST (Q5 and Q6)

**The approach is NOT dead, but it does not buy what the ticket implies it buys.**

1. **The dmesg zone will be empty for this bug.** `dmesg-ramoops-N` records are produced by a
   `kmsg_dumper` that only runs on oops/panic/shutdown. A hard lockup that ends in a watchdog reset
   never reaches any of those. VERIFIED.

2. **The console zone is the thing worth having, and it already works with the shipped kernel
   config.** `CONFIG_PSTORE_CONSOLE=y` is set, and `pstore_console_write()` is a real console whose
   `->write` is called synchronously at printk time. Every kernel message lands in the ramoops
   console ring **as it is printed**, with no dependence on panic. So the last ~32KB of kernel log
   before the wedge survives the watchdog reset — which is precisely what is lost today, because
   journald never flushes it. VERIFIED.
   **Caveat:** the RPi overlay defaults `console-size = <0>`, i.e. the console zone is *disabled*.
   It must be passed explicitly. VERIFIED.

3. **`pstore/ftrace` is the only thing that can point at the stuck function, and it is not compiled
   in.** `# CONFIG_PSTORE_FTRACE is not set`. It works with interrupts disabled (it is not
   panic-driven), so it is genuinely applicable — but it needs a kernel rebuild and a full OTA, not a
   `/boot` write, and it imposes a store-to-WC-memory on *every kernel function call* on a 1GHz
   ARM11. See Q5.

4. **The firmware almost certainly does not zero DRAM on a watchdog reset**, on the strength of one
   source-level fact: on BCM2835 a normal `reboot` and a watchdog timeout are *the same hardware
   event* — `bcm2835_restart()` arms the watchdog with a 10-tick timeout and sets exactly the same
   `PM_RSTC_WRCFG_FULL_RESET` bit that `bcm2835_wdt_start()` sets. VERIFIED, see Q6. Since ramoops on
   Pi demonstrably survives `reboot`, it survives a watchdog timeout. This is an INFERENCE from a
   verified source identity, not a measurement.

5. **You cannot do this with a cmdline.txt one-liner.** The module-parameter route needs `mem=` to
   keep the kernel out of the region, which on a 512MB browser kiosk means throwing away ~300MB. The
   device-tree route is the only viable one, and it needs a *new file* on the shared FAT partition
   (`overlays/ramoops.dtbo`, which is not built today) plus a `config.txt` line. See Q3.

---

## Q1 — pstore symbols in the built `.config`

Exact lines from `kernel-build-artifacts/.config`:

```
7175:CONFIG_PSTORE=y
7176:CONFIG_PSTORE_DEFAULT_KMSG_BYTES=10240
7177:CONFIG_PSTORE_COMPRESS=y
7178:CONFIG_PSTORE_CONSOLE=y
7179:# CONFIG_PSTORE_PMSG is not set
7180:# CONFIG_PSTORE_FTRACE is not set
7181:CONFIG_PSTORE_RAM=y
7182:# CONFIG_PSTORE_BLK is not set
```

VERIFIED. Summary against what was asked:

| Symbol | State |
|---|---|
| `CONFIG_PSTORE` | `=y` |
| `CONFIG_PSTORE_RAM` | `=y` |
| `CONFIG_PSTORE_CONSOLE` | `=y` |
| `CONFIG_PSTORE_FTRACE` | **not set** |
| `CONFIG_PSTORE_DEFLATE_COMPRESS` | **does not exist in 6.6** |

**`CONFIG_PSTORE_DEFLATE_COMPRESS` is not a 6.6 symbol.** The crypto-API-selected compressor choice
was removed; 6.6 has a single boolean hardwired to zlib deflate. `fs/pstore/Kconfig:24-35`:

```
24  config PSTORE_COMPRESS
25          bool "Pstore compression (deflate)"
26          depends on PSTORE
27          select ZLIB_INFLATE
28          select ZLIB_DEFLATE
29          default y
...
33            algorithm, using the library implementation instead of using the full
34            blown crypto API. This reduces the risk of secondary oopses or other
35            problems while pstore is recording panic metadata.
```

So compression is on, is deflate, and is not configurable. VERIFIED.

**Compression applies to dmesg records only, not console records.** `fs/pstore/platform.c:331-352`
compresses inside `pstore_dump()`; `pstore_console_write()` at `platform.c:393-406` sets
`record.buf = (char *)s` and calls `psinfo->write()` directly with no compression step. So
`console-ramoops-0` is plain text. VERIFIED.

**Enabling `CONFIG_PSTORE_FTRACE` is possible — its dependencies are already met.**
`fs/pstore/Kconfig:55-59` requires `FUNCTION_TRACER` and `DEBUG_FS`; the config has
`7951:CONFIG_FUNCTION_TRACER=y`, `7953:CONFIG_DYNAMIC_FTRACE=y`, `7802:CONFIG_DEBUG_FS=y`. VERIFIED.

**Adjacent config facts that bear on this bug:**
```
7798:CONFIG_MAGIC_SYSRQ=y
7862:# CONFIG_PANIC_ON_OOPS is not set
7864:CONFIG_PANIC_TIMEOUT=0
7865:# CONFIG_SOFTLOCKUP_DETECTOR is not set
7866:CONFIG_DETECT_HUNG_TASK=y
1791:CONFIG_OF_RESERVED_MEM=y
```
There is no hardlockup detector available on a UP ARM11 (no NMI / perf-based watchdog), and the
softlockup detector is off. Note that even if `SOFTLOCKUP_DETECTOR` were enabled it would not fire
in a *hard* lockup — it is driven by an hrtimer, which is exactly what has stopped. VERIFIED
(config) / INFERRED (the consequence).

---

## Q2 — Does this tree ship a ramoops overlay?

**Yes, and it is bcm2835-native.** Two files exist:

- `arch/arm/boot/dts/overlays/ramoops-overlay.dts` — `compatible = "brcm,bcm2835"`
- `arch/arm/boot/dts/overlays/ramoops-pi4-overlay.dts` — `compatible = "brcm,bcm2711"` (not ours)

Full text of `ramoops-overlay.dts` (VERIFIED, 25 lines):

```
 1  /dts-v1/;
 2  /plugin/;
 3
 4  / {
 5      compatible = "brcm,bcm2835";
 6
 7      fragment@0 {
 8          target = <&rmem>;
 9          __overlay__ {
10              ramoops: ramoops@b000000 {
11                  compatible = "ramoops";
12                  reg = <0x0b000000 0x10000>; /* 64kB */
13                  record-size = <0x4000>; /* 16kB */
14                  console-size = <0>; /* disabled by default */
15              };
16          };
17      };
18
19      __overrides__ {
20          base-addr = <&ramoops>,"reg:0";
21          total-size = <&ramoops>,"reg:4";
22          record-size = <&ramoops>,"record-size:0";
23          console-size = <&ramoops>,"console-size:0";
24      };
25  };
```

**Overlay name:** `ramoops` (loaded as `dtoverlay=ramoops`).
**Parameters accepted:** `base-addr`, `total-size`, `record-size`, `console-size` — four, no more.
Notably **there is no `ftrace-size` parameter**, so if `CONFIG_PSTORE_FTRACE` is ever enabled the
overlay cannot allocate an ftrace zone; that would need a modified `.dts`. VERIFIED.

`overlays/overlay_map.dts:251-255` routes the name per SoC:
```
251     ramoops {
252         bcm2835;
253         bcm2711 = "ramoops-pi4";
254         bcm2712 = "ramoops-pi4";
255     };
```
so on this board `dtoverlay=ramoops` loads the bcm2835 file directly. VERIFIED.

`overlays/README:3984-3996` documents defaults: base 0x0b000000, total 64kB, record 16kB,
console-size 0. VERIFIED.

`overlays/Makefile:227-228` lists both `ramoops.dtbo` and `ramoops-pi4.dtbo` as build targets, so
the kernel build *can* produce them. VERIFIED.

### The overlay is NOT in the deployed image

This is the practical blocker.

- `ls deploy/images/raspberrypi0-wifi/*.dtbo | wc -l` → **201** overlays deployed, **zero** matching
  `ramoops`. VERIFIED.
- `sources/meta-raspberrypi/conf/machine/include/rpi-base.inc` defines
  `RPI_KERNEL_DEVICETREE_OVERLAYS` as an explicit whitelist of **70** `overlays/*.dtbo` entries;
  `grep -c ramoops` on that file → **0**. VERIFIED.
- `deploy/images/raspberrypi0-wifi/bootfiles/` contains **no `overlays/` directory at all** — only
  `bootcode.bin`, `cmdline.txt`, `config.txt`, the `fixup*.dat` and `start*.elf` files. VERIFIED.

So enabling this requires a recipe change (`RPI_KERNEL_DEVICETREE_OVERLAYS:append = " overlays/ramoops.dtbo"`),
a rebuild, and then getting a **new file** onto the shared FAT partition.

### The base DTB will accept the overlay

`bcm2708-rpi-zero-w.dts` → `bcm2708.dtsi:2` → `bcm2835.dtsi:2` → `bcm283x.dtsi`, which defines the
label at `bcm283x.dtsi:33`:
```
33      rmem: reserved-memory {
34          #address-cells = <1>;
35          #size-cells = <1>;
36          ranges;
37
38          cma: linux,cma {
```
so `target = <&rmem>` resolves. VERIFIED.

And the **deployed** `bcm2708-rpi-zero-w.dtb` (31873 bytes) contains a `__symbols__` node and
exports the string `rmem`, confirmed by `strings` on the binary — so the firmware can resolve the
label at runtime. VERIFIED.

---

## Q3 — How to reserve the memory on this platform

### 3a. Do `ramoops.mem_address=` / `mem_size=` work without a DT node on ARM?

**They work as far as the driver is concerned — and that is exactly the problem.**

`fs/pstore/ram.c:912-959`, `ramoops_register_dummy()`, builds a `ramoops_platform_data` purely from
the module parameters and registers a platform device with no `of_node`:

```
921      if (!mem_size)
922          return;
923
924      pr_info("using module parameters\n");
...
952      dummy = platform_device_register_data(NULL, "ramoops", -1,
953              &pdata, sizeof(pdata));
```

`ramoops_probe()` at `ram.c:738` takes the DT branch only when `dev_of_node(dev) && !pdata`, so the
module-param device goes straight to the platform-data path. **No DT node is consulted, and nothing
anywhere reserves the memory.** VERIFIED.

### 3b. Is `mem=` needed on ARM?

**Yes — the kernel's own documentation says so, in exactly these terms.**
`Documentation/admin-guide/ramoops.rst:60-69`:

```
60   Setting the ramoops parameters can be done in several different manners:
61
62    A. Use the module parameters (which have the names of the variables described
63    as before). For quick debugging, you can also reserve parts of memory during
64    boot and then use the reserved memory for ramoops. For example, assuming a
65    machine with > 128 MB of memory, the following kernel command line will tell
66    the kernel to use only the first 128 MB of memory, and place ECC-protected
67    ramoops region at 128 MB boundary::
68
69      mem=128M ramoops.mem_address=0x8000000 ramoops.ecc=1
```

and at `ramoops.rst:123-127` the platform-device route is documented as additionally requiring an
explicit `memblock_reserve()` in architecture code. VERIFIED.

**Consequence for this device: the cmdline-only route is not viable.** `mem=176M` on a 512MB board
would strip ~300MB from a Chromium kiosk that is already memory-constrained. Without `mem=`, the
region is inside System RAM and unreserved, which is the silent-corruption case in Q4. There is no
ARM equivalent of x86's `memmap=` reservation. INFERRED from the two verified facts above.

### 3c. Does the DT route reserve correctly, given CMA?

Yes, and the ordering is safe. The overlay node carries a static `reg = <0x0b000000 0x10000>`, so it
is reserved by `memblock_reserve()` during the early flat-DT scan. `fdt_init_reserved_mem()`
(`drivers/of/of_reserved_mem.c:309-357`) only *allocates* for nodes whose size is still zero:

```
331          if (rmem->size == 0)
332              err = __reserved_mem_alloc_size(node, rmem->name,
333                               &rmem->base, &rmem->size);
```

`linux,cma` is a size-only node (`bcm283x.dtsi:38-43`, `size = <0x4000000>`, no `reg`), so CMA is
placed *around* the already-reserved ramoops region, not on top of it. There is also an explicit
`__rmem_check_for_overlap()` that prints `OVERLAP DETECTED!` (`of_reserved_mem.c:299`). VERIFIED.

The reserved-memory node becomes a platform device because `"ramoops"` is one of seven compatibles
explicitly whitelisted in `drivers/of/platform.c:535-544`:
```
540      { .compatible = "ramoops" },
```
VERIFIED.

### 3d. Does the vc_mem map constrain the address?

`vc_mem.mem_base = 0x1ec00000` (492MB), `vc_mem.mem_size = 0x20000000` (512MB) — so ARM-visible RAM
is `0x00000000`–`0x1ec00000` and the GPU owns the top 20MB.

`0x0b000000` = 176MB, and `0x0b000000 + 0x10000` = `0x0b010000`. That is comfortably inside ARM RAM
and ~316MB below the GPU split. **The stock overlay default is safe on this board.** VERIFIED
(arithmetic against the values supplied in the task; I did not read vc_mem off the device).

### 3e. The u-boot chain does not sit on that address, and does not eat the overlay

The device boots firmware → u-boot → kernel (`build/conf/local.conf:105: RPI_USE_U_BOOT = "1"`).
Two things had to be checked and both come out well.

**The overlay and the cmdline still reach the kernel.**
`sources/meta-raspberrypi/recipes-bsp/rpi-u-boot-scr/files/boot.cmd.in` is four lines:
```
1  fdt addr ${fdt_addr} && fdt get value bootargs /chosen bootargs
2  fatload mmc 0:1 ${kernel_addr_r} uImage
3  if test ! -e mmc 0:1 uboot.env; then saveenv; fi;
4  bootm ${kernel_addr_r} - ${fdt_addr}
```
Line 4 passes `${fdt_addr}` — the **firmware-loaded** FDT, i.e. the one the firmware has already
patched with any `dtoverlay=` from `config.txt`. Line 1 pulls `bootargs` out of that same FDT's
`/chosen`, i.e. from `cmdline.txt`. So both `config.txt` overlays and `cmdline.txt` parameters
survive the u-boot hop. VERIFIED.
(Consistent with `CONFIG_CMDLINE_FROM_BOOTLOADER=y` at `.config:401`.)

**u-boot never touches 176MB.** `include/configs/rpi.h:32` sets `CFG_SYS_SDRAM_SIZE = SZ_128M`, so
u-boot confines itself and its relocation to the bottom 128MB (`0x08000000`). All load addresses in
`board/raspberrypi/rpi/rpi.env:71-75` are at or below `0x02700000`:
```
71  kernel_addr_r=0x00080000
72  scriptaddr=0x02400000
73  pxefile_addr_r=0x02500000
74  fdt_addr_r=0x02600000
75  ramdisk_addr_r=0x02700000
```
and lines 68-69 set `fdt_high=ffffffff` / `initrd_high=ffffffff`, which *disables* u-boot's DTB and
initrd relocation entirely. The deployed `uImage` is 7,389,208 bytes; loaded at `0x00080000` it ends
near `0x00790000`, and the ARM decompressor targets `0x8000` with self-relocation just past the
decompressed image — all far below `0x0b000000`. VERIFIED (files) / INFERRED (the decompressor
arithmetic).

One residual unknown: `rpi.env:28-29` notes that "newer versions [of the boot firmware] place the
firmware-loaded DTB in high memory." I could not determine where this firmware puts it on a 512MB
Zero W. It is very unlikely to be at exactly 176MB, and a collision would show up immediately as a
failed boot or a garbled DTB, not as silent corruption — but this is NOT VERIFIED.

---

## Q4 — Failure mode if the address is wrong

**In no case does a wrong ramoops address stop the kernel booting.** `ramoops_probe()` is an ordinary
platform-driver probe; every error path is `goto fail_*` → `return err` (`ram.c:870-877`). A failed
probe is logged and ignored. VERIFIED. The four distinct outcomes:

### (a) Inside System RAM but not reserved — SILENT TWO-WAY CORRUPTION. This is the dangerous one.

`fs/pstore/ram_core.c:482-504`:
```
488      if (pfn_valid(start >> PAGE_SHIFT))
489          prz->vaddr = persistent_ram_vmap(start, size, memtype);
490      else
491          prz->vaddr = persistent_ram_iomap(start, size, memtype,
492                            prz->label);
```
When the address is inside System RAM, `pfn_valid()` is true and the code takes `persistent_ram_vmap()`
(`ram_core.c:~420-455`), which does `pfn_to_page()` + `vmap()` and **performs no ownership check
whatsoever** — no `request_mem_region()`, no consultation of memblock. If nothing reserved those
pages, the buddy allocator still owns them and will hand them to somebody else.

Result: ramoops writes its ring buffer over live kernel data, *and* whatever else got those pages
overwrites the ramoops buffer. The kernel boots normally and prints a cheerful
`ramoops: using 0x10000@0xb000000, ecc: 0` (`ram.c:864-866`). The corruption is silent, delayed, and
would look exactly like a new random instability on a box you are already debugging for
instability. VERIFIED.

**This is the reason the cmdline-only route must not be used without `mem=`.**

### (b) Outside System RAM (e.g. into the GPU region ≥ 0x1ec00000) — clean failure.

`pfn_valid()` false → `persistent_ram_iomap()` (`ram_core.c:457-480`), which *does* claim the region:
```
462      if (!request_mem_region(start, size, label ?: "ramoops")) {
463          pr_err("request mem region (%s 0x%llx@0x%llx) failed\n",
```
If it collides with a claimed resource, `request_mem_region()` fails, `persistent_ram_buffer_map()`
returns `-ENOMEM` after printing `Failed to map ...` (`ram_core.c:494-498`), probe fails, no ramoops,
boot continues. Safe and diagnosable from dmesg. VERIFIED.

### (c) Sizes inconsistent — clean failure, `ram.c:754-760`:
```
754      if (!pdata->mem_size || (!pdata->record_size && !pdata->console_size &&
755              !pdata->ftrace_size && !pdata->pmsg_size)) {
756          pr_err("The memory size and the record/console size must be "
757              "non-zero\n");
758          err = -EINVAL;
```
Note also `ram.c:762-769`: non-power-of-two sizes are silently **rounded down**, not rejected. So a
sloppy `total-size` quietly becomes something smaller than asked for. VERIFIED.

### (d) Stale or garbage contents at the address — handled, not fatal.

`persistent_ram_post_init()` (`ram_core.c:506-548`) checks a `PERSISTENT_RAM_SIG` (0x43474244, "DBGC")
xor'd with the zone type. On mismatch it logs `no valid data in buffer (sig = 0x%08x)` and zaps the
zone; on a valid signature with impossible start/size it logs `found existing invalid buffer` and
zaps. Either way, boot continues. VERIFIED.

**Practical read:** the only outcome that hurts is (a), and (a) is precisely what you get from the
cmdline-parameter route without `mem=`. The DT route cannot produce (a), because the node's `reg`
causes the early `memblock_reserve()`.

---

## Q5 — Does ramoops record anything useful for an interrupts-off hard lockup?

Answering this honestly in three parts, because they have different answers.

### The dmesg zone: NO. It will be empty.

`dmesg-ramoops-N` records come from `pstore_dump()`, registered as a `kmsg_dumper`
(`fs/pstore/platform.c:277`, `375-377`, `382-385`). `kmsg_dump()` is called from `panic()`, `oops_exit()`,
`emergency_restart()` and the shutdown paths. A CPU that stops servicing interrupts and is then shot
by the hardware watchdog reaches **none** of them. Nothing is written. VERIFIED.

Also relevant: `# CONFIG_PANIC_ON_OOPS is not set` and `# CONFIG_SOFTLOCKUP_DETECTOR is not set`, so
there is currently no software path that would turn this wedge into a panic either.

### The console zone: YES — and this is the real reason to do this at all.

`CONFIG_PSTORE_CONSOLE=y` is already set. `pstore_console_write()` (`platform.c:393-406`) is a
console `->write` handler, registered at `platform.c:413-423` with:
```
422      pstore_console.flags = CON_PRINTBUFFER | CON_ENABLED | CON_ANYTIME;
423      register_console(&pstore_console);
```
It writes each chunk straight through `psinfo->write()` into the ramoops console PRZ, uncompressed,
**at the moment the message is printed**. There is no dumper, no panic, no crash involved.

So after the watchdog resets the board, `/sys/fs/pstore/console-ramoops-0` holds the tail of the
kernel log right up to the wedge — brcmfmac chatter, SDIO errors, mmc timeouts, whatever was on its
way out when the CPU stopped. **Today that is lost entirely**, because it lived only in the kernel
log buffer and journald never got to flush it. This is a genuine, real gain and it needs no kernel
rebuild. VERIFIED.

Two honest caveats:
- The overlay ships `console-size = <0>` (VERIFIED, `ramoops-overlay.dts:14`) — the zone is off
  unless `console-size=` is passed. Easy to get wrong and then conclude "ramoops doesn't work".
- A message stored into the printk ring buffer microseconds before the lockup, but not yet flushed
  to consoles, is lost. In ordinary process context `console_unlock()` flushes synchronously so the
  gap is small, but it is not zero. INFERRED from the printk architecture; I did not trace 6.6's
  flush paths exhaustively.

### `pstore/ftrace`: YES in principle, and it is the only thing that can name the stuck function —
### but it costs a rebuild and it is expensive.

What it records, from `fs/pstore/ftrace.c:26-58`: for every traced kernel function call, a fixed
16-ish-byte record of `(ip, parent_ip, timestamp, cpu)` — **not** arguments, **not** a stack, **not**
any text. On readback the records are merged by timestamp (`pstore_ftrace_combine_log()`,
`ftrace.c:157-208`) and rendered as a caller→callee list. You get "the last N function calls the CPU
made", nothing richer.

**Does it work with interrupts disabled? Yes.** `ftrace.c:48-56`:
```
48      local_irq_save(flags);
49
50      rec.ip = ip;
51      rec.parent_ip = parent_ip;
52      pstore_ftrace_write_timestamp(&rec, pstore_ftrace_stamp++);
53      pstore_ftrace_encode_cpu(&rec, raw_smp_processor_id());
54      psinfo->write(&record);
55
56      local_irq_restore(flags);
```
It *itself* disables interrupts around the write, and it is invoked from the ftrace call site, not
from any crash path. So it keeps recording in a context where interrupts are already off. VERIFIED.
(It bails out only if `oops_in_progress` — `ftrace.c:41-42` — which is the opposite situation.)

**What stops it being the answer:**

1. `# CONFIG_PSTORE_FTRACE is not set`. Enabling it is a **kernel rebuild and a full RAUC OTA**, not
   a `/boot` write. VERIFIED.
2. The RPi overlay has **no `ftrace-size` parameter** (`ramoops-overlay.dts:19-24` lists only four),
   so the ftrace zone cannot be sized from `config.txt`. A modified `.dts` would be needed too.
   VERIFIED.
3. It is off at boot and must be armed: `/sys/kernel/debug/pstore/record_ftrace`
   (`ftrace.c:132-143`) or the `pstore.record_ftrace=1` module parameter (`ftrace.c:127-131`).
4. **Cost.** Every kernel function call becomes a trap into `pstore_ftrace_call()` plus a store to
   write-combined memory, with an irq save/restore around it. On one 1GHz ARM11 core with no
   meaningful branch prediction, this is a large multiple on kernel-side time. On a board that is
   already marginal enough to wedge under WiFi receive load, **this may well change the timing of
   the bug you are trying to catch, or make the kiosk unusable while armed.** INFERRED, but the
   kernel's own docs warn about the overhead.
5. **It may not even name the culprit.** If the CPU is spinning inside a single function — e.g. a
   `while` loop polling an SDIO/mmc register, which is a very plausible shape for "stops servicing
   interrupts" — no *new* calls occur, so the trace ends at the last call before the spin. That is
   still the single most valuable datum available, but it is a hint, not a stack trace. INFERRED.

### Summary answer to Q5

| Zone | Captures this bug? | Needs |
|---|---|---|
| `dmesg-ramoops` | **No** — needs oops/panic, which never happens | — |
| `console-ramoops` | **Yes** — last kernel log before the wedge | already `=y`; must pass `console-size=` |
| `ftrace-ramoops` | **Yes, partially** — last function calls, works irqs-off | kernel rebuild + modified overlay + big perf cost |

---

## Q6 — BCM2835 / RPi-specific gotchas

### The decisive fact: on BCM2835, `reboot` *is* a watchdog reset

This is the strongest available evidence that DRAM survives, and it is verifiable in this tree.
`drivers/watchdog/bcm2835_wdt.c`:

Arming the watchdog, `bcm2835_wdt_start()` at lines 68-72:
```
68      writel_relaxed(PM_PASSWORD | (SECS_TO_WDOG_TICKS(wdog->timeout) &
69                  PM_WDOG_TIME_SET), wdt->base + PM_WDOG);
70      cur = readl_relaxed(wdt->base + PM_RSTC);
71      writel_relaxed(PM_PASSWORD | (cur & PM_RSTC_WRCFG_CLR) |
72          PM_RSTC_WRCFG_FULL_RESET, wdt->base + PM_RSTC);
```

Performing an ordinary `reboot`, `__bcm2835_restart()` at lines 114-119:
```
114     /* use a timeout of 10 ticks (~150us) */
115     writel_relaxed(10 | PM_PASSWORD, wdt->base + PM_WDOG);
116     val = readl_relaxed(wdt->base + PM_RSTC);
117     val &= PM_RSTC_WRCFG_CLR;
118     val |= PM_PASSWORD | PM_RSTC_WRCFG_FULL_RESET;
119     writel_relaxed(val, wdt->base + PM_RSTC);
```

**These are the same register writes.** A software reboot on this SoC is implemented *as* a watchdog
timeout with a 150µs fuse. VERIFIED.

Therefore: "does the ramoops region survive a hardware watchdog reset?" is not a separate question
from "does it survive `reboot`?" — the SoC cannot tell them apart. Since ramoops on Raspberry Pi is
routinely used across `reboot` (that is its entire purpose, and the upstream overlay exists because
it works), the watchdog case behaves identically. **INFERRED**, from a VERIFIED source identity.

A secondary confirmation of the same shape: `bcm2835_restart()` passes a *partition number* through
`PM_RSTS` for the firmware to read after the reset (`bcm2835_wdt.c:95-112`). The firmware reading
state out of a register that survived the reset tells you the reset is a warm SoC reset, not a
power cycle. VERIFIED (comment + code), INFERRED (the conclusion).

### Does the firmware zero DRAM?

**REPORTED, not verified.** The originating Raspberry Pi forum thread — the one in which RPi engineer
PhilE supplied the overlay that later became `ramoops-overlay.dts` — has the original poster stating
the region survived even a fast power unplug: *"It even worked when I rebooted by quickly unplugging
the power, ram didn't loose it's contents!"*. That is a forum anecdote about DRAM decay timing, not a
firmware guarantee, and I would not lean on the power-cycle part. But it is consistent with the
firmware not memsetting DRAM at boot, and no source I found claims it does.

I could not find any authoritative Raspberry Pi statement, in this tree or on the web, that the
VideoCore firmware clears DRAM on reset. Absence of evidence, stated as such.

### Known bug worth knowing about: ramoops panic capture fails on Pi 4

Multiple reports (RPi forum thread 377193; `raspberrypi/linux` issue 5298) that panic records do not
appear in `/sys/fs/pstore` on **Pi 4** while the same setup works on **Pi 3B+ and Pi 5** — with
ramoops registering correctly in dmesg in all cases. Neither report has a maintainer root-cause.

Relevance here: Pi 4 is BCM2711 with a completely different EEPROM bootloader; the Zero W is BCM2835
and shares the boot path with the 3B+ that is reported working. So this is probably not our problem —
but it is a live, unexplained failure of exactly this mechanism on RPi hardware, and it means
"ramoops registered successfully" is **not** proof that ramoops will produce anything. REPORTED.

### The `/boot` write is bigger than one line

The overlay is the only viable route (Q3), and it requires **two** things on the shared FAT
partition, not one:

1. **A new file `overlays/ramoops.dtbo`.** The `bootfiles/` directory has **no `overlays/`
   directory at all** today, and the 201 deployed `.dtbo` files do not include ramoops. VERIFIED.
2. **A line in `config.txt`**, e.g. `dtoverlay=ramoops,console-size=0x8000,total-size=0x20000`.

Worth noting for risk staging: **step 1 alone changes nothing.** An overlay file that is never
referenced by `config.txt` is inert. So the file can be placed and verified first, and only then the
`config.txt` line appended — which keeps the irreversible-looking part down to a single appended line
on a file that already has appended lines (`recipes-bsp/bootfiles/rpi-config_%.bbappend` already
appends three HDMI lines to it).

For reference, the current deployed `cmdline.txt` is one line:
```
dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait  net.ifnames=0 panic=10
```
and `config.txt` ends with `enable_uart=1` plus the three kiosk HDMI lines. VERIFIED.

### Other notes

- `enable_uart=1` is already set in `config.txt`, but `CMDLINE_SERIAL = "console=tty1"`
  (`build/conf/local.conf:29`) means no serial console is requested. Consistent with the stated
  constraint. VERIFIED.
- 512MB board, so no ARM highmem is involved; `pfn_valid()` is unambiguous across the whole
  ARM-visible range. INFERRED.
- `mem_type` should be left at 0 (write-combined). `ramoops.rst:27-32` warns that `mem_type=1`
  (`pgprot_noncached`) maps strongly-ordered on ARM, where atomics are implementation-defined and
  "won't work on many ARMs". Do not set it. VERIFIED.

---

## Recommended configuration, if the owner proceeds

```
dtoverlay=ramoops,total-size=0x20000,record-size=0x4000,console-size=0x10000
```

- `total-size=0x20000` (128KB) instead of the 64KB default, to give the console zone room.
- `console-size=0x10000` (64KB) — **the whole point**; the default of 0 disables it.
- `record-size=0x4000` (16KB) leaves 64KB for dmesg records, i.e. 4 slots, for the (unlikely) case
  that this ever does produce a real oops.
- `base-addr` left at the default `0x0b000000` — verified safe against vc_mem, u-boot and CMA above.

Post-boot checks, all read-only over SSH:
- `dmesg | grep -i ramoops` → expect `ramoops: using 0x20000@0xb000000, ecc: 0`
- `dmesg | grep -i 'reserved mem\|OVERLAP'` → expect the region listed, and no `OVERLAP DETECTED!`
- `mount -t pstore pstore /sys/fs/pstore` then `ls /sys/fs/pstore`
- Prove the mechanism end-to-end **before** trusting it on the real bug: `reboot`, then confirm
  `console-ramoops-0` exists and contains the pre-reboot log. Because reboot and watchdog reset are
  the same hardware event (Q6), a passing reboot test is a passing watchdog test.

## What I could not verify

- Where this firmware places the DTB in high memory on a 512MB Zero W (potential, unlikely,
  collision with 0x0b000000).
- Whether the VideoCore firmware clears DRAM — no authoritative source found either way.
- The root cause of the Pi 4 ramoops failure, and hence whether any part of it could apply here.
- Anything about the live device: I read only the build tree.
