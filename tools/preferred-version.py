#!/usr/bin/env python3
"""Check each PREFERRED_VERSION against the recipes already checked out.

    preferred-version.py check   -- where a pin selects an older recipe than
                                    the layer beside it already ships

A pinned layer can carry several versions of one recipe, and a PREFERRED_VERSION
decides which is built. That decision is often a weak `??=` default written
upstream, not by anyone here, and nothing in the tree says when it has gone
stale: the layer pin reads `current` while the image builds a recipe two series
behind the one sitting next to it.

Pure filesystem scan of sources/. No build, no network, no bitbake. See
docs/layer-currency.md.
"""
import re
import subprocess
import sys
from pathlib import Path

# Where kas checks the layers out. Without it there is nothing to compare.
SOURCES = "sources"

# Layer directories hold recipes under recipes-<category>/. Anchoring on that
# keeps the walk off sources/*/conf, scripts and the git objects.
RECIPE_GLOB = "recipes-*/**/*.bb"

# Where a PREFERRED_VERSION is set. kas configs are read as text because a
# local_conf_header block is raw bitbake inside YAML.
CONF_GLOBS = ("*.conf", "*.inc", "*.yaml", "*.yml")
CONF_ROOTS = (SOURCES, "includes", "meta-wisekiosk", ".")

# `PREFERRED_VERSION_<pn>[:override] <op> "<value>"`. The pn may itself carry a
# ${...}, which is why it is captured loosely and filtered below.
ASSIGN = re.compile(
    r"^\s*PREFERRED_VERSION_([A-Za-z0-9${}._+-]+?)"
    r"(?::[A-Za-z0-9_${}-]+)?\s*(\?\?=|\?=|:=|=)\s*\"([^\"]*)\"")

# Strongest first. bitbake resolves a weak default only when nothing stronger
# sets the variable, so this orders the assignments found for one recipe.
STRENGTH = {"=": 0, ":=": 0, "?=": 1, "??=": 2}

# A recipe file is <pn>_<pv>.bb. Versions are compared as the recipe FILENAME
# spells them: the real PV is often `${LINUX_VERSION}+git`, which needs bitbake
# to expand, and a series choice is made on the filename anyway.
RECIPE_NAME = re.compile(r"^(.+?)_(.+)\.bb$")

# bitbake's wildcard. `6.6.%` selects linux-raspberrypi_6.6.bb, so the trailing
# separator is dropped with it rather than requiring something after the dot.
WILDCARD = "%"

# An assignment whose value or recipe name expands a variable cannot be resolved
# without bitbake. Counted and named rather than dropped: a check that silently
# skips what it cannot read reports the same clean line as one that found
# nothing wrong.
UNRESOLVED = "expands a variable"
AMBIGUOUS = "set more than one way at the same strength"


def repo_top():
    run = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    return Path(run.stdout.strip()) if run.returncode == 0 else None


def refuse(message: str) -> int:
    print(f"{message} -- refusing to report a pass", file=sys.stderr)
    return 2


def version_key(version: str):
    """A version as a comparable tuple, numeric runs compared as numbers.

    `6.12` sorts above `6.6`, which a string compare gets backwards, and that
    is the whole case this exists for."""
    return tuple((0, int(part)) if part.isdigit() else (1, part)
                 for part in re.split(r"[._-]", version) if part)


def selects(pattern: str, version: str) -> bool:
    if pattern.endswith(WILDCARD):
        return version.startswith(pattern[:-1].rstrip("._-"))
    return version == pattern


def recipes(top: Path):
    """Every recipe under sources/, as {pn: {version: layer}}.

    One walk, because a per-recipe glob over a nine-layer checkout is the whole
    cost of this check."""
    found = {}
    for layer in sorted((top / SOURCES).iterdir()):
        if not layer.is_dir():
            continue
        for path in layer.rglob(RECIPE_GLOB):
            m = RECIPE_NAME.match(path.name)
            if m:
                found.setdefault(m.group(1), {})[m.group(2)] = \
                    path.parent.relative_to(top).as_posix()
    return found


