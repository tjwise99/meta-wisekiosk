#!/usr/bin/env python3
"""Check the pinned upstream layers against the branch heads they track.

    layer-currency.py check    -- which `commit:` pins upstream has moved past

The pins come from includes/, and each remote is asked directly: no build and no
checkout, network only. See docs/layer-currency.md.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

# Every file carrying a `commit:`. kas merges the repos dictionary across them,
# so they are read as one; see docs/layers-and-kas.md.
PIN_FILES = ("includes/base.yaml",
             "includes/rauc.yaml",
             "includes/platforms/raspberrypi.yaml")

# The branch a repo declaring none inherits, and the file that sets it.
DEFAULTS_FILE = "includes/base.yaml"

# A full object name. A short or symbolic pin is not comparable against what
# ls-remote returns, and comparing it would report `behind` on spelling alone.
SHA = re.compile(r"^[0-9a-f]{40}$")

BEHIND = "behind"
CURRENT = "current"


def repo_top() -> Path:
    return Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                               capture_output=True, text=True,
                               check=True).stdout.strip())


def refuse(message: str) -> int:
    print(f"{message} -- refusing to report a pass", file=sys.stderr)
    return 2


def tail(stream: str, lines: int = 3) -> str:
    return " / ".join(stream.strip().splitlines()[-lines:]) or "(no output)"


def load_pins(top: Path):
    """The repo entries from the pin files, and the branch they default to.

    Merged by name as kas merges them: a later file adding layers to a repo an
    earlier one pinned is one entry, not two. An entry that is not a mapping is
    carried through unmerged, for check() to refuse rather than normalise."""
    repos, default_branch = {}, None
    for name in PIN_FILES:
        doc = yaml.safe_load((top / name).read_text())
        doc = doc if isinstance(doc, dict) else {}
        for repo, entry in (doc.get("repos") or {}).items():
            entry = {} if entry is None else entry
            was = repos.get(repo)
            repos[repo] = ({**was, **entry}
                           if isinstance(was, dict) and isinstance(entry, dict)
                           else entry)
        if name == DEFAULTS_FILE:
            default_branch = (((doc.get("defaults") or {}).get("repos") or {})
                              .get("branch"))
    return repos, default_branch


def ls_remote(url: str, branch: str):
    """The head of one branch at a remote, or a refusal message.

    A hang is not a refusal, so both prompts are closed off: a url that has gone
    private fails instead of blocking. GIT_TERMINAL_PROMPT alone leaves git
    falling back to an SSH_ASKPASS helper, which on a host with a display waits
    on a dialog nobody is watching."""
    ref = f"refs/heads/{branch}"
    run = subprocess.run(["git", "ls-remote", url, ref],
                         capture_output=True, text=True,
                         env={**os.environ, "GIT_TERMINAL_PROMPT": "0",
                              "GIT_ASKPASS": ""})
    if run.returncode != 0:
        return None, (f"`git ls-remote {url} {ref}` failed "
                      f"({run.returncode}): {tail(run.stderr)}")
    fields = run.stdout.split("\n", 1)[0].split()
    if len(fields) != 2 or not SHA.match(fields[0]):
        return None, (f"{url} reports no {ref}, so this pin has no branch to "
                      "be compared against")
    return fields[0], None


def check() -> int:
    top = repo_top()
    missing = [f for f in PIN_FILES if not (top / f).is_file()]
    if missing:
        return refuse(f"{', '.join(missing)} missing, so the pins could not "
                      "be read")

    repos, default_branch = load_pins(top)
    found, excluded = {BEHIND: [], CURRENT: []}, []
    for name, entry in sorted(repos.items()):
        if not isinstance(entry, dict):
            return refuse(f"the {name} entry is not a mapping, so its pin "
                          "could not be read")

        url = entry.get("url")
        if url is None:
            # kas resolves a repo declaring no url to the repository holding
            # the config file, so there is no upstream to ask.
            excluded.append(name)
            continue
        if not isinstance(url, str) or not url.strip():
            return refuse(f"the {name} entry declares a url of {url!r}, which "
                          "is not a remote that can be asked")

        commit = entry.get("commit")
        if not isinstance(commit, str) or not SHA.match(commit):
            return refuse(f"{name} carries no full-length `commit:` pin "
                          f"({commit!r}), so nothing could be compared "
                          f"against {url}")

        explicit = entry.get("branch")
        branch = explicit or default_branch
        if not isinstance(branch, str) or not branch.strip():
            return refuse(f"{name} sets no `branch:` and {DEFAULTS_FILE} sets "
                          "no defaults.repos.branch, so no branch could be "
                          f"resolved for {url}")

        head, why = ls_remote(url, branch)
        if why:
            return refuse(why)
        found[BEHIND if head != commit else CURRENT].append(
            (name, branch, explicit is not None, commit, head, url))

    if not found[BEHIND] and not found[CURRENT]:
        return refuse(f"{', '.join(PIN_FILES)} pin no upstream repository")

    for status in (BEHIND, CURRENT):
        for name, branch, explicit, pin, head, url in found[status]:
            # The branch a repo did not ask for by name is the inference worth
            # seeing: it is what a wrong chain default would hide.
            where = branch if explicit else f"{branch} (chain default)"
            shas = f"{pin} -> {head}" if status == BEHIND else pin
            print(f"{status}  {name}  {where}  {shas}  {url}")

    total = len(found[BEHIND]) + len(found[CURRENT])
    print(f"\n{len(found[BEHIND])} of {total} pinned layers behind the branch "
          f"head they track, {len(found[CURRENT])} current")
    if excluded:
        print(f"excluded: {', '.join(sorted(excluded))} -- no `url:`, so kas "
              "resolves it to this repository and there is no pin to compare")
    print(f"pins read from {', '.join(PIN_FILES)}")
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
