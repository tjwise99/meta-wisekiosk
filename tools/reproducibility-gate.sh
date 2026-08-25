#!/usr/bin/env bash
# Refuse to put an image on a board unless the software on it can be rebuilt
# from what is published (#46).
#
#   tools/reproducibility-gate.sh --tree                 -- clean + pushed
#   tools/reproducibility-gate.sh --image <rootfs.ext4>  -- ... and the image names HEAD
#
# There is NO override flag, and that is the design. An investigation starts
# from a board and has to arrive at the source that built it; a build from a
# tree nobody else can check out records a commit that cannot be fetched, and
# the record reads exactly as convincing as a real one. With no CI here, every
# image is a hand-built dev image, so this is the only place the guarantee can
# be made -- and a flag to skip it would be used on the day it mattered.
#
# Host-side, not a bbclass: cleanliness and pushed-ness are facts about the
# builder's git tree at the moment of shipping, not about the image. tools/
# ci-guards.sh guard 10 checks that this is wired in; this checks the tree and
# the artifact. See docs/layers-and-kas.md.

set -uo pipefail

usage() {
    sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'
}

mode=""
image=""
while [ $# -gt 0 ]; do
    case "$1" in
        --tree)  mode=tree ;;
        --image) mode=image; shift; image=${1-} ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown argument: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# The mode is REQUIRED and never inferred. A caller whose image variable came
# out empty must land here, not silently downgrade to the weaker tree-only
# check -- that failure would look identical to a passing gate.
case "$mode" in
    tree) ;;
    image)
        if [ -z "$image" ]; then
            printf 'REFUSING: --image was given an empty path\n' >&2
            exit 1
        fi
        ;;
    *) printf 'no mode given\n\n' >&2; usage >&2; exit 2 ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { printf 'REFUSING: not inside a git repository -- nothing to attribute an image to\n' >&2; exit 1; }
cd "$root" || exit 2

HEAD=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$HEAD" ]; then
    printf 'REFUSING: this repository has no HEAD commit\n' >&2
    exit 1
fi

refused=0
refuse() { printf 'REFUSING: %s\n' "$*" >&2; refused=1; }
pass()   { printf 'ok    %s\n' "$*"; }

# --- (a) the working tree is clean ----------------------------------------
# --porcelain, so UNTRACKED files count. That is deliberately stronger than
# what the image itself can report: image-buildinfo flags a layer with
# `git diff`, which is tracked-only, and a new untracked .bb is picked up by
# BBFILES and lands in the image while that diff reads clean. Scope is the whole
# repository, because kiosk-zero-w.yaml, includes/ and patches/ are build inputs
# as much as the layer is.
dirty=$(git status --porcelain 2>/dev/null)
if [ -n "$dirty" ]; then
    refuse "the working tree is not clean -- this build is not reproducible from any commit:"
    printf '%s\n' "$dirty" | sed 's/^/        /' >&2
    printf '        commit or stash these, then rebuild.\n' >&2
else
    pass "working tree is clean"
fi

# --- (b) HEAD is published on origin --------------------------------------
# Reachability from ANY origin ref, not just origin/main: a PR branch is
# fetchable, which is all "someone else can check this out" requires.
#
# NEVER fetches. A gate that mutates refs to make itself pass is not a gate, and
# a fetch here would also mean the answer depends on when it last ran.
remote=$(git ls-remote origin 2>/dev/null)
lsrc=$?
if [ $lsrc -ne 0 ] || [ -z "$remote" ]; then
    # Fail CLOSED. Offline is indistinguishable here from "the branch was never
    # pushed", and the expensive mistake is the one that ships.
    refuse "cannot reach origin -- cannot prove $HEAD is published, so refusing"
    printf '        this gate never assumes; get online, or push, and retry.\n' >&2
else
    shas=$(printf '%s\n' "$remote" | awk '{print $1}' | sort -u)
    published=0
    while IFS= read -r sha; do
        [ -n "$sha" ] || continue
        if [ "$sha" = "$HEAD" ]; then published=1; break; fi
        # An ancestor test needs the remote commit in THIS object store. Without
        # it the question is undecidable, and undecidable refuses.
        git cat-file -e "${sha}^{commit}" 2>/dev/null || continue
        if git merge-base --is-ancestor "$HEAD" "$sha" 2>/dev/null; then published=1; break; fi
    done <<< "$shas"
    if [ "$published" -eq 1 ]; then
        pass "HEAD ($HEAD) is published on origin"
    else
        refuse "HEAD is on no ref published to origin:"
        printf '        %s\n' "$HEAD" >&2
        printf '        push the branch, then rebuild -- an unpushed commit cannot be checked out by anyone else.\n' >&2
    fi
fi

# --- (c) the image names HEAD ---------------------------------------------
# Only where an image is actually in hand. A .raucb cannot be read this way and
# nothing ties one to a rootfs (#48), so the bundle-shipping recipes run --tree.
if [ "$mode" = "image" ]; then
    if [ ! -f "$image" ]; then
        refuse "no image artifact at $image -- nothing to attribute; build first"
    elif ! command -v debugfs > /dev/null 2>&1; then
        # Refuse, never skip: an artifact that exists and cannot be read is not
        # the same as no artifact.
        refuse "debugfs missing -- cannot read $image; install e2fsprogs"
    else
        info=$(debugfs -R "cat /etc/buildinfo" "$image" 2>/dev/null | tr -d '\r')
        # image-buildinfo writes "%-17s = %s:%s%s" per BBLAYERS entry, so the
        # layer's own line is `meta-wisekiosk = <branch>:<sha>[ -- modified]`.
        # The ` -- modified` flag is deliberately ignored: it is `git diff` only,
        # and check (a) above is both stronger and authoritative.
        rev=$(awk '$1 == "meta-wisekiosk" && $2 == "=" { print $3; exit }' <<< "$info")
        commit=${rev##*:}
        if [ -z "$info" ]; then
            refuse "no /etc/buildinfo in $image -- this image cannot name the commit it was built from"
            printf '        is INHERIT += "image-buildinfo" still in kiosk-zero-w.yaml?\n' >&2
        elif [ -z "$rev" ]; then
            refuse "/etc/buildinfo in $image has no meta-wisekiosk layer line -- the layer was renamed or is not in BBLAYERS"
        elif ! [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
            # This is what turns image-buildinfo's silent <unknown> into a
            # failure. The class never warns and never fails the build.
            refuse "the image records '$commit', not a 40-character sha -- the build could not read its own git tree, so nothing in $image is attributable"
        elif [ "$commit" != "$HEAD" ]; then
            refuse "the image was not built from HEAD:"
            printf '        image: %s\n' "$commit" >&2
            printf '        HEAD : %s\n' "$HEAD" >&2
            printf '        run `just build` -- the sha is in do_image'\''s signature\n' >&2
            printf '        (kiosk-buildinfo-cachesafe), so a moved HEAD re-stamps on its own.\n' >&2
            printf '        Or check out the commit the image came from.\n' >&2
        else
            pass "image names HEAD ($commit)"
        fi
    fi
fi

if [ "$refused" -ne 0 ]; then
    printf '\nreproducibility gate REFUSED\n' >&2
    exit 1
fi
printf '\nreproducibility gate passed\n'
