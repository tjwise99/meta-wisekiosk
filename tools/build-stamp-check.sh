#!/usr/bin/env bash
# Does the built image name the commit it was built from?
#
#   tools/build-stamp-check.sh                  -- newest artifact under build/
#   tools/build-stamp-check.sh --require        -- ... and an unreadable one FAILS
#   tools/build-stamp-check.sh [--require] <rootfs.ext4|rootfs-dir>
#
# Host-only: CI never builds, so this is not in tools/ci-guards.sh. Guard 9
# checks the wiring; this reads the artifact. See docs/layers-and-kas.md.

set -uo pipefail

EXT4_GLOB="build/tmp-*/deploy/images/*/core-image-base-*.rootfs.ext4"
ROOTFS_GLOB="build/tmp-*/work/*/core-image-base/*/rootfs"

require=0
target=""
for arg in "$@"; do
    case "$arg" in
        --require) require=1 ;;
        -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) printf 'unknown option: %s\n' "$arg" >&2; exit 2 ;;
        *)  target=$arg ;;
    esac
done

die()  { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
# Loud, on stdout, exit 0 -- see tools/doc-image.py.
skip() {
    if [ "$require" -eq 1 ]; then die "$*"; fi
    printf 'SKIPPED: %s -- build stamp check did not run\n' "$*"
    exit 0
}

# Newest match, or empty. `-nt` follows symlinks: the .ext4 in deploy/images is
# a symlink onto the build-stamped file.
newest_of() {
    local best="" f
    for f in "$@"; do
        [ -e "$f" ] || continue
        if [ -z "$best" ] || [ "$f" -nt "$best" ]; then best=$f; fi
    done
    printf '%s' "$best"
}

if [ -z "$target" ]; then
    cd "$(git rev-parse --show-toplevel)" || exit 2
    mapfile -t ext4s < <(compgen -G "$EXT4_GLOB")
    target=$(newest_of "${ext4s[@]+"${ext4s[@]}"}")
    if [ -z "$target" ]; then
        # The rootfs directory's mtime is epoch-clamped; the recipe workdir above
        # it is what dates the build.
        mapfile -t trees < <(compgen -G "$ROOTFS_GLOB")
        parents=()
        for t in "${trees[@]+"${trees[@]}"}"; do parents+=("$(dirname "$t")"); done
        newest_parent=$(newest_of "${parents[@]+"${parents[@]}"}")
        [ -n "$newest_parent" ] && target="$newest_parent/rootfs"
    fi
    [ -n "$target" ] || skip "no built image under $EXT4_GLOB or $ROOTFS_GLOB"
fi

[ -e "$target" ] || die "no such image artifact: $target"

if [ -d "$target" ]; then
    info=$(cat "$target/etc/build-info" 2>/dev/null)
else
    # Refuse, never skip: an artifact that exists and cannot be read is not the
    # same as no artifact.
    command -v debugfs >/dev/null 2>&1 \
        || die "debugfs missing -- cannot read $target; install e2fsprogs"
    info=$(debugfs -R "cat /etc/build-info" "$target" 2>/dev/null)
fi
info=$(printf '%s' "$info" | tr -d '\r')

[ -n "$info" ] || die "no /etc/build-info in $target -- this image cannot name the commit it was built from (is INHERIT += \"kiosk-buildstamp\" still in kiosk-zero-w.yaml?)"

# First KEY= line, unquoted. One awk, not `sed | head`: under pipefail that
# returns head's SIGPIPE kill of sed.
field() {
    awk -v k="$1" 'index($0, k "=") == 1 { sub(/^[^=]*=/, ""); gsub(/"/, ""); print; exit }' <<< "$info"
}

version=$(field BUILD_INFO_VERSION)
commit=$(field META_WISEKIOSK_COMMIT)
short=$(field META_WISEKIOSK_COMMIT_SHORT)
dirty=$(field META_WISEKIOSK_DIRTY)
branch=$(field META_WISEKIOSK_BRANCH)

[ "$version" = "1" ] \
    || die "BUILD_INFO_VERSION is '${version:-<absent>}', this check knows 1 -- the format moved and the checker did not"

[[ "$commit" =~ ^[0-9a-f]{40}$ ]] \
    || die "META_WISEKIOSK_COMMIT is '${commit:-<absent>}', not a 40-character sha -- the build could not read its own git tree, so nothing in $target is attributable"

[ "${#short}" -eq 12 ] && [ "$short" = "${commit:0:12}" ] \
    || die "META_WISEKIOSK_COMMIT_SHORT is '${short:-<absent>}', not the first 12 characters of $commit"

case "$dirty" in
    0|1) ;;
    *) die "META_WISEKIOSK_DIRTY is '${dirty:-<absent>}', not 0 or 1" ;;
esac

printf 'build stamp ok: %s  branch %s  dirty %s\n' "$short" "${branch:-<absent>}" "$dirty"
printf '  source: %s\n' "$target"
if [ "$dirty" = "1" ]; then
    printf '  WARNING: built from a modified tree -- %s does not describe what shipped\n' "$commit"
fi
