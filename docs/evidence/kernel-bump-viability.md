# Kernel bump viability — raspberrypi0-wifi / linux-raspberrypi 6.6.63

Read-only investigation. Nothing was modified; no bitbake run; no device touched.
All patch-application testing was done on a **copy** in the scratchpad, not in the build tree.

**Bottom line up front:** patching beats bumping, and not only on cost.
`rpi-6.6.y` HEAD (6.6.78) contains **only one of the two fixes**. The `!sgl` guard
(52e8726d6782) was **never backported to 6.6.y at all**. So a version bump does not even
reach parity with the patch option, while dragging in 2623 commits.

---

## 1. How the kernel is pinned today — VERIFIED

`/home/tjwise/meta-wisekiosk/sources/meta-raspberrypi/recipes-kernel/linux/linux-raspberrypi_6.6.bb`

```
 1  LINUX_VERSION ?= "6.6.63"
 2  LINUX_RPI_BRANCH ?= "rpi-6.6.y"
 3  LINUX_RPI_KMETA_BRANCH ?= "yocto-6.6"
 5  SRCREV_machine = "e442e5c1ab6bff5b5460b4fc949beb72aaf77970"
 6  SRCREV_meta    = "52ff0d75713ce61962b325a2090bd55e216f0cf3"
10  SRC_URI = " \
11      git://github.com/raspberrypi/linux.git;name=machine;branch=${LINUX_RPI_BRANCH};protocol=https \
12      git://git.yoctoproject.org/yocto-kernel-cache;type=kmeta;name=meta;branch=${LINUX_RPI_KMETA_BRANCH};destsuffix=${KMETA};protocol=https \
13      file://powersave.cfg \
14      file://android-drivers.cfg \
```

- **LINUX_VERSION** = `6.6.63` (line 1)
- **SRC_URI branch** = `${LINUX_RPI_BRANCH}` = `rpi-6.6.y` (lines 2, 11)
- **SRCREV_machine** = `e442e5c1ab6bff5b5460b4fc949beb72aaf77970` (line 5)
- **SRCREV_meta** = `52ff0d75713ce61962b325a2090bd55e216f0cf3` (line 6)
- **KBRANCH** — **not set anywhere.** VERIFIED: it appears in neither
  `linux-raspberrypi_6.6.bb`, `linux-raspberrypi.inc`, nor any bbappend in this tree.
  meta-raspberrypi drives the branch through `LINUX_RPI_BRANCH` on the `SRC_URI`
  directly, and inherits `linux-yocto.inc` (`linux-raspberrypi.inc:12`) for the
  kernel-meta machinery. So the branch handle to change is `LINUX_RPI_BRANCH`, not `KBRANCH`.

`PV` is derived: `linux-raspberrypi.inc:9` → `PV = "${LINUX_VERSION}+git${SRCPV}"`.
Observable in the deploy dir as `uImage-1-6.6.63+git0+52ff0d7571_e442e5c1ab-r0-...`
(VERIFIED, `ls build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/`).

### bbappends that touch this recipe — VERIFIED (2 of them, both trivial)

`/home/tjwise/meta-wisekiosk/meta-autonomos-raspberrypi/recipes-kernel/linux/linux-raspberrypi_%.bbappend` (whole file, 3 lines):
```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://k3s-netfilter.cfg"
```

`/home/tjwise/meta-wisekiosk/sources/meta-rauc-community/meta-rauc-raspberrypi/recipes-kernel/linux/linux-raspberrypi_%.bbappend` (whole file):
```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
inherit rauc-integration
SRC_URI:append:rauc-integration = " file://rauc.cfg"
CMDLINE:remove:rauc-integration = "root=/dev/mmcblk0p2"
```

Neither sets `LINUX_VERSION` or `SRCREV`. **The project's own bbappend already uses
`SRC_URI +=` with a `FILESEXTRAPATHS:prepend`** — i.e. the exact mechanism option 4 needs
is already wired up and proven working in this tree. Adding two `file://*.patch` entries is
a two-line edit to a file that already exists.

