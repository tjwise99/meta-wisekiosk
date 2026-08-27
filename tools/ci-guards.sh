#!/usr/bin/env bash
# Repository invariants. CI and the pre-commit hook run this same script, so the
# guard set cannot diverge. A guard may still fail closed locally where the host
# lacks a prerequisite CI installs -- guard 4 needs PyYAML (README "Quick
# start") -- which is a missing prerequisite, not a divergent verdict on the tree.
#
# These are deliberately dependency-light: no bitbake, no network. A Yocto build
# is hours on this tree and cannot gate a commit; what CAN gate a commit is
# whether the tree is about to publish something it should not.
#
# Run by hand:  tools/ci-guards.sh

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

fail=0
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }
ok()  { printf 'ok    %s\n' "$*"; }

# --- 1. secrets must not be in the tree AT ALL ----------------------------
# This repository is PUBLIC, and secrets.yaml holds the SSID, the PSK hash, the
# site hostname and the device machine-id -- none of it credential-shaped, so no
# scanner would stop it.
#
# Stronger than "untracked": the file must not EXIST here. Nothing site-specific
# reaches the image any more, so the build has no reason to read it, and a build
# that cannot read it cannot bake it. Secrets live at
# $KIOSK_SECRETS or ~/.config/wisekiosk/secrets.yaml.
if [ -n "$(git ls-files -- secrets.yaml)" ]; then
    bad "secrets.yaml is TRACKED -- this repository is public"
elif [ -e secrets.yaml ]; then
    bad "secrets.yaml exists in the tree -- move it to ~/.config/wisekiosk/secrets.yaml"
else
    ok "no secrets.yaml in the tree"
fi

# --- 1b. no site value may be a build input -------------------------------
# The fail-closed half. If one of these is ever referenced again, the build
# would bake one site's configuration into every image and put that site's
# wireless credentials inside every update bundle.
#
# patches/ is scanned because a kas patch is a build input like any other: it is
# applied to the meta-autonomos checkout before bitbake ever parses it, so a
# patch is a route to reintroduce credential baking into a tree this repository
# does not otherwise contain. Only ADDED lines count -- 0002 exists precisely to
# delete the ${WIFI_SSID} substitution, so its deletion lines quote the string it
# removes and are filtered out below.
#
# The paths are checked for existence first. grep over a path that no longer
# exists reports nothing and this guard would read green, which is how a layer
# rename silently disarms it.
scan1b=(kiosk-zero-w.yaml meta-wisekiosk includes patches)
missing1b=""
for p in "${scan1b[@]}"; do
    [ -e "$p" ] || missing1b="$missing1b $p"
done
if [ -n "$missing1b" ]; then
    bad "guard 1b cannot scan -- path renamed or removed:$missing1b"
fi
sitevals=$(grep -rnE '\$\{(WIFI_SSID|WIFI_PSK_HASH|KIOSK_URL|KIOSK_HOSTNAME|KIOSK_MACHINE_ID|KIOSK_NAMESERVER)\}' \
    "${scan1b[@]}" 2>/dev/null \
    | grep -vE ':[[:space:]]*#' \
    | grep -vE '^patches/[^:]+:[0-9]+:-')
if [ -n "$sitevals" ]; then
    bad "site configuration is a build input again:"
    printf '%s\n' "$sitevals" | sed 's/^/        /'
else
    ok "no site value reaches the image"
fi

if grep -qE '^[[:space:]]*-[[:space:]]*secrets\.yaml' kiosk-zero-w.yaml 2>/dev/null; then
    bad "kiosk-zero-w.yaml still includes secrets.yaml as a kas include"
else
    ok "secrets.yaml is not a kas include"
fi

# --- 2. the tracked template must stay empty ------------------------------
# secrets.yaml.tmpl's own header says every value MUST be empty. Someone filling
# one in "just to test" publishes it, and the file looks completely normal.
if [ -f secrets.yaml.tmpl ]; then
    filled=$(grep -nE '^[[:space:]]*[A-Z_][A-Z0-9_]*[[:space:]]*\??=[[:space:]]*"[^"]+"' secrets.yaml.tmpl)
    if [ -n "$filled" ]; then
        bad "secrets.yaml.tmpl has non-empty values:"
        printf '%s\n' "$filled" | sed 's/^/        /'
    else
        ok "secrets.yaml.tmpl values are all empty"
    fi
fi

# --- 3. shell scripts must parse ------------------------------------------
# sh -n catches the unterminated quote / missing fi class. It is not shellcheck
# and does not pretend to be; it needs nothing installed and never false-alarms.
# The extensionless scripts are named explicitly because '*.sh' cannot see
# them; the existence check keeps a rename from silently shrinking the scan,
# same as guard 1b. The pre-commit hook is in that set: it is the thing that
# runs this script, so a syntax error in it disarms every guard here.
scan3=(meta-wisekiosk/recipes-core/kiosk-netcheck/files/kiosk-netcheck
       meta-wisekiosk/recipes-core/kiosk-provision/files/kiosk-provision
       meta-wisekiosk/recipes-core/kiosk-recover/files/kiosk-recover
       meta-wisekiosk/recipes-core/kiosk-session/files/kiosk-launch
       .githooks/pre-commit)
