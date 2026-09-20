# Can the kiosk browser composite its animation on the GPU instead of repainting it in software?

| | |
|---|---|
| **Issue** | #100 gpu-compositing |
| **Status** | open |
| **Opened / concluded** | 2026-09-19 / — |

The park-wait-times marquee stutters on the Pi Zero W because WebKit renders in software: the image
disables the GPU (`DISABLE_VC4GRAPHICS = "1"`, `GDK_GL=disable`, fbdev), so a continuous `transform`
animation is repainted on the single armv6 core every frame. WebKit here is built with accelerated
compositing support; it is off at runtime behind three blockers, all closed by switching from the
Broadcom userland EGL to vc4 + mesa. This investigation tests whether that switch — plus promoting
the animation to a composited layer, which the GPU can only help once it exists — makes the animation
smooth without saturating the core. Concludes when Run 2 measures the built-and-flashed vc4 image.

## Test runs

| Run | Board (role) | Image commit | Harness / scripts | Result (1 line) |
|---|---|---|---|---|
| 1 | prod · Pi Zero W | *unidentified older image (see below)* | `webkit://gpu` read, `/proc/<pid>/stat` sampling | pending |
| 2 | prod · Pi Zero W | *this build, `/etc/buildinfo`* | `webkit://gpu` read, `kiosk-soak` | pending |

### Run 1 — prod, baseline on the currently-flashed image

- **Board:** prod, Raspberry Pi Zero W (armv6, VideoCore IV, 512 MB).
- **Image commit:** *not verifiable.* The board runs kernel 6.6.63 against the tree's pinned
  `PREFERRED_VERSION_linux-raspberrypi = "6.12.%"`, carries no `/etc/buildinfo`, and its
  `KIOSK_URL` points at the dev mirror rather than the baked `http://localhost:8080` — so this is an
  older image than `just build` now produces. Per R1 this run is therefore a **baseline only**, not a
  clean measurement of the tree; it establishes the compositing state (empty) and the software-render
  CPU cost against which Run 2 is read. Recorded, not blended into Run 2's table.
- **Scripts deployed:** none durable. `webkit://gpu` is a built-in WebKit page; sampling is
  `/proc/<pid>/stat` read over SSH — no script placed on the board.
- **Procedure:** set `KIOSK_URL=webkit://gpu` in `/data/config/kiosk.conf`, `systemctl restart kiosk`,
  capture with `tools/kiosk-screenshot.sh`, revert the URL, restart. Separately, sample
  `utime+stime` from `/proc/<surf-pid>/stat` and `/proc/<webkit-pid>/stat` twice 5 s apart on the
  served page.
- **Raw capture:** pending — `run1-webkit-gpu.png`, `run1-cpu.txt`.

### Run 2 — prod, the built-and-flashed vc4 image

- **Board:** prod, Raspberry Pi Zero W.
- **Image commit:** the commit `just build` stamps into `/etc/buildinfo` for this build; confirmed by
  `grep ^meta-wisekiosk /etc/buildinfo` on the board after flashing.
- **Procedure:** flash the vc4 image, provision, boot; read `webkit://gpu` (expect `Hardware` or
  `Shared Memory`); measure marquee CPU the same way as Run 1; watch memory with `kiosk-soak` for OOM
  under full KMS + mesa on a 512 MB board.
- **Raw capture:** pending — `run2-webkit-gpu.png`, `run2-cpu.txt`, `run2-soak.log`.

## Configuration under test

The tree facts the runs rest on; each cited to its source.

- WebKit **is** built with accelerated compositing: `ENABLE_GRAPHICS_CONTEXT_GL=ON`, `USE_GBM=ON`,
  `USE_LIBDRM=ON`, `ENABLE_X11_TARGET=ON` — `build/tmp-raspberrypi0-wifi/.../webkitgtk3/2.44.3/build/CMakeCache.txt`.
  Removing `jit gtk4 enchant` (`kiosk-zero-w.yaml:86`) and adding `reduce-size` (`:113`) has no effect
  on GL (`jit`/`gtk4` are not PACKAGECONFIG items; JIT is off via unconditional `EXTRA_OECMAKE:append:armv6`).
- Compositing is off behind three runtime blockers, traced in the extracted WebKit 2.44.3 source
  (`Source/WebKit/UIProcess/gtk/{AcceleratedBackingStoreDMABuf.cpp, AcceleratedBackingStore.cpp, HardwareAccelerationManager.cpp}`):
  1. The board's EGL is the Broadcom userland binary and advertises neither `EGL_KHR_platform_gbm`
     nor `EGL_MESA_platform_surfaceless` → no accelerated backing store at all.
  2. `GDK_GL=disable` — `meta-wisekiosk/recipes-core/kiosk-session/files/kiosk-launch:8`.
  3. No GLX module in the X server (fbdev path).
- The vc4 switch closes all three: deleting `DISABLE_VC4GRAPHICS = "1"` (`kiosk-zero-w.yaml:60`) adds
  `vc4graphics` to `MACHINE_FEATURES` (`sources/meta-raspberrypi/conf/machine/include/rpi-base.inc:125`),
  which routes `virtual/egl` to mesa (`EGL_MESA_platform_surfaceless` unconditional in
  `mesa-24.0.7/src/egl/main/eglglobals.c`) and pulls `xserver-xorg-extension-glx`. Full KMS is
  meta-raspberrypi's default `VC4DTBO = "vc4-kms-v3d"`.
- `WEBKIT_FORCE_COMPOSITING_MODE=1` cannot rescue the current stack — it is read only after the
  requirements check has already passed.
- Cost and reach: a `MACHINE_FEATURES` change invalidates WebKit and costs a full rebuild (~4.5 h),
  per [`README.md`](../../../README.md). `config.txt`/`cmdline.txt` live on the shared FAT partition
  and cannot arrive by OTA, so the vc4 overlay needs a reflash.

The full feasibility analysis, with every probe and source line, is the working brief this section
summarises (kept out of tree as a scratch artefact; its findings are transcribed here).

## Metrics

Per run, filled as each runs. Never merged across runs.

*Run 1 (baseline):* pending.
*Run 2 (vc4 image):* pending.

## Findings

- **Confirmed (pre-run, from source and probes):** WebKit is compositing-capable; the block is the
  Broadcom EGL, not a missing feature. Legacy dispmanx/Broadcom GLES is a dead end (WebKitGTK has no
  dispmanx target, and the EGL fails the extension gate regardless). vc4 + mesa is the only path.
- **Open — decided by Run 2:** whether vc4 + mesa lands WebKit in `Hardware` (dma-buf) or only
  `Shared Memory` compositing mode, and whether that removes the marquee's per-frame CPU cost.
- **Open — the precondition:** GPU compositing only helps a layer that is *promoted* and animated by
  CSS, not by per-frame JS (JIT is off on armv6). The marquee must be a CSS `@keyframes` +
  `will-change: transform` animation before the GPU can help it. Shipped as a WiseKiosk `SRCREV` bump
  baked into this build.
- **Open — the display risk:** full KMS discards the firmware HDMI settings
  (`meta-wisekiosk/recipes-bsp/bootfiles/rpi-config_%.bbappend`) and changes geometry 1824×984→1920×1080;
  and full KMS on a 512 MB board wants cma-128, an OOM risk to watch.

## Changes configured as a result

Pending Run 2. Expected outcome: a code change enabling vc4 + mesa (dropping `DISABLE_VC4GRAPHICS`
and `GDK_GL=disable`) with the marquee promoted to a composited CSS layer — or, if Run 2 shows the
payoff does not justify the display risk, no change with that rationale recorded here.
