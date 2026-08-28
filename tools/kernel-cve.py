#!/usr/bin/env python3
"""Re-judge the kernel's CVE findings against the sources this config compiles.

    kernel-cve.py check [--datadir DIR]

cve-check scores the kernel against the whole Linux source tree; a Zero W config
compiles a fraction of it. poky ships the filter and this drives it, against the
kernel CNA's own vulns database.

Refuses rather than reports when the filter had nothing to filter on: an SPDX
document written without SPDX_INCLUDE_COMPILED_SOURCES yields zero compiled
files, and the filter then runs to completion, exits clean and returns every
finding unchanged. See docs/cve-and-sbom.md.
"""
import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

# poky's own script. Pinned with the rest of the tree, so its behaviour moves
# only when the poky pin does.
FILTER = "sources/poky/scripts/contrib/improve_kernel_cve_report.py"

# cve-check's JSON summary. The text manifest beside the image carries the same
# findings, but the filter reads and rewrites this form.
SUMMARY_GLOB = "build/tmp-*/log/cve/cve-summary.json"

# The kernel recipe's SPDX document, under the SAME tmp tree as the summary: a
# host that has built for two machines has two, and crossing them would filter
# one board's findings by another board's compiled sources.
SPDX_GLOB = "deploy/spdx/*/*/recipes/recipe-{pn}.spdx.json"

# Local-only, like the Grype database and the CVE history beside it. 485 MB and
# ~15k CVE records, none of it a build input.
DATADIR = Path.home() / ".cache/wisekiosk/linux-vulns"
OUTPUT = Path.home() / ".cache/wisekiosk/kernel-cve-summary.json"

KERNEL_PRODUCT = "linux_kernel"
NOT_COMPILED = "not-applicable-config"

# The filter's own count of what it read, which is the number that decides
# whether it filtered anything. Absent means it did not get that far.
COMPILED_LOG = re.compile(r"Total compiled files (\d+)")

# PV as cve-check writes it -- EXTENDPE + PV, e.g. `1_6.6.63+git`. The filter
# parses this with packaging.Version, which rejects both affixes outright.
PV = re.compile(r"^(?:\d+_)?(\d+(?:\.\d+)*)")


def repo_top() -> Path:
    return Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                               capture_output=True, text=True,
                               check=True).stdout.strip())


def refuse(message: str) -> int:
    print(f"{message} -- refusing to report a pass", file=sys.stderr)
    return 2


def compiled_sources(spdx: dict) -> set:
    """The source files an SPDX document says were compiled.

    Mirrors the filter's own read_spdx2/read_spdx3 selection, so the count this
    refuses on is the count the filter will act on. The leading path component
    is the package directory and is dropped, because the CNA names files
    relative to the kernel tree root."""
    if spdx.get("spdxVersion") == "SPDX-2.2":
        return {f["fileName"][f["fileName"].find("/") + 1:]
                for f in spdx.get("files", ())
                if "SOURCE" in f.get("fileTypes", ())}
    return {i["name"][i["name"].find("/") + 1:] for i in spdx.get("@graph", ())
            if i.get("software_primaryPurpose") == "source"}


def upstream_version(raw: str) -> str:
    """`1_6.6.63+git` -> `6.6.63`, or "" where no version is readable."""
    found = PV.match(raw.split("-")[0])
    return found.group(1) if found else ""


def kernel_package(summary: dict):
    """The one recipe in the summary that cve-check maps to the Linux kernel."""
    return next((p for p in summary.get("package", ())
                 if any(v.get("product") == KERNEL_PRODUCT
                        for v in p.get("products", ()))), None)


def newest(paths):
    found = sorted({p.resolve() for p in paths if p.is_file()},
                   key=lambda p: p.stat().st_mtime, reverse=True)
    return found[0] if found else None


def statuses(package: dict) -> Counter:
    return Counter(i.get("status", "(none)") for i in package.get("issue", ()))


def tally(counted: Counter) -> str:
    return ", ".join(f"{n} {s}" for s, n in sorted(counted.items()))


