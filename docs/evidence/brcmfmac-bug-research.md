# brcmfmac SDIO rx crash on BCM43430 / Pi Zero W / kernel 6.6.63 — research findings

Date: 2026-08-13. Read-only investigation. Nothing was modified, no device was touched, no bitbake run.

Local driver source read:
`/home/tjwise/meta-wisekiosk/build/tmp-raspberrypi0-wifi/work-shared/raspberrypi0-wifi/kernel-source/drivers/net/wireless/broadcom/brcm80211/brcmfmac/`
Kernel version confirmed from `kernel-source/Makefile`: **VERSION 6, PATCHLEVEL 6, SUBLEVEL 63** (6.6.63, EXTRAVERSION empty).

Legend: **[V]** = verified in local source or in a commit/branch I fetched. **[I]** = inference, stated as such.

---

## Bottom line first

**I did not find a known bug whose published signature matches this crash.** There is no upstream
commit, bugzilla entry, linux-wireless thread or raspberrypi/linux issue describing a *prefetch abort
to an unmapped data address* out of `brcmf_sdio_dataworker` under sustained SDIO rx. Saying otherwise
would be manufacturing a cause.

What I *did* find is **one genuine, unguarded defect that is live in this exact tree** (an
unbounded rx-glom subframe count walking off a fixed-size scatterlist), whose two upstream fixes are
both **missing from 6.6.63**. Its published failure mode is a NULL dereference, **not** this crash —
so it is a real bug you should close regardless, but I cannot claim it is *this* bug. Details and the
mismatch are spelled out in §2 and §3.

---

## 1. Is this a known bug?

### 1a. The two upstream commits that touch this exact path

Both are by Norbert van Bolhuis, both November 2024, both in `bcmsdh.c`, both **absent from 6.6.63**.

| Commit | Subject | Mainline since | In `linux-6.6.y`? | In local 6.6.63 tree? |
|---|---|---|---|---|
| `857282b819cbaa0675aaab1e7542e2c0579f52d7` | wifi: brcmfmac: Fix oops due to NULL pointer dereference in `brcmf_sdiod_sglist_rw()` | **v6.13** [V] | **Yes** — backported as `07c020c6d14d`, stable committer date 2024-12-14, first tag **v6.6.66** [V] | **No** [V] |
| `52e8726d6782...` | wifi: brcmfmac: fix scatter-gather handling by detecting end of sg list | **v6.14** [V] | **No** — never backported to `linux-6.6.y` *or* `linux-6.12.y` [V] | **No** [V] |

URLs:
- https://github.com/torvalds/linux/commit/857282b819cbaa0675aaab1e7542e2c0579f52d7
- https://github.com/torvalds/linux/commit/52e8726d6782 (full sha resolvable via that prefix)
- Stable backport of the first: https://github.com/gregkh/linux/commit/07c020c6d14d

Containment was measured with `gh api repos/torvalds/linux/compare/<tag>...<sha> --jq .status`, not
recalled:
```
v6.13...857282b819cb  => behind    ahead_by=0   behind_by=14289   (v6.13 contains it)
v6.12...857282b819cb  => diverged                                 (v6.12 does not)
v6.14...52e8726d6782  => ahead                                    (v6.14 contains it)
v6.13...52e8726d6782  => diverged  ahead_by=12                    (v6.13 does not)
```

The 6.6.66 landing point was found by `gh api repos/gregkh/linux/compare/07c020c6d14d...v6.6.6N`:
v6.6.64 `behind`, v6.6.65 `behind`, v6.6.66 `ahead`. So **6.6.63 is two point releases short of the
one backport that exists**.

**The raspberrypi tree already carries it.** `repos/raspberrypi/linux` branch `rpi-6.6.y` contains
`07c020c6d14d` in `bcmsdh.c` [V]. So a plain rpi-6.6.y bump past 6.6.66 picks up fix #1 for free;
fix #2 would still have to be cherry-picked.

