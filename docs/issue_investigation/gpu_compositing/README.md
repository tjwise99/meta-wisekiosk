# Can the kiosk browser composite its animation on the GPU instead of repainting it in software?

| | |
|---|---|
| **Issue** | #100 gpu-compositing |
| **Status** | open |
| **Opened / concluded** | 2026-09-19 / — |

The park-wait-times marquee stutters on the Pi Zero W because WebKit renders in software: the image
disabled the GPU, so a continuous `transform` animation is repainted on the single armv6 core every
frame. WebKit here is built with accelerated compositing support and was held off at runtime by three
blockers, all of which the switch from the Broadcom userland EGL to vc4 + mesa closes. This
investigation measures whether that switch, plus promoting the animation to a composited layer, makes
the animation smooth without saturating the core — and what full KMS costs a 512 MB board. It
concludes when Run 2 measures the vc4 image on a board.

## Test runs

One numbered run, and it is **Run 2**. R1 requires a test run to name the image commit it ran, and
[`TEMPLATE.md`](../TEMPLATE.md) is explicit that an unverifiable "probably this build" is not a
commit — *leave the run out until you can name it*. The board's pre-vc4 state cannot be tied to a
commit (see Findings, "Pre-work probe"), so it is recorded as a probe under Findings and is **not** a
numbered run.

| Run | Board (role) | Image commit | Harness / scripts | Result (1 line) |
|---|---|---|---|---|
| 2 | prod · Pi Zero W | *this build, `/etc/buildinfo`* | `tools/kiosk-gpu-check.sh` — durable; `kiosk-soak` | pending |

### Run 2 — the vc4 image

- **Board:** prod, Raspberry Pi Zero W. One board, one build, one test — R3 holds trivially, because
  this is the investigation's only run. See "Delivery and board" for the authorization it carries.
- **Image commit:** the commit `just build` stamps into `/etc/buildinfo` for this build, confirmed by
  `grep ^meta-wisekiosk /etc/buildinfo` on the board. The base is `364a42f`, plus this branch's vc4
  edits and nothing else: **no application is baked into the image and no `SRCREV` is bumped**. The
  page still comes from the dev mirror over `KIOSK_URL`, so the marquee's CSS change reaches the
  board by redeploying the mirror, independently of this image. That keeps one variable per run —
  the display stack — rather than shipping a browser change and a rendering change in one build.
- **Scripts deployed:**
  - [`kiosk-gpu-check.sh`](../../../tools/kiosk-gpu-check.sh) — DURABLE, committed at that path with
    its self-test [`kiosk-gpu-check-test.sh`](../../../tools/kiosk-gpu-check-test.sh) and wired into
    `tools/ci-guards.sh`; it ships in the pull request that closes #100 gpu-compositing. Reads the
    GPU path's footprint in the web process over SSH and exits non-zero when it is absent or
    software-only. Its header records why the buffer mode itself is not readable headless.
  - `kiosk-soak.sh` — DURABLE, already in the image via
    `meta-wisekiosk/recipes-core/kiosk-soak/kiosk-soak_1.0.bb`.
- **Procedure:** deliver as "Delivery and board" sets out, reboot, then: `just gpu-check <host>` for
  the exit-coded guard; `just gpu-capture <host>` and read `webkit://gpu`'s Renderer row off the
  capture by eye, recording `Hardware`, `Shared Memory`, both, or absent; run the within-image
  compositing A/B below, which is where the marquee CPU numbers come from; run `kiosk-soak` for at
  least one hour and read `CmaFree` alongside it, because full KMS takes its framebuffer from the CMA
  pool on a 512 MB board.
- **The causal measurement (E1) — self-contained, with nothing to compare against:** sample marquee
  CPU with compositing on, then with `WEBKIT_DISABLE_COMPOSITING_MODE=1` in the same image on the
  same boot, and compare *those two*. This is the whole causal claim. Nothing here is read against
  the pre-work probe's numbers: that board's image cannot be named and its page has since changed,
  so a delta across the two would measure an unknown image and a changed page as well as the display
  stack. Within one image on one boot, compositing is the only thing that moves.
