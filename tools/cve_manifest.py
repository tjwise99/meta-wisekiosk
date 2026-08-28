"""The CVE manifest parser, shared by every tool that reads one.

A module, not a command: `cve-report.py`, `cve-delta.py`, `cve-scan.py` and
`layer-currency.py` all read the `.cve` manifest an audit build leaves behind,
and four copies of this drifted into three different behaviours on the same
malformed input -- one refusing loudly, one truncating silently, one yielding a
phantom record. Underscored so it can be imported; the tools stay hyphenated.

See docs/cve-and-sbom.md.
"""
import re

# Every record opens with this key; the fields after it are order-independent.
RECORD_START = "LAYER"

LAYER = "LAYER"
PACKAGE = "PACKAGE NAME"
VERSION = "PACKAGE VERSION"
CVE = "CVE"
STATUS = "CVE STATUS"

# Why a finding was called Patched or Ignored -- cpe-incorrect, disputed,
# upstream-wontfix and the rest.
DETAIL = "CVE DETAIL"

UNPATCHED = "Unpatched"

# `KEY: value`; the value may hold colons (MORE INFORMATION is a URL).
FIELD = re.compile(r"^([A-Z][A-Za-z0-9 ]*):[ ]?(.*)$")

# The keys the regex cannot tell from free NVD prose: a kernel stable-commit
# trailer inside CVE SUMMARY spells `CVE: CVE-...` and reads as one.
# cve-check.bbclass writes all six once and BEFORE the only free-prose fields
# (CVE DESCRIPTION, CVE SUMMARY), so prose can only ever be a later occurrence
# and the first write is provably the record's own value.
#
# DETAIL is reserved with the five identity keys because it is load-bearing:
# cve-delta reads it to tell a ruling we shipped from the feed moving, and
# cve-report prints the judgement histogram from it.
RESERVED = (LAYER, PACKAGE, VERSION, CVE, STATUS, DETAIL)

# The keys every record must carry. DETAIL is reserved but optional -- only a
# Patched or Ignored finding has a reason.
REQUIRED = (LAYER, PACKAGE, VERSION, CVE, STATUS)


class ManifestError(Exception):
    """A manifest line that cannot be attributed to a record."""


def complete(rec):
    """One record, checked for the keys that identify it.

    A prose line starting `LAYER:` splits a record in two rather than
    overwriting a key, so the repeat check cannot see it; the halves it leaves
    are short of the other required keys, which this can."""
    missing = [k for k in REQUIRED if k not in rec]
    if missing:
        raise ManifestError(
            f"a record carries no {', '.join(missing)} (it names "
            f"{rec.get(CVE) or rec.get(PACKAGE) or 'nothing'}), so free CVE "
            "prose has been read as the start of a record")
    return rec


def records(text, hijacks=None):
    """The manifest's `KEY: value` blocks, as dicts.

    Split on the LAYER key, not on blank lines: CVE SUMMARY and CVE DESCRIPTION
    are free NVD prose and may carry one. A reserved key repeated inside a
    record keeps its first value and appends a description of the repair to
    `hijacks`; a record short of a required key cannot be repaired and raises
    ManifestError."""
    rec = None
    for line in text.splitlines():
        m = FIELD.match(line)
        if not m:
            continue
        key, value = m.group(1), m.group(2)
        if key == RECORD_START:
            if rec is not None:
                yield complete(rec)
            rec = {}
        if rec is None:
            continue
        if key in RESERVED and key in rec:
            if rec[key] != value and hijacks is not None:
                hijacks.append(f"{rec.get(PACKAGE, '?')} {rec.get(CVE, '?')}: "
                               f"prose {key} {value!r} ignored for {rec[key]!r}")
            continue
        rec[key] = value
    if rec is not None:
        yield complete(rec)


def report_hijacks(hijacks, prefix="parsed:"):
    """Print each repair the parse made. Every tool reading a manifest calls
    this: a repair only one of them mentions is a silent one everywhere else."""
    for note in hijacks:
        print(f"{prefix}   {note}")
