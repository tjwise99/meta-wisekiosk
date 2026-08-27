#!/usr/bin/env python3
"""PreToolUse hook: make the model self-review before a commit.

Fires on Bash `git *` calls, returns immediately unless the command commits.
For a commit, reads CONTRIBUTING.md's "## Review checklist" section, groups its
numbered questions under their **Group** heading, maps the paths about to be
committed to those groups (union — a path can pull in more than one group), and
exits 2 with the matching questions on stderr. Claude Code blocks the commit and
feeds that text to the model, which answers the questions and re-runs the commit.
No prompt reaches the human. Fires the same way inside subagents.

The group names here and the `**Group**` headings in CONTRIBUTING.md are one
taxonomy authored in two files: a rename in either place would silently select no
questions, which reads as a clean commit. `tools/ci-guards.sh` guard 13 holds the
two sides equal, so a one-word rename fails the guards instead of disarming a
question group.

A marker keyed on the staged content (`git write-tree`, plus the unstaged tracked
diff under `-a`) is the loop guard: the first attempt at a given content-state
blocks, the retry of that same state is allowed through. Changing files in
response yields a new state, which blocks again for a fresh review.

The population is the staged set (`git diff --cached`), plus the tracked-unstaged
set when the commit stages it itself (`-a`/`--all`). No changes in scope, no group
selected, or any internal error allows the commit silently rather than raising.
"""

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time

GUARD_DIR = os.path.join(tempfile.gettempdir(), "claude-review-commit-hook")


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    if not isinstance(payload, dict):
        return 0

    if payload.get("tool_name") != "Bash":
        return 0

    command = (payload.get("tool_input") or {}).get("command")
    if not isinstance(command, str) or not commits(command):
        return 0

    try:
        git_dir = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or "."
        docs_root = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or "."

        changed = committed_paths(git_dir, command)
        if not changed:
            return 0

        groups_needed = select_groups(changed)
        if not groups_needed:
            return 0

        groups = parse_checklist(os.path.join(docs_root, "CONTRIBUTING.md"))

        seen = set()
        questions = []
        for name in groups_needed:
            for number, title in groups.get(name, []):
                if number in seen:
                    continue
                seen.add(number)
                questions.append((int(number), number, title.rstrip(".")))

        if not questions:
            return 0

        session = payload.get("session_id") or ""
        key = content_key(git_dir, command, session)
        if key is None or not claim(key):
            return 0

        questions.sort(key=lambda q: q[0])
        lines = [f"{number}. {title}" for _, number, title in questions]
        header = (
            f"Before this commit — walk these review-checklist questions against "
            f"the {len(changed)} staged path(s), fix anything that fails, then re-run "
            "the commit (an unchanged re-run is allowed through):"
        )
        sys.stderr.write(header + "\n" + "\n".join(lines) + "\n")
        return 2
    except Exception:
        return 0


SEPARATORS = {"&&", "||", "|", ";", "&"}
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def tokenize(line):
    """Shell-tokenise one line, with `;` `&&` `||` `|` `&` as their own tokens.

    `punctuation_chars` makes the operators separate tokens rather than gluing
    them to an adjacent word (`status;git` would otherwise tokenise as one word);
    newlines are split by the caller, since shlex treats a newline as ordinary
    whitespace and would fold two commands into one.
    """
    lex = shlex.shlex(line, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    return list(lex)


HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_]\w*)\1")


def command_lines(command):
    """Yield each line, skipping the body of a heredoc.

    A `<<DELIM` redirection makes the following lines data until a line equal to
    DELIM, so the per-line pass must not read them as commands — otherwise a
    `cat <<EOF` whose body contains `git commit …` reads as a commit. Over-skipping
    (a `<<` inside a quoted argument) at worst misses a commit, which is the
    fail-open direction.
    """
    lines = command.splitlines()
    i = 0
    while i < len(lines):
        yield lines[i]
        match = HEREDOC.search(lines[i])
        i += 1
        if match:
            delim = match.group(2)
            while i < len(lines) and lines[i].strip() != delim:
                i += 1
            i += 1  # the closing delimiter line is not a command either