No `PREFERRED_VERSION_linux-raspberrypi` anywhere in the project layers, includes, kas
config or `build/conf/local.conf` (VERIFIED by grep). Version selection is by
default-highest-PV among the recipes present. **Note this: the vendored meta-raspberrypi
scarthgap branch ALSO ships `linux-raspberrypi_6.12.bb` at 6.12.93** — see §3.

---

## 2. What the pin corresponds to upstream — VERIFIED (GitHub API + git ls-remote)

| | SHA | date | Makefile SUBLEVEL |
|---|---|---|---|
| pinned SRCREV_machine | `e442e5c1ab6bff5b5460b4fc949beb72aaf77970` | 2024-12-06 | **63** |
| backport 07c020c6d14d | `07c020c6d14d29e5a3ea4e4576b8ecf956a80834` | 2024-12-14 | **65** → released in **6.6.66** |
| `rpi-6.6.y` HEAD | `bba53a117a4a5c29da892962332ff1605990e17a` | **2025-03-26** | **78** |

Commands (output verbatim above):
- `git ls-remote https://github.com/raspberrypi/linux.git refs/heads/rpi-6.6.y` → `bba53a117a4a5c29da892962332ff1605990e17a`
- `gh api repos/raspberrypi/linux/commits/<sha> --jq '{sha,date,msg}'`
- `gh api "repos/raspberrypi/linux/contents/Makefile?ref=<sha>" --jq .content | base64 -d | head -4`

**LINUX_VERSION reachable on rpi-6.6.y: 6.6.78.** That is the ceiling — the branch's
last commit is 2025-03-26; the Pi kernel maintainers moved to `rpi-6.12.y` (which is at
6.12.93 as of the vendored recipe). `rpi-6.6.y` is a dead branch, not a maintained LTS.

Total delta 6.6.63 pin → 6.6.78 HEAD: **2623 commits, 300 files changed** (VERIFIED,
`gh api repos/raspberrypi/linux/compare/e442e5c1...bba53a11 --jq '{total_commits,files_changed:(.files|length)}'`
→ `{"ahead":2623,"behind":0,"files_changed":300,"total_commits":2623}`).

### ⚠ THE FINDING THAT DECIDES THIS — VERIFIED

I fetched `bcmsdh.c` at `rpi-6.6.y` HEAD (6.6.78) with
`curl https://raw.githubusercontent.com/raspberrypi/linux/bba53a11.../drivers/net/wireless/broadcom/brcm80211/brcmfmac/bcmsdh.c`:

```
--- nents line ---
773:	nents *= 2;
--- !sgl check present? ---
(no match for "out of (pre-allocated) scatterlist" — grep exit 1)
```

So at **6.6.78**:
- ✅ `857282b819cb` / `07c020c6d14d` (`nents *= 2`, 35→64) **is present**
- ❌ `52e8726d6782` (the `if (!sgl)` bounds check) **is absent**

Confirmed independently from the branch history: the only commit touching `bcmsdh.c` on
`rpi-6.6.y` since 2023 is `07c020c6d14d` (VERIFIED,
`gh api "repos/raspberrypi/linux/commits?sha=rpi-6.6.y&path=.../bcmsdh.c"`).

**A version bump gets one fix. Patching gets both.** The `!sgl` guard is the belt to the
`nents *= 2` braces — it turns "run off the end of the sg table" from an oops into
`-ENOMEM` and a failed SDIO transfer. Given `STATUS.md`'s captured oops is
`brcmf_sdio_dataworker` executing a corrupted address with a live `sk_buff` in registers,
that second patch is exactly the one that converts the remaining residual risk from
"panic" to "dropped frame".

---

## 3. Is a newer meta-raspberrypi branch an option? — VERIFIED, and mostly NO

`LAYERSERIES_COMPAT` per branch (`gh api "repos/agherzan/meta-raspberrypi/contents/conf/layer.conf?ref=<br>"`):

