#!/usr/bin/env python3
"""Check what the docs tell you to run against what the image actually ships.

    doc-image.py check                      -- every git-tracked *.md vs the build tree
    doc-image.py snapshot <rootfs> <out>    -- write a snapshot by hand, to inspect

`doc-links.py` proves cross-references resolve; that checks the docs against
themselves. This checks them against the image, which is the failure nothing
else here catches.

The failure it exists for, concretely: a doc prescribed running `fbgrab` on a
device whose image no longer carried it, and nothing compared the two. The case
is at docs/issue_investigation/screenshot_capture_fbgrab/README.md.

Two claim kinds are checked, chosen because both are unambiguous in plain GFM
and need no annotation, frontmatter or generator dialect in the source files:

  1. Commands inside `ssh root@... '...'` invocations, and the same shape
     through the kiosk-ssh.sh wrapper. The image logs in as root, so that
     prefix scopes the check to the running device for free.
  2. Backticked absolute paths under /usr/bin, /usr/sbin, /bin and /sbin.

Deliberately NOT checked: bare commands in fenced blocks (ambiguous -- many run
on the workstation), and paths under /data and /var (created at runtime, absent
from the image by design). Adding those needs a scope marker the source files do
not carry, and guessing produces noise that gets the whole check ignored.

There is no waiver list. A path the image does not carry is either wrong in the
doc or missing from the image, and both are worth fixing; an allowlist only
records that neither was done.

The snapshot is regenerated from the build tree on every run and written under
build/, which is gitignored. A committed snapshot drifts from the image it
claims to describe and nothing notices. With no build tree the check cannot run
at all, and says so loudly rather than passing by default.
"""
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

BIN_DIRS = ("usr/bin", "usr/sbin", "bin", "sbin")
# Kept small on purpose: enough to answer questions the docs actually ask,
# small enough that the snapshot stays reviewable in a diff. /usr/lib/modules
# is excluded -- 1750 .ko files would bury every real change.
PATH_DIRS = ("etc", "usr/lib/systemd/system", "usr/lib/udev/rules.d", "boot")

BIN_PREFIXES = ("/usr/bin/", "/usr/sbin/", "/bin/", "/sbin/")

# Where the regenerated snapshot lands. Under build/, which .gitignore covers,
# so it cannot be committed and cannot drift.
SNAPSHOT_SCRATCH = Path("build/.doc-image-snapshot.json")

# The rootfs bitbake leaves behind for the image this repository builds. Newest
# mtime wins: a machine that has built more than one target has more than one.
ROOTFS_GLOB = "build/tmp-*/work/*/core-image-base/*/rootfs"

# Shell builtins and control words that appear inside ssh '...' but are not
# binaries the image has to carry.
NOT_BINARIES = {
    "if", "then", "else", "elif", "fi", "for", "do", "done", "while", "case",
    "esac", "function", "return", "exit", "set", "unset", "export", "local",
    "read", "eval", "exec", "source", "shift", "trap", "wait", "echo", "cd",
    "test", "true", "false", "printf", "break", "continue", "time", "sudo",
}


def repo_top() -> Path:
    return Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                               capture_output=True, text=True,
                               check=True).stdout.strip())


def tracked_markdown(top: Path):
    listing = subprocess.run(["git", "ls-files", "--", "*.md"], cwd=top,
                             capture_output=True, text=True,
                             check=True).stdout
    return sorted(top / line for line in listing.splitlines() if line)


def build_time(rootfs: Path) -> float:
    """When the rootfs was actually built.

    Not its own mtime: reproducible builds clamp every timestamp inside the
    rootfs to SOURCE_DATE_EPOCH, so the directory reads as 2018 on a build from
    this morning. The recipe workdir above it is not clamped. Take the later of
    the two, so this stays right if a future build stops clamping."""
    return max(rootfs.stat().st_mtime, rootfs.parent.stat().st_mtime)


def find_rootfs(top: Path):
    """The most recently built rootfs under build/, or None if there is none."""
    candidates = sorted(top.glob(ROOTFS_GLOB), key=build_time, reverse=True)
    return candidates[0] if candidates else None


def scan_rootfs(rootfs: Path):
    """(binaries, paths) as the image carries them, or (None, None) if the
    directory holds no binaries -- an empty scan must not read as a pass."""
    binaries, paths = set(), set()
    for d in BIN_DIRS:
        p = rootfs / d
        if p.is_dir():
            binaries.update(f.name for f in p.iterdir())
    for d in PATH_DIRS:
        p = rootfs / d
        if p.is_dir():
            for f in p.rglob("*"):
                paths.add("/" + str(f.relative_to(rootfs)))
    if not binaries:
        return None, None
    return binaries, paths


def snapshot(rootfs: Path, out: Path) -> int:
    if not rootfs.is_dir():
        print(f"not a directory: {rootfs}", file=sys.stderr)
        return 2
    binaries, paths = scan_rootfs(rootfs)
    if binaries is None:
        print(f"no binaries found under {rootfs} -- wrong directory?", file=sys.stderr)
        return 2
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps({
            "rootfs": str(rootfs),
            "binaries": sorted(binaries),
            "paths": sorted(paths),
        }, indent=1) + "\n")
    except OSError as e:
        print(f"cannot write {out}: {e}", file=sys.stderr)
        return 2
    print(f"{out}: {len(binaries)} binaries, {len(paths)} paths")
    return 0