def check(argv=()) -> int:
    datadir = DATADIR
    rest = list(argv)
    while rest:
        flag = rest.pop(0)
        if flag != "--datadir":
            return refuse(f"{flag!r} is not an option this reads")
        if not rest:
            return refuse("--datadir takes a value")
        datadir = Path(rest.pop(0)).expanduser()

    top = repo_top()
    script = top / FILTER
    if not script.is_file():
        print(f"SKIPPED: no {FILTER} -- sources/ is not checked out")
        return 0

    summary = newest(top.glob(SUMMARY_GLOB))
    if summary is None:
        # cve-check is opt-in, so no summary is the expected state of a tree
        # that has not run an audit build, not a fault.
        print(f"SKIPPED: no CVE summary under {SUMMARY_GLOB} "
              "-- `just cve-build` writes it")
        return 0

    if not any(datadir.glob("**/CVE-*.json")):
        return refuse(
            f"{datadir} holds no CVE-*.json records; clone the kernel CNA "
            "database with\n  git clone --depth=1 "
            "https://git.kernel.org/pub/scm/linux/security/vulns.git "
            f"{datadir}")

    try:
        report = json.loads(summary.read_text(encoding="ISO-8859-1"))
    except (json.JSONDecodeError, OSError) as exc:
        return refuse(f"{summary.name}: {exc}")

    kernel = kernel_package(report)
    if kernel is None:
        return refuse(f"{summary.name} maps no recipe to {KERNEL_PRODUCT}")

    version = upstream_version(kernel.get("version", ""))
    if not version:
        return refuse(f"no version readable from {kernel.get('version')!r}")

    spdx_path = newest((summary.parents[2]).glob(
        SPDX_GLOB.format(pn=kernel["name"])))
    if spdx_path is None:
        return refuse(f"no SPDX document for {kernel['name']} under "
                      f"{summary.parents[2]}/deploy/spdx")

    try:
        files = compiled_sources(json.loads(
            spdx_path.read_text(encoding="ISO-8859-1")))
    except (json.JSONDecodeError, OSError, KeyError) as exc:
        return refuse(f"{spdx_path.name}: {exc}")

    # The whole point of the gate. Without compiled sources the filter returns
    # every finding unchanged and exits 0, which reads exactly like a filter
    # that found nothing to remove.
    if not files:
        return refuse(
            f"{spdx_path.name} lists no compiled sources, so the filter would "
            "measure nothing; the audit build must set "
            f"SPDX_INCLUDE_COMPILED_SOURCES:pn-{kernel['name']} (it is in "
            "includes/cve-audit.yaml) and a build that predates the flag "
            "cannot supply it from sstate")

    # The filter parses the version with packaging.Version, which rejects
    # cve-check's `1_6.6.63+git` outright. It reads the version from the report,
    # so the normalisation has to happen in a copy of the report.
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    normalised = OUTPUT.with_name("kernel-cve-input.json")
    kernel_in = dict(kernel, version=version)
    normalised.write_text(json.dumps(
        dict(report, package=[kernel_in if p is kernel else p
                              for p in report["package"]])),
        encoding="ISO-8859-1")

    run = subprocess.run(
        [sys.executable, str(script), "--spdx", str(spdx_path),
         "--datadir", str(datadir), "--old-cve-report", str(normalised),
         "--new-cve-report", str(OUTPUT)],
        capture_output=True, text=True,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    if run.returncode != 0:
        detail = (run.stderr or run.stdout).strip().splitlines()
        return refuse(f"{Path(FILTER).name} exited {run.returncode}: "
                      + (detail[-1] if detail else "no output"))

    # The filter's own measurement of what it read, cross-checked against this
    # reader's. Two readers of one document agreeing is what makes the count
    # trustworthy; a disagreement means they select different files and the
    # refusal above is guarding the wrong number.
    logged = COMPILED_LOG.search(run.stderr or "")
    if logged is None:
        return refuse(f"{Path(FILTER).name} did not report how many compiled "
                      "files it read, so the filter is unmeasured")
    if int(logged.group(1)) != len(files):
        return refuse(f"{Path(FILTER).name} read {logged.group(1)} compiled "
                      f"files where this reader counts {len(files)}")

    try:
        after = kernel_package(json.loads(
            OUTPUT.read_text(encoding="ISO-8859-1")))
    except (json.JSONDecodeError, OSError) as exc:
        return refuse(f"{OUTPUT.name}: {exc}")
    if after is None:
        return refuse(f"{OUTPUT.name} maps no recipe to {KERNEL_PRODUCT}")

    was, now = statuses(kernel), statuses(after)
    dropped = sum(1 for i in after.get("issue", ())
                  if i.get("detail") == NOT_COMPILED)

    print(f"kernel:   {kernel['name']} {version} "
          f"(cve-check wrote {kernel.get('version')!r})")
    print(f"compiled: {len(files)} source files, agreed by both readers")
    print(f"before:   {tally(was)}")
    print(f"after:    {tally(now)}")
    print(f"filtered: {dropped} findings the config does not compile")

    # The filter re-judges every kernel CVE against the CNA record, so the
    # change in Unpatched is not the compiled-sources yield alone. `filtered`
    # above is that yield; this line is the whole effect.
    print(f"net:      {was.get('Unpatched', 0)} -> {now.get('Unpatched', 0)} "
          "Unpatched, from the compiled-sources filter AND the CNA re-judgement")
    print(f"report:   {OUTPUT}")
    print(f"summary:  {summary.relative_to(top)}")
    print(f"spdx:     {spdx_path.relative_to(top)}")

    # Reports, never gates: exit 0 with findings, like the rest of the audit
    # group. A nonzero exit is reserved for a report that cannot be trusted.
    return 0


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "check":
        return check(sys.argv[2:])
    print("\n\n".join(__doc__.strip().split("\n\n")[:2]), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