def assignments(top: Path):
    """Every PREFERRED_VERSION set in the tree, as {pn: [(strength, op, value,
    file)]}."""
    files = {p for root in CONF_ROOTS for g in CONF_GLOBS
             for p in (top / root).glob(g if root == "." else f"**/{g}")}
    found = {}
    for path in sorted(files):
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        if "PREFERRED_VERSION" not in text:
            continue
        for line in text.splitlines():
            m = ASSIGN.match(line)
            if m:
                found.setdefault(m.group(1), []).append(
                    (STRENGTH[m.group(2)], m.group(2), m.group(3),
                     path.relative_to(top).as_posix()))
    return found


def resolve(setting):
    """The assignment bitbake would use, or a reason it cannot be read here."""
    strongest = min(s for s, _, _, _ in setting)
    winning = [a for a in setting if a[0] == strongest]
    if len({a[2] for a in winning}) > 1:
        return None, AMBIGUOUS
    return winning[0], None


def check() -> int:
    top = repo_top()
    if top is None:
        return refuse("not inside a git work tree, so sources/ could not be "
                      "located")
    if not (top / SOURCES).is_dir():
        print(f"SKIPPED: no {SOURCES}/ checkout, so there are no recipes to "
              "compare a PREFERRED_VERSION against -- `just build` populates it")
        return 0

    available = recipes(top)
    if not available:
        return refuse(f"{SOURCES}/ holds no recipe matching {RECIPE_GLOB}, so "
                      "every PREFERRED_VERSION would report as unresolvable")

    set_by = assignments(top)
    behind, skipped = [], []
    for pn, setting in sorted(set_by.items()):
        winner, why = resolve(setting)
        if why:
            skipped.append((pn, why, ", ".join(sorted({a[3] for a in setting}))))
            continue
        _, op, pattern, where = winner
        if "${" in pn or "${" in pattern:
            skipped.append((pn, UNRESOLVED, where))
            continue

        versions = available.get(pn)
        if not versions:
            continue
        chosen = sorted((v for v in versions if selects(pattern, v)),
                        key=version_key)
        newest = max(versions, key=version_key)
        if not chosen:
            skipped.append((pn, f"{pattern!r} matches no recipe under "
                            f"{SOURCES}/", where))
            continue
        if version_key(chosen[-1]) < version_key(newest):
            behind.append((pn, op, pattern, chosen[-1], newest,
                           versions[newest], where))

    for pn, op, pattern, chosen, newest, layer, where in behind:
        print(f"behind  {pn}  {op} {pattern!r} selects {chosen}, but {newest} "
              f"is already checked out in {layer}")
        print(f"          set in {where}")

    print(f"\n{len(behind)} of {len(set_by)} PREFERRED_VERSION settings select "
          f"an older recipe than the layer beside them already ships")

    # Grouped, because one upstream include holds forty of them and a
    # line-per-setting buries the three findings above. Counted and named all
    # the same: what could not be read is part of the answer.
    for why in sorted({w for _, w, _ in skipped}):
        names = sorted(pn for pn, w, _ in skipped if w == why)
        where = sorted({f for _, w, f in skipped if w == why})
        print(f"unread:   {len(names)} setting"
              f"{'' if len(names) == 1 else 's'} {why} "
              f"({', '.join(names[:3])}"
              f"{f' and {len(names) - 3} more' if len(names) > 3 else ''}"
              f"; {where[0]}"
              f"{f' and {len(where) - 1} other' if len(where) > 1 else ''}"
              f"{' files' if len(where) > 2 else ' file' if len(where) > 1 else ''})")

    print("A setting in a machine conf applies only when that machine is "
          "built, and this does not read bitbake's override chain: read the "
          "file named beside a finding before acting on it.")
    print("A newer recipe being present is not a reason to take it: a series "
          "bump can change a kernel ABI, a device tree or a rebuild cost. This "
          "reports the choice, it does not make it. See docs/layer-currency.md.")

    # Reports, never gates: exit 0 with findings. A nonzero exit is reserved for
    # a report that cannot be trusted. See docs/layer-currency.md.
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "check":
        return check()
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