Other brcmfmac SDIO commits after 6.6.63, for completeness — none of them is an rx-path data
corruption fix:
- `c623b6358088` (2026-04-16) sdio.c — use-after-free when stopping the watchdog task (teardown path)
- `2a665946e040` (2026-06-19) sdio.c — initialize SDIO data work before cleanup (probe/teardown path)
- `43b25879f004` (2026-07-18) — drain `bus_reset` work on device removal (removal path)
- `243307a0d1b0` (2026-02-03) — kernel oops when probe fails (probe path)

### 1b. Mailing list / bugzilla

**Could not be searched.** `git.kernel.org` and `lore.kernel.org` both return an Anubis
"Access Denied" interstitial to WebFetch from this host [V — three separate fetches, all blocked].
I substituted the GitHub mirrors of `torvalds/linux`, `gregkh/linux` and `raspberrypi/linux` for the
git history, which is complete for commits, but **the mailing-list discussion and kernel bugzilla
remain unsearched**. That is a real gap in this report, not a null result.

### 1c. raspberrypi/linux issues

Nothing matching. The closest neighbours, none of which is this bug:

- **#2555 — "Kernel oops or hard freeze when streaming video on Zero W (and Pi 3B+)"** (open)
  https://github.com/raspberrypi/linux/issues/2555
  Zero W, load-triggered, but kernel 4.14 and the traces land in VCHIQ / `alloc_contig_range`, i.e.
  camera DMA, not brcmfmac. Labelled "wifi" but the evidence in-thread is not.
- **#4466 — "RPI0w Kernel Panic Related to ipv6_rcv"** (open)
  https://github.com/raspberrypi/linux/issues/4466
  **This is the closest structural match.** Pi Zero W Rev 1.1, ARMv6, 5.10.17. "Unable to handle
  kernel paging request at virtual address bf8447b8", **Oops: 80000005 — an instruction fetch
  abort**, PC unresolved, "bad PC value", crashing in the network receive path. Same *class* as
  yours: a wild branch during rx on this SoC, with no symbol at PC. No root cause, no workaround,
  never diagnosed. Different kernel and different oops code (yours `8000000d`), so it is corroborating
  context, not an identification.
- **#5572 — "Raspberry Pi Zero W: kernel oops and panic under memory or storage load in any recent
  kernel"** (open) https://github.com/raspberrypi/linux/issues/5572
  Zero W, 6.1.21+ crashes, 5.10.103+ clean. Trigger is `stress --vm 1` and `stress --hdd 2`;
  `stress --cpu 4` does **not** crash it. No bisect, no diagnosis, no workaround.
  Relevant because it says memory/IO pressure alone crashes this board on post-5.10 kernels with no
  WiFi involved — worth weighing given `zram`/`zsmalloc` are in your `Modules linked in:`.
