# Would a kernel bump fix the ARMv6 prefetch-abort-in-softirq crash?

Read-only research. Nothing was built, nothing was touched on any device.
Research date 2026-08-13. Every claim tagged VERIFIED / INFERRED / UNREACHABLE.

## BOTTOM LINE (answer to Q6, up front)

**No identified fix. A bump to 6.6.66+, to 6.6.151, or to 6.12.103 is speculative for THIS
crash.** [INFERRED, from the VERIFIED deltas below]

The strongest single fact: **the ARM32 softirq-stack machinery this crash runs on is
byte-identical from v6.1 through today's mainline.** `call_with_stack.S` has not been touched
since 2022-10, and `do_softirq_own_stack()` / `init_irq_stacks()` in `arch/arm/kernel/irq.c` are
character-for-character the same in v6.6.63 and in `torvalds/linux` master. There is no ARM32
stack-switching fix to acquire by bumping, because there is no ARM32 stack-switching change.
[VERIFIED]

The second strongest: **the same crash signature is reported on 5.10.17**, which predates ARM32
IRQ stacks and ARM32 `VMAP_STACK` entirely (both landed in **v5.18**). Whatever this is, it is
not caused by the machinery the crash trace runs through. [VERIFIED]

Two commits in the window are worth naming anyway, neither of them a match to the reported
symptom, both cheap to get and both on this SoC's hot paths — see "Two honest maybes".

## Sources

| Source | Status |
|---|---|
| `github.com` API (`torvalds/linux`, `gregkh/linux`, `raspberrypi/linux`) via `gh` | reachable, used for everything |
| `raw.githubusercontent.com` (source at tags) | reachable |
| `git.kernel.org` | HTTP 200, not needed |
| **`lore.kernel.org`** | **HTTP 403 to this host, both `/linux-arm-kernel/` and `/all/?q=`** [UNREACHABLE] |

Consequence of the lore 403: I could not search mailing-list discussion, only committed history
and GitHub issues. A patch posted-but-never-merged would not appear in this research. [UNREACHABLE]

## Baseline anchors [VERIFIED]

- `v6.6.63` = `bff3e13adb72`, released **2024-11-22**.
- `linux-6.6.y` HEAD = `d27334b2888c` = **Linux 6.6.151** (2026-08-09).
- `linux-6.12.y` HEAD = `25c09b42358e` = **Linux 6.12.103** (2026-08-09).
- `raspberrypi/linux` `rpi-6.6.y` HEAD = `bba53a117a4a`, **2025-03-26** — the RPi 6.6 branch is
  effectively frozen. `rpi-6.12.y` exists and is the live one. This matters: "bump 6.6.y" on a
  Yocto `linux-raspberrypi` recipe means taking *RPi's* frozen 6.6 branch, not `gregkh`'s 6.6.151,
  unless the recipe rebases. Worth checking which the recipe actually tracks.

---

## Q1 — 6.6.63 → 6.6.151 delta on the named paths

### `net/core/dev.c` [VERIFIED — full commit list, 15 commits]

Nothing touching `__netif_receive_skb_one_core`, `deliver_skb`, `process_backlog` or
`net_rx_action` in a way that could fix a corrupted indirect-call target. The full list:

