#!/usr/bin/env python3
"""Check the pinned upstream repositories against the branch heads they track.

    layer-currency.py check          -- which `commit:` pins upstream has moved past
    layer-currency.py gap <repo> [--fetch]
                                     -- which unpatched CVEs bumping one pin
                                        would plausibly close

`check` reads the pins from includes/ and asks each remote directly: no build and
no checkout, network only. Where sources/ happens to hold a clone it says how far
behind as well, and never requires one. `gap` reads that clone and the newest CVE
manifest, offline; `--fetch` is the only thing here that writes to sources/.
See docs/layer-currency.md.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cve_manifest import (CVE, LAYER, PACKAGE, STATUS, UNPATCHED,
                          ManifestError, records, report_hijacks)

try:
    import yaml
except ImportError:
    yaml = None

# Where the pins live. Scanned rather than listed, so a pin added to a new
# include file is covered the day it lands.
INCLUDES = "includes"
PIN_GLOBS = ("*.yaml", "*.yml")

# What a repo entry is asked about. Two files setting one of these differently
# is decided by kas on include-chain order, which is not visible from here.
PIN_KEYS = ("url", "commit", "branch")

# A full object name. A short or symbolic pin is not comparable against what
# ls-remote returns, and comparing it would report `behind` on spelling alone.
SHA = re.compile(r"^[0-9a-f]{40}$")

# Long enough for a slow remote, short enough that a stalled one is reported
# rather than waited on.
LS_REMOTE_TIMEOUT = 30

BEHIND = "behind"
CURRENT = "current"

# Where kas checks the pins out. Everything that reads it is opportunistic: the
# no-checkout guarantee is the point of `check`, so an absent sources/ costs
# detail and never an answer.
SOURCES = "sources"
ORIGIN = "origin"

# The CVE manifest an audit build leaves behind, read to say what a pin is
# WORTH. Without one every repo reports `unknown` rather than nothing. The
# parser is shared with cve-report, cve-delta and cve-scan.
MANIFEST_GLOB = "build/tmp-*/deploy/images/*/*.cve"

# A CVE named in a commit subject or body. Evidence of intent, never proof a
# finding flips -- see `gap`'s closing note.
CVE_ID = re.compile(r"CVE-\d{4}-\d{4,7}")

# A repo declaring no `layers:` block contributes its own directory as one layer
# named after the repo, which is what kas does and what bblayers.conf shows.
DEPENDENCY_ONLY = "contributes 0 (dependency only)"
UNKNOWN = "contribution unknown (no audit build)"

# Long enough for a real fetch of a large layer, short enough that a stalled
# remote is reported rather than waited on.
FETCH_TIMEOUT = 300


def repo_top():
    """The repository root, or None outside a work tree."""
    run = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    return Path(run.stdout.strip()) if run.returncode == 0 else None


def refuse(message: str) -> int:
    print(f"{message} -- refusing to report a pass", file=sys.stderr)
    return 2


def tail(stream: str, lines: int = 3) -> str:
    return " / ".join(stream.strip().splitlines()[-lines:]) or "(no output)"


def nested(doc, *keys):
    """A value down a chain of mapping keys, or None if any hop is not one."""
    for key in keys:
        doc = doc.get(key) if isinstance(doc, dict) else None
    return doc


def load_pins(top: Path):
    """Every repo entry under includes/, or a refusal message.

    Returns the entries merged by name -- a later file adding layers to a repo
    an earlier one pinned is one entry, not two -- with the branch an entry
    declaring none inherits, and the files read. Two files setting one repo's
    url, commit or branch to different values refuse; setting it in one file
    and not the other, or to the same value, merges. An entry that is not a
    mapping is carried through unmerged, for check() to refuse rather than
    normalise."""
    root = top / INCLUDES
    files = sorted({p for g in PIN_GLOBS for p in root.rglob(g)}) \
        if root.is_dir() else []
    if not files:
        return None, (f"{INCLUDES}/ holds no YAML file, so no pin could be "
                      "read")

    repos, pin_files, defaults, pinned = {}, [], {}, {}
    for path in files:
        rel = path.relative_to(top).as_posix()
        try:
            doc = yaml.safe_load(path.read_text())
        except (yaml.YAMLError, OSError, UnicodeDecodeError) as exc:
            return None, f"{rel} could not be parsed ({exc})"

        branch = nested(doc, "defaults", "repos", "branch")
        if branch is not None:
            defaults[rel] = branch

        entries = doc.get("repos") if isinstance(doc, dict) else None
        if not isinstance(entries, dict):
            continue
        pin_files.append(rel)
        for repo, entry in entries.items():
            entry = {} if entry is None else entry
            # Keyed on the value's repr, so an unhashable one still compares
            # and two files spelling it identically stay one value.
            for key in PIN_KEYS if isinstance(entry, dict) else ():
                if key in entry:
                    pinned.setdefault((repo, key), {})[repr(entry[key])] = rel
            was = repos.get(repo)
            repos[repo] = ({**was, **entry}
                           if isinstance(was, dict) and isinstance(entry, dict)
                           else entry)

    for (repo, key), values in sorted(pinned.items()):
        if len(values) > 1:
            return None, (f"{repo} is given more than one `{key}:` across the "
                          "pin files ("
                          + ", ".join(f"{f} -> {v}" for v, f
                                      in sorted(values.items(),
                                                key=lambda kv: kv[1]))
                          + "), and which one kas would use is decided by an "
                          "include chain this does not read")

    # Picking one of two chain defaults would resolve in silence a question
    # this cannot answer.
    if len(set(defaults.values())) > 1:
        return None, ("more than one chain default branch is set ("
                      + ", ".join(f"{f} -> {b}"
                                  for f, b in sorted(defaults.items()))
                      + "), so no branch could be resolved")

    return (repos, next(iter(defaults.values()), None), pin_files), None


def newest_manifest(top: Path):
    """The most recently written CVE manifest under build/, or None."""
    unique = {p.resolve() for p in top.glob(MANIFEST_GLOB)}
    found = sorted((p for p in unique if p.is_file()),
                   key=lambda p: p.stat().st_mtime, reverse=True)
    return found[0] if found else None


def manifest_records(manifest: Path, hijacks=None):
    """The manifest's records, as dicts.

    A prose line the field regex reads as a record key would otherwise put a
    phantom record in the layer counts, which is a wrong CONTRIBUTION number
    with nothing to show it went wrong."""
    return list(records(manifest.read_text(errors="replace"), hijacks))


def layers_of(name: str, entry: dict):
    """The layer names one repo entry contributes.

    kas adds the repo's own directory as a layer where the entry declares no
    `layers:` block, which is how meta-raspberrypi and meta-lts-mixins reach
    bblayers.conf, so the repo name is the fallback rather than an empty set."""
    declared = entry.get("layers")
    return tuple(declared) if isinstance(declared, dict) and declared else (name,)


def contribution(by_layer, layers):
    """What a repo's layers put in the image, as (phrase, ranking weight).

    The phrase counts RECIPES CARRYING CVE RECORDS -- a layer can contribute a
    .bbappend or a class that changes the image without owning a record, so
    zero is `dependency only` on the CVE-attribution axis, not `unused`.

    The WEIGHT is unpatched findings, which is a different number and the one
    the ranking needs. meta-raspberrypi contributes a single recipe and owns
    3723 of this image's 3941 unpatched findings; poky contributes 88 recipes
    and owns 95. Ranking on the recipe count puts the pin worth bumping last."""
    if by_layer is None:
        return UNKNOWN, -1
    recipes = set().union(*(by_layer[n][0] for n in layers if n in by_layer)) \
        if layers else set()
    unpatched = sum(by_layer[n][1] for n in layers if n in by_layer)
    if not recipes:
        return DEPENDENCY_ONLY, 0
    return (f"contributes {len(recipes)} "
            f"recipe{'' if len(recipes) == 1 else 's'}, "
            f"{unpatched} unpatched"), unpatched


def git(path: Path, *args, timeout=30):
    """One git command in a checkout, or None where it failed."""
    try:
        run = subprocess.run(["git", "-C", str(path), *args],
                             capture_output=True, text=True, timeout=timeout,
                             env={**os.environ, "GIT_TERMINAL_PROMPT": "0",
                                  "GIT_ASKPASS": ""})
    except (subprocess.TimeoutExpired, OSError):
        return None
    return run.stdout.strip() if run.returncode == 0 else None


def ancestry(top: Path, entry: dict, pin: str, head: str):
    """How far a pin is behind the head, as a phrase, or None.

    Strictly opportunistic. sources/ is a clone the build already made, so the
    distance costs nothing where it exists -- but `check` promises no checkout,
    so an absent or unfetched one degrades to today's output rather than
    refusing or fetching behind the caller's back."""
    path = entry.get("path")
    if not isinstance(path, str) or not path.strip():
        return None
    where = top / path
    if not (where / ".git").exists() and not where.is_dir():
        return None
    if git(where, "cat-file", "-e", f"{head}^{{commit}}") is None:
        return "the clone predates this head; `git fetch` to measure the gap"
    count = git(where, "rev-list", "--count", f"{pin}..{head}")
    if count is None:
        return None
    linear = git(where, "merge-base", "--is-ancestor", pin, head) is not None
    return (f"behind by {count} commits" if linear else
            f"{count} commits ahead on the head, and the pin is NOT an "
            "ancestor of it -- the branch was rewritten")