missing3=""
for p in "${scan3[@]}"; do [ -e "$p" ] || missing3="$missing3 $p"; done
[ -n "$missing3" ] && bad "guard 3 cannot scan -- path renamed or removed:$missing3"
badsh=0
while IFS= read -r f; do
    [ -f "$f" ] || continue
    if ! err=$(bash -n "$f" 2>&1); then
        bad "shell syntax error: $f"
        printf '%s\n' "$err" | sed 's/^/        /'
        badsh=1
    fi
done < <(git ls-files -- '*.sh' "${scan3[@]}")
[ "$badsh" -eq 0 ] && ok "shell scripts parse"

# --- 4. kas configs must be valid YAML ------------------------------------
# A kas file that does not parse fails hours into a build, or worse, silently
# drops a block: kas merges local_conf_header by BLOCK NAME and the top-level
# file wins, so a duplicated name is discarded with no warning at all.
#
# Cannot-check is not check-clean: without a YAML parser this fails closed
# rather than exit 0 on a search it could not perform, as the identity scan
# fails closed for a missing map. CI installs PyYAML before this runs, so a
# green CI means the files were parsed; a local route without it fails here,
# pointing at the README prerequisite. The message names the missing tool, so
# it reads as "cannot check", not the older false positive of "every kas file
# is invalid YAML".
if ! command -v python3 > /dev/null; then
    bad "guard 4 cannot check YAML: python3 not available"
elif ! python3 -c 'import yaml' 2>/dev/null; then
    bad "guard 4 cannot check YAML: python3 has no yaml module -- install PyYAML; see README \"Quick start\" for a PEP-668-safe route. CI installs it automatically."
else
    badyaml=0
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        if ! err=$(python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$f" 2>&1); then
            bad "YAML does not parse: $f"
            printf '%s\n' "$err" | sed 's/^/        /'
            badyaml=1
        fi
    done < <(git ls-files -- '*.yaml' '*.yml')
    [ "$badyaml" -eq 0 ] && ok "kas/YAML files parse"
fi

# --- 5. gitleaks, if present ----------------------------------------------
# Optional locally, required in CI. It catches the credential-shaped half; the
# checks above catch the half it structurally cannot see.
if command -v gitleaks > /dev/null; then
    # Explicit --config: gitleaks does discover .gitleaks.toml on its own, but a
    # silently-unfound allowlist would fail the known finding on every run, and
    # a check that is always red gates nothing.
    glargs=()
    [ -f .gitleaks.toml ] && glargs=(--config .gitleaks.toml)
    if gitleaks detect "${glargs[@]}" --no-banner --redact --exit-code 1; then
        ok "gitleaks found no leaks"
    else
        bad "gitleaks reported findings"
    fi
else
    printf 'skip  gitleaks not installed locally (CI runs it)\n'
fi

# --- 6. no IP addresses in tracked files ----------------------------------
# This repo is PUBLIC and its docs are meant to be generic. A hardcoded LAN
# address fingerprints the network and is caught by neither gitleaks nor guard 1
# (an RFC1918 address is not credential-shaped). NO exemptions: device addresses
# live only in the environment (KIOSK_HOST) or a local .env, never in the tree,
# so any private IPv4 in a tracked file fails. `just find <cidr>` is how an
# address is discovered at use time.
ipre='(^|[^0-9.])(192\.168\.[0-9]{1,3}\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})([^0-9.]|$)'
ipfound=$(
    while IFS= read -r f; do
        case "$f" in
            *.png|*.jpg|*.jpeg|*.gz|*.bz2|*.xz|*.zst|*.raucb|*.wic|*.ico) continue ;;
        esac
        grep -HnE "$ipre" "$f" 2>/dev/null
    done < <(git ls-files)
)
if [ -n "$ipfound" ]; then
    bad "IP address in a tracked file -- keep the tree generic (KIOSK_HOST / just find, never committed):"
    printf '%s\n' "$ipfound" | sed 's/^/        /'
else
    ok "no IP addresses in tracked files"
fi

# --- 7. an auto-enabled service recipe must be reachable from an image -----
# A recipe under meta-wisekiosk/recipes*/ can auto-enable a systemd service yet
# be in no IMAGE_INSTALL, so it never runs (kiosk-provision #35, read-only-
# rootfs-config #10); recipe and IMAGE_INSTALL each parse fine alone, only the
# cross-check sees it. Scoped to auto-enabled services (owner, 2026-08-15): a
# debug tool (no service, or unit shipped disabled like kiosk-bootprof) and a
# config-only recipe are out of scope. "Reachable" is a literal IMAGE_INSTALL
# token; a transitively-pulled recipe false-FAILs (safe) -- name it or extend.
# Paths are existence-checked first (as 1b/3) so a rename cannot read green.
scan7_root="meta-wisekiosk"
scan7_image="kiosk-zero-w.yaml"

