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

Self-test: bash .claude/hooks/guard-memory-hygiene-test.sh  (`just guards`, CI)
"""
import json
import os
import re
import sys

# Agent memory lives OUTSIDE the repository, at ~/.claude/projects/<slug>/memory/,
# so the match is on the absolute path the harness passes and never on a
# repo-relative one. `local/` is the gitignored working-note tree inside it.
MEMORY = re.compile(r"/\.claude/projects/.*/memory/.*\.md$")
LOCAL = re.compile(r"(?:^|/)local/.*\.md$")

# A ticket reference anywhere on the line. Status narration names its ticket;
# a durable rule speaks of "a PR" or "such a PR" and names none, which is the
# whole separation this hook rests on.
TICKET = re.compile(r"#\d+\b")

# Status jargon: vocabulary that exists only to record where a ticket currently
# sits. Flagged when the line also names a ticket.
JARGON = re.compile(
    r"un-?merged"
    r"|merge-?ready"
    r"|mergeable"
    r"|awaiting\s+owner"
    r"|ready\s+to\s+merge"
    r"|still\s+(?:open|blocked)"
    r"|blocked[_\s-]by\s+#?\d+",
    re.I,
)

# `merged`, `closed`, `open` and `draft` are ordinary English, so proximity is
# not enough -- "PR #40 ... closed no issue" is history in a legal lesson. The
# tell is the label shape: the status word bound directly to the number.
LABEL = re.compile(
    r"#\d+\s*\(?\s*(?:is|was|now|still|remains)?\s*(?:not\s+)?"
    r"(?:merged|closed|open|draft|mergeable|merge-?ready)\b",
    re.I,
)

# The same words shouted are a LABEL, not prose -- `#47 template MERGED` puts a
# word between the number and the status and walks past LABEL, and that spelling
# is as common in a status roll-up as the tight one. Case-sensitive, and still
# requires a ticket on the line.
CAPS_STATUS = re.compile(r"\b(?:MERGED|CLOSED|MERGEABLE|MERGE-?READY|DRAFT|UN-?MERGED)\b")

# A dated status block header is unambiguous on its own -- nothing durable is
# stamped with the day it was true.
STATUS_HEADER = re.compile(r"\bSTATUS\s+20\d\d\b")

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
    parts = [tool_input.get("content") or "", tool_input.get("new_string") or ""]
    for edit in tool_input.get("edits") or []:
        if isinstance(edit, dict):
            parts.append(edit.get("new_string") or "")
    return "\n".join(p for p in parts if p)


def findings(text: str):
    """Offending lines, scanned per line: status narration is a line, and a
    ticket on one line has no bearing on a status word three paragraphs down."""
    hits = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if STATUS_HEADER.search(stripped) or LABEL.search(stripped):
            hits.append(stripped)
        elif TICKET.search(stripped) and (JARGON.search(stripped)
                                          or CAPS_STATUS.search(stripped)):
            hits.append(stripped)
    return hits


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0  # fail-open: never interfere on a parse error
    if data.get("tool_name") not in ("Write", "Edit", "MultiEdit"):
        return 0
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path") or ""
    if not (MEMORY.search(path) or LOCAL.search(path)):
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
    reason = MESSAGE.format(path=path, evidence=evidence)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": reason,
        }
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