def ls_remote(url: str, branch: str):
    """The head of one branch at a remote, or a refusal message.

    Both git prompts are closed off because a hang is not a refusal: a url that
    has gone private fails instead of waiting on a credential nobody types."""
    ref = f"refs/heads/{branch}"
    try:
        run = subprocess.run(["git", "ls-remote", url, ref],
                             capture_output=True, text=True,
                             timeout=LS_REMOTE_TIMEOUT,
                             env={**os.environ, "GIT_TERMINAL_PROMPT": "0",
                                  "GIT_ASKPASS": ""})
    except subprocess.TimeoutExpired:
        return None, (f"`git ls-remote {url} {ref}` did not answer within "
                      f"{LS_REMOTE_TIMEOUT}s")
    if run.returncode != 0:
        return None, (f"`git ls-remote {url} {ref}` failed "
                      f"({run.returncode}): {tail(run.stderr)}")

    lines = run.stdout.strip().splitlines()
    if not lines:
        return None, (f"{url} reports no {ref}, so this pin has no branch to "
                      "be compared against")
    if len(lines) > 1:
        return None, (f"{url} answers {ref} with {len(lines)} refs, so the "
                      "head it names is ambiguous")

    # The ref is compared, not assumed: ls-remote matches a ref TAIL, so a
    # differently-named upstream branch can answer and be reported as this one.
    fields = lines[0].split()
    if len(fields) != 2 or not SHA.match(fields[0]) or fields[1] != ref:
        return None, (f"{url} answers {ref} with {lines[0]!r}, which is not "
                      "that ref at a full object name")
    return fields[0], None