| branch | LAYERSERIES_COMPAT | linux-raspberrypi_6.6 | linux-raspberrypi_6.12 |
|---|---|---|---|
| **scarthgap** (vendored, in use) | `nanbield scarthgap` — local file `sources/meta-raspberrypi/conf/layer.conf:12` | 6.6.63 | **6.12.93** |
| styhead | `styhead walnascar` | 6.6.63 | 6.12.25 |
| walnascar | `styhead walnascar` | 6.6.63 | 6.12.25 |
| master | `wrynose` | **6.6.78** | 6.12.87 |

**No newer branch declares `scarthgap`.** Switching the layer branch to styhead,
walnascar or master forces a full poky/distro upgrade — off the table for a change whose
whole purpose is a 7-line wifi driver fix.

But that comparison is a red herring in two ways:

1. **You do not need the branch to get the version.** The bump is three variable values.
   `master`'s `linux-raspberrypi_6.6.bb` is `LINUX_VERSION=6.6.78`,
   `SRCREV_machine=bba53a117a4a5c29da892962332ff1605990e17a`,
   `SRCREV_meta=2a0755715e994658c580454e1292e11e11c1cc35`. Those three lines can be set
   from the existing `linux-raspberrypi_%.bbappend` on the current scarthgap layer with no
   branch switch and no compat problem. So "would it force a distro upgrade?" — **no, not
   if you bump in the bbappend**, which is the only sane way to do it anyway.
   Both SRCREVs are **already in the local download mirror** (VERIFIED:
   `git --git-dir=build/downloads/git2/github.com.raspberrypi.linux.git cat-file -t bba53a11...` → `commit`;
   same for `2a0755715e...` in the yocto-kernel-cache mirror). Network cost of a bump ≈ zero.

2. **It still does not get you the second fix** (§2). 6.6.78 lacks the `!sgl` guard, so
   even the in-place bump would need `52e8726d6782` added as a patch on top. At which
   point you are doing the patch work anyway, plus 2623 commits of unrelated churn.

**The vendored scarthgap branch already carries `linux-raspberrypi_6.12.bb` at 6.12.93**
(local file `sources/meta-raspberrypi/recipes-kernel/linux/linux-raspberrypi_6.12.bb:1`,
HEAD commit `6ca1f75 linux-raspberrypi_6.12: bump SRCREV to rpi-6.12.y HEAD (6.12.93)`,
author Enzo Frese, 2026-06-13 — this is an upstream commit on `origin/scarthgap`, not a
local hack; `git branch -a --contains HEAD` lists `remotes/origin/scarthgap`). A 6.12
kernel is therefore *reachable* on the current layer branch. **It is also a 6.6→6.12
jump on an ARMv6 board with 512MB and a hand-tuned boot profile**, and it changes
`yocto-6.6` → `yocto-6.12` kernel-cache, defconfig fragments, module set, and every
overlay. It is not in the same risk class as the other two options and should not be
grouped with them.

---

## 4. ⭐ CHEAPEST ALTERNATIVE: patch 6.6.63 in place — VERIFIED, BOTH PATCHES APPLY CLEAN

Target file, unmodified, in the existing work-shared kernel source:
```
/home/tjwise/meta-wisekiosk/build/tmp-raspberrypi0-wifi/work-shared/raspberrypi0-wifi/kernel-source/drivers/net/wireless/broadcom/brcm80211/brcmfmac/bcmsdh.c
md5  7d8d2ec12d7bb17252a2be52cbde68af
size 32663 bytes, 1258 lines
```

### 4a. `857282b819cb` — nents 35 → 64

Patch hunk header `@@ -770,7 +770,7 @@ void brcmf_sdiod_sgtable_alloc(...)`:
```
 	nents = max_t(uint, BRCMF_DEFAULT_RXGLOM_SIZE,
 		      sdiodev->settings->bus.sdio.txglomsz);
-	nents += (nents >> 4) + 1;
+	nents *= 2;
 
 	WARN_ON(nents > sdiodev->max_segment_count);
```