- **Raw capture:** pending — `run2-webkit-gpu.png`, `run2-cpu-compositing-on.txt`,
  `run2-cpu-compositing-off.txt`, `run2-soak.log`, `run2-gpu-check.txt`.

### Delivery and board

Run 2 is on prod, the wall-mounted Pi Zero W. `local/device-identity.md` is unchanged; the guard
still matches the delivery steps and still `exit 2`s, and each is approved by a human at the prompt,
the same as any gated operation here.

**The change does not fit one delivery route, so it takes two.** Not a reflash, and not all by
bundle:

- The **rootfs half** — mesa, `xf86-video-modesetting`, the GLX extension, the launcher without
  `GDK_GL=disable` — rides the RAUC bundle: `KIOSK_HOST=… just kiosk-ota` (the host is an environment
  default, not a recipe argument). The deployed RAUC boot script loads the kernel from the rootfs
  slot, so kernel, modules and mesa are all inside A/B rollback cover. **Do not reboot at this step.**
- The **boot half** — `dtoverlay=vc4-kms-v3d` into `/boot/config.txt` and
  ` video=HDMI-A-1:1920x1080@60D` into `/boot/cmdline.txt` — is hand-edited over SSH, because OTA
  cannot carry it: both files live on the shared FAT partition and `RAUC_BUNDLE_SLOTS = "rootfs"`
  means RAUC never writes them.

  This **accepts the no-A/B-protection risk on `/boot`**, knowingly. That partition is shared by both
  slots, so a bad write breaks both and needs the card pulled. It is bounded by: a backup taken first
  (a `tar` of the partition plus a raw `dd | gzip` of p1 and the pre-vc4 `config.txt`, into the
  gitignored `local/`), one small atomic write per file (temp → fsync → `mv` → fsync, no stray
  newline), verification by grepping for the two specific lines present and nothing duplicated, and
  the operator present during delivery.

**Recovery, in the order to try it.** Unreachable after the reboot: `kiosk-netcheck` rolls the slot
back automatically after three failed boots. Reachable but black: `just kiosk-rollback`, then restore
`config.txt` and `cmdline.txt` **file by file** from the backup — never untar the whole partition
over `/boot`, which clobbers `uboot.env` and takes out both slots. The irreducible risk is a power
cut or a card failure during the single FAT write, which costs a physical trip to the unit; nothing
in this procedure removes it.


## Configuration under test

The tree facts the runs rest on; each cited to its source.

- WebKit **is** built with accelerated compositing: `ENABLE_GRAPHICS_CONTEXT_GL=ON`, `USE_GBM=ON`,
  `USE_LIBDRM=ON`, `ENABLE_X11_TARGET=ON` — `build/tmp-raspberrypi0-wifi/.../webkitgtk3/2.44.3/build/CMakeCache.txt`.
  Removing `jit gtk4 enchant` and adding `reduce-size` in `kiosk-zero-w.yaml` has no effect on GL
  (`jit`/`gtk4` are not PACKAGECONFIG items; JIT is off via unconditional `EXTRA_OECMAKE:append:armv6`).
- Compositing was off behind three runtime blockers, traced in the extracted WebKit 2.44.3 source
  (`Source/WebKit/UIProcess/gtk/{AcceleratedBackingStoreDMABuf.cpp, AcceleratedBackingStore.cpp, HardwareAccelerationManager.cpp}`):
  1. The board's EGL is the Broadcom userland binary and advertises neither `EGL_KHR_platform_gbm`
     nor `EGL_MESA_platform_surfaceless` → no accelerated backing store at all.
  2. `GDK_GL=disable` in the launcher.
  3. No GLX module in the X server (fbdev path).