def check() -> int:
    if yaml is None:
        return refuse("python3 has no yaml module, so no pin could be parsed "
                      "-- install PyYAML; the README prerequisites give a "
                      "PEP-668-safe route")
    top = repo_top()
    if top is None:
        return refuse("not inside a git work tree, so includes/ could not be "
                      "located")

    loaded, why = load_pins(top)
    if why:
        return refuse(why)
    repos, default_branch, pin_files = loaded

    # Per layer: the recipes carrying records, and how many of their findings
    # are unpatched. The first is what the report says, the second is what it
    # ranks on -- see contribution().
    manifest = newest_manifest(top)
    hijacks, by_layer = [], None
    if manifest is not None:
        by_layer = {}
        try:
            parsed = manifest_records(manifest, hijacks)
        except ManifestError as exc:
            return refuse(f"{manifest.name}: {exc}")
        for rec in parsed:
            recipes, unpatched = by_layer.setdefault(rec[LAYER], (set(), 0))
            recipes.add(rec[PACKAGE])
            by_layer[rec[LAYER]] = (
                recipes, unpatched + (rec.get(STATUS) == UNPATCHED))

    found, excluded = {BEHIND: [], CURRENT: []}, []
    for name, entry in sorted(repos.items()):
        if not isinstance(entry, dict):
            return refuse(f"the {name} entry is not a mapping, so its pin "
                          "could not be read")

        url, commit = entry.get("url"), entry.get("commit")
        if url is None and commit is None:
            excluded.append(name)
            continue
        if url is None:
            return refuse(f"{name} carries a `commit:` pin but no `url:`, so "
                          "there is no remote to compare it against; the repo "
                          "kas resolves to this repository carries neither")
        if not isinstance(url, str) or not url.strip():
            return refuse(f"the {name} entry declares a url of {url!r}, which "
                          "is not a remote that can be asked")

        if not isinstance(commit, str) or not SHA.match(commit):
            typed = (" -- YAML types an unquoted all-digit sha as an integer"
                     if isinstance(commit, int) else "")
            return refuse(f"{name} carries no full-length `commit:` pin "
                          f"({commit!r}){typed}, so nothing could be compared "
                          f"against {url}")

        explicit = entry.get("branch")
        branch = explicit or default_branch
        if not isinstance(branch, str) or not branch.strip():
            return refuse(f"{name} sets no `branch:` and no file under "
                          f"{INCLUDES}/ sets defaults.repos.branch, so no "
                          f"branch could be resolved for {url}")

        head, why = ls_remote(url, branch)
        if why:
            return refuse(why)
        phrase, weight = contribution(by_layer, layers_of(name, entry))
        found[BEHIND if head != commit else CURRENT].append(
            (name, branch, explicit is not None, commit, head, url, phrase,
             weight, ancestry(top, entry, commit, head)))

    # Every entry reading as the self repo means the discriminator stopped
    # discriminating, which would empty the report without emptying the pins.
    if len(excluded) > 1:
        return refuse(f"{', '.join(sorted(excluded))} all carry neither `url:` "
                      "nor `commit:`, and only one entry resolves to this "
                      "repository")
    if not found[BEHIND] and not found[CURRENT]:
        return refuse(f"{INCLUDES}/ pins no upstream repository")

    # `behind` ranked by what the bump could move, so the first line is the pin
    # worth reading. A pin behind by a quarter of security backports and one
    # whose layer reaches no recipe in the image are the same line otherwise.
    found[BEHIND].sort(key=lambda r: (-r[7], r[0]))
    for status in (BEHIND, CURRENT):
        for (name, branch, explicit, pin, head, url, phrase, _,
             far) in found[status]:
            where = branch if explicit else f"{branch} (chain default)"
            shas = f"{pin} -> {head}" if status == BEHIND else pin
            print(f"{status}  {name}  {where}  {shas}  {phrase}  {url}")
            if far and status == BEHIND:
                print(f"          {far}")

    total = len(found[BEHIND]) + len(found[CURRENT])
    print(f"\n{len(found[BEHIND])} of {total} pinned repositories behind the "
          f"branch head they track, {len(found[CURRENT])} current")
    if by_layer is None:
        print("contribution unknown throughout: no CVE manifest under "
              f"{MANIFEST_GLOB} -- `just cve-build` writes one")
    if excluded:
        print(f"excluded: {excluded[0]} -- neither `url:` nor `commit:`, so "
              "kas resolves it to this repository and there is no pin to "
              "compare")
    print(f"pins read from {', '.join(pin_files)}")
    report_hijacks(hijacks)
    print("`behind` says the head has moved off the pin, not that the pin is "
          "unsafe; what those commits carry is a separate read. "
          "See docs/layer-currency.md.")

    # Reports, never gates: exit 0 with findings. A nonzero exit is reserved for
    # a report that cannot be trusted. See docs/layer-currency.md.
    return 0


