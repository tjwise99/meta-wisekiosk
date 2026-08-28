#!/usr/bin/env python3
"""Check the pinned upstream repositories against the branch heads they track.

    layer-currency.py check    -- which `commit:` pins upstream has moved past

The pins come from includes/, and each remote is asked directly: no build and no
checkout, network only. See docs/layer-currency.md.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

# Where the pins live. Scanned rather than listed, so a pin added to a new
# include file is covered the day it lands.
INCLUDES = "includes"
PIN_GLOBS = ("*.yaml", "*.yml")

# A full object name. A short or symbolic pin is not comparable against what
# ls-remote returns, and comparing it would report `behind` on spelling alone.
SHA = re.compile(r"^[0-9a-f]{40}$")

# Long enough for a slow remote, short enough that a stalled one is reported
# rather than waited on.
LS_REMOTE_TIMEOUT = 30

BEHIND = "behind"
CURRENT = "current"


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
    declaring none inherits, and the files read. Merged in path order; where
    two files set one repo's key that order decides it, which is not kas's
    include-chain precedence. An entry that is not a mapping is carried through
    unmerged, for check() to refuse rather than normalise."""
    root = top / INCLUDES
    files = sorted({p for g in PIN_GLOBS for p in root.rglob(g)}) \
        if root.is_dir() else []
    if not files:
        return None, (f"{INCLUDES}/ holds no YAML file, so no pin could be "
                      "read")

    repos, pin_files, defaults = {}, [], {}
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
            was = repos.get(repo)
            repos[repo] = ({**was, **entry}
                           if isinstance(was, dict) and isinstance(entry, dict)
                           else entry)

    # Picking one of two chain defaults would resolve in silence a question
    # this cannot answer.
    if len(set(defaults.values())) > 1:
        return None, ("more than one chain default branch is set ("
                      + ", ".join(f"{f} -> {b}"
                                  for f, b in sorted(defaults.items()))
                      + "), so no branch could be resolved")

    return (repos, next(iter(defaults.values()), None), pin_files), None


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
        found[BEHIND if head != commit else CURRENT].append(
            (name, branch, explicit is not None, commit, head, url))

    # Every entry reading as the self repo means the discriminator stopped
    # discriminating, which would empty the report without emptying the pins.
    if len(excluded) > 1:
        return refuse(f"{', '.join(sorted(excluded))} all carry neither `url:` "
                      "nor `commit:`, and only one entry resolves to this "
                      "repository")
    if not found[BEHIND] and not found[CURRENT]:
        return refuse(f"{INCLUDES}/ pins no upstream repository")

    for status in (BEHIND, CURRENT):
        for name, branch, explicit, pin, head, url in found[status]:
            where = branch if explicit else f"{branch} (chain default)"
            shas = f"{pin} -> {head}" if status == BEHIND else pin
            print(f"{status}  {name}  {where}  {shas}  {url}")

    total = len(found[BEHIND]) + len(found[CURRENT])
    print(f"\n{len(found[BEHIND])} of {total} pinned repositories behind the "
          f"branch head they track, {len(found[CURRENT])} current")
    if excluded:
        print(f"excluded: {excluded[0]} -- neither `url:` nor `commit:`, so "
              "kas resolves it to this repository and there is no pin to "
              "compare")
    print(f"pins read from {', '.join(pin_files)}")
    print("`behind` says the head has moved off the pin, not that the pin is "
          "unsafe; what those commits carry is a separate read. "
          "See docs/layer-currency.md.")

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