- #3849, #4783, #4161, #152 (Raspberry-Pi-OS-64bit) — all `brcmf_sdio_txfail` / `failed backplane
  access` / CMD53 timeout stories. **Ruled out for you**: every one of them has non-zero SDIO error
  counters, and your host controller counters are all zero.

---

## 2. The glomming / rx aggregation path — what is actually wrong in this tree

### 2a. VERIFIED: the rx glom subframe count is unbounded, and the scatterlist is fixed at 35 entries

`bcmsdh.c:750-778` — the scatter-gather table is sized once, at probe:

```c
750  void brcmf_sdiod_sgtable_alloc(struct brcmf_sdio_dev *sdiodev)
760      sdiodev->sg_support = host->max_segs > 1;
764      sdiodev->max_segment_count = min_t(uint, host->max_segs, SG_MAX_SINGLE_ALLOC);
771      nents = max_t(uint, BRCMF_DEFAULT_RXGLOM_SIZE,
772                    sdiodev->settings->bus.sdio.txglomsz);
773      nents += (nents >> 4) + 1;
775      WARN_ON(nents > sdiodev->max_segment_count);
778      err = sg_alloc_table(&sdiodev->sgtable, nents, GFP_KERNEL);
```

`BRCMF_DEFAULT_RXGLOM_SIZE` is 32 (`bcmsdh.c:52`) and `txglomsz` defaults to
`BRCMF_DEFAULT_TXGLOM_SIZE` = 32 (`common.c:36-39`), so **nents = 32 + 2 + 1 = 35** [V].
Line 773 is exactly the line commit `857282b819cb` replaces with `nents *= 2` (→ 64).

Now the chain-building loop, `sdio.c:1558-1595`:

```c
1558      for (totlen = num = 0; dlen; num++) {
1560          sublen = get_unaligned_le16(dptr);
1561          dlen -= sizeof(u16);  dptr += sizeof(u16);
...
1585          pnext = brcmu_pkt_buf_get_skb(sublen + bus->sgentry_align);
1591          skb_queue_tail(&bus->glom, pnext);
```

**There is no cap on `num` anywhere in this loop** [V]. The iteration count is driven purely by
`dlen`, the length of the glom descriptor the *firmware* handed us (`sdio.c:1550`, `bus->glomd->len`,
a `u16`). The only sanity checks are `dlen != 0`, `dlen` even (line 1552), and a per-subframe minimum
length (1563). A descriptor claiming, say, 60 subframes produces a 60-deep `bus->glom` queue and the
code is perfectly happy.

That queue then goes straight into the scatter-gather walk, `bcmsdh.c:445-475`:

```c
447      sgl = sdiodev->sgtable.sgl;
448      skb_queue_walk(target_list, pkt_next) {
450          while (pkt_offset < pkt_next->len) {
...
458              sg_set_buf(sgl, pkt_data, sg_data_sz);     /* <-- no NULL check */
459              sg_cnt++;
461              sgl = sg_next(sgl);
464              if (req_sz >= max_req_sz || sg_cnt >= max_seg_cnt) { ... reset sgl ... }
```

The reset at 464 is bounded by `max_seg_cnt = min(sdiodev->max_segment_count, target_list->qlen)`
(`bcmsdh.c:425`), i.e. **by the queue length, not by the table size**. On this SoC
`host->max_segs = 128` (`drivers/mmc/host/bcm2835-mmc.c:1357`, `mmc->max_segs = 128`) [V], so
`max_segment_count = 128`. Therefore any `bus->glom` queue deeper than 35 walks `sgl` past the end of
a 35-entry table, `sg_next()` returns NULL at the last entry, and `sg_set_buf(NULL, ...)` dereferences
it. **Line 458 is precisely where commit `52e8726d6782` inserts `if (!sgl) { ret = -ENOMEM; goto
exit; }` — and that guard is not in this tree** [V].

So: **an unguarded, reachable defect, live in 6.6.63, in the rx aggregation path, and rate-dependent
in exactly the way you describe** (deeper superframes only occur when the firmware has many packets
queued, which only happens at sustained high rx rate).

### 2b. VERIFIED: the precondition stated in commit 857282b819cb does NOT hold on this board

The commit message says the bug "occurs when a high `sd_sgentry_align` value applies (e.g. 512)". On
this platform it does not:

- `sdio.c:559-561`: `ALIGNMENT` is 8 on 64-bit, **4 on 32-bit**. You are 32-bit ARM → 4.
- `sdio.c:4211-4216`: `bus->sgentry_align = ALIGNMENT;` and is only raised
  `if (sdiodev->settings->bus.sdio.sd_sgentry_align > ALIGNMENT)`.
- `of.c` sets **only** `brcm,drive-strength` (`of.c:128-129`). It never touches `sd_sgentry_align` or
  `sd_head_align` [V]. There is no `brcmfmac_pdata` platform data for this device, so
  `brcmf_get_module_param()` falls through to `brcmf_of_probe()` (`common.c:594-597`).

⇒ `sd_sgentry_align == 0`, `bus->sgentry_align == 4` [V]. The tx tail-padding path the commit
describes (a second skb allocated per original skb because tailroom cannot hold a 512-byte tail pad)
**cannot fire here**.

This matters: it means the *tx* mechanism that motivated the fix is not your mechanism. The **rx**
mechanism in §2a is a different, independently reachable route to the same overrun, and it is the one
that is rate-dependent. That reading is [I], derived from the source above, not from any commit
message.

### 2c. VERIFIED: the deglom trim/pull path is correctly bounds-checked — I found no defect there

I specifically went looking for the classic unvalidated `__skb_trim`/`skb_pull` in
`brcmf_sdio_rxglom()` and it is **not** there. `sdio.c:1704-1714`:

```c
1704      skb_queue_walk_safe(&bus->glom, pfirst, pnext) {
1705          dptr = (u8 *) (pfirst->data);
1706          sublen = get_unaligned_le16(dptr);
1707          doff = brcmf_sdio_getdatoffset(&dptr[SDPCM_HWHDR_LEN]);
1713          __skb_trim(pfirst, sublen);
1714          skb_pull(pfirst, doff);
```

`sublen` and `doff` are re-read raw from the device-supplied subframe header with no check *at this
point*, but the validation walk immediately above (`sdio.c:1674-1689`) has already run
`brcmf_sdio_hdparse(..., BRCMF_SDIO_FT_SUB)` over every subframe with `rd_new.len = pnext->len`, and
`hdparse` enforces both bounds (`sdio.c:1416-1418`: `type == BRCMF_SDIO_FT_SUB && len > rd->len` →
`-EPROTO`; `sdio.c:1453-1460`: `dat_offset < SDPCM_HDRLEN || dat_offset > rd->len` → `-ENXIO`), and
any error aborts the whole superframe at 1691-1700. The buffers are host RAM and the SDIO read has
completed, so there is no TOCTOU between validation and use. **Clean** [V].

### 2d. VERIFIED: no use-after-free found in the glom teardown either

`brcmf_sdio_free_glom` (`sdio.c:1300-1315`) uses `skb_queue_walk_safe` + `skb_unlink` before
`brcmu_pkt_buf_free_skb` — correct. The handoff loop at 1704-1736 unlinks `pfirst` (line 1717 / 1729)
*before* passing it to `brcmf_rx_event`/`brcmf_rx_frame`, and `pnext` was captured before the body
ran, so the iterator never touches a freed skb. `bus->glomd` is freed once and NULLed
(`sdio.c:1614-1615`). I found nothing here [V].

Incidentally `brcmu_pkt_buf_free_skb()` carries `WARN_ON(skb->next)`
(`brcmutil/utils.c:37`) — if a still-queued skb were being freed you would have seen that warning
first, and you did not.

---

## 3. Where the crash signature and the glom bug disagree — read this before acting

The §2a overrun terminates as `sg_set_buf(NULL, ...)` → **a data abort at or near virtual address 0,
inside `brcmf_sdiod_sglist_rw`, with a resolvable PC and a normal backtrace.**

Yours is a **prefetch abort** ("when execute", Oops `8000000d`) at `c1137c58`, with `*pgd=0100041e(bad)`,
**neither PC nor LR resolving to a symbol**, and a `Code:` line full of `b62fce74`-style values —
which are userspace-range ARM32 addresses, i.e. the CPU is fetching instructions from a page that
contains a table of pointers. Those are different failures. **The glom/sgtable bug does not produce
your oops** [I, but a confident one — the faulting instruction and the fault class both differ].

Three further observations from your register dump, offered as leads rather than conclusions, all [I]:

1. **`c1137c58` and `c49eb964` are both in the ARM32 lowmem linear map**, not in module space. So this
   is not a stale pointer into an unloaded module (which is what #4466's `bf8447b8` looks like) — it
   is a branch into an ordinary data page. LR sitting in lowmem too means the *call site* was also
   already bogus, i.e. corruption happened at least one frame earlier than the fault.
2. **"Fatal exception in interrupt" means `in_interrupt()` was true.** On ARM `die()` only panics with
   that wording from hard or soft IRQ context. `brcmf_sdio_dataworker` is a workqueue (process
   context), so the fault happened in a **softirq running on top of** that worker — which is exactly
   where `netif_rx()` lands you: `sdio.c:1733 brcmf_rx_frame()` → `core.c:519 brcmf_netif_rx()` →
   `netif_rx()` → local_bh_enable → `net_rx_action` → `deliver_skb()` → `pt_prev->func(...)`, an
   indirect call. **The wild branch may well be in the network stack, not in brcmfmac at all**, with
   brcmfmac merely being the thing that delivers enough packets to reach it. The `ipv6` module in your
   `Modules linked in:` and issue #4466's `ipv6_rcv` are worth a second look here.
3. **`r4` points at a `kmalloc-cg-2k` object.** `-cg` is the memcg-*accounted* kmalloc cache. brcmfmac
   rx buffers cannot come from there: `brcmu_pkt_buf_get_skb()` is `dev_alloc_skb()`
   (`brcmutil/utils.c:17-28`) → `__alloc_skb` → `kmalloc_reserve()` (`net/core/skbuff.c:549-575`),
   which uses `skb_small_head_cache` or a plain `kmalloc-<n>` bucket and never sets `__GFP_ACCOUNT`.
   So **`r4` is not a driver rx buffer** — it is a socket-side accounted allocation. That is a hint
   the corrupted object belongs to the socket/TCP layer rather than to the SDIO driver.

None of that identifies the bug. It does suggest that "the crash is inside the brcmfmac rx glom code"
is the wrong starting premise, and that the more productive next step is a `CONFIG_SLUB_DEBUG` /
`slub_debug=FZPU` or KASAN run to catch the *writer* rather than the eventual wild branch —
acknowledging that KASAN on a 512 MB ARMv6 board with one 1 GHz core is a serious ask.

---

## 4. Workarounds that do not require patching

### 4a. VERIFIED: there is no module parameter that disables host rx deglomming

The complete `module_param` list in `common.c:36-77` is: `txglomsz`, `debug`, `p2pon`,
`feature_disable`, `alternative_fw_path`, `fcmode`, `roamoff`, `iapp`, and (DEBUG builds only)
`ignore_probe_fail` [V]. Nothing else exists.

**`brcmfmac.txglomsz=` will not help you, and it is worth being explicit about why**, because it is
the obvious thing to reach for:
- It only affects the **host→device** direction (`sdio.c:2235, 2264, 2303, 2363-2365`, all guarded by
  `bus->txglom`). Your problem is device→host.
- It cannot even shrink the scatterlist, because `nents` takes `max(BRCMF_DEFAULT_RXGLOM_SIZE=32,
  txglomsz)` (`bcmsdh.c:771-772`) — the 32 is a floor. `txglomsz=1` still yields nents = 35 [V].

### 4b. VERIFIED: debugfs exposes counters only, no knobs

`brcmf_debugfs_sdio_count_read` (`sdio.c:3368-3400`) is a `seq_file` read-only dump including
`rxglomfail`, `rxglomframes`, `rxglompkts`. **Useful for diagnosis** — if `rxglomframes` is climbing
and `rxglompkts / rxglomframes` is above ~35, §2a is live on your box and you can prove it without
crashing anything. There is no writable knob [V].

### 4c. The one real runtime lever: the firmware iovar — [V for the mechanism, [I] for the invocation

The device→host glomming you want to turn off is the firmware's **tx** glom (the file says so
explicitly, `sdio.c:3745-3748`): *"the commands below use the terms tx and rx from a device
perspective, ie. bus:txglom affects the bus transfers from device to host."*

And the driver already knows how to disable it — it just only does so for old SDIO cores
(`sdio.c:3749-3754`):

```c
3749      if (core->rev < 12) {
3750          /* for sdio core rev < 12, disable txgloming */
3751          iovar = 0;
3752          err = brcmf_iovar_data_set(dev, "bus:txglom", &iovar, sizeof(iovar));
```

(For the record, the `"bus:rxglom"` set at `sdio.c:3769-3781` is the *opposite* of what its name
suggests: it enables **host tx** glomming and sets `bus->txglom = true`. It is gated on
`sdiodev->sg_support`. Do not reach for it.)

**There is a userspace path to that iovar.** `vendor.c:19` defines
`brcmf_cfg80211_vndr_cmds_dcmd_handler`, registered as nl80211 vendor subcommand
`BRCMF_VNDR_CMDS_DCMD` (`vendor.c:111-116`), wired up at `cfg80211.c:7907-7908` [V]. That handler
passes arbitrary dcmds/iovars through to firmware — it is the interface `nexutil` and Broadcom's
`dhdutil`-style tools drive.

⇒ **[I, UNTESTED]** Setting `bus:txglom = 0` from userspace via that vendor command (e.g.
`nexutil -s'bus:txglom' -i -v0`, exact syntax unconfirmed) should stop the firmware from sending
superframes, which would take `brcmf_sdio_rxglom()` out of the path entirely and make the §2a overrun
unreachable. **I have not verified that `nexutil` is present in your image, that its iovar-set syntax
is as written, or that the 43430 firmware accepts the iovar post-init rather than only at bus
bring-up.** Treat this as a lead to test, on a bench unit, not as a fix. The throughput cost is
likely significant — deglomming exists because CMD53 per-frame overhead on this bus is high.

### 4d. Not available without patching

- **Forcing `sg_support = false`** would route superframe reads through the single-buffer + memcpy
  path (`bcmsdh.c:580-592`) and bypass the sgtable completely. But `sg_support` is derived from
  `host->max_segs > 1` (`bcmsdh.c:760`) with no override, so this needs an mmc-host or DT change.
- **Cherry-picking `52e8726d6782`** is a 5-line, self-contained, fail-closed guard. It is the
  cheapest correct change if you are willing to patch, and it is *not* in any stable tree, so a
  kernel bump alone will not deliver it.
- **Bumping rpi-6.6.y past 6.6.66** delivers `857282b819cb` (nents 35 → 64) for free [V]. That raises
  the bar from 35 subframes to 64 rather than removing it, and per §2b its stated precondition does
  not apply here anyway.

### 4e. The workaround you already have

Your own data — reliable at 1.5–2.5 MB/s, never at ~0.35 MB/s — is itself the mitigation: rate-limit
the receive. `tc` egress shaping on the far end, a smaller `SO_RCVBUF`, or a `--limit-rate` on
whatever pulls the payload. Unsatisfying, and it does not tell you what is broken, but it is the only
lever in this document that needs neither a patch nor an unverified tool.

---

## 5. Answers, condensed

1. **Known bug?** No published report matches this signature. Two real upstream fixes exist in this
   code path (§1a); neither is in 6.6.63; one is in 6.6.66+, the other in no stable tree at all.
   lore.kernel.org and kernel bugzilla could not be reached from this host and remain unsearched.
2. **Glom path:** one genuine unguarded defect [V] — unbounded subframe count (`sdio.c:1558`) feeding
   a fixed 35-entry scatterlist (`bcmsdh.c:773`) with no end-of-list check (`bcmsdh.c:458`). The
   deglom trim/pull and the teardown are both clean [V].
3. **Post-6.6.63 stable backports:** `857282b819cb` → `07c020c6d14d`, first in **v6.6.66**. That is
   the only one. `52e8726d6782` was never backported to 6.6.y or 6.12.y [V].
4. **No-patch workaround:** no module parameter, no debugfs knob [V]. The one candidate is the
   firmware iovar `bus:txglom = 0` through the existing nl80211 vendor dcmd interface — mechanism
   verified in source, invocation untested [I].
5. **Source review:** file:line citations throughout §2. Indirect calls reachable from
   `brcmf_sdio_rxglom` are `proto.h:61` (`drvr->proto->hdrpull`) and `proto.h:114`
   (`drvr->proto->rxreorder`), both via `core.c:506/510`; beyond that, `core.c:519 netif_rx()` hands
   off to softirq where `deliver_skb()` calls `pt_prev->func()`. No freed-then-reused skb found.

## 6. What I could not establish

- lore.kernel.org / linux-wireless archives and kernel bugzilla: **blocked, not searched.**
- Whether `bus->glom.qlen` on your device ever actually exceeds 35 — this is measurable from the
  existing debugfs counters (§4b) without any code change, and it is the single cheapest experiment
  that would confirm or kill §2a.
- Any causal link between the §2a defect and your actual oops. §3 argues they are different failures.