def gap(name: str, fetch: bool) -> int:
    """Which unpatched findings the commits between a pin and its head name.

    Offline against the clone kas already made. `--fetch` is opt-in and is the
    only thing here that writes to sources/: fetching inside a report would
    break the no-checkout promise this file opens with, and a silent one would
    make a stale clone indistinguishable from an upstream with nothing new."""
    if yaml is None:
        return refuse("python3 has no yaml module, so no pin could be parsed "
                      "-- install PyYAML; the README prerequisites give a "
                      "PEP-668-safe route")
    top = repo_top()
    if top is None:
        return refuse("not inside a git work tree, so includes/ could not be "
                      "located")
    loaded, why = load_pins(top)
    if why:
        return refuse(why)
    repos, default_branch, _ = loaded

    entry = repos.get(name)
    if not isinstance(entry, dict):
        return refuse(f"{name} is not a repo pinned under {INCLUDES}/ "
                      f"({', '.join(sorted(repos))})")
    pin, branch = entry.get("commit"), entry.get("branch") or default_branch
    path = entry.get("path")
    if not isinstance(pin, str) or not SHA.match(pin):
        return refuse(f"{name} carries no full-length `commit:` pin, so there "
                      "is nothing to measure a gap from")
    if not isinstance(path, str) or not (top / path).is_dir():
        return refuse(f"{name} has no checkout at {path!r}, and the gap is read "
                      "from one -- `just build` populates sources/")

    where = top / path
    if fetch and git(where, "fetch", ORIGIN, branch,
                     timeout=FETCH_TIMEOUT) is None:
        return refuse(f"`git fetch {ORIGIN} {branch}` failed in {path}")

    ref = f"refs/remotes/{ORIGIN}/{branch}"
    head = git(where, "rev-parse", "--verify", f"{ref}^{{commit}}")
    if head is None:
        return refuse(f"{path} has no {ref}, so there is no head to compare the "
                      "pin against -- re-run with --fetch")
    if git(where, "cat-file", "-e", f"{pin}^{{commit}}") is None:
        return refuse(f"{path} does not hold the pinned commit {pin[:12]}, so "
                      "the range could not be walked -- re-run with --fetch")

    # An empty range offline is two situations that print identically: upstream
    # genuinely has nothing new, or this clone was never fetched past the pin.
    # Reporting a bare 0 would read as the first whichever it was, and the
    # difference is exactly what the caller is asking about.
    if head == pin:
        print(f"SKIPPED: {ref} in {path} sits on the pin itself, so the range "
              "is empty. That is either an upstream with nothing new or a "
              "clone never fetched past it, and offline these are the same "
              "answer -- re-run with --fetch, or ask the remote with "
              "`layer-currency.py check`")
        return 0

    hijacks = []
    log = git(where, "log", "--format=%s%n%b", f"{pin}..{head}")
    if log is None:
        return refuse(f"`git log {pin[:12]}..{ref}` failed in {path}")
    commits = git(where, "rev-list", "--count", f"{pin}..{head}") or "?"
    named = set(CVE_ID.findall(log))

    manifest = newest_manifest(top)
    if manifest is None:
        print(f"SKIPPED: {commits} commits in the gap naming {len(named)} "
              f"CVEs, but no CVE manifest under {MANIFEST_GLOB} to intersect "
              "them against -- `just cve-build` writes one")
        return 0

    try:
        parsed = manifest_records(manifest, hijacks)
    except ManifestError as exc:
        return refuse(f"{manifest.name}: {exc}")
    unpatched = [r for r in parsed
                 if r.get(STATUS) == UNPATCHED and r.get(CVE) in named]
    for r in sorted(unpatched, key=lambda r: (r.get(PACKAGE, ""),
                                              r.get(CVE, ""))):
        print(f"{r.get(CVE)}  {r.get(PACKAGE, '?')}  "
              f"CVSSv3 {r.get('CVSS v3 BASE SCORE', '?')}  "
              f"[{r.get(LAYER, '?')}]")

    packages = {r.get(PACKAGE) for r in unpatched}
    print(f"\n{len(unpatched)} unpatched findings across {len(packages)} "
          f"packages would plausibly close, out of {len(named)} CVEs named "
          f"across {commits} commits between the pin and {ORIGIN}/{branch}")
    print(f"pin:  {pin}\nhead: {head}  ({path}, "
          + ("fetched just now" if fetch
             else "as last fetched -- pass --fetch to update") + ")")
    report_hijacks(hijacks)
    print("`would plausibly close` is what a commit message NAMES, not what a "
          "rebuild proves. The authoritative answer is bumping the pin and "
          "re-running `just cve-build`. See docs/layer-currency.md.")

    # Reports, never gates: exit 0 with findings. A nonzero exit is reserved for
    # a report that cannot be trusted. See docs/layer-currency.md.
    return 0


def main() -> int:
    argv = sys.argv[1:]
    if argv == ["check"]:
        return check()
    fetch = "--fetch" in argv
    rest = [a for a in argv if a != "--fetch"]
    if len(rest) == 2 and rest[0] == "gap":
        return gap(rest[1], fetch)
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
