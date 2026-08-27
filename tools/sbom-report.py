#!/usr/bin/env python3
"""Report the SBOM the build emitted: where it is, and how much it describes.

    sbom-report.py check    -- artifacts, SPDX version, and document counts

create-spdx runs on every build -- kiosk-zero-w.yaml names it so that stays true
across an upstream bump -- so unlike the CVE manifest this needs no audit build.
What it does not do is surface what it wrote: the documents land under deploy/
and nothing there says they are present or how many of them there are.

Counts come from the SPDX documents themselves and from the image manifest,
which are two independent statements about the same image. The manifest lists
what was installed; the SPDX tree describes every package built, including the
-dbg and -dev variants no image carries, so the two numbers are expected to
differ and are printed side by side rather than reconciled.

The rolled-up `.spdx.tar.zst` beside the image is reported by path only. Opening
it needs zstd, which is not a build-host prerequisite here, and a report that
refuses to run on a host missing an optional tool is a report nobody runs.

With no build in the tree this says so and exits clean, for the reason
doc-image.py's check does. An SPDX tree that holds no documents is the other
case -- the directory is there and the reading of it failed -- and that refuses
to report a pass.
"""
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# The version directory create-spdx writes under, discovered rather than
# assumed: the name IS the SPDX version, and reading it means a bump to 3.0
# shows up in the report instead of emptying it.
SPDX_ROOT_GLOB = "build/tmp-*/deploy/spdx/*"

# One document per built package, per architecture directory.
PACKAGE_GLOB = "*/packages/*.spdx.json"

# The rolled-up archive beside the image, and the plain-text list of what the
# rootfs actually installed. Both exist twice -- timestamped and symlinked --
# so both are resolved and de-duplicated.
ARCHIVE_GLOB = "build/tmp-*/deploy/images/*/*.spdx.tar.zst"
IMAGE_MANIFEST_GLOB = "build/tmp-*/deploy/images/*/*.manifest"


def repo_top() -> Path:
    return Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                               capture_output=True, text=True,
                               check=True).stdout.strip())


def newest(top: Path, pattern: str):
    """The most recently written match for a glob, or None.

    By mtime, resolved and de-duplicated. The deploy directory is not clamped to
    SOURCE_DATE_EPOCH the way the rootfs is, so a file's own timestamp is the
    build that wrote it. A resolved path that does not exist is a symlink whose
    target was pruned, and is skipped rather than stat'ed."""
    unique = {p.resolve() for p in top.glob(pattern)}
    found = sorted((p for p in unique if p.exists()),
                   key=lambda p: p.stat().st_mtime, reverse=True)
    return found[0] if found else None


def check() -> int:
    top = repo_top()
    root = newest(top, SPDX_ROOT_GLOB)
    if root is None or not root.is_dir():
        # Loud, on stdout, and exit 0: a Yocto build is hours and cannot gate a
        # commit, but a silent skip would read exactly like a clean report.
        print(f"SKIPPED: no SPDX output under {SPDX_ROOT_GLOB} "
              "-- `just build` writes it")
        return 0

    documents = sorted(root.glob(PACKAGE_GLOB))
    if not documents:
        print(f"{root} holds no package documents -- refusing to report a pass",
              file=sys.stderr)
        return 2

    per_arch = {}
    for doc in documents:
        per_arch[doc.parent.parent.name] = per_arch.get(doc.parent.parent.name, 0) + 1
    for arch, n in sorted(per_arch.items()):
        print(f"{n:6d}  {arch}")

    # From a file the build wrote, not from the version directory: a directory's
    # mtime moves only when an entry is added or removed, so an incremental
    # rebuild into the same arch directories would leave it reading weeks old.
    # The roll-up archive is the per-build artifact; the newest package document
    # stands in for a tree whose image task has not run.
    archive = newest(top, ARCHIVE_GLOB)
    stamp = archive or max(documents, key=lambda p: p.stat().st_mtime)
    built = datetime.fromtimestamp(stamp.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
    print(f"\n{len(documents)} SPDX package documents, "
          f"SPDX {root.name}, in {root.relative_to(top)} (built {built})")

    if archive is None:
        # Not a failure: the per-package documents above are the SBOM. The
        # archive is the shippable roll-up of them, and its absence is worth
        # naming rather than passing over.
        print(f"no rolled-up archive under {ARCHIVE_GLOB}")
    else:
        mb = archive.stat().st_size / (1024 * 1024)
        print(f"archive:  {archive.relative_to(top)} ({mb:.1f} MiB, not opened here)")

    manifest = newest(top, IMAGE_MANIFEST_GLOB)
    if manifest is None:
        print(f"no image manifest under {IMAGE_MANIFEST_GLOB}")
    else:
        installed = sum(1 for line in manifest.read_text(errors="replace").splitlines()
                        if line.strip())
        print(f"manifest: {manifest.relative_to(top)} "
              f"({installed} packages installed in the image)")
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "check":
        return check()
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