Local file, lines 750–778 (Read tool, line numbers as shown):
```
750	void brcmf_sdiod_sgtable_alloc(struct brcmf_sdio_dev *sdiodev)
...
771		nents = max_t(uint, BRCMF_DEFAULT_RXGLOM_SIZE,
772			      sdiodev->settings->bus.sdio.txglomsz);
773		nents += (nents >> 4) + 1;
774	
775		WARN_ON(nents > sdiodev->max_segment_count);
776	
777		brcmf_dbg(TRACE, "nents=%d\n", nents);
778		err = sg_alloc_table(&sdiodev->sgtable, nents, GFP_KERNEL);
```

Context matches **byte for byte**, at effectively the patch's own line numbers.
`patch -p1 --dry-run --verbose` output:
```
checking file drivers/net/wireless/broadcom/brcm80211/brcmfmac/bcmsdh.c
Hunk #1 succeeded at 770.
done
```
**Zero fuzz, zero offset.** APPLIES CLEANLY.

### 4b. `52e8726d6782` — detect end of sg list

Patch hunk header `@@ -455,6 +455,11 @@ static int brcmf_sdiod_sglist_rw(...)`:
```
 			if (sg_data_sz > max_req_sz - req_sz)
 				sg_data_sz = max_req_sz - req_sz;
 
+			if (!sgl) {
+				/* out of (pre-allocated) scatterlist entries */
+				ret = -ENOMEM;
+				goto exit;
+			}
 			sg_set_buf(sgl, pkt_data, sg_data_sz);
 			sg_cnt++;
 
```

Local file, lines 447–463:
```
447		sgl = sdiodev->sgtable.sgl;
448		skb_queue_walk(target_list, pkt_next) {
449			pkt_offset = 0;
450			while (pkt_offset < pkt_next->len) {
451				pkt_data = pkt_next->data + pkt_offset;
452				sg_data_sz = pkt_next->len - pkt_offset;
453				if (sg_data_sz > sdiodev->max_segment_size)
454					sg_data_sz = sdiodev->max_segment_size;
455				if (sg_data_sz > max_req_sz - req_sz)
456					sg_data_sz = max_req_sz - req_sz;
457	
458				sg_set_buf(sgl, pkt_data, sg_data_sz);
459				sg_cnt++;
460	
461				sgl = sg_next(sgl);
```

Context matches **byte for byte at exactly the patch's own line numbers** (455/456
pre-context, 457 blank, 458/459 post-context). `patch -p1 --dry-run --verbose`:
```
checking file drivers/net/wireless/broadcom/brcm80211/brcmfmac/bcmsdh.c
Hunk #1 succeeded at 455.
done
```
**Zero fuzz, zero offset.** APPLIES CLEANLY.

The `goto exit` target exists at line 511 and does the right thing — it re-inits the
sg table (`sg_init_table`, line 512) and drains `local_list`. VERIFIED by reading the
function; the patch needs no additional label.

### 4c. Sequential application — VERIFIED by actually doing it (in scratchpad copy)

```
patch -p1 < 857282b819cb.patch   → rc=0
patch -p1 < 52e8726d6782.patch   → rc=0
result: line 778  nents *= 2;
result: lines 458-463  if (!sgl) { /* out of (pre-allocated)... */ ret = -ENOMEM; goto exit; }
no .rej files, no .orig files
```

They are independent hunks ~300 lines apart, so order does not matter. Both applied to
the real 6.6.63 source content with no manual intervention.

### 4d. What the bbappend edit looks like

