#!/usr/bin/env python3
"""PreToolUse ask-gate on writes to agent memory and gitignored `local/` notes.

PR and issue STATUS is the GitHub tracker's. A memory or a working note holds
owner rules and durable lessons; the moment it also carries "PR #N is
merge-ready, un-merged" it is a second, unsynchronised copy of state that a
merge silently falsifies, and the next reader trusts the stale copy.

Surfaces as `ask`, never a block: a durable rule about PR hygiene has to be
able to quote the vocabulary it rules on, and only the human can tell that
apart from narration. Every other path is silent — this hook exists for two
directories and is invisible everywhere else.

The jargon list is the vocabulary this store's own handoffs used. It catches
those spellings; it is not a general detector of status, and a phrasing outside
the list passes.

Self-test: bash .claude/hooks/guard-memory-hygiene-test.sh  (`just guards`, CI)
"""
import json
import os
import re
import sys


def relative(path: str) -> str:
    """Repo-relative form of the edited path, as guard-design-surfaces.py does.

    A path that is already relative is already repo-relative and is returned
    untouched -- resolving it against the process cwd would aim it somewhere
    else entirely. `CLAUDE_PROJECT_DIR` is set by the same settings.json entry
    that locates this file, so an absolute path always has a root to subtract.
    """
    if not os.path.isabs(path):
        return path
    root = os.environ.get("CLAUDE_PROJECT_DIR")
    if not root:
        return path
    try:
        return os.path.relpath(path, os.path.abspath(root))
    except ValueError:
        return path


# Agent memory lives OUTSIDE the repository, at ~/.claude/projects/<slug>/memory/,
# so it is matched on the path as given. Anchored to accept a relative spelling
# too: the harness passes absolute paths, and a guard that goes silent on the
# shape it did not expect fails open.
MEMORY = re.compile(r"(?:^|/)\.claude/projects/.*/memory/.*\.md$", re.I)

# `local/` is the repository's own gitignored working-note tree, so it is matched
# against the REPO-RELATIVE path and anchored at the root, exactly as .gitignore
# spells it. An unanchored `/local/` would take in `/usr/local/share/doc/*.md`,
# a vendored `node_modules/*/local/`, and a `docs/local/` a contributor adds for
# localisation -- none of them agent notes.
LOCAL = re.compile(r"^local/.*\.md$", re.I)

# Status narration names its ticket; a durable rule speaks of "a PR" or "such a
# PR" and names none, which is the whole separation this hook rests on. A PR
# referenced by URL is named just as specifically as one referenced by number.
TICKET = re.compile(r"#\d+\b|/(?:pull|issues)/\d+\b")

# How far a ticket may sit from a lowercase status tell and still be bound to
# it. A line is not a unit of meaning -- the same durable memory reflowed to one
# long line puts "PR #40 ... presented as mergeable" together, and a line-wide
# test turns a legal lesson into a finding on nothing but its wrapping.
#
# CAPS_STATUS is exempt and searches the whole line: a shouted status word is a
# label wherever it sits, never the mid-sentence prose a rule is written in.
NEAR = 40

# Status jargon: vocabulary that exists only to record where a ticket sits.
JARGON = re.compile(
    r"un-?merged"
    r"|merge-?ready"
    r"|mergeable"
    r"|awaiting\s+(?:owner|review|merge|sign-?off)"
    r"|pending\s+(?:merge|review|sign-?off)"
    r"|ready\s+to\s+merge"
    r"|no\s+merge\s+yet"
    r"|still\s+(?:open|blocked|pending|in\s+draft|a\s+draft)"
    r"|not\s+(?:yet\s+)?(?:been\s+)?merged"
    r"|blocked[_\s-]by\s+#?\d+",
    re.I,
)

# `merged`, `closed`, `open` and `draft` are ordinary English, and `merged` and
# `closed` are TERMINAL -- a merge cannot be falsified by a later merge, so
# "shipped in PR #51, merged 2026-08-26" is durable history, not status. The
# tell is therefore the label shape: the status bound to the number by table
# furniture or a copula and nothing else. The separator admits no word character
# and no sentence punctuation -- neither `,` nor `.`, because both join clauses
# in ordinary prose, and admitting them makes every citation a finding.
LABEL = re.compile(
    r"#\d+[\s|*_:()\[\]<>—–-]*"
    r"(?:(?:is|was|now|still|remains|has|have|had)[\s|*_]+)?"
    r"(?:not\s+(?:yet\s+)?(?:been\s+)?)?"
    r"(?:merged|closed|open|draft|mergeable|merge-?ready)\b",
    re.I,
)

