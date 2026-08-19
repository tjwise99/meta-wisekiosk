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

## What commit an image was built from

`meta-wisekiosk/classes/kiosk-buildstamp.bbclass`, globally inherited from `kiosk-zero-w.yaml`,
writes `/etc/build-info` in a rootfs postprocess:

```
BUILD_INFO_VERSION="1"
META_WISEKIOSK_COMMIT="<40 hex>"        META_WISEKIOSK_DIRTY="0|1"
META_WISEKIOSK_COMMIT_SHORT="<12 hex>"  META_WISEKIOSK_BRANCH="<name>"
BUILD_MACHINE=  BUILD_DISTRO=  BUILD_DISTRO_VERSION=  BUILD_LAYERS="name:sha …"
```

Every value is quoted, including those that cannot contain a space: the designed failure value is the
literal `<unknown>`, and unquoted, `<` `>` are redirection operators — `. /etc/build-info` would die
on a syntax error, leave the field empty rather than `<unknown>`, and abandon every later line. Only
`META_WISEKIOSK_DIRTY` answers "was the tree modified"; `BUILD_LAYERS` deliberately carries no dirty
marker, because OE's per-layer flag is `git diff` (tracked only) and would call a tree clean that
`DIRTY` calls dirty.

Four things about it are load-bearing:

- **The sha comes from `BBLAYERS`, not `COREBASE`.** `oe.buildcfg.get_scmbasepath` joins `COREBASE`
  with `meta`, which is why OE's own `METADATA_REVISION` reports poky's HEAD — already pinned in
  `includes/base.yaml`, and never this repository's commit. `meta-wisekiosk` is the one layer kas
  does not clone, so git inside it answers with this working tree.
- **It is captured in configuration space with `:=` and a `[vardepvalue]`**, copying
  `metadata_scm.bbclass`. A package recipe running `git` in `do_install` instead would produce a task
  hash bitbake cannot invalidate: sstate would replay the old package and every later image would bake
  the first commit ever built — a file that exists, parses and is wrong. Image tasks carry
  `SSTATE_SKIP_CREATION`, so this route has no cache to replay.
- **The function is appended to `ROOTFS_POSTPROCESS_COMMAND` with no trailing semicolon**, and this
  is correctness, not style. `image.bbclass` installs that variable's value as its own `vardeps` and
  bitbake splits it on whitespace, so `kiosk_write_build_info;` is looked up as a variable of that
  exact name and resolves to nothing — the body, and every value in it, reaches no task hash.
  `oe/utils.py` meanwhile does `cmds.replace(";", " ")` before executing, so it runs perfectly. Two
  consumers of one string with opposite parsers: the file is written once and then frozen while the
  source moves. This shipped, was caught only by a real build, and is now gated by guard 9 across
  every class in the layer.
- **`DIRTY` is `git status --porcelain` over the whole repository, so an untracked file counts.**
  Same scope as the sha above it, which is the repository's HEAD, not the layer's — `kiosk-zero-w.yaml`,
  `includes/` and `patches/` are build inputs living outside the layer. OE's `is_layer_modified` is
  `git diff` only, and a new untracked `.bb` is picked up by `BBFILES` — it is in the image while
  reading clean. A dirty build is recorded, never refused.

`BUILD_LAYERS` narrows but does not close the gap that `sources/` is gitignored: a hand-patched
upstream layer, or a signing key rotated in `local/keys`, moves the image without moving
`META_WISEKIOSK_COMMIT`.

Verification splits in two, because CI never builds. `tools/ci-guards.sh` guard 9 checks the wiring
still exists and that no postprocess function anywhere in the layer carries the semicolon above;
`tools/build-stamp-check.sh` (`just build-stamp`) reads the file back out of the
shipped `.ext4` with `debugfs` and rejects the `<unknown>` that git failing inside kas-container
would leave. `just flash` and `just kiosk-preflight` run it with `--require`.

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