- The tree closes all three. `kiosk-zero-w.yaml` sets no `DISABLE_VC4GRAPHICS`, so
  `sources/meta-raspberrypi/conf/machine/include/rpi-base.inc:125` puts `vc4graphics` in
  `MACHINE_FEATURES`; that routes `virtual/egl` to mesa
  (`rpi-default-providers.inc:5`, `EGL_MESA_platform_surfaceless` unconditional in
  `mesa-24.0.7/src/egl/main/eglglobals.c`), swaps `xf86-video-fbdev` for `xf86-video-modesetting`
  and adds `xserver-xorg-extension-glx` (`rpi-base.inc:13-14`).
  `meta-wisekiosk/recipes-core/kiosk-session/files/kiosk-launch` exports no `GDK_GL`.
- Full KMS is a hard set, not a default taken: `VC4DTBO` is `?=` in
  `sources/meta-raspberrypi/recipes-bsp/bootfiles/rpi-config_git.bb:28`, and several of
  meta-raspberrypi's machine configs override it to `vc4-fkms-v3d`.
  `kiosk-zero-w.yaml`'s `graphics` block sets `VC4DTBO = "vc4-kms-v3d"`.
- The firmware HDMI keys in `meta-wisekiosk/recipes-bsp/bootfiles/rpi-config_%.bbappend` are inert
  under KMS. `kiosk-zero-w.yaml`'s `graphics` block carries
  `CMDLINE:append = " video=HDMI-A-1:1920x1080@60D"` in their place; the
  trailing `D` forces the connector enabled and digital, which is what `hdmi_force_hotplug` did
  (`Documentation/fb/modedb.rst:49-50` in the pinned kernel source).
- mesa is pinned to poky's 24.0.7 by `PREFERRED_VERSION_mesa` and `PREFERRED_VERSION_mesa-gl` in
  `kiosk-zero-w.yaml`'s `graphics` block. meta-raspberrypi ships
  `mesa_25.1.6.bb`, which `inherit`s the `rust` class where poky's `mesa.inc` does not, and ships no
  `mesa-gl` at that version. `just preferred-version` reports the pin as behind by design; the
  reason is at the pin. See [`../../layer-currency.md`](../../layer-currency.md).
- **The Renderer row is page-only, and that shaped the tooling.** WebKit computes the buffer mode in
  `AcceleratedBackingStoreDMABuf::rendererBufferMode()` from EGL extension queries
  (`Source/WebKit/UIProcess/gtk/AcceleratedBackingStoreDMABuf.cpp:62-87`), writes it to no
  `WEBKIT_DEBUG` channel and no log at all, and surfaces it in exactly one place: the **Renderer**
  row that `handleGPU` renders into the `webkit://gpu` page
  (`Source/WebKit/UIProcess/API/glib/WebKitProtocolHandler.cpp:163-179, 357`). It is therefore
  readable only as pixels, by a browser, by eye. There is no way to read it over SSH and no way to
  exit-code on it.

  This is why [`kiosk-gpu-check.sh`](../../../tools/kiosk-gpu-check.sh) has two modes rather than
  one. Its default mode is the durable regression guard and reads a **proxy** — whether a web process
  holds `/dev/dri` open with a `vc4`/`v3d` gallium driver mapped — which is decidable from `/proc`
  and is what fails if a future change re-disables the GPU. Its `--capture` mode drives the page and
  produces a PNG, and deliberately issues **no verdict**, because nothing in it ever read that row.
  A single-mode tool here would either have been unable to fail, or would have asserted a string it
  never saw.
- `WEBKIT_FORCE_COMPOSITING_MODE=1` could not have rescued the old stack — it is read only after the
  requirements check has already passed.
- **The deleted fbdev comment's claim, answered rather than dropped.** The removed `display:` comment
  recorded that `gldriver_test.sh` installs `99-fbturbo.conf` "because v3d is not `okay` on this
  board". That is a statement about the *device tree the Raspbian predecessor booted* — with no
  `vc4-kms-v3d` overlay loaded, the v3d node is indeed disabled and the script correctly falls back.
  It is not a claim about the silicon. This image loads the overlay (`VC4DTBO`), which is what
  enables the node. Recorded here so the question is not re-asked from the deleted comment's absence;
  Run 2's `drv=` output is what confirms it.
