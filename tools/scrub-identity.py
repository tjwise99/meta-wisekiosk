#!/usr/bin/env python3
"""Pre-publish identity scan: keep the site out of a PUBLIC repository.

    scrub-identity.py --check [root]    exit 1 if any identifier is present
    scrub-identity.py --apply [root]    rewrite tracked files, print what changed

This repository is public and none of what it must not publish is
credential-shaped -- an SSID, a LAN address, a hostname, a MAC, a machine-id and
a PSK hash all pass gitleaks untouched while together fingerprinting one
network. `tools/ci-guards.sh` guard 6 catches the RFC1918 half; this catches the
rest.

Two halves, because they fail differently:

  PATTERN    shapes that are never legitimate here, recognised with no
             configuration: a MAC, a private IPv4, a filled-in site value, a
             board serial. Runs everywhere, including CI and a fresh clone.

  KNOWN      the literal strings in gitignored `local/device-identity.md`,
             substring-matched. Only this half can catch a hostname or an SSID,
             because neither has a recognisable shape -- and it can only run
             where that file exists.

When the map is absent the run reports PARTIAL and names the half that did not
run. It never prints "clean" for a scan it did not perform: a check that cannot
see the map must not claim the tree is scrubbed.

Scope is `git ls-files` -- the tracked set is exactly what publishing publishes,
and it excludes `build/`, `sources/` and `local/` for free.
"""
import re
import subprocess
import sys
from pathlib import Path

MAP_REL = 'local/device-identity.md'

# Keys under this namespace are recorded in the map but deliberately NOT scanned:
# `raspberrypi0-wifi` is the Yocto MACHINE name and appears in hundreds of
# tracked paths, so scanning for it would fail every file in the tree.
PUBLIC_NS = 'public.'

# A `key = value` line inside the map's ```identity fence. Parsing is scoped to
# that fence so the surrounding prose -- which necessarily discusses the format --
# cannot register a pattern of its own.
FENCE_OPEN = re.compile(r'^```identity\s*$')
FENCE_CLOSE = re.compile(r'^```\s*$')
MAP_ROW = re.compile(r'^\s*([A-Za-z0-9_.]+)\s*=\s*(\S.*?)\s*$')

# --- the pattern half ------------------------------------------------------
# Each entry is (label, compiled regex, remedy). A hit is a failure; there are
# no exemptions, because every legitimate use of these values is out of tree
# (the environment, `just find`, ~/.config/wisekiosk/secrets.yaml, local/).
PATTERNS = [
    (
        'MAC address',
        # The all-ff broadcast and all-zero null addresses are excluded: they
        # name no board, and `tools/kiosk-find.sh` filters the broadcast entry
        # out of a neighbour table by literal. The narrowing is not reachable by
        # the defect -- a board MAC is neither of those two constants.
        re.compile(r'(?<![0-9A-Fa-f:])(?!(?:ff:){5}ff|(?:00:){5}00)'
                   r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f:])', re.I),
        'a MAC identifies one board and its vendor OUI; keep it in local/',
    ),
    (
        'private IPv4',
        re.compile(r'(?<![0-9.])(?:192\.168\.\d{1,3}\.\d{1,3}'
                   r'|10\.\d{1,3}\.\d{1,3}\.\d{1,3}'
                   r'|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?![0-9.])'),
        'device addresses live in KIOSK_HOST or a local .env; `just find <cidr>` discovers one',
    ),
    (
        'filled-in site value',
        # The template keeps every value empty, so an empty pair never matches.
        # A `${VAR}` reference is a build-input question, not a leak -- that is
        # ci-guards guard 1b's subject -- so it is excluded here.
        re.compile(r'\b(?:WIFI_SSID|WIFI_PSK_HASH|KIOSK_URL|KIOSK_HOSTNAME|KIOSK_MACHINE_ID'
                   r'|KIOSK_NAMESERVER|MIRROR_HOST)\s*\??=\s*"(?!\s*\$\{)[^"\s][^"]*"'),
        'site configuration belongs in ~/.config/wisekiosk/secrets.yaml, never in the tree',
    ),
    (
        'board serial',
        re.compile(r'\b[Ss]erial\b\s*[:=]\s*`?[0-9a-f]{16}\b'),
        'a Pi serial identifies one physical unit; keep it in local/',
    ),
]