The mechanism is already present. `meta-autonomos-raspberrypi/recipes-kernel/linux/linux-raspberrypi_%.bbappend`
already has `FILESEXTRAPATHS:prepend := "${THISDIR}/files:"` and a `SRC_URI +=`. Drop the
two `.patch` files into `meta-autonomos-raspberrypi/recipes-kernel/linux/files/` and append
them to `SRC_URI`. Note the `_%.` wildcard means it applies to whichever
`linux-raspberrypi` version is selected — if the 6.12 recipe ever wins version selection,
these patches would be attempted against 6.12 and fail the build loudly (not silently).
That is arguably a feature, but a `_6.6.bbappend` would be tighter. INFERRED (reasoning
from bbappend wildcard semantics, not tested).

Use the **torvalds** `.patch` files as fetched, not the stable-backport `07c020c6d14d`
variant — the latter carries an `[ Upstream commit ... ]` line but is otherwise identical
in the diff; either works. VERIFIED both fetched successfully (2092 / 1380 / 2201 bytes).

---

## 5. Risk of a version bump that the A/B fallback does NOT cover

The fallback covers exactly one thing: **the kernel image**, because it is in the rootfs slot.

VERIFIED — `sources/meta-rauc-community/meta-rauc-raspberrypi/recipes-bsp/rpi-u-boot-scr/files/boot.cmd.in`,
last three lines:
```
load ${BOOT_DEV} ${kernel_addr_r} boot/@@KERNEL_IMAGETYPE@@
if test ! -e mmc 0:1 uboot.env; then saveenv; fi;
@@KERNEL_BOOTCMD@@ ${kernel_addr_r} - ${fdt_addr}
```
with `BOOT_DEV` set to `mmc 0:2` / `mmc 0:3` in the slot loop above. `KERNEL_BOOTCMD` for
this machine is `bootm` (`sources/meta-raspberrypi/conf/machine/include/rpi-base.inc:119`,
`KERNEL_BOOTCMD ??= "bootm"`), and `KERNEL_IMAGETYPE` is `uImage` because
`RPI_USE_U_BOOT = "1"` (`includes/platforms/raspberrypi.yaml:31`,
`build/conf/local.conf:105`) selects `KERNEL_IMAGETYPE_UBOOT` at `rpi-base.inc:120-123`.

Now the gaps.

### 5.1 ⛔ Device tree and overlays are NOT in the bundle — the biggest gap

`@@KERNEL_BOOTCMD@@ ${kernel_addr_r} - ${fdt_addr}` boots the kernel against
**`${fdt_addr}`** — the DTB the VideoCore firmware loaded from the **FAT partition
(mmc 0:1)** before U-Boot ever ran. That partition is shared, not A/B.

`RAUC_BUNDLE_SLOTS = "rootfs"` — `meta-autonomos-core/recipes-core/bundles/update-bundle.bb:19`.
**One slot. The boot partition is not in the bundle.** VERIFIED.

Consequence: an OTA-delivered 6.6.78 kernel runs against **6.6.63-era DTBs and overlays**,
and if the newer kernel needs a newer DT (new required properties, a renamed compatible, a
changed overlay parameter), fallback restores the old kernel but there is no mechanism that
would have updated the DT in the first place. Device tree is largely backward compatible in
practice, so this is not likely to fire — but it is the failure mode that is *invisible*
until it fires, and the fallback does not protect against it, it just hides it.

Note the image *does* install `kernel-devicetree` into the rootfs
(`includes/platforms/raspberrypi.yaml:37`: `IMAGE_INSTALL:append = " kernel-image kernel-devicetree ..."`).
Those rootfs DTBs are **inert** — nothing loads them; the FAT copies are authoritative.
That is a live trap: a bump will look like it shipped new DTBs, and it did, to a directory
nobody reads.

### 5.2 ⛔ The `ramoops` overlay lives in the FAT partition