| Commit | Release | Subject |
|---|---|---|
| `95ccf006bbc8` | 6.6.x | net: reenable NETIF_F_IPV6_CSUM offload for BIG TCP packets |
| `b1bc4a35a04c` | 6.6.x | net: xdp: Disallow attaching device-bound programs in generic mode |
| `026b2a1b6a6f` | 6.6.x | net: Add non-RCU dev_getbyhwaddr() helper |
| `474cebf2978d` | **6.6.84** | net: Handle napi_schedule() calls from non-interrupt |
| `8dde02229b3c` | 6.6.x | net: Rename mono_delivery_time to tstamp_type |
| `2156d9e9f2e4` | 6.6.x | net: gso: Forbid IPv6 TSO with extensions … |
| `03765d5c1808` | **6.6.120** | net: Remove conditional threaded-NAPI wakeup based on task state |
| `f3652768a89c` | **6.6.120** | net: Allow to use SMP threads for backlog NAPI |
| `0ba0a79500fc` | 6.6.x | net: update netdev_lock_{type,name} |
| `507692c05636` | **6.6.123** | **Revert** "net: Allow to use SMP threads for backlog NAPI." |
| `5a530c8ead06` | **6.6.123** | **Revert** "net: Remove conditional threaded-NAPI wakeup…" |
| `9464ca7a6e56` | 6.6.128 | net: remove WARN_ON_ONCE when accessing forward path array |
| `9ac6aebef4b4` | 6.6.x | net: consume xmit errors of GSO frames |
| `ed71cf465c75` | 6.6.x | net: correctly handle tunneled traffic on IPV6_CSUM GSO fallback |
| `a1d397dbc00a` | 6.6.x | net: add a common function to compute features for upper devices |

Note the backlog-NAPI pair went in at 6.6.120 and came back out at 6.6.123 — net zero, and RT
plumbing regardless. `474cebf2978d` (6.6.84) is the only one on the backlog path; it is about
`napi_schedule()` from bare task context deferring softirq work past a NOHZ tick-stop, whose
symptom is the `"NOHZ tick-stop error: local softirq work is pending, handler #08!!!"` message,
not a corrupted call target. [VERIFIED from commit text]

### ARM32 `call_with_stack` / `do_softirq_own_stack` / softirq stack [VERIFIED]

**Zero changes.** Specifically:

- `arch/arm/lib/call_with_stack.S`: last modified `5854e4d8530e` ("ARM: 9233/1: stacktrace: Skip
  frame pointer boundary check for call_with_stack()"), **2022-08-26**, released in **v6.1**. It is
  the HEAD version of that file in `torvalds/linux` master today. `arch/arm/lib/` has **no**
  commits at all on `linux-6.6.y` since v6.6.63.
- `arch/arm/kernel/irq.c`: I fetched the `CONFIG_IRQSTACKS` block from `v6.6.63` and from
  `torvalds/linux` master and they are identical, including
  `call_with_stack(____do_softirq, NULL, __this_cpu_read(irq_stack_ptr))`. The only mainline change
  to that file since is `bc033158a0e6` "ARM: Switch to irq_get_nr_irqs()" (2024-10-15, a cleanup in
  `handle_IRQ()`), and it is not in 6.6.y at all.

### ARM32 VMAP_STACK / percpu [VERIFIED]

Three ARM commits landed in **Linux 6.6.64** — one release after the running kernel — and they are
the only VMAP-touching changes in the entire window. **All three are KASAN-only:**

| Stable commit | Upstream | Release | Subject | Applies? |
|---|---|---|---|---|
| `1359fd9eae29` | `d6e6a74d4cea` | **6.6.64** | ARM: 9429/1: ioremap: Sync PGDs for VMALLOC shadow | KASAN_VMALLOC only |
| `ef21187c0672` | `44e9a3bb76e5` | **6.6.64** | ARM: 9430/1: entry: Do a dummy read from VMAP shadow | KASAN_VMALLOC only |
| `2c932d5c7aac` | `93ee385254d5` | **6.6.64** | ARM: 9431/1: mm: Pair atomic_set_release() with _read_acquire() | vmalloc_seq, SMP-only |

`1359fd9eae29` says plainly "sync the **KASAN shadow memory** for the VMALLOC area"; `ef21187c0672`
says "also do a dummy read from the VMAP stack's corresponding **KASAN shadow** memory". Both are
`Fixes:` of KASAN commits and were reported against an ST board with KASAN on. `2c932d5c7aac` is a
one-line barrier tightening in `arch/arm/mm/ioremap.c`'s `vmalloc_seq` handling, which only exists
to sync PGDs **between CPUs** — inert on a single-CPU system. [VERIFIED from commit text + diffstat]

Unless the image is built with `CONFIG_KASAN_VMALLOC=y` — which on a Pi Zero W would be obvious and
would have made the crash far slower and far noisier — none of the three can apply.

Later ARM commits in the window, all in **6.6.143/6.6.144**, are a Russell King fault-reporting
refactor plus two unrelated fixes:

- `98b209cd62ef` (6.6.144) "ARM: allow `__do_kernel_fault()` to report execution of memory faults" —
  **diagnostics**, it makes the `when execute` wording available from a second code path.
- `89b37df6f805` (6.6.144) "ARM: group is_permission_fault() with is_translation_fault()" — prep.
- `1f7cc85046f1` (6.6.144) "ARM: fix hash_name() fault" — `load_unaligned_zeropad()` in the dcache
  path under `DEBUG_ATOMIC_SLEEP`+`KFENCE`. Not the network path.
- `de1ba6c93868` (6.6.144) "ARM: fix branch predictor hardening" — moves `harden_branch_predictor()`
  so interrupts are disabled at the call site. `harden_branch_predictor()` is **ARMv7/Spectre-BHB**
  machinery; ARM1176 is not in its CPU list. [INFERRED — ARMv6 exclusion is from the Kconfig
  dependency shape, not re-read line by line]
- `c2e3aadc8fef` (6.6.143) "ARM: 9475/1: entry: use byte load for KASAN VMAP stack shadow" — KASAN.

`arch/arm/mm/proc-v6.S`, `arch/arm/mm/cache-v6.S`, `arch/arm/kernel/traps.c`,
`arch/arm/kernel/unwind.c`, `arch/arm/kernel/stacktrace.c` and `arch/arm/mm/dma-mapping.c`:
**no commits at all** on `linux-6.6.y` since v6.6.63. [VERIFIED]

---

## Q2 — 6.12.y and mainline to 6.14

### 6.12.y (currently 6.12.103) [VERIFIED]

Same picture, same commits, different hashes:

- `arch/arm/lib/`: nothing since 2024-09 (`f6fc302db018`, a `MODULE_DESCRIPTION()` addition).
  `call_with_stack.S` last touched 2022.
- `arch/arm/kernel/`: `c86d26b4b089` (= ARM 9430/1, the KASAN shadow dummy read), `c74990828d3c`
  (= ARM 9475/1, KASAN byte load), plus `ca29cfcc4a21` "ARM: fix cacheflush with PAN" (LPAE PAN, and
  ARMv6 has no LPAE and no PAN) and XIP fixes. None applicable.
- `arch/arm/mm/`: the same four-commit fault refactor (`fed889edca79`, `25ae6a5c473b`,
  `d5e8be7bea8d`, `47c5d569d39d`), the same two KASAN/vmalloc_seq commits (`ad6750c17fb4`,
  `0cfd6929fa78`), `1c4026344310` memremap, `8ec5b525221e` `%pK`. None applicable.
- `net/core/dev.c`: 20 commits, all GSO/XDP/netmem/lock-annotation work. The only ones near the
  crash path are `d1ceef54b239` (the same `napi_schedule()` from non-interrupt fix) and
  `76e56dbe508b` "net: flush_backlog() small changes". Neither is a corruption fix.

**Going 6.6 → 6.12 buys nothing on any of the three named subsystems.** [VERIFIED]

It does change a great deal else (allocator, scheduler, timer, compiler flags), so it could easily
make the crash change *shape* or change *rate* without fixing it. That is worth stating explicitly
because "it stopped reproducing in the first hour" on a bug with a 50–70 s trigger under a specific
throughput is very weak evidence, and a 6.12 bump is exactly the change most likely to generate it.

### Mainline to 6.14 [VERIFIED]

Nothing beyond the above. `call_with_stack.S` HEAD in master is still the 2022 commit. The one
mainline commit that touches the exact function in the trace is `46173144e03d` "net: mark
deliver_skb() as unlikely and not inlined" (2025-11-03) — a **codegen/layout** change, not a fix,
and it is **not in 6.6.y or 6.12.y** (I checked both branches: zero commits matching `deliver_skb`).
If it were taken it would shift `__netif_receive_skb_one_core+0x5c`, which is worth knowing only so
nobody mistakes a changed offset for a fixed bug.

---

## Q3 — Is there a known ARM32 VMAP_STACK/softirq indirect-call bug?

**No such bug is identified, and there is positive evidence against the hypothesis.** [VERIFIED]

Three independent legs:

1. **The code has not changed.** `call_with_stack.S` is identical from v6.1 to master. If there
   were a live ARM32 stack-switching defect of this severity, five years of stable maintenance did
   not touch it.

2. **The mechanism predates the machinery.** ARM32 IRQ stacks (`d4664b6c987f`), running softirqs on
   the per-CPU IRQ stack (`9974f857768e`), vmap'ed stacks (`a1c510d0adc6`) and `call_with_stack`
   unwind support (`0b78f2e92d0c`) **all first shipped in v5.18** — I pinned this by ancestry
   against v5.10/v5.15/v5.16/v5.17/v5.18 tags. `raspberrypi/linux` issue #4466 reports the same
   crash on **5.10.17**, where `call_with_stack` was not in the softirq path and `VMAP_STACK` did
   not exist on ARM. A mechanism that requires those cannot explain a 5.10 occurrence of the same
   signature.

3. **`call_with_stack` cannot produce a varying-LR/constant-PC fault by miscomputing anything.**
   Reading the v6.6.63 source: it pushes `{fpreg, lr}` (or `{fp, ip, lr, pc}` under GCC frame-pointer
   unwinding), sets `sp = r2`, moves `r0 = r1` and `r2 = r0`, then `bl_r r2`. The only inputs are
   `____do_softirq` (a link-time constant) and `__this_cpu_read(irq_stack_ptr)`. There is no
   arithmetic on the target. A corrupted `irq_stack_ptr` would give a **data** abort on stack
   access, not an instruction fetch at `_end+0x111660`, and a corrupted target would fault at
   `call_with_stack+0x18` itself — but your trace has `call_with_stack+0x18` as a *return address*,
   meaning it dispatched correctly and the fault happened several frames deeper. [INFERRED, from
   reading the .S at v6.6.63]

Web search on this topic surfaced only the 2021–2022 development history of the feature
(Ard Biesheuvel's series, LWN coverage), no defect reports. Note the caveat: **lore is 403 from
this host**, so a mailing-list-only report would not have been found. [UNREACHABLE]

---

## Q4 — Is `_end + ~1.09 MB` meaningful on ARM32?

**Almost certainly not, and the specific percpu hypothesis is structurally impossible on this
config.** Concretely:

**Where percpu lives on ARM32** [VERIFIED — read `arch/arm/kernel/vmlinux.lds.S` at v6.6.63]:

```
	.exit.data : { ARM_EXIT_KEEP(EXIT_DATA) }

#ifdef CONFIG_SMP
	PERCPU_SECTION(L1_CACHE_BYTES)
#endif
	...
	__init_end = .;
	_sdata = .;  RW_DATA(...)  _edata = .;  BSS_SECTION(0,0,0)  _end = .;
```

Two things follow.

1. The percpu template section is **inside `__init_begin … __init_end`**, i.e. *before* `_edata`
   and *before* `_end`, and it is freed with initmem. It is never after `_end`.
2. It is compiled in **only under `CONFIG_SMP`**. `bcmrpi_defconfig` does not set `CONFIG_SMP`
   (I fetched the file; the symbol is absent and the Kconfig default is n), so on the stock ARMv6
   Pi config there is **no separate percpu area at all**: percpu variables sit in ordinary
   `.data`/`.bss` inside the kernel image and `per_cpu_offset()` is the literal constant `0`.

   **So on a UP build, "a percpu pointer used where a linear pointer was expected" cannot produce a
   wrong address, because the two are the same address and the offset is zero.** There is no delta
   to add once, twice, or not at all. [VERIFIED for `bcmrpi_defconfig`; **confirm against your own
   Yocto `.config` before relying on it** — if your build sets `CONFIG_SMP=y` on this single-core
   part, this leg collapses and the hypothesis becomes testable, see the discriminator below.]

**What is actually after `_end`** [INFERRED]: nothing structural is guaranteed. ARM's early
allocations (page tables via `early_alloc`, `mem_map`, CMA) go through `memblock`, which allocates
**top-down** from `arm_lowmem_limit` by default — i.e. from the *top* of lowmem, not from just
above the kernel image. `swapper_pg_dir` on non-LPAE ARM is at `PAGE_OFFSET + 0x4000`, which is
*below* `_text`, not above `_end`. So `_end + 0x111660` is overwhelmingly likely to be **ordinary
lowmem that the buddy allocator hands out as free pages** — general kernel heap, slab, page cache.

**Why the fault is a prefetch abort regardless of contents**: `map_lowmem()` in `arch/arm/mm/mmu.c`
maps the kernel *text* executable and the remainder of lowmem `MT_MEMORY_RW` (XN). So *any* branch
into post-`_end` lowmem produces exactly `8000000d … when execute`, whatever bytes are there. The
address therefore tells you where the branch went, and **nothing about what lives there**. Do not
read meaning into the target region. [INFERRED from the mapping code; I did not read every branch
of `map_lowmem()`]

**Would a fixed-offset error produce a constant PC?** Only if both operands are constant. A wrong
`struct packet_type *` walked out of `ptype_base[]` would make `pt_prev->func` a **load from heap**,
and heap contents are not reproducible across boots — that gives a *varying* PC, not a constant one.
A constant PC across separate crashes means the faulting value is derived from **link-time
constants**, not from data. That is the single most informative thing in your report, and it is
what makes the percpu/fixed-offset family of hypotheses attractive — it is just that on a UP ARM32
build there is no such offset in existence. [INFERRED]

**Cheap read-only discriminators** (System.map + the crash log, no device change):

- `0xc1137c58 - <&ip_rcv>` and `0xc1137c58 - <&ip_packet_type>` from your `System.map`. If either
  equals a round or recognisable quantity, you have the offset. If `CONFIG_SMP=y`, compare the first
  against `__per_cpu_offset[0]` (= `pcpu_base_addr - __per_cpu_start`).
- `0xc1137c58 - <&_end>` you already have: `0x111660`. Compare that against
  `__init_end - __init_begin` (initmem size) and against `_end - __per_cpu_start` from
  `System.map` — if the target is `_end` plus the size of a section, that is a linker-arithmetic
  bug and it is findable statically.
- Check whether `0xc1137c58` is congruent to a real symbol modulo the kernel's section alignment
  (`1<<SECTION_SHIFT` = 1 MB under `STRICT_KERNEL_RWX`). `0x111660` is `0x100000 + 0x11660` —
  **one 1 MB section plus 0x11660**. A one-section (one first-level page table entry) overshoot is
  a suggestive shape and is worth ten minutes with `System.map`: check whether
  `0xc1137c58 - 0x100000 = 0xc1037c58` lands inside a real function. [INFERRED — this is a
  hypothesis generated from the arithmetic, not a finding]

---

## Q5 — raspberrypi/linux issues

### #4466 "RPI0w Kernel Panic Related to ipv6_rcv" — **STILL OPEN** [VERIFIED]

Opened 2021-07-21, 10 comments, **last comment 2021-11-18**, no labels, **never closed, no linked
commit, no fix**. Read in full.

The decisive content is `bao-eng`'s 2021-09-29 report, on **5.10.17 on a Pi Zero W**, which is your
crash:

```
Unable to handle kernel paging request at virtual address bf8447b8
Internal error: Oops: 80000005 [#1] ARM
PC is at 0xbf8447b8      LR is at 0x2a
Backtrace:
 [<bf00876c>] (ipv6_rcv [ipv6]) from [<c071293c>] (__netif_receive_skb_one_core+0x64/0x84)
 (__netif_receive_skb_one_core) from (__netif_receive_skb+0x20/0x7c)
 (__netif_receive_skb) from (process_backlog+0x6c/0x110)
 (process_backlog) from (net_rx_action+0x160/0x414)
 (net_rx_action) from (__do_softirq+0x118/0x3e0)
Code: bad PC value
Kernel panic - not syncing: Fatal exception in interrupt
```

Same architecture, same board, same oops class (`80000005` is the 5.10 spelling of an ARM prefetch
abort; yours is `8000000d`), **same frame — the `deliver_skb()` indirect call out of
`__netif_receive_skb_one_core`** — same panic string, and critically the reporter writes "**same
problem (same address bf8447b8)**", i.e. **the constant-PC property reproduces independently**.
The workload was an OTA image download — sustained TCP receive over WiFi. It was `ipv6_rcv` there
and `ip_rcv` for you, which is just which `packet_type` was current.

Two other reporters in the thread (`ckelloug3`, `pastcompute`) hit related panics on Zero W with
`brcmfmac` loaded. `pelwell` (RPi engineer) engaged twice in July 2021 and the thread then died.

**Never resolved, no commit ever linked, no fix.** [VERIFIED]

### `call_with_stack` in RPi issues [VERIFIED]

Two hits, neither relevant: #6413 "Kernel Oops when communicating with an USB device" (open, 2024,
Pi 4/5 class) and #5297 (closed, Pi 4 armv7h, `vc4-kms-v3d` CMA). `call_with_stack` appears in
those as a routine stack-trace line, not as a suspect.

### #2555 "Kernel oops or hard freeze when streaming video on Zero W" — **OPEN since 2018-05-13, 63 comments** [VERIFIED]

This is the one that changes the picture, and it was not on your list.

It documents Pi Zero W kernel corruption under **sustained load with `brcmfmac` in the module list**
— camera streaming, `mavlink-router`, and notably one reporter whose Zero W "consistently froze when
trying to `apt-get update && apt-upgrade` **via WiFi**". The oopses are register-file corruption,
not a consistent code path:

- `Unable to handle kernel paging request at virtual address 6000009b` — **`0x6000009b` is a CPSR
  value**. A status register got into a general-purpose register or into PC.
- `PC is at no_work_pending+0x30` with `LR is at 0xbea4f970` (a *userspace* address).
- `kernel BUG at Returning to usermode but unexpected PSR bits set?:5!`

The community-established mitigation, reported independently as effective by at least six users
(`maciek01`, `cmptscpeacock`, `kbharadwaj93`, `wollew`, `Krautmaster`, `julled`), is
**`force_turbo=1` with `over_voltage=4`** — i.e. pinning the ARM clock and voltage and suppressing
DVFS transitions. `Krautmaster`, who ran the fix 24/7: "*I think the issue is more likely the turbo
mode or frequency switching (maybe even idle) than the overvolt itself.*" RPi's `JamesH65` and
`popcornmix` participated; the issue was never closed and no kernel commit was ever linked.

`bcmrpi_defconfig` ships `CONFIG_CPU_FREQ=y` with
`CONFIG_CPU_FREQ_DEFAULT_GOV_ONDEMAND=y` [VERIFIED — fetched the file].

**Why this matters for your rate threshold** [INFERRED]: "reproducible at 1.5–2.5 MB/s, *never* at
0.35 MB/s" is a poor fit for a software race, which would still fire at low rate, just more rarely —
you would expect a longer MTBF, not immunity. It is an excellent fit for a load-gated
frequency/voltage transition: sustained TCP receive at 2 MB/s saturates a 1 GHz ARM11 and drives
`ondemand` to the turbo OPP, while 0.35 MB/s never leaves the low OPP. That is a **threshold**, and
you have a threshold.

I want to be honest about the gap: #2555's corruption is *varying* and yours is *constant*, so this
is not a clean match either. But it is a documented, independently-reproduced, community-mitigated
Pi Zero W failure mode under exactly your workload shape, and it costs almost nothing to test.

---

## Two honest maybes in the bump window

Neither matches "constant bogus PC". Both are real fixes on this board's hot paths, and both are
free if a bump happens for other reasons.

1. **`07c020c6d14d` (upstream `857282b819cb`) — "wifi: brcmfmac: Fix oops due to NULL pointer
   dereference in `brcmf_sdiod_sglist_rw()`" — landed in Linux 6.6.66.** [VERIFIED]
   The pre-allocated sg table is sized `max(rxglom,txglom) + (max>>4) + 1` = 35 entries, but the
   packet queue can reach 64 SKBs, so `sg_next()` returns NULL mid-walk. It is in the **brcmfmac
   SDIO glom path**, it triggers **only when many SKBs are queued**, i.e. under sustained
   throughput, and 6.6.66 is exactly the bump you asked about.
   *Why it is probably not your bug*: the documented symptom is a NULL dereference (fault address
   near 0, data abort), not an instruction fetch at `_end+0x111660`. `sg_next()` returns NULL
   cleanly at the end marker rather than walking off the end, so it does not corrupt memory.
   [INFERRED from commit text]

2. **`5bfd0078f738` (upstream `ff09b71bf9da`) — "mmc: bcm2835: Fix `dma_unmap_sg()` nents value" —
   landed in Linux 6.6.100.** [VERIFIED]
   `dma_unmap_sg()` was called with the value `dma_map_sg()` *returned* instead of the value it was
   *passed*. On a non-coherent ARM11 that means cache maintenance over the wrong number of SG
   entries — a genuine silent-corruption primitive.
   *Why it is probably not your bug*: `drivers/mmc/host/bcm2835.c` is the **SDHOST** controller
   (`compatible = "brcm,bcm2835-sdhost"`), and its own file header says "the sdhost controller
   allows to use the sdhci controller for wifi" — so on a Pi Zero W this driver is the **SD card**,
   not the WiFi SDIO, which is `sdhci-iproc`. It would only be in play if the crash workload also
   writes to the card. Given your STATUS.md hazard note about sustained SDIO traffic wedging the
   board, it is worth knowing this bug existed on this exact SoC's MMC driver for the whole life of
   6.6.63. [VERIFIED for the driver identity; INFERRED for the Pi Zero W controller split]

Also noted, not applicable: `ed4168d1a50f` (brcmfmac watchdog UAF on stop), `f50a2b9e57a7`,
`c268331845ee`, `1335161f8502`, `b516ac892bcb` — all removal/teardown or BCM43752-specific; the
Pi Zero W is BCM43438.

---

## What I would do instead of bumping

All read-only or SSH-revertible. Ordered by information per unit of risk.

1. **Settle `CONFIG_SMP`** in the running image (`/proc/config.gz`, or the Yocto `.config`). It
   decides whether the percpu hypothesis in Q4 is even expressible. One grep.
2. **Do the `System.map` arithmetic** in Q4. `0x111660 = 0x100000 + 0x11660` — check whether
   `0xc1037c58` (target minus one 1 MB section) is a real symbol. Free, and if it hits, it names the
   bug.
3. **Test the DVFS hypothesis without touching `/boot`.** `echo performance >
   /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` pins the ARM clock at max from userspace;
   `echo powersave` pins it at min. Both are one-line reverts over SSH, and `/boot` stays untouched
   — this is the SSH-safe approximation of #2555's `force_turbo=1`. If the crash survives *both*
   pinned governors, DVFS is excluded and #2555 is off the table. If it disappears under one, you
   have a mitigation you can hold while the real cause is found. Read
   `/sys/devices/system/cpu/cpu0/cpufreq/stats/time_in_state` before and after to confirm the pin
   actually took, rather than assuming.
4. **If a bump happens anyway, go to `rpi-6.12.y`, not `rpi-6.6.y`** — RPi's 6.6 branch has been
   frozen since 2025-03-26, so a "6.6.y bump" through the RPi recipe may deliver none of the stable
   fixes catalogued above. Check what the Yocto recipe actually tracks before costing the work.
5. **Treat a post-bump non-reproduction as inconclusive for at least an order of magnitude more
   run-time than 50–70 s.** A 6.12 bump changes allocator, scheduler and codegen; the most likely
   outcome of the bump is that the *layout* moves and the constant PC becomes a different constant.