# `ssh root@host '<script>'` and the two forms the docs actually use for it: the
# kiosk-ssh.sh wrapper, which is how this repo tells you to reach the device, and
# a double-quoted script. Matching only bare ssh with single quotes made the
# whole check inert -- every device command in the tracked docs was in one of the
# forms it could not see.
SSH_INVOCATION = re.compile(
    r"""(?:(?:[\w./-]*/)?kiosk-ssh\.sh|ssh)\s+(?:-\S+\s+)*root@\S+\s+"""
    r"""(?:'([^']*)'|"([^"]*)")""", re.S)


def ssh_commands(text):
    """Commands invoked through `ssh root@... '<script>'`. Yields (cmd, line)."""
    for m in SSH_INVOCATION.finditer(text):
        line = text[:m.start()].count("\n") + 1
        script = m.group(1) if m.group(1) is not None else m.group(2)
        # Split on shell separators, then take the leading word of each piece.
        for piece in re.split(r"[;&|]+|\$\(|\n", script):
            piece = piece.strip()
            if not piece:
                continue
            word = piece.split()[0]
            if word.startswith(("-", "$", "#", '"')):
                continue
            if "=" in word and not word.startswith("/"):
                continue
            name = word.rsplit("/", 1)[-1]
            if name and name not in NOT_BINARIES and re.fullmatch(r"[A-Za-z0-9_.-]+", name):
                yield name, line


def binary_paths(text):
    """Backticked absolute paths under a bin directory. Yields (path, line)."""
    for m in re.finditer(r"`(/[A-Za-z0-9_./@%+-]+)`", text):
        p = m.group(1)
        if p.startswith(BIN_PREFIXES) and not p.endswith("/"):
            yield p, text[:m.start()].count("\n") + 1


def check() -> int:
    top = repo_top()
    rootfs = find_rootfs(top)
    if rootfs is None:
        # Loud, on stdout, and exit 0. A Yocto build is hours and cannot gate a
        # commit, so the absence of one must not fail anything -- but silence
        # here would be indistinguishable from a clean run, which is the exact
        # failure this whole script exists to prevent.
        print("SKIPPED: no build rootfs under "
              f"{ROOTFS_GLOB} -- doc-image check did not run")
        return 0

    binaries, paths = scan_rootfs(rootfs)
    if binaries is None:
        print(f"rootfs at {rootfs} carries no binaries -- refusing to report a pass",
              file=sys.stderr)
        return 2
    rc = snapshot(rootfs, top / SNAPSHOT_SCRATCH)
    if rc:
        return rc

    docs = tracked_markdown(top)
    if not docs:
        print("no git-tracked Markdown files -- discovery is broken, not the docs",
              file=sys.stderr)
        return 2

    findings, examined = [], 0
    for md in docs:
        text = md.read_text(errors="replace")
        rel = md.relative_to(top)
        for name, line in ssh_commands(text):
            examined += 1
            if name in binaries:
                continue
            findings.append((f"{rel}:{line}", f"ssh root@ runs `{name}`", "not in image"))
        for p, line in binary_paths(text):
            examined += 1
            # By basename, against the bin scan. binary_paths yields only
            # BIN_PREFIXES paths and PATH_DIRS holds no bin directory, so
            # `paths` can never carry one of these.
            if p.rsplit("/", 1)[-1] in binaries:
                continue
            findings.append((f"{rel}:{line}", f"names `{p}`", "not in image"))

    seen, unique = set(), []
    for f in findings:
        if f[1:] not in seen:
            seen.add(f[1:])
            unique.append(f)

    for loc, what, why in unique:
        print(f"{loc}  {what} -- {why}")
    # `examined` is reported because a silent extraction failure and a clean
    # pass are otherwise the same output: both print zero findings.
    # The build time is printed because a months-old rootfs compares clean
    # against today's prose, and that drift is what the check exists to catch.
    built = datetime.fromtimestamp(build_time(rootfs)).strftime("%Y-%m-%d %H:%M")
    print(f"\n{len(unique)} unresolved, {examined} claims examined "
          f"against {len(binaries)} binaries in {rootfs} (built {built})")
    if not examined:
        # Two causes, indistinguishable from here: the docs genuinely name no
        # device binary, or the extraction regexes stopped matching. The first
        # is the expected state of a tree whose facts live in code comments,
        # which this script does not scan -- failing on it would make the gate
        # permanently red and get it deleted. So report inertness in the one
        # place a reader is already looking, and do not claim a pass.
        print(f"NO CLAIMS: {len(docs)} files carry no `ssh root@` or `kiosk-ssh.sh "
              "root@` command and no backticked /usr/bin path -- this check is "
              "inert, verify the extraction before trusting it")
    return 1 if unique else 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "check":
        return check()
    if len(sys.argv) == 4 and sys.argv[1] == "snapshot":
        return snapshot(Path(sys.argv[2]), Path(sys.argv[3]))
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