`STATUS.md:32-35`: *"ramoops is live and now permanent: `/boot/overlays/ramoops.dtbo` plus
one additive `dtoverlay=` line in `config.txt`."* Both of those are on the **shared FAT
partition**, hand-installed, outside the build and outside the bundle. A kernel bump does
not touch them — good, they survive — but it also means the overlay is a `.dtbo` built
against the 6.6.63 overlay set being consumed by a 6.6.78 kernel. `ramoops-overlay.dts` is
a plain `reserved-memory` node (per `kiosk-reference/docs/evidence/ramoops-feasibility-research.md:124,139-151`),
which is about as stable a binding as DT has, so the concrete risk is low. **But if it
silently stops binding, the instrument that just found the root cause goes dark, and
nothing reports that** — pstore failing to register is not a boot failure, so RAUC marks
the slot good and the fallback never triggers.

### 5.3 KERNEL_IMAGETYPE=uImage / LOADADDR

`LOADADDR=${UBOOT_ENTRYPOINT}` = `0x00008000` (`linux-raspberrypi.inc:45-48`). Current
uImage is **7,389,208 bytes** (VERIFIED, `ls` on the deploy dir). Within 6.6.y a bump will
not move `UBOOT_ENTRYPOINT`, but the image grows, and `kernel_addr_r` vs `fdt_addr`
spacing is set by U-Boot's board defaults. A uImage that grows into the FDT region gives a
corrupt-DT boot. This one **is** covered by fallback (the slot fails to boot, counters
decrement, U-Boot picks the other slot) — so it costs a reboot cycle, not a trip.

### 5.4 Module packaging — covered, but note the scale

`kernel-image` and the modules are installed into the **rootfs slot**
(`includes/platforms/raspberrypi.yaml:37`), so kernel and modules always move together and
a `vermagic` mismatch across an A/B update is structurally impossible. Good.

Scale, though: the current image manifest holds **1747 `kernel-module-*` packages**, every
one named `kernel-module-<x>-6.6.63` (VERIFIED,
`deploy/licenses/raspberrypi0_wifi/core-image-base-*/package.manifest`). A `LINUX_VERSION`
bump renames all 1747. Nothing in this project pins a versioned module name (VERIFIED by
grep over `meta-autonomos-*`, `includes`, `*.yaml`, `build/conf/local.conf` — the only hit
is `packagegroup-autonomos-kubernetes.bb:11` naming the unversioned `kernel-modules`), so
`do_rootfs` should re-resolve fine. INFERRED that it resolves; not tested.

### 5.5 RAUC bundle

`RAUC_BUNDLE_FORMAT = "verity"`, `RAUC_BUNDLE_SLOTS = "rootfs"`, compatible string
`autonomos-${MACHINE}` (`update-bundle.bb:14-20`). None of these are kernel-version
derived, so the bundle rebuilds and installs identically. No risk here beyond §5.1.

### 5.6 WiFi firmware API vs brcmfmac

The firmware is a **separate recipe**: `linux-firmware-rpidistro-bcm43430`, pulled by
`sources/meta-raspberrypi/conf/machine/raspberrypi0-wifi.conf:10`, present in the manifest
as unversioned `linux-firmware-rpidistro-bcm43430`. A kernel bump does not change it.
brcmfmac's firmware-API expectations did not change within 6.6.y — the only brcmfmac
commits in the 6.6.63→6.6.78 range are five bugfixes (`3877fc67bd3d` txfinalize NULL deref,
`c9480e9f2d10` of_property_read_string_index return check, `009bacab99e1` WPA3 SAE struct
size, `19958067c4be` missing header, `07c020c6d14d` the nents fix) — VERIFIED via
`gh api "repos/raspberrypi/linux/commits?sha=rpi-6.6.y&path=.../brcmfmac&since=2024-12-06"`.
So firmware/driver API mismatch is a **non-risk for a 6.6.x bump**. It would be a real
risk for 6.12, which is not evaluated here.

Worth noting: `009bacab99e1 brcmfmac: Fix structure size for WPA3 external SAE` is a
*structure size* fix in the driver's firmware interface. Benign in isolation, but it is
the class of change that a bump brings along and a targeted patch does not.

---

## 6. Cost

### 6a. Patch-only change

