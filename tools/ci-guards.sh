#!/usr/bin/env bash
# Repository invariants. CI and the pre-commit hook run this same script, so a
# guard cannot pass locally and fail in CI, or the reverse.
#
# These are deliberately dependency-light: no bitbake, no network. A Yocto build
# is hours on this tree and cannot gate a commit; what CAN gate a commit is
# whether the tree is about to publish something it should not.
#
# Run by hand:  tools/ci-guards.sh

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

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
scan1b="kiosk-zero-w.yaml meta-wisekiosk includes patches"
missing1b=""
for p in $scan1b; do
    [ -e "$p" ] || missing1b="$missing1b $p"
done
if [ -n "$missing1b" ]; then
    bad "guard 1b cannot scan -- path renamed or removed:$missing1b"
fi
sitevals=$(grep -rnE '\$\{(WIFI_SSID|WIFI_PSK_HASH|KIOSK_URL|KIOSK_HOSTNAME|KIOSK_MACHINE_ID|KIOSK_NAMESERVER)\}' \
    $scan1b 2>/dev/null \
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
scan3="meta-wisekiosk/recipes-core/kiosk-netcheck/files/kiosk-netcheck \
       meta-wisekiosk/recipes-core/kiosk-provision/files/kiosk-provision \
       meta-wisekiosk/recipes-core/kiosk-session/files/kiosk-launch \
       .githooks/pre-commit"
missing3=""
for p in $scan3; do [ -e "$p" ] || missing3="$missing3 $p"; done
[ -n "$missing3" ] && bad "guard 3 cannot scan -- path renamed or removed:$missing3"
badsh=0
while IFS= read -r f; do
    [ -f "$f" ] || continue
    if ! err=$(bash -n "$f" 2>&1); then
        bad "shell syntax error: $f"
        printf '%s\n' "$err" | sed 's/^/        /'
        badsh=1
    fi
done < <(git ls-files -- '*.sh' $scan3)
[ "$badsh" -eq 0 ] && ok "shell scripts parse"

# --- 4. kas configs must be valid YAML ------------------------------------
# A kas file that does not parse fails hours into a build, or worse, silently
# drops a block: kas merges local_conf_header by BLOCK NAME and the top-level
# file wins, so a duplicated name is discarded with no warning at all.
if ! command -v python3 > /dev/null; then
    printf 'skip  python3 not available, YAML not parsed\n'
elif ! python3 -c 'import yaml' 2>/dev/null; then
    # Distinguishing "cannot check" from "check failed" matters: the first
    # version of this reported every kas file as invalid YAML on a host whose
    # python3 simply lacked the module, which reads as a broken repository.
    printf 'skip  python3 has no yaml module, YAML not parsed\n'
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
    glargs=""
    [ -f .gitleaks.toml ] && glargs="--config .gitleaks.toml"
    if gitleaks detect $glargs --no-banner --redact --exit-code 1; then
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

if [ "$fail" -ne 0 ]; then
    printf '\nguards FAILED\n'
    exit 1
fi
printf '\nguards passed\n'