# Combined text of a recipe: the .bb plus every require/include-d .inc (systemd
# metadata may live there), resolved beside the requiring file first else by
# basename in the layer; recursive, visited-guarded. NOT followed: `inherit` of
# a custom .bbclass, or a .bbappend -- a recipe signalled only that way is missed.
recipe_text7() {
    local f=$1 seen=$2 inc resolved
    [ -f "$f" ] || return 0
    case " $seen " in *" $f "*) return 0 ;; esac
    seen="$seen $f"
    cat "$f"
    while IFS= read -r inc; do
        [ -n "$inc" ] || continue
        if [ -f "$(dirname "$f")/$inc" ]; then
            resolved="$(dirname "$f")/$inc"
        else
            resolved=$(find "$scan7_root" -name "$(basename "$inc")" -type f 2>/dev/null | head -n1)
        fi
        [ -n "$resolved" ] && recipe_text7 "$resolved" "$seen"
    done < <(grep -hE '^[[:space:]]*(require|include)[[:space:]]' "$f" 2>/dev/null \
             | sed -E 's/^[[:space:]]*(require|include)[[:space:]]+//; s/[[:space:]].*$//')
}

missing7=""
[ -d "$scan7_root" ] || missing7="$missing7 $scan7_root"
[ -f "$scan7_image" ] || missing7="$missing7 $scan7_image"
if [ -n "$missing7" ]; then
    bad "guard 7 cannot scan -- path renamed or removed:$missing7"
else
    # PN = .bb basename minus the trailing _<version> (bitbake splits at last _).
    recipes7=$(find "$scan7_root" -path "${scan7_root}/recipes*/*" -name '*.bb' 2>/dev/null | sort -u)
    if [ -z "$recipes7" ]; then
        bad "guard 7 found no recipes under ${scan7_root}/recipes* -- glob broken or layer renamed"
    else
        # IMAGE_INSTALL tokens (any :append/:prepend/override/legacy _append),
        # minus :remove tokens (a :remove wins regardless of order); inline
        # comments stripped so they cannot smuggle a token in.
        ii_add=$(grep -E '^[[:space:]]*IMAGE_INSTALL([:_][A-Za-z0-9._:+-]+)?[[:space:]]*[?:+.]*=' "$scan7_image" \
            | grep -vE '^[[:space:]]*IMAGE_INSTALL[:_][^=]*remove' \
            | sed -E 's/^[^=]*=//; s/#.*//; s/"//g' | tr '\n' ' ')
        ii_remove=$(grep -E '^[[:space:]]*IMAGE_INSTALL[:_][^=]*remove[^=]*=' "$scan7_image" \
            | sed -E 's/^[^=]*=//; s/#.*//; s/"//g' | tr '\n' ' ')
        unreachable7=""
        while IFS= read -r bb; do
            [ -n "$bb" ] || continue
            text=$(recipe_text7 "$bb" "")
            # here-strings, never `| grep -q`: grep -q + pipefail inverts a match
            # (producer SIGPIPEs to 141) once text exceeds the pipe buffer.
            grep -qE '^[[:space:]]*inherit[[:space:]].*systemd' <<< "$text" || continue
            grep -qE '^[[:space:]]*SYSTEMD_SERVICE' <<< "$text" || continue
            # disabled only if a disable assignment exists and no enable one does
            # (per-PN/later enable wins; no assignment defaults to enable).
            ae=$(sed -nE '/^[[:space:]]*SYSTEMD_AUTO_ENABLE/{s/#.*//;p;}' <<< "$text")
            if grep -qE '=[^=]*disable' <<< "$ae" && ! grep -qE '=[^=]*enable' <<< "$ae"; then
                continue
            fi
            pn=$(basename "$bb" | sed -E 's/\.bb$//; s/_[^_]*$//')
            case " $ii_add " in
                *" $pn "*)
                    case " $ii_remove " in
                        *" $pn "*) unreachable7="$unreachable7 $pn" ;;
                    esac
                    ;;
                *) unreachable7="$unreachable7 $pn" ;;
            esac
        done <<< "$recipes7"
        if [ -n "$unreachable7" ]; then
            bad "auto-enabled service recipe is installed by no image:"
            for pn in $unreachable7; do printf '        %s\n' "$pn"; done
        else
            ok "every auto-enabled service recipe is reachable from an image"
        fi
    fi
fi