Adding `file://*.patch` to `SRC_URI` changes the `SRC_URI` variable, which is in the
vardeps of `do_fetch` / `do_unpack` / `do_patch`. That re-hashes the whole
`linux-raspberrypi` task chain from `do_patch` onward. Measured task times for this exact
recipe on this host (`build/tmp-raspberrypi0-wifi/buildstats/20260810212128/linux-raspberrypi-1_6.6.63+git-r0/*`,
`Elapsed time` lines — VERIFIED):

| task | seconds |
|---|---|
| do_compile | 2100 (35 min) |
| do_compile_kernelmodules | 2834 (47 min) |
| do_package | 256 |
| do_package_write_ipk | 380 |
| do_package_qa | 92 |
| do_kernel_configme + configcheck + metadata | ~101 |
| do_deploy | 30 |
| **do_fetch (first ever, full clone)** | **3182 (53 min)** |

Then downstream: `do_rootfs` ~240–350 s, `do_image_ext4` ~35 s, `do_image_wic` ~75–145 s,
`update-bundle do_bundle` ~19 s (VERIFIED from the same buildstats tree).

**`do_fetch` will not repeat the 53 minutes.** The git mirror
`build/downloads/git2/github.com.raspberrypi.linux.git` is 5.7 GB and holds the pinned
rev; the fetcher's `need_update()` returns false for a SRCREV already present, so the
task re-runs but does no network work. INFERRED (mechanism), but the mirror's contents are
VERIFIED (`cat-file -t e442e5c1...` → `commit`).

**Realistic wall clock: ~1.5–2 hours**, dominated by kernel + modules compile, plus
rootfs/wic/bundle.

### 6b. LINUX_VERSION bump

Everything in 6a, **plus**:
- `PV` changes → the recipe's whole `WORKDIR`/`work-shared` path changes → nothing in the
  existing tmpdir is reusable for this recipe (no partial reuse of the incremental kernel
  build tree).
- 1747 package names change → `do_package_write_ipk` writes 1747 new ipks and the old ones
  linger in the feed.
- `do_kernel_version_sanity_check` will hard-fail if `LINUX_VERSION` and `SRCREV_machine`
  disagree. That is a **safety**, not a risk: a mismatched pair errors at build time, not
  on the device.
- Network: **near zero**, both new SRCREVs are already in the mirrors (VERIFIED, §3).

**Realistic wall clock: ~2 hours.** The bump is not dramatically more expensive to
*build* than the patch. Its cost is in review and risk (2623 commits, 300 files), not CPU.

### 6c. Does webkitgtk3 rebuild? — NO, in either case. VERIFIED chain.

`webkitgtk3` is `sources/meta-openembedded/meta-oe/recipes-support/webkitgtk/webkitgtk3_2.44.3.bb`.
Its `DEPENDS` (lines 30-49) is: `ruby-native gperf-native unifdef-native cairo harfbuzz
jpeg atk libwebp gtk+3 libxslt libtasn1 libnotify gstreamer1.0 gstreamer1.0-plugins-base
glib-2.0-native gettext-native`. **No `virtual/kernel`, no `linux-raspberrypi`.**

Yocto task hashing: a task's signature is its own variable/file dependencies plus the
signatures of the tasks it depends on, transitively. `linux-raspberrypi` enters no
recipe's `DEPENDS` here except the image's runtime install, and image tasks are *downstream*
of webkit, not upstream. The kernel's `do_populate_sysroot` feeds only recipes that
`DEPENDS` on `virtual/kernel` — and there are **none** in this project's layers (VERIFIED:
grep for `virtual/kernel` / `inherit module` across `meta-autonomos-core` and
`meta-autonomos-raspberrypi` returns nothing; there are no out-of-tree kernel modules).

The one thing that *could* have linked them is kernel headers, and it does not:

- `glibc.inc:4` → `DEPENDS = "... linux-libc-headers ..."` — the **recipe name**, not a
  virtual, and not `virtual/kernel`.
