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
sitevals=$(grep -rnE '\$\{(WIFI_SSID|WIFI_PSK_HASH|KIOSK_URL|KIOSK_HOSTNAME|KIOSK_MACHINE_ID|KIOSK_NAMESERVER)\}' \
    kiosk-zero-w.yaml meta-autonomos-core meta-autonomos-raspberrypi includes 2>/dev/null \
    | grep -vE ':[[:space:]]*#')
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
badsh=0
while IFS= read -r f; do
    [ -f "$f" ] || continue
    if ! err=$(bash -n "$f" 2>&1); then
        bad "shell syntax error: $f"
        printf '%s\n' "$err" | sed 's/^/        /'
        badsh=1
    fi
done < <(git ls-files -- '*.sh' 'tools/kiosk-netcheck')
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

if [ "$fail" -ne 0 ]; then
    printf '\nguards FAILED\n'
    exit 1
fi
printf '\nguards passed\n'