- **Two things about the guard that no board has yet shown**, both resolved by Run 2's raw output
  rather than by argument, and both recorded because the guard's current rule depends on them:
  1. **Which process holds the DRM fd.** The accelerated backing store is created in WebKit's *UI*
     process (`AcceleratedBackingStoreDMABuf` lives under `UIProcess/`) while the GL work happens in
     the web process, so either or both may hold it. `kiosk-gpu-check.sh` therefore accepts any
     member of the `surf`/`WebKit*` family. Naming `WebKitWebProcess` specifically would be stricter,
     and would also make the gate permanently red if it turns out `surf` is the holder.
  2. **Whether a "mixed" state can arise** — one process mapping a hardware driver while another maps
     only `swrast`. The guard passes on the hardware match. If Run 2 shows the combination occurs,
     the rule should tighten to fail-closed, since a regression guard's whole purpose is to fail on
     re-disable. Run 2 must record the full `drv=` and `drifd=` line for **every** process the walk
     finds, not just the verdict.
- Cost: the `MACHINE_FEATURES` change invalidates WebKit and costs a full rebuild (~4.5 h), per
  [`../../../README.md`](../../../README.md) §"Quick start".

## Metrics

Per run, filled as each runs. Never merged across runs.

*Run 2 (the vc4 image):* pending.

## Findings

- **Pre-work probe — prod's pre-vc4 state. NOT a run, and nothing is read against it.** Before this
  change, the board showed `webkit://gpu` with the **Renderer row absent entirely** — the state that
  means no DMABuf mode is available at all — and the marquee repainting in software on the single
  core. The image it was running **cannot be named**: it carries no `/etc/buildinfo`, runs kernel
  6.6.63 against the tree's pinned `PREFERRED_VERSION_linux-raspberrypi = "6.12.%"`, and points
  `KIOSK_URL` at the dev mirror rather than the baked `http://localhost:8080`. R1 is explicit that an
  unnameable image is not a run, so this is recorded here as a **qualitative probe**: it says the GPU
  path was off, which is what motivated the work. It contributes **no number** to any comparison, and
  the page it rendered has since changed. The causal claim is Run 2's within-image A/B alone.

- **Confirmed (pre-run, from source and probes):** WebKit is compositing-capable; the block was the
  Broadcom EGL, not a missing feature. Legacy dispmanx/Broadcom GLES is a dead end (WebKitGTK has no
  dispmanx target, and the EGL fails the extension gate regardless). vc4 + mesa is the only path.
- **Open — decided by Run 2:** whether vc4 + mesa lands WebKit in `Hardware` (dma-buf) or only
  `Shared Memory` compositing mode, and whether that removes the marquee's per-frame CPU cost.
- **Open — the precondition:** GPU compositing only helps a layer that is *promoted* and animated by
  CSS, not by per-frame JS (JIT is off on armv6). The marquee must be a CSS `@keyframes` +
  `will-change: transform` animation before the GPU can help it. That change ships through the dev
  mirror the board already loads, not through this image, so it can be applied and reverted without
  a rebuild — and Run 2 must record which state the page was in.

- **Confound, stated rather than resolved — `will-change` and vc4 ship together, and the result
  belongs to vc4.** Once compositing is on, the `infinite` transform animation self-promotes its
  layer within about 1.2 s, so the `will-change: transform` hint's marginal contribution is the
  startup hitch alone; the per-frame repaint saving is vc4's. The two arrive in the same delivery and
  are not separated by these runs. The causal evidence for #100 gpu-compositing is therefore the
  **within-image compositing A/B** recorded in Run 2 — marquee CPU with compositing on versus
  `WEBKIT_DISABLE_COMPOSITING_MODE=1` on the same boot — plus the owner's direct observation of the
  panel. **Nothing here credits the `will-change` line for the vc4 result.** Its independent benefit
  is not measured, and deliberately so: a hint-on-software-image run would be a null by construction,
  so no second run exists for it. An accepted, stated limitation.

