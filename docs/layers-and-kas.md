# Layers and kas

This explains how the repository is put together, for someone who has not worked with Yocto before.
It assumes you know what a compiler and a package are, and nothing else.

## The short version

BitBake builds the image. It does not know where anything is; it reads a list of directories called
*layers*, each holding build instructions. kas is a small program that assembles that list: it clones
the repositories the layers come from, patches one of them, writes BitBake's config files, and
launches the build. `kiosk-zero-w.yaml` is the whole input.

## What a layer is

A **layer** is a directory with a `conf/layer.conf` in it. That file is what makes it a layer;
everything else is convention. Inside it:

- `recipes-<category>/<name>/<name>_<version>.bb` — a **recipe**, the instructions for building one
  piece of software. `meta-wisekiosk/recipes-core/kiosk-session/kiosk-session_1.0.bb` builds the
  kiosk's systemd unit and launcher.
- `recipes-<category>/<name>/<name>_%.bbappend` — a **bbappend**, a fragment that *adds to* a recipe
  someone else's layer defines. It does not replace the recipe; BitBake parses the `.bb` and then
  every `.bbappend` that matches its name, in layer-priority order. The `%` is a wildcard over the
  version, so `surf_%.bbappend` applies to whatever version of `surf` is in play.
- `classes/*.bbclass` — reusable logic a recipe can `inherit`.
- side directories such as `files/` holding the loose files a recipe installs.

The image is the union of every enabled layer. Nothing in this repository outside `meta-wisekiosk/`
is a layer, and BitBake never reads any of it.

### Recipes vs. bbappends here

`meta-wisekiosk/` contains both. The `kiosk-*` recipes are ours from scratch — nothing upstream
builds them. The bbappends adjust software that poky, meta-raspberrypi or meta-autonomos already
package: `icu_%.bbappend` filters out locale data we do not ship, `u-boot_%.bbappend` sets
`bootdelay=0`, `linux-raspberrypi_%.bbappend` adds two kernel patches.

The distinction matters when reading a build failure: a recipe failing is our code; a bbappend
failing usually means upstream's recipe changed underneath it.

## What kas does

Run `kas-container build kiosk-zero-w.yaml` and, in order, kas:

1. **Reads the config chain.** `kiosk-zero-w.yaml` includes `includes/base.yaml`, which includes
   `includes/rauc.yaml`; `includes/platforms/raspberrypi-zero-w.yaml` includes
   `includes/platforms/raspberrypi.yaml`. kas merges them into one configuration. Dictionaries merge
   key by key, which is how `includes/platforms/raspberrypi.yaml` can add a second layer to the
   `meta-autonomos` repo that `includes/base.yaml` declared.
2. **Clones every entry under `repos:`** into the path each names, all under the gitignored
   `sources/`. Each entry is pinned with `commit:`, so a checkout gets the exact same tree every
   time.
3. **Applies patches.** A repo entry may carry a `patches:` block; kas applies those to that repo's
   checkout after cloning. See below.
4. **Writes `build/conf/bblayers.conf`** — BitBake's list of enabled layers — from the `layers:` key
   of each repo. A repo with no `layers:` key contributes its own root as one layer; a repo with
   `layers:` contributes exactly the subdirectories listed. This build enables 17 layers.
5. **Writes `build/conf/local.conf`** from `machine:`, `distro:` and every `local_conf_header:`
   block, concatenated. This is where `kiosk-zero-w.yaml`'s long commented blocks end up — they are
   ordinary BitBake variable assignments with the reasoning kept next to them.
6. **Runs `bitbake core-image-base`** (the `target:`).

`kas-container checkout kiosk-zero-w.yaml` does steps 1–5 and stops. That is the fast way to inspect
what a config change actually produced.

### One trap worth knowing

kas merges `local_conf_header` **by block name**, and the top-level file wins. Two files using the
same block name means one is discarded — silently, with no warning, and the variables in it simply
never reach BitBake. Keep the names unique. This is the main reason this repository carries its own
`includes/` tree rather than cross-including upstream's.

## How this repository consumes meta-autonomos

`meta-autonomos` supplies the `autonomos` distro (systemd as init, the ext4 sizing), the
`autonomos-rauc.bbclass` that sets the RAUC *compatible* string to the literal
`autonomos-${MACHINE}`, the RAUC bundle recipe, and the Raspberry Pi platform layer. It is fetched
like any other dependency:

```yaml
meta-autonomos:
  url: "https://github.com/jsmith212/meta-autonomos.git"
  branch: main
  commit: 1fd4eb55c2ef0902176986bb0dea90e7c34d02bf
  path: "sources/meta-autonomos"
  layers:
    meta-autonomos-core:
  patches:
    01-graphics:
      repo: meta-wisekiosk
      path: "patches/meta-autonomos/0001-distro-make-graphics-strip-conditional.patch"
    02-wpa:
      repo: meta-wisekiosk
      path: "patches/meta-autonomos/0002-wpa-supplicant-stop-baking-credentials.patch"
```

`repo: meta-wisekiosk` says the patch *file* lives in this repository (the url-less entry in
`includes/base.yaml` is kas's name for the repo containing the config file); `path:` is relative to
that repository's root. The patch is applied to `sources/meta-autonomos`.

Almost everything this project needs is expressible as a bbappend or a higher-priority file in
`meta-wisekiosk/`, and lives there. Two things are not, and only those two are patches.

### Why patch 0001 cannot be a bbappend

Upstream's `autonomos.conf` had `DISTRO_FEATURES:remove = " x11 wayland"`. BitBake applies every
`:remove` **after** every `:append`, no matter which file or layer they came from. So there is no
downstream file — not a bbappend, not an image recipe, not `local.conf` — that can put `x11` back.
A kiosk needs x11. The removal has to become conditional where it is written, which means changing
upstream's file, which means a patch.

### Why patch 0002 cannot be a bbappend

Upstream's `wpa-supplicant_%.bbappend` had a `do_install:append` that substituted `WIFI_SSID` and
`WIFI_PSK_HASH` into `/etc/wpa_supplicant.conf` at build time. Two problems: one image serves exactly
one site, and every update bundle built from it carries that site's wireless credentials.

Adding our own bbappend does not help, because **bbappend bodies concatenate**. Ours would run
*after* upstream's, not instead of it — there is no mechanism to remove another layer's
`do_install:append`. `BBMASK` can exclude the whole file, but upstream's bbappend also replaces
`/etc/wpa_supplicant.conf` itself, so masking it would change what the image contains. The only
surgical option is to patch the body to a no-op.

Both patch headers record this reasoning and whether the change is suitable to send upstream.

## Layer priority

`meta-wisekiosk/conf/layer.conf` sets:

```
BBFILE_PRIORITY_wisekiosk = "10"
```

Priority decides who wins when two layers say something about the same recipe. Upstream's layers are
`autonomos-core` at 6 and `autonomos-raspberrypi` at 7, and the Raspberry Pi BSP layer
(`raspberrypi`) sits at 9 — so 10 puts this layer above every layer whose recipes it appends. (These
are *collection* names from each layer's `layer.conf`, which is what `bitbake-layers show-layers`
prints; they drop the `meta-` prefix the directory names carry, so `meta-autonomos-core` the
directory is `autonomos-core` the layer.) Higher wins, so:

- when two layers carry a `.bb` for the same recipe at the same version, the higher-priority layer's
  file is the one used;
- when two layers carry a `.bbappend` for one recipe, both are parsed, but in priority order — ours
  last, so our assignments land on top;
- `FILESPATH`, the search order for `file://` entries in `SRC_URI`, is built in the same order, so a
  file present in both layers resolves to ours.

Being higher priority does **not** disable upstream. Both `meta-autonomos-core` and
`meta-autonomos-raspberrypi` are enabled and doing most of the work; priority only settles conflicts.

## The `wpa_supplicant.service` shadow

The kiosk's wpa_supplicant must read its configuration from `/data/config/wpa_supplicant.conf` — the
partition that survives an A/B update — rather than from a copy baked into the rootfs. That means
changing the systemd unit file, which upstream ships beside its own recipe.

No patch is needed, because of how BitBake resolves `file://` entries. Upstream's
`wpa-supplicant-service.bb` says `SRC_URI = "file://wpa_supplicant.service"` — an unqualified name.
BitBake resolves it against `FILESPATH`, and `FILESEXTRAPATHS:prepend` entries are placed **ahead of
a recipe's own side directories**. So:

```
meta-wisekiosk/recipes-connectivity/wpa-supplicant/wpa-supplicant-service.bbappend
    FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

meta-wisekiosk/recipes-connectivity/wpa-supplicant/files/wpa_supplicant.service   <- wins
sources/meta-autonomos/.../wpa-supplicant-service/wpa_supplicant.service          <- shadowed
```

The recipe is unchanged and unaware; it asks for a filename and gets ours. This is the general escape
hatch for "upstream's recipe is fine, but one of its input files is wrong" — and it is worth
recognising, because a shadowed file is invisible in the recipe you are reading.

This particular file is the network lifeline: a unit that does not bring up `wlan0` is a board that
needs someone standing in front of it. Nothing automates a check on it — after any change near this
file, inspect the built rootfs rather than trusting the tree:

```sh
debugfs -R "cat /etc/systemd/system/wpa_supplicant.service" \
  build/tmp-raspberrypi0-wifi/deploy/images/raspberrypi0-wifi/core-image-base-raspberrypi0-wifi.rootfs.ext4
```

and confirm it reads `/data/config/wpa_supplicant.conf` and requires `data.mount`.

## Bumping the upstream pin

Upstream is dormant, and the pin is deliberate — a floating branch would make every rebuild's diff
unattributable. To move it:

1. Edit `commit:` under `meta-autonomos` in `includes/base.yaml`.
2. `kas-container checkout kiosk-zero-w.yaml`. kas re-clones and re-applies both patches. **If either
   patch does not apply, kas fails here** — that is the signal that upstream touched one of the two
   files, and the patch needs regenerating against the new tree.
3. Regenerate a patch by checking out the new upstream commit in a scratch worktree, making the
   change, and running `git format-patch` into `patches/meta-autonomos/`. Keep the header's
   explanation of why it cannot be a bbappend and its upstream-submission status.
4. Re-run `tools/ci-guards.sh`, then rebuild and compare the image manifest against the previous
   build before shipping anything to a device.

The same steps apply to every other pinned repo. The pins live in three files: most repos in
`includes/base.yaml`, meta-rauc in `includes/rauc.yaml`, and the three Raspberry Pi repos
(meta-raspberrypi, meta-lts-mixins, meta-rauc-community) in `includes/platforms/raspberrypi.yaml` —
`grep -rn 'commit:' includes/` lists them all.

## What commit an image was built from

Every slot carries `/etc/buildinfo`, written by poky's `image-buildinfo` class, switched on by
`INHERIT += "image-buildinfo"` in `kiosk-zero-w.yaml`. The class walks `BBLAYERS` and asks git for
each layer's branch and revision. `meta-wisekiosk` is a subdirectory of this repository, so git walks
up and its line names **this repo's** HEAD:

```
meta-wisekiosk    = <branch>:<sha>
```

`grep ^meta-wisekiosk /etc/buildinfo` on a board is how an investigation learns which source built
the software in front of it.

The stamp is **cache-safe**: `image-buildinfo` reads git live in `do_image`, so on its own the sha
reaches no task signature and a commit touching only docs or `tools/` would leave the previous
build's stamp in place — making the check below unsatisfiable on a clean, pushed tree.
[`kiosk-buildinfo-cachesafe`](../meta-wisekiosk/classes/kiosk-buildinfo-cachesafe.bbclass) puts the
sha in `do_image`'s vardeps, so a moved HEAD re-stamps on the next `just build` and nothing else does.

That is a record, not a guarantee — the class never fails a build, and writes the literal `<unknown>`
when git errors. The guarantee is [`tools/reproducibility-gate.sh`](../tools/reproducibility-gate.sh),
which every recipe that puts an image on a board calls, and which **refuses, with no override flag**,
unless:

- the working tree is clean by `git status --porcelain` — **untracked files included**. Stronger than
  the ` -- modified` flag `image-buildinfo` writes, which is `git diff` and therefore tracked-only: a
  new untracked `.bb` is picked up by `BBFILES` and ships while the layer reads clean. The gate
  ignores that flag and asks git itself.
- HEAD is reachable from some ref on `origin`. It never fetches, and an unreachable `origin` refuses
  rather than assuming — offline is not distinguishable from never-pushed.
- where the caller holds the rootfs (`flash`, `kiosk-preflight`), `/etc/buildinfo` names a 40-hex sha
  equal to HEAD. The bundle-shipping recipes cannot check this — a `.raucb` is not readable with
  `debugfs` and nothing binds one to a rootfs (#48 bundle-image-tie) — so they enforce the first two.

There is no CI here and every image is hand-built, so shipping is the only place the guarantee can be
made — and a skip flag would be used on exactly the day it mattered.