# --- 8. the recovery script must be wired into the /data placement path ----
# The kiosk-recover script (issue #28) lives on /data, not the rootfs, so guard
# 7 -- which polices auto-enabled rootfs SERVICES reaching an image -- is blind
# to it by construction: no service, in no IMAGE_INSTALL. Its own reachability
# check is that tools/provision.sh (the /data placement path) actually copies
# it. Two ways this silently breaks and both fail here: the script goes missing
# from its recipe home, or provision.sh stops referencing it (a rename, a
# refactor). Paths are existence-checked first, as 1b/3/7, so neither can read
# green by disappearing.
recover_src="meta-wisekiosk/recipes-core/kiosk-recover/files/kiosk-recover"
recover_placer="tools/provision.sh"
if [ ! -f "$recover_src" ]; then
    bad "guard 8: recovery script missing at $recover_src -- nothing to place on /data"
elif [ ! -f "$recover_placer" ]; then
    bad "guard 8: $recover_placer missing -- the /data placement path is gone"
else
    # Not "is the path named" -- a comment or the RECOVER_SRC= assignment would
    # satisfy that -- but "is the script actually placed": a non-comment
    # install/cp command whose target is RECOVER.sh. Comments are stripped first
    # so a mention in prose cannot green the guard. grep -c, not `| grep -q`
    # (pipefail inverts a match -- see the note above), counts placement commands.
    # Heuristic: recognizes install/cp (a tar/cat placement would need this
    # widened). The real backstop is provision.sh's own delivery verify -- both
    # card and device modes read RECOVER.sh back -- so a miss here fails at
    # provision time, not silently.
    placements=$(grep -vE '^[[:space:]]*#' "$recover_placer" \
        | grep -cE '(install|cp)[[:space:]].*RECOVER\.sh')
    if [ "$placements" -eq 0 ]; then
        bad "guard 8: $recover_placer names but does not place the recovery script (no install/cp of RECOVER.sh) -- not wired onto /data"
    else
        ok "recovery script is wired into the /data placement path"
    fi
fi

# --- 9. no *_COMMAND may glue a `;` to a function name ---------------------
# image.bbclass does `d.setVarFlag(var, 'vardeps', d.getVar(var))` over every
# rootfs/image command variable, and bitbake splits a vardeps value on
# WHITESPACE into names. `func;` is no name at all, so the function's body never
# reaches the task hash: edit the function and bitbake replays the sstate rootfs,
# and the change silently does not ship. oe.utils strips the `;` and runs it
# either way, so the build succeeds and the form looks correct.
#
# `func ;` is legal and NOT flagged -- it splits into `func` and `;`, and `func`
# is a name. The fix is to drop the character, never to restructure.
#
# `${VAR};` and `"…";` are caught too, not just a bare name: the trap is the
# character, whatever precedes it.
#
# Scanned over every file bitbake or kas reads here, not just the class that had
# the bug: the layer's .bbclass/.bb/.bbappend/.inc/.conf, includes/*.yaml,
# kiosk-zero-w.yaml, and patches/ (added lines only). Nothing about the glued
# form looks wrong at review, and the only other way to notice it is a rebuild
# that does not change. Continuations are joined first -- a multi-line command
# list is the shape most likely to carry one. Paths are existence-checked, as
# 1b/3/7/8, so a rename cannot read green.
scan9="meta-wisekiosk includes kiosk-zero-w.yaml patches"
missing9=""
for p in $scan9; do [ -e "$p" ] || missing9="$missing9 $p"; done
if [ -n "$missing9" ]; then
    bad "guard 9 cannot scan -- path renamed or removed:$missing9"
else
    # The LAYER's own files are counted separately, as guard 7 does. Combining
    # them with the kas config first would keep the list non-empty forever --
    # `printf kiosk-zero-w.yaml` always emits -- so a broken layer glob or a
    # renamed layer would read green with nothing actually scanned.
    layer9=$(find meta-wisekiosk -type f \
                 \( -name '*.bbclass' -o -name '*.bb' -o -name '*.bbappend' \
                    -o -name '*.inc' -o -name '*.conf' \) 2>/dev/null | sort -u)
    if [ -z "$layer9" ]; then
        bad "guard 9 found no bitbake files under meta-wisekiosk -- glob broken or layer renamed"
    else
        files9=$( { printf '%s\n' "$layer9"
                    find includes -type f \( -name '*.yaml' -o -name '*.yml' \)
                    printf '%s\n' kiosk-zero-w.yaml
                    find patches -type f -name '*.patch'; } 2>/dev/null | sort -u )
        # A whole-line `#` is skipped so a quoted example cannot fail the guard;
        # mid-line text is NOT stripped, because `#` inside a bitbake string is
        # literal and stripping it would hide a real hit.
        hits9=$(
            while IFS= read -r f; do
                [ -f "$f" ] || continue
                # A patch is a build input like any other (guard 1b's reason):
                # it is applied to the meta-autonomos checkout before bitbake
                # parses it, so it is a route to reintroduce the glued form.
                # ADDED lines only -- a context line is upstream's existing
                # content and a removed line is the defect going away. Non-added
                # lines are BLANKED rather than dropped, so reported line numbers
                # still point into the patch.
                case "$f" in
                    patches/*) src9=$(sed -e '/^+/!s/.*//' -e 's/^+//' "$f") ;;
                    *)         src9=$(cat "$f") ;;
                esac
                awk -v F="$f" -v SEMI='[A-Za-z0-9_}"'"'"'];' '
                    { if (line == "" && $0 ~ /^[[:space:]]*#/) next
                      if (line == "") start = NR
                      line = line $0
                      if (line ~ /\\$/) { sub(/\\$/, " ", line); next }
                      if (line ~ /^[[:space:]]*[A-Z][A-Z0-9_]*_(PRE|POST)[A-Z_]*COMMANDS?([:_][A-Za-z0-9._:+-]+)?[[:space:]]*[?:+.]*=/ \
                          && line ~ SEMI)
                          printf "%s:%d: %s\n", F, start, line
                      line = "" }
                ' <<< "$src9"
            done <<< "$files9"
        )
        if [ -n "$hits9" ]; then
            bad "a *_COMMAND glues ';' to a function name -- its body reaches no task hash:"
            printf '%s\n' "$hits9" | sed 's/^/        /'
        else
            ok "no *_COMMAND glues ';' to a function name"
        fi
    fi