# The same words shouted are a label wherever they sit, so a word may stand
# between them and the number -- `#47 template MERGED`. Case-sensitive, and
# still requires a ticket on the line. OPEN and BLOCKED belong here as much as
# MERGED: they are the halves of a roll-up that actually rot.
CAPS_STATUS = re.compile(
    r"\b(?:MERGED|CLOSED|OPEN|BLOCKED|DRAFT|MERGEABLE|MERGE-?READY|UN-?MERGED"
    r"|IN\s+REVIEW)\b"
)

# A dated status block header is unambiguous on its own -- nothing durable is
# stamped with the day it was true.
STATUS_HEADER = re.compile(r"\bSTATUS\s+20\d\d\b")

# Text being QUOTED is being mentioned, not asserted. A concrete owner rule is
# written `never put "PR #83 is MERGEABLE" in a memory`, and that is the useful
# form -- flagging it would fire the gate on the very lesson this hook teaches.
QUOTED = re.compile(r"`[^`]*`|\"[^\"]*\"")

FENCE = re.compile(r"^\s*(?:```|~~~)")

MESSAGE = (
    "TICKET HYGIENE — {path} reads like PR/issue STATUS: {evidence}\n"
    "Status belongs on the GitHub ticket as a comment, where the next reader is already "
    "looking and where a merge updates it. Memory and `local/` hold owner rules and durable "
    "lessons ONLY; a status line here becomes a second copy that nothing keeps true, and the "
    "stale copy is the one that gets acted on.\n"
    "Approve only if this is a durable rule or lesson that merely CITES a ticket "
    "(\"the reproducibility gate shipped in PR #51\"). If it records where a ticket stands "
    "today, put it on the ticket instead."
)


def text_of(tool_input: dict) -> str:
    """The text this call would write, whichever edit shape carried it."""
    parts = [tool_input.get("content"), tool_input.get("new_string")]
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        parts += [e.get("new_string") for e in edits if isinstance(e, dict)]
    return "\n".join(p for p in parts if isinstance(p, str) and p)


def bound(line: str, tell) -> bool:
    """Does a ticket sit within NEAR characters of a match of `tell`?

    The gap is measured between nearest edges, so it is the prose actually
    standing between them and is unaffected by how the file is wrapped.
    """
    tickets = [m.span() for m in TICKET.finditer(line)]
    if not tickets:
        return False
    for m in tell.finditer(line):
        a, b = m.span()
        for c, d in tickets:
            if max(a - d, c - b, 0) <= NEAR:
                return True
    return False


def scannable(line: str) -> str:
    """The line with quoted spans blanked, length preserved so NEAR is unmoved."""
    return QUOTED.sub(lambda m: " " * (m.end() - m.start()), line)


def findings(text: str):
    """Offending lines. A line bounds the search but does not decide it: LABEL
    is adjacency-bound by its own pattern, and the looser tells must clear
    `bound`. A fenced block is captured output, not an assertion about a ticket.
    """
    hits, fenced = [], False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
            continue
        if fenced:
            continue
        stripped = line.strip()
        if not stripped:
            continue
        probe = scannable(stripped)
        if (STATUS_HEADER.search(probe)
                or LABEL.search(probe)
                or bound(probe, JARGON)
                or (TICKET.search(probe) and CAPS_STATUS.search(probe))):
            hits.append(stripped)
    return hits


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") not in ("Write", "Edit", "MultiEdit"):
        return 0
    tool_input = data.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0
    path = tool_input.get("file_path")
    if not isinstance(path, str):
        return 0
    if not (MEMORY.search(path) or LOCAL.search(relative(path))):
        return 0
    # In scope. Announce it under KIOSK_HOOK_TRACE so the self-test can tell a
    # clean scan from a path the hook never looked at -- silence means both, and
    # a scoping regression would read as a suite of passing cases.
    if os.environ.get("KIOSK_HOOK_TRACE"):
        sys.stderr.write(f"memory-hygiene: scanned {path}\n")
    hits = findings(text_of(tool_input))
    if not hits:
        return 0
    evidence = "; ".join(f'"{h[:120]}"' for h in hits[:3])
    if len(hits) > 3:
        evidence += f" (+{len(hits) - 3} more)"
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": MESSAGE.format(path=path, evidence=evidence),
        }
    }))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Fail-open on ANY malformed payload, not only one that fails to parse:
        # a hook that dies mid-decision is a hook nobody keeps installed.
        sys.exit(0)
