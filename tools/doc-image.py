#!/usr/bin/env python3
"""Check what the docs tell you to run against what the image actually ships.

    doc-image.py snapshot <rootfs-dir> <out.json>
    doc-image.py check <docs-dir> <snapshot.json> [waivers.txt]

`doc-facts.py` proves a restructure loses no facts and `doc-links.py` proves
cross-references resolve; both check the docs against themselves. This checks
them against the image, which is the failure nothing else here catches.

The failure it exists for, concretely: `fbgrab` was dropped from IMAGE_INSTALL
on 2026-08-11 00:19 because a white PNG was read as a broken capture path. The
diagnosis was overturned 20 hours later -- fbgrab wrote correct RGB with a zero
alpha channel, and the reader was wrong -- but the correction landed only in the
docs. Recipe 9 was then written prescribing a binary the image no longer had,
and `tools/fbgrab-fix.py` stayed in the tree to repair its output. Nothing
compared the two, so nothing said so.

Two claim kinds are checked, chosen because both are unambiguous in plain GFM
and need no annotation, frontmatter or generator dialect in the source files:

  1. Commands inside `ssh root@... '...'` invocations. The Yocto image logs in
     as root; the Raspbian card used `pi@` and sudo. That distinction already
     exists in the prose, so it scopes the check to the running image for free.
  2. Backticked absolute paths under /usr/bin, /usr/sbin, /bin and /sbin.

Deliberately NOT checked: bare commands in fenced blocks (ambiguous -- many run
on the workstation), and paths under /data and /var (created at runtime, absent
from the image by design). Adding those needs a scope marker the source files do
not carry, and guessing produces noise that gets the whole check ignored.

A waiver file records paths that are legitimately absent, one per line, with the
reason after a `#`. The point of the waiver is not to silence the check but to
make the next contributor meet an argument instead of a gap.
"""
import json
import re
import sys
from pathlib import Path

BIN_DIRS = ("usr/bin", "usr/sbin", "bin", "sbin")
# Kept small on purpose: enough to answer questions the docs actually ask,
# small enough that the snapshot stays reviewable in a diff. /usr/lib/modules
# is excluded -- 1750 .ko files would bury every real change.
PATH_DIRS = ("etc", "usr/lib/systemd/system", "usr/lib/udev/rules.d", "boot")

BIN_PREFIXES = ("/usr/bin/", "/usr/sbin/", "/bin/", "/sbin/")

# Shell builtins and control words that appear inside ssh '...' but are not
# binaries the image has to carry.
NOT_BINARIES = {
    "if", "then", "else", "elif", "fi", "for", "do", "done", "while", "case",
    "esac", "function", "return", "exit", "set", "unset", "export", "local",
    "read", "eval", "exec", "source", "shift", "trap", "wait", "echo", "cd",
    "test", "true", "false", "printf", "break", "continue", "time", "sudo",
}


def snapshot(rootfs: Path, out: Path) -> int:
    if not rootfs.is_dir():
        print(f"not a directory: {rootfs}", file=sys.stderr)
        return 2
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
        print(f"no binaries found under {rootfs} -- wrong directory?", file=sys.stderr)
        return 2
    out.write_text(json.dumps({
        "rootfs": str(rootfs),
        "binaries": sorted(binaries),
        "paths": sorted(paths),
    }, indent=1) + "\n")
    print(f"{out}: {len(binaries)} binaries, {len(paths)} paths")
    return 0


def load_waivers(path):
    waived = {}
    if path and Path(path).exists():
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, _, reason = line.partition("#")
            waived[name.strip()] = reason.strip()
    return waived


def ssh_commands(text):
    """Commands invoked through `ssh root@... '<script>'`. Yields (cmd, line)."""
    for m in re.finditer(r"ssh\s+(?:-\S+\s+)*root@\S+\s+'([^']*)'", text, re.S):
        line = text[:m.start()].count("\n") + 1
        script = m.group(1)
        # Split on shell separators, then take the leading word of each piece.
        for piece in re.split(r"[;&|]+|\$\(|\n", script):
            piece = piece.strip()
            if not piece:
                continue
            word = piece.split()[0]
            if word.startswith(("/", "-", "$", "#", '"')) and not word.startswith("/"):
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


def check(docs: Path, snap_path: Path, waivers_path=None) -> int:
    snap = json.loads(snap_path.read_text())
    binaries, paths = set(snap["binaries"]), set(snap["paths"])
    if not binaries:
        print("snapshot carries no binaries -- refusing to report a pass",
              file=sys.stderr)
        return 2
    waived = load_waivers(waivers_path)
    findings, waived_hits, examined = [], 0, 0

    for md in sorted(docs.rglob("*.md")):
        if any(part in {".git", "node_modules"} for part in md.parts):
            continue
        text = md.read_text(errors="replace")
        rel = md.relative_to(docs)
        for name, line in ssh_commands(text):
            examined += 1
            if name in binaries:
                continue
            if name in waived:
                waived_hits += 1
                continue
            findings.append((f"{rel}:{line}", f"ssh root@ runs `{name}`", "not in image"))
        for p, line in binary_paths(text):
            examined += 1
            if p in paths or p.rsplit("/", 1)[-1] in binaries:
                continue
            if p in waived:
                waived_hits += 1
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
    print(f"\n{len(unique)} unwaived, {waived_hits} waived, "
          f"{examined} claims examined against {len(binaries)} binaries")
    if not examined:
        print("examined no claims at all -- extraction is broken, not the docs",
              file=sys.stderr)
        return 2
    return 1 if unique else 0


def main() -> int:
    if len(sys.argv) >= 4 and sys.argv[1] == "snapshot":
        return snapshot(Path(sys.argv[2]), Path(sys.argv[3]))
    if len(sys.argv) >= 4 and sys.argv[1] == "check":
        return check(Path(sys.argv[2]), Path(sys.argv[3]),
                     sys.argv[4] if len(sys.argv) > 4 else None)
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