fi

# --- 10. the reproducibility gate must stay wired in ----------------------
# CI never builds, so it cannot check an image. What it CAN check is that the
# record is still switched on and that every recipe putting an image on a board
# still calls the gate -- the two halves of #46. Deleting either is a one-line
# edit that leaves both files parsing and every other guard green.
#
# The mode is asserted, not just the call: --image is the full check
# (clean + pushed + image names HEAD) and --tree is the subset. A site that can
# prove the image matches and quietly drops to --tree still looks wired.
gate10="tools/reproducibility-gate.sh"
conf10="kiosk-zero-w.yaml"
missing10=""
for p in "$gate10" "$conf10" justfiles/deploy.just justfiles/ota.just justfiles/device.just; do
    [ -e "$p" ] || missing10="$missing10 $p"
done
if [ -n "$missing10" ]; then
    bad "guard 10 cannot scan -- path renamed or removed:$missing10"
else
    [ -x "$gate10" ] || bad "guard 10: $gate10 is not executable -- every call site would fail open on a permission error"

    inherits10=$(grep -vE '^[[:space:]]*#' "$conf10" \
        | grep -cE '^[[:space:]]*INHERIT[[:space:]]*\+?=[[:space:]]*"image-buildinfo"')
    if [ "$inherits10" -eq 0 ]; then
        bad "guard 10: $conf10 does not inherit image-buildinfo -- images would carry no /etc/buildinfo, and the gate's image check would refuse every build"
    else
        ok "kiosk-zero-w.yaml inherits image-buildinfo"
    fi

    # Cache safety: every part asserted, any one alone is inert.
    # See docs/layers-and-kas.md, "What commit an image was built from".
    cache10="meta-wisekiosk/classes/kiosk-buildinfo-cachesafe.bbclass"
    # IMAGE_CLASSES, not INHERIT -- ordering, see the doc section above.
    cinh10=$(grep -vE '^[[:space:]]*#' "$conf10" \
        | grep -cE '^[[:space:]]*IMAGE_CLASSES[[:space:]]*\+?=[[:space:]]*"kiosk-buildinfo-cachesafe"')
    if [ ! -f "$cache10" ]; then
        bad "guard 10: $cache10 missing -- /etc/buildinfo would silently go stale whenever a commit changes no bitbake input"
    elif [ "$cinh10" -eq 0 ]; then
        bad "guard 10: $conf10 does not add kiosk-buildinfo-cachesafe to IMAGE_CLASSES -- the class exists but nothing inherits it (or a global INHERIT was used, which parses too early and gets welded), so the stamp is not cache-safe"
    else
        # Comments stripped: a guard greened by a comment that describes the
        # wiring would be worse than no guard.
        cbody10=$(grep -vE '^[[:space:]]*#' "$cache10")
        cmiss10=""
        # grep -c and compare, never `| grep -q`: -q exits on the first hit, the
        # producer dies of SIGPIPE at 141, and pipefail returns that -- the test
        # would be false precisely when the pattern matches.
        n10=$(grep -cE '^[[:space:]]*include[[:space:]]+conf/build-rev\.inc' <<< "$cbody10")
        [ "$n10" -eq 0 ] && cmiss10="$cmiss10 include-conf/build-rev.inc"
        # do_image specifically, and it must name the variable carrying the sha.
        # The same flag on do_rootfs, or naming something else, reads as wired
        # and changes no hash -- so nothing re-stamps and nothing says so.
        #
        # Deletion detection only: no source-text check can prove the token
        # survived as its own entry in the parsed flag. Backstop is the gate.
        n10=$(grep -cF "appendVarFlag('do_image', 'vardeps', ' KIOSK_BUILDINFO_REV')" <<< "$cbody10")
        [ "$n10" -eq 0 ] && cmiss10="$cmiss10 appendVarFlag(do_image,vardeps,'_KIOSK_BUILDINFO_REV')"
        # Absence must be LOUD. Without the fatal, a build with no injected sha
        # succeeds and silently stops re-stamping.
        n10=$(grep -cF 'bb.fatal' <<< "$cbody10")
        [ "$n10" -eq 0 ] && cmiss10="$cmiss10 bb.fatal-when-unset"
        if [ -n "$cmiss10" ]; then
            bad "guard 10: $cache10 is not wired -- /etc/buildinfo would go stale on a commit that changes no bitbake input; missing:"
            for m in $cmiss10; do printf '        %s\n' "$m"; done
        else
            ok "the /etc/buildinfo stamp is cache-safe (host sha in do_image's signature)"
        fi

        # The sha reaches bitbake only if the host writes it BEFORE the build.
        # Every route to bitbake that can produce a flashable image must run the
        # writer; one that does not trips the class's bb.fatal, which is loud but
        # is a broken build, not a guarantee. Checked per call site, in file
        # order, so a new entry point added without the writer is caught here.
        writer10="tools/write-build-rev.sh"
        if [ ! -x "$writer10" ]; then
            bad "guard 10: $writer10 missing or not executable -- no build could inject the commit it is building from"
        else
            uninj10=$(
                for f in Justfile justfiles/ota.just tools/rauc-rotate-build.sh; do
                    [ -f "$f" ] || { printf '%s: MISSING FILE\n' "$f"; continue; }
                    awk -v F="$f" -v W="$writer10" '
                        /^[[:space:]]*#/ { next }
                        index($0, W) { armed = 1; next }
                        /kas-container[[:space:]]+(build|shell)/ {
                            if (!armed) printf "%s:%d: %s\n", F, NR, $1
                            armed = 0
                            next
                        }
                        # Last rule: the writer and build rules match first, so an
                        # unindented line in a shell script is not a boundary. A
                        # recipe header disarms, so a writer-only recipe cannot
                        # arm the next one.
                        /^[^[:space:]#]/ { armed = 0 }
                    ' "$f"
                done
            )
            if [ -n "$uninj10" ]; then
                bad "guard 10: a build that can produce a flashable image does not run $writer10 first:"
                printf '%s\n' "$uninj10" | sed 's/^/        /'
            else
                ok "every build entry point injects the commit it is building from"
            fi
        fi

        # Generated build input, never source. Untracked instead of ignored would
        # make `git status --porcelain` dirty and the gate would refuse EVERY
        # flash -- the mechanism would break the thing it exists to serve.
        if ! git check-ignore -q meta-wisekiosk/conf/build-rev.inc; then
            bad "guard 10: meta-wisekiosk/conf/build-rev.inc is not gitignored -- once written it would leave the tree dirty and the reproducibility gate would refuse every flash"
        else
            ok "the generated build-rev fragment is gitignored"
        fi
    fi

    # Body of one just recipe: from its `name ...:` header to the next
    # non-blank unindented line. Comment lines are dropped.
    recipe_body10() {
        awk -v r="$2" '
            $0 ~ "^" r "[ :]" { inb = 1; next }
            inb && NF && /^[^[:space:]]/ { inb = 0 }
            inb && !/^[[:space:]]*#/ { print }
        ' "$1"
    }

    unwired10=""
    # <justfile>:<recipe>:<required mode>
    for spec in \
        "justfiles/deploy.just:flash:--image" \
        "justfiles/ota.just:kiosk-preflight:--image" \
        "justfiles/ota.just:kiosk-send-direct:--tree" \
        "justfiles/ota.just:kiosk-install:--tree" \
        "justfiles/device.just:rauc-install:--tree"
    do
        jf10=${spec%%:*}
        rest10=${spec#*:}
        rn10=${rest10%%:*}
        mode10=${rest10#*:}
        body10=$(recipe_body10 "$jf10" "$rn10")
        if [ -z "$body10" ]; then
            unwired10="$unwired10 $jf10:$rn10(recipe-gone)"
            continue
        fi
        calls10=$(grep -cF -- "$gate10 $mode10" <<< "$body10")
        [ "$calls10" -eq 0 ] && unwired10="$unwired10 $jf10:$rn10($mode10)"
    done
    if [ -n "$unwired10" ]; then
        bad "a recipe that puts an image on a board does not call the reproducibility gate:"
        for u in $unwired10; do printf '        %s\n' "$u"; done
    else
        ok "every image-to-board recipe calls the reproducibility gate"
    fi

    # The rotation path reaches a device WITHOUT calling the gate itself: it goes
    # through kiosk-preflight, which runs it in the strongest --image form, once
    # per install phase. So the invariant here is positional, not a call site --
    # every install must be PRECEDED by a preflight. A refactor that reorders or
    # drops one strips the gate off the rotation path while every other check
    # here stays green.
    rot10="tools/rauc-rotate.sh"
    if [ ! -f "$rot10" ]; then
        bad "guard 10: $rot10 missing -- the rotation path's gating cannot be checked"
    else
        ungated10=$(awk '
            /^[[:space:]]*#/ { next }
            /just[[:space:]]+kiosk-preflight/ { armed = 1 }
            /just[[:space:]]+kiosk-install|rauc[[:space:]]+install/ {
                if (!armed) printf "%d: %s\n", NR, $0
                armed = 0; n++
            }
            END { if (n == 0) print "0: no install phase found -- this guard went stale, or the script was restructured" }
        ' "$rot10")
        if [ -n "$ungated10" ]; then
            bad "guard 10: an install in $rot10 is not preceded by kiosk-preflight -- the rotation path would reach a device ungated:"
            printf '%s\n' "$ungated10" | sed 's/^/        /'
        else
            ok "every install in the rotation path is preceded by kiosk-preflight"
        fi
    fi
fi

# --- 11. the identity scan must stay wired into every route ---------------
# Guard 6 above sees RFC1918 addresses and nothing else. A hostname, an SSID, a
# MAC, a board serial, a machine-id and a PSK hash are none of them
# credential-shaped and none of them address-shaped, so gitleaks and guard 6
# both pass while the tree publishes the site. tools/scrub-identity.py is what
# sees those, and it is run once per route rather than from here -- running it
# from inside this script AND from the hook and the workflow would scan the tree
# twice on every commit.
#
# So what is asserted here is the WIRING, as guard 10 does for the
# reproducibility gate: dropping the call from the hook, the workflow or the
# justfile is a one-line edit that leaves every file parsing and every other
# guard green. Comments are stripped first, so a mention in prose cannot green
# it. Paths are existence-checked, as 1b/3/7/8/9/10.
#
# The STRENGTH of each call is asserted too, not just its presence. `--check` is
# a substring of `--check --allow-partial`, so a presence test alone reads green
# on a route that has had the known-value half switched off -- and that half is
# the only thing that sees a hostname, an SSID or a machine-id. Where the map
# exists the scan must be able to fail; where it structurally cannot (a clone in
# CI) the workflow declares the limit. So --allow-partial belongs on the
# workflow route and on NEITHER strict one, and both directions are checked: a
# strict route that gains the flag fails here, and a workflow route that loses
# it fails here too.
#
# The Justfile is read as the `guards` RECIPE, not as a file: a call elsewhere in
# it is a different route, and a rename of the recipe must fail here rather than
# silently widen the scan.
scrub11="tools/scrub-identity.py"
call11="$scrub11 --check"
part11="--allow-partial"
if [ ! -x "$scrub11" ]; then
    bad "guard 11: $scrub11 missing or not executable -- nothing scans for device identity"
else
    unwired11=""
    loose11=""
    for route11 in ".githooks/pre-commit:strict" ".github/workflows/guards.yml:partial" "Justfile:strict"; do
        f=${route11%:*}
        want11=${route11##*:}
        if [ ! -f "$f" ]; then
            unwired11="$unwired11 $f(missing)"
            continue
        fi
        case "$f" in
            Justfile) body11=$(awk '/^guards:/ { inr = 1; next } inr && /^[^[:space:]]/ { exit } inr' "$f") ;;
            *)        body11=$(cat "$f") ;;
        esac
        # grep -c and compare, never `| grep -q`: -q exits on the first hit, the
        # producer dies of SIGPIPE at 141, and pipefail returns that -- the test
        # would be false precisely when the pattern matches.
        calls11=$(printf '%s\n' "$body11" | grep -vE '^[[:space:]]*#' | grep -F -- "$call11")
        n11=$(printf '%s\n' "$calls11" | grep -cF -- "$call11")
        if [ "$n11" -eq 0 ]; then
            unwired11="$unwired11 $f"
            continue
        fi
        p11=$(printf '%s\n' "$calls11" | grep -cF -- "$part11")
        if [ "$want11" = strict ] && [ "$p11" -ne 0 ]; then
            loose11="$loose11 $f($part11-on-a-strict-route)"
        elif [ "$want11" = partial ] && [ "$p11" -ne "$n11" ]; then
            loose11="$loose11 $f(declared-limit-dropped)"
        fi
    done
    if [ -n "$unwired11" ]; then
        bad "guard 11: the identity scan is not wired into every route -- a tracked hostname, SSID, MAC or machine-id would publish unseen; missing from:"
        for u in $unwired11; do printf '        %s\n' "$u"; done
    elif [ -n "$loose11" ]; then
        bad "guard 11: a route runs the identity scan at the wrong strength -- $part11 belongs on the workflow route ONLY, where the gitignored map structurally cannot exist:"
        for u in $loose11; do printf '        %s\n' "$u"; done
    else
        ok "the identity scan is wired into the hook, the workflow and the justfile, strict on both local routes"
    fi

    # And RUN it here too. This script is the allowlisted entry point an agent
    # reaches for, so "guards passed" printed by it must not be readable as "no
    # identity in the tree": a MAC seeded into a tracked CLAUDE.md left this
    # script green (guard 6 sees addresses, gitleaks sees credential shapes)
    # while the identity scan reported it on the same tree. The cost is one
    # extra pass over the tracked files on the routes that also call it.
    #
    # --allow-partial belongs HERE and not in the route calls: this script runs
    # in CI, where gitignored local/device-identity.md structurally cannot
    # exist. Refusing to exit 0 on a scan that could not run in full is the
    # route's job, where the map is present.
    if out11=$("$scrub11" --check --allow-partial 2>&1); then
        ok "no device identity in any tracked file ($(printf '%s\n' "$out11" | head -n1))"
    else
        bad "guard 11: device identity in a tracked file -- do not publish:"
        printf '%s\n' "$out11" | sed 's/^/        /'
    fi
fi

# --- 12. the device guard must still pass its own self-test ---------------
# .claude/hooks/guard.sh blocks destructive operations aimed at the prod board
# and image writes to a fixed disk. A guard nobody exercises is indistinguishable
# from a guard that matches nothing, so its self-test is a repository invariant,
# not a convenience: an edit that opens a rule fails here.
guardtest12=".claude/hooks/guard-test.sh"
if [ ! -f "$guardtest12" ]; then
    bad "guard 12: $guardtest12 missing -- the device guard is no longer self-tested"
elif out12=$(bash "$guardtest12" 2>&1); then
    ok "the device guard passes its self-test ($(printf '%s\n' "$out12" | tail -n1))"
else
    bad "the device guard FAILS its own self-test:"
    printf '%s\n' "$out12" | grep -E '^(FAIL|pass=)' | sed 's/^/        /'
fi

# --- 13. the review checklist is ONE taxonomy, authored in two files ------
# .claude/hooks/review-diff.py selects `**Group**` names; CONTRIBUTING.md's
# "## Review checklist" defines them. Both files say in prose that a rename in
# either place silently selects nothing -- and prose is what a one-word rename
# walks past. A group that matches nothing yields zero questions, and zero
# questions is exactly what a clean commit looks like: staging the site-secrets
# template with `**RAUC / signing / secrets**` renamed committed it with no
# review question at all, and no gate saw it.
rd13=".claude/hooks/review-diff.py"
cb13="CONTRIBUTING.md"
if [ ! -f "$rd13" ] || [ ! -f "$cb13" ]; then
    bad "guard 13: $rd13 or $cb13 missing -- the review checklist taxonomy cannot be checked"
elif ! command -v python3 > /dev/null 2>&1; then
    bad "guard 13: python3 missing -- the review checklist taxonomy cannot be checked"
else
    out13=$(python3 - "$rd13" "$cb13" <<'PY'
import re
import sys

src = open(sys.argv[1], encoding='utf-8').read()
doc = open(sys.argv[2], encoding='utf-8').read()

# Read from the source as literals rather than by importing: importing runs a
# PreToolUse hook, and a list kept here by hand would make this file a THIRD
# author of the same taxonomy.
selected = set(re.findall(r'needed\.add\(\s*"([^"]+)"\s*\)', src))

parts = doc.split('## Review checklist', 1)
headings, questions, current = set(), {}, None
if len(parts) > 1:
    for line in re.split(r'\n## ', parts[1])[0].splitlines():
        m = re.match(r'^\*\*([^*]+)\*\*\s*$', line)
        if m:
            current = m.group(1).strip()
            headings.add(current)
        elif current and re.match(r'^\d+\.\s+\*\*[^*]+\*\*', line):
            questions[current] = questions.get(current, 0) + 1

problems = []
if not selected:
    problems.append(f'no group name read out of {sys.argv[1]} -- the extraction went stale')
if not headings:
    problems.append(f'no **Group** heading under "## Review checklist" in {sys.argv[2]}')
problems += [f'{sys.argv[1]} selects "{n}", which is no **Group** heading in {sys.argv[2]}'
             for n in sorted(selected - headings)]
problems += [f'{sys.argv[2]} group "{n}" is selected by no path rule in {sys.argv[1]}'
             for n in sorted(headings - selected)]
problems += [f'group "{n}" carries no numbered question, so selecting it asks nothing'
             for n in sorted(headings) if not questions.get(n)]

print('\n'.join(problems))
PY
    )
    if [ -n "$out13" ]; then
        bad "guard 13: the review checklist taxonomy differs between the two files that author it:"
        printf '%s\n' "$out13" | sed 's/^/        /'
    else
        ok "the review checklist taxonomy agrees in CONTRIBUTING.md and review-diff.py"
    fi
fi

if [ "$fail" -ne 0 ]; then
    printf '\nguards FAILED\n'
    exit 1
fi
printf '\nguards passed\n'
