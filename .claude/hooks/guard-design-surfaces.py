#!/usr/bin/env python3
"""PreToolUse self-check on Edit/Write/MultiEdit.

Not a permission gate and not a hard block — it injects a reminder into the acting
model's own context (main loop or subagent) at the moment a generated artifact or a
design surface is touched, so the question always fires and can never be silently
skipped. The model answers it and only bubbles up to the owner when the answer is
"this doesn't fit". Ordinary recipes, tooling and prose are silent.

Blocking belongs to `.claude/hooks/guard.sh`, which gates irreversible device and
disk operations. Nothing here is irreversible, so nothing here exits non-zero:
this always exits 0.
"""
import json
import os
import re
import sys


def relative(path: str) -> str:
    """Repo-relative form of the edited path.

    The harness passes an absolute path, while every pattern below is anchored
    at the repository root — `^includes/` against `/home/…/includes/base.yaml`
    matches nothing, and the hook would go silent on every surface it exists to
    catch. Outside the project (or with no project dir set) the path is returned
    unchanged, which simply matches nothing.
    """
    root = os.environ.get("CLAUDE_PROJECT_DIR")
    if not root:
        return path
    try:
        return os.path.relpath(os.path.abspath(path), os.path.abspath(root))
    except ValueError:
        return path

# Generated or fetched — regenerate, don't hand-edit; the reminder names how.
GENERATED = [
    (r"^build/|/build/", "just build (bitbake writes this tree)"),
    (r"^sources/|/sources/", "kas, from the commit pinned in includes/base.yaml"),
    (r"meta-wisekiosk/conf/build-rev\.inc$", "tools/write-build-rev.sh, before every build"),
]

# Gitignored operator state, not a source surface at all.
LOCAL = r"^local/|/local/"

# Decision surfaces — a decision lives here, not an implementation byproduct.
DESIGN_RAUC = [
    r"includes/rauc\.yaml$",
    r"secrets\.yaml\.tmpl$",
    r"rauc.*\.bb(append|class)?$",
]
DESIGN = [
    r"^kiosk-zero-w\.yaml$",   # the one kas entry point
    r"^includes/",             # repo pins and machine config
    r"^patches/",              # what kas applies to the upstream checkout
]


def reminder(path: str):
    for pat, how in GENERATED:
        if re.search(pat, path):
            return (
                f"SELF-CHECK — {path} is a GENERATED artifact, produced by `{how}`. "
                "A hand-edit is overwritten by the next run, or worse survives it and makes the "
                "tree disagree with what built the image. Change the recipe, the kas pin or the "
                "writer, not this file."
            )
    if re.search(LOCAL, path):
        return (
            f"SELF-CHECK — {path} is under gitignored `local/`: operator notes, keys and raw "
            "captures. Nothing here is published and nothing here is a build input, so a fact "
            "that belongs to the repository does not belong here. Investigation findings move to "
            "docs/issue_investigation/ under TEMPLATE.md; a script put on a board is shipped in a "
            "recipe or committed beside the investigation (R2), never left only here."
        )
    for pat in DESIGN_RAUC:
        if re.search(pat, path):
            return (
                f"SELF-CHECK — {path} carries the RAUC signing/keyring decision. The keyring and "
                "the `compatible` string are a ONE-WAY lock: a deployed board refuses a bundle "
                "signed by a key it does not trust and refuses a compatible that is not its own, "
                "and there is no remote undo — a wrong change strands every unit in the field. "
                "Before proceeding: is this the decided rotation order (docs/rauc-key-rotation.md), "
                "and does any secret VALUE become a build input? If either answer is unclear, STOP "
                "and bubble it up to the owner. (CONTRIBUTING.md § Review checklist, "
                "CLAUDE.md § Halt and ask.)"
            )
    for pat in DESIGN:
        if re.search(pat, path):
            return (
                f"SELF-CHECK — {path} is a DESIGN/DECISION surface (the kas entry point, a repo "
                "pin, a machine config, or a patch to upstream). Before proceeding, answer "
                "honestly: does this edit match a DECIDED design intent and THIS ticket's scope? "
                "Touching DISTRO_FEATURES, MACHINE_FEATURES or webkit's PACKAGECONFIG invalidates "
                "WebKit and costs ~4.5 h of rebuild, so it is a decision, not a tweak; kas merges "
                "local_conf_header by BLOCK NAME and the top-level file wins, so a duplicated name "
                "is discarded in silence. If this invents a choice nobody made, or folds something "
                "in to make a gate pass, STOP and bubble it up to the owner. "
                "(CONTRIBUTING.md § Review checklist, CLAUDE.md § Halt and ask.)"
            )
    return None


def main():
    try:
        data = json.load(sys.stdin)
        path = relative((data.get("tool_input") or {}).get("file_path", "") or "")
    except Exception:
        return 0  # fail-open: never interfere on a parse error
    note = reminder(path)
    if note is None:
        return 0
    # stdout carries it into the model's context; stderr shows it in the
    # transcript. Exit 0 either way — see the module docstring.
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": note,
        }
    }))
    sys.stderr.write(note + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