- **Accepted verification gap — nothing in the tree obliges the substantive check.** The in-tree
  verification of #100 gpu-compositing proves **the CSS declaration resolved on the animating row
  and nowhere else — nothing more**. It asserts nothing about layer creation, about compositing, or
  about CPU. The CPU-reduction claim rests **entirely on Run 2**, which TST018's own rationale says
  is **obliged by nothing**: TST018 is `active:false` / proposed and concerns emulated boot, not
  this. Wherever this record describes the on-device evidence it carries that qualifier; nothing
  here says "verified on device" unqualified, because six months from now that would read as a
  stronger claim than the tree supports.

- **Open — the display risk:** full KMS ignores the firmware HDMI settings and changes geometry
  1824×984 → 1920×1080, which `video=` is there to pin.

- **Decided — take the overlay's CMA default for this build, and raise it only if the soak says so
  (owner, 2026-09-20).** The KMS framebuffer is allocated from CMA, and this tree sets no pool size:
  `CMDLINE_CMA` is referenced at `sources/meta-raspberrypi/recipes-bsp/bootfiles/rpi-cmdline.bb:57`
  and **assigned in no file** under `sources/meta-raspberrypi`, and the `graphics` block sets no
  `cma-` overlay parameter. What ships is therefore the `vc4-kms-v3d` overlay's own default. An
  earlier draft of this document named `cma-128`; it was removed, and this is the decision that
  replaces it.

  **Trigger:** add `cma-128` **only if the Run 2 soak shows CMA pressure**.
  [`kiosk-gpu-check.sh`](../../../tools/kiosk-gpu-check.sh) reads `CmaTotal`/`CmaFree`, and the run
  reads them again across the `kiosk-soak` hour.

  **Rationale:** `cma-128` takes 128 MB of a 512 MB machine away from everything else, most of it
  from WebKit's headroom — on a board whose whole problem is that it has none. The pool is not
  pre-spent on a shortage nobody has measured. The cost of the bet losing is known and accepted: too
  small for 1920×1080 surfaces as an allocation failure hours into the soak rather than a blank
  screen at boot, and correcting it means a 4.5 h rebuild plus a second hand-edit of prod's `/boot`.

- **OPEN, OWNER DECISION — how the prod guard should treat `gpu-capture`.** `just gpu-capture`
  rewrites `/data/config/kiosk.conf` and restarts the kiosk twice, which is a mutation of the
  wall-mounted board. `.claude/hooks/guard.sh` rule 1 did not know the recipe existed: neither its
  read-only prose list nor its blocking regex named it, its `systemctl` alternation carries no
  `restart`, and the restart is inside a heredoc in any case — so it would have run unprompted. Both
  spellings, the recipe and the direct `tools/kiosk-gpu-check.sh … --capture` path, sit in the
  blocking regex, with `gpu-check` (read-only) left in the allowed list, and
  `.claude/hooks/guard-test.sh` covers both directions. Whether the blocking form should stay or
  become a scoped exemption is the owner's call. The blocking form is the reversible default: it fails safe,
  and relaxing it later is one alternative in one regex.

- **Accepted risk — rollback is unexercised, on the board this runs against.** Delivery touches `/boot`,
  which has no A/B protection, on prod, with RAUC rollback never yet proven in anger (see
  [`../../../README.md`](../../../README.md) §"Known gaps"). It is a known condition of the run, not
  a blocker, and the recovery order is in "Delivery and board".

## Changes configured as a result

Pending Run 2. The branch carries the code change under test — vc4 + mesa with full KMS, the
`video=` mode, the mesa pin, and `kiosk-gpu-check.sh` as its regression guard — and this section
records the outcome once Run 2 decides whether it ships or is reverted with that rationale.