def commit_segments(command):
    """Yield the git-commit simple-commands in `command`.

    Parses the whole command first — so a message whose quoting spans a newline
    (the multi-line `-m`/trailer form) stays a single token — then each line, so
    an *unquoted* newline separating two commands is still a boundary. shlex folds
    an unquoted newline into whitespace, which is why the per-line pass is needed;
    a line whose quote spans the break simply fails to parse there and was already
    covered by the whole-command pass.
    """
    for text in (command, *command_lines(command)):
        try:
            tokens = tokenize(text)
        except ValueError:
            continue
        for segment in split_simple_commands(tokens):
            if segment_is_commit(segment):
                yield segment


def commits(command):
    """True when a simple-command in `command` is a git commit that writes one.

    `commit` inside a quoted argument of another command — an echo, a `-m`
    message — is never mistaken for the git subcommand.
    """
    for _ in commit_segments(command):
        return True
    return False


def split_simple_commands(tokens):
    segment = []
    for token in tokens:
        if token in SEPARATORS:
            if segment:
                yield segment
            segment = []
        else:
            segment.append(token)
    if segment:
        yield segment


def segment_is_commit(segment):
    i = 0
    while i < len(segment) and re.match(r"^\w+=", segment[i]):
        i += 1
    if i >= len(segment):
        return False
    word = segment[i]
    if word != "git" and not word.endswith("/git"):
        return False

    i += 1
    while i < len(segment):
        token = segment[i]
        if token in GIT_OPTS_WITH_VALUE:
            i += 2
            continue
        if token.startswith("-"):
            i += 1
            continue
        return token == "commit" and "--dry-run" not in segment
    return False


def content_key(git_dir, command, session):
    """Stable digest of the content this commit would record, or None if unknown."""
    tree = run_git(git_dir, ["write-tree"])
    if tree is None:
        return None
    material = session + "\0" + tree.strip()
    if stages_all(command):
        unstaged = run_git(git_dir, ["diff"])
        if unstaged is not None:
            material += "\0" + unstaged
    return hashlib.sha256(material.encode("utf-8", "replace")).hexdigest()


def claim(key):
    """Return True the first time this content-state is seen, False every time after."""
    try:
        os.makedirs(GUARD_DIR, exist_ok=True)
        prune_markers()
        marker = os.path.join(GUARD_DIR, key)
        fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
        return True
    except FileExistsError:
        return False
    except Exception:
        return False


def prune_markers():
    """Drop markers older than a day so the guard directory does not grow without
    bound; a block and its retry happen within seconds, so this never removes a
    marker that is still guarding a live retry."""
    cutoff = time.time() - 86400
    try:
        for name in os.listdir(GUARD_DIR):
            path = os.path.join(GUARD_DIR, name)
            try:
                if os.path.getmtime(path) < cutoff:
                    os.unlink(path)
            except OSError:
                pass
    except OSError:
        pass


def committed_paths(git_dir, command):
    """Paths this commit would record: staged, plus tracked-unstaged under -a."""
    paths = set()

    staged = run_git(git_dir, ["diff", "--cached", "--name-only"])
    if staged is not None:
        for line in staged.splitlines():
            if line.strip():
                paths.add(line.strip())

    if stages_all(command):
        tracked = run_git(git_dir, ["diff", "--name-only"])
        if tracked is not None:
            for line in tracked.splitlines():
                if line.strip():
                    paths.add(line.strip())

    paths.discard("")
    return paths


def stages_all(command):
    """True when the git-commit simple-command carries -a / --all.

    Scoped to the commit segment: an earlier command's flag (`ls -la && git
    commit`) is a different segment and does not count.
    """
    return any(segment_stages_all(segment) for segment in commit_segments(command))


def segment_stages_all(segment):
    """True when a commit segment's own flags carry -a / --all (combined short too)."""
    for token in segment:
        if token == "--all":
            return True
        if token.startswith("-") and not token.startswith("--") and "a" in token[1:]:
            return True
    return False


def run_git(git_dir, args):
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=git_dir,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except Exception:
        return None
    if result.returncode != 0:
        return None
    return result.stdout


GROUP_RE = re.compile(r"^\*\*([^*]+)\*\*\s*$")
ITEM_RE = re.compile(r"^(\d+)\.\s+\*\*([^*]+)\*\*")