# This file necessarily contains every pattern it searches for, as source. A
# scanner that fails on its own source is a scanner nobody can commit.
SELF = 'tools/scrub-identity.py'


def repo_root(argv_root):
    if argv_root:
        return Path(argv_root).resolve()
    top = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                         capture_output=True, text=True, check=True).stdout.strip()
    return Path(top)


def load_map(root):
    """[(key, real, placeholder)] for the scanned rows, or None if no map."""
    path = root / MAP_REL
    if not path.exists():
        return None
    rows, inside = [], False
    for line in path.read_text(encoding='utf-8').splitlines():
        if not inside:
            if FENCE_OPEN.match(line):
                inside = True
            continue
        if FENCE_CLOSE.match(line):
            break
        m = MAP_ROW.match(line)
        if not m:
            continue
        key, real = m.group(1), m.group(2)
        if key.startswith(PUBLIC_NS) or not real:
            continue
        rows.append((key, real, '<' + key.upper().replace('.', '_') + '>'))
    return rows


def tracked(root):
    """(relative path, text) for every tracked file that decodes as UTF-8."""
    listing = subprocess.run(['git', 'ls-files'], cwd=root,
                             capture_output=True, text=True, check=True).stdout
    for name in listing.splitlines():
        if not name:
            continue
        path = root / name
        try:
            yield name, path.read_text(encoding='utf-8')
        except (UnicodeDecodeError, OSError):
            continue


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else '--check'
    if mode not in ('--check', '--apply'):
        print(f'usage: {SELF} [--check|--apply] [root]', file=sys.stderr)
        return 2

    root = repo_root(sys.argv[2] if len(sys.argv) > 2 else None)
    rows = load_map(root)

    findings, rewritten, scanned = [], [], 0

    for name, text in tracked(root):
        scanned += 1
        new = text

        if name != SELF:
            for label, pattern, remedy in PATTERNS:
                for m in pattern.finditer(text):
                    line = text.count('\n', 0, m.start()) + 1
                    findings.append(f'{name}:{line}  {label} -- {remedy}')

        for _key, real, placeholder in (rows or []):
            if name == MAP_REL or real not in new:
                continue
            findings.append(f'{name}  known identifier ({new.count(real)}x) from {MAP_REL}')
            new = new.replace(real, placeholder)

        if mode == '--apply' and new != text:
            (root / name).write_text(new, encoding='utf-8')
            rewritten.append(name)

    half = 'PATTERN + KNOWN' if rows else 'PATTERN only'
    print(f'{len(PATTERNS)} patterns, {len(rows or [])} known values, '
          f'{scanned} tracked files scanned ({half})')

    if mode == '--apply':
        print(f'{len(rewritten)} file(s) rewritten')
        for f in rewritten:
            print(f'  {f}')
        return 0

    if findings:
        print(f'\nIDENTITY IN A TRACKED FILE ({len(findings)}) -- do not publish:')
        for f in findings:
            print(f'  {f}')
        return 1

    if rows is None:
        print(f'  PARTIAL -- no {MAP_REL}, so the KNOWN half did not run. '
              'Pattern scan found nothing; a hostname or SSID leak would not be visible here.')
        return 0
    if not rows:
        print(f'  PARTIAL -- {MAP_REL} has no usable rows inside its ```identity fence, '
              'so the KNOWN half scanned nothing.')
        return 0

    print('  clean -- no identity in any tracked file')
    return 0


if __name__ == '__main__':
    sys.exit(main())