- `gcc-cross.inc:9` → `EXTRADEPENDS = "linux-libc-headers"`.
- `sources/poky/meta/conf/distro/include/default-providers.inc:41` →
  `PREFERRED_PROVIDER_linux-libc-headers ?= "linux-libc-headers"`.
- `sources/poky/meta/conf/distro/include/tcmode-default.inc:24,52` →
  `LINUXLIBCVERSION ?= "6.6%"`, `PREFERRED_VERSION_linux-libc-headers ?= "${LINUXLIBCVERSION}"`.
- That resolves to `sources/poky/meta/recipes-kernel/linux-libc-headers/linux-libc-headers_6.6.bb`,
  whose `SRC_URI` (via `linux-libc-headers.inc:60`) is
  `${KERNELORG_MIRROR}/linux/kernel/v${HEADER_FETCH_VER}/linux-${PV}.tar.${KORG_ARCHIVE_COMPRESSION}`
  — a **kernel.org tarball at PV 6.6**, with a fixed `SRC_URI[sha256sum]`.

**`linux-libc-headers` is a completely separate recipe from `linux-raspberrypi`.** It has
its own PV (6.6), its own source (kernel.org, not the Pi tree), and no reference to
`LINUX_VERSION` or `SRCREV_machine`. Changing either of those in `linux-raspberrypi`
cannot alter `linux-libc-headers`'s task hash, therefore cannot alter glibc's, therefore
cannot alter gcc-cross's, therefore cannot alter webkitgtk3's.

**Confirmed empirically too**: build `20260813212054` shows `linux-raspberrypi` running
`do_*_setscene` tasks (sstate hits) alongside webkit work, and build `20260812040827`
shows `linux-raspberrypi do_package` running for 1689 s while webkit was pulled entirely
from setscene. The two are independent in this tree's own history.

For scale, webkit's real cost here: `do_compile` **8963.85 s (2h29m)** in run
`20260811004025`, plus a 1972 s partial in `20260810193239` (VERIFIED from buildstats).
Not rebuilding it is worth more than everything else in this decision combined.

⚠ **One caveat on 6.12**: everything above holds for a change *within* `linux-raspberrypi`.
It does **not** hold if `LINUXLIBCVERSION` / `PREFERRED_VERSION_linux-libc-headers` is
moved off `6.6%`. Do not touch those. If a 6.12 kernel were ever adopted and someone
"matched" the headers to it, **that would re-hash glibc → gcc-cross → everything, including
webkitgtk3**. That is the one edit in this area that costs the 6-hour build.

---

## Recommendation

**Patch 6.6.63.** It is not merely cheaper — it is the only option that delivers **both**
fixes, because `52e8726d6782` was never backported to 6.6.y. Both patches apply with zero
fuzz and zero offset to the exact source in this build tree, verified by actually running
`patch` against a copy. The mechanism (`SRC_URI +=` in an existing bbappend with
`FILESEXTRAPATHS:prepend`) is already in place and already working. Cost is a kernel
rebuild plus image and bundle, ~1.5–2 h, **no webkitgtk3 rebuild**.

A bump to 6.6.78 costs about the same CPU, brings 2623 commits across 300 files onto a
board whose boot path is hand-tuned, opens the DT-not-in-the-bundle gap in §5.1, and still
leaves you writing one of the two patches by hand.

If the patch is applied, the revert is deleting two `SRC_URI` lines and rebuilding — and
on the device it is `just kiosk-rollback` plus a reboot, unchanged.

### Things I could not determine
- Whether `do_fetch` performs any network round-trip when only `file://` entries are added
  to `SRC_URI` (mechanism reasoned, not measured — I did not run bitbake).
- Whether `do_rootfs` cleanly resolves the 1747 renamed module packages after a
  `LINUX_VERSION` bump (reasoned from the absence of versioned pins; not tested).
- Whether the hand-installed `/boot/overlays/ramoops.dtbo` on the FAT partition would still
  bind under a 6.6.78 kernel (binding is stable in principle; not tested, and I did not
  touch the device).