def parse_checklist(contributing_path):
    """Group -> [(number, title), ...], parsed from '## Review checklist'."""
    with open(contributing_path, encoding="utf-8") as f:
        text = f.read()

    heading = "## Review checklist"
    start = text.find(heading)
    if start == -1:
        return {}
    section = text[start + len(heading):]
    next_h2 = re.search(r"\n## ", section)
    if next_h2:
        section = section[: next_h2.start()]

    groups = {}
    current_group = None

    for line in section.splitlines():
        gmatch = GROUP_RE.match(line)
        if gmatch:
            current_group = gmatch.group(1).strip()
            continue

        imatch = ITEM_RE.match(line)
        if imatch and current_group is not None:
            number, title = imatch.group(1), imatch.group(2).strip()
            groups.setdefault(current_group, []).append((number, title))

    return groups


# Paths that carry a signing, keyring or site-secret decision, wherever they sit
# in the tree. Matched on the whole path, not a prefix: the RAUC bundle recipe,
# the rotation tooling and the rotation write-up live in three different
# directories and every one of them is the same review question.
#
# `sign` is word-bounded like `keys?` beside it. Unbounded it matched the `sign`
# inside `design`, `assign` and `signal`, so every docs/design/* and *design*
# tooling path drew the keyring and site-secret questions — and a reader trained
# to wave three irrelevant questions through is how a real question 9 gets waved
# through.
#
# `provision` is here for the same reason: tools/provision.sh is the file that
# writes a site's SSID and PSK hash onto a card, so it is the exact subject of
# question 10 (no secret as a build input) and question 11 (no identity in the
# tree) -- and it drew neither, because its name carries no signing word.
SECRET_PATH = re.compile(
    r"(rauc|\bsign(ing|ed|er|s)?\b|secrets?|keyring|gitleaks|\bkeys?\b|\bprovision(ing)?\b)", re.I
)


def select_groups(changed):
    """Map changed paths to CONTRIBUTING.md Review checklist **Group** names (union).

    The six names below are authored twice, here and as `**Group**` headings in
    CONTRIBUTING.md's "## Review checklist". They must match character for
    character; a name that matches nothing selects no questions and the commit
    goes through looking reviewed. `tools/ci-guards.sh` guard 13 compares the two
    sets and fails on any name present on one side only.
    """
    needed = set()
    for path in changed:
        norm = path.replace(os.sep, "/")

        # The layer itself: recipes, bbappends, classes, layer.conf.
        if norm.startswith("meta-wisekiosk/"):
            needed.add("Layer & recipes")

        # The kas entry point and everything it pulls in — pins, machine config,
        # DISTRO_FEATURES, PACKAGECONFIG.
        if norm == "kiosk-zero-w.yaml" or norm.startswith("includes/"):
            needed.add("Build config & pins")

        # Patches kas applies to the upstream checkout before bitbake parses it
        # -- and the ones a recipe applies through SRC_URI, which live beside
        # that recipe under meta-wisekiosk/. Questions 7 and 8 (why not a
        # bbappend, does it still apply) are the same questions wherever the
        # patch sits, and keying on the `patches/` prefix alone asked neither of
        # them about the in-layer half.
        if norm.startswith("patches/") or norm.endswith(".patch"):
            needed.add("Upstream patches")

        if SECRET_PATH.search(norm):
            needed.add("RAUC / signing / secrets")

        # Anything that gates, builds or drives — the recipes, the hooks, the
        # guard's own self-test, the workflows.
        if norm == "Justfile" or norm.startswith(
            ("tools/", "justfiles/", ".github/", ".claude/", ".githooks/")
        ):
            needed.add("Tooling, guards & CI")

        # `.gitignore` is what keeps local/ — the identity map, the keys, the raw
        # captures — out of a PUBLIC tree. Removing one line publishes all of it.
        if norm == ".gitignore":
            needed.add("RAUC / signing / secrets")

        # Every tracked Markdown file, wherever it lives: documentation in this
        # repository sits beside the code it explains, so a recipe's README is
        # as much in scope as anything under docs/.
        if norm.startswith("docs/") or norm.endswith(".md"):
            needed.add("Docs & investigations")

    # A changed path that matches nothing must not read as "no review needed".
    # main() treats an empty set as exactly that and lets the commit through with
    # no question and no marker claimed, so a path this function has not learned
    # about yet is silently exempt — the one outcome no branch above intends.
    # Everything in this repository that is not layer, build config, patch,
    # secret-adjacent or prose is machinery, so that is where the fallback lands.
    if changed and not needed:
        needed.add("Tooling, guards & CI")

    return needed


if __name__ == "__main__":
    sys.exit(main())
