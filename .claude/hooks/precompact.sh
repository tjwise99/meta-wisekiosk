#!/usr/bin/env bash
# PreCompact -- fires before the context is summarized.
#
# Compaction loses fidelity unpredictably. The repository is the durable state;
# context is not. So the one thing worth doing here is surfacing what is NOT yet
# on disk, because that is exactly what the summary will lose.
#
# This never blocks. Blocking an auto-compact would wedge a session that has run
# out of room -- the failure mode would be worse than the thing it prevents. Every
# external call is hard-bounded for the same reason: `docker ps` blocked for over
# two minutes once while the daemon was busy with a build, and a missing build
# line is a far smaller loss than a stalled compaction.
set -uo pipefail

payload=$(cat 2>/dev/null)
trigger=$(printf '%s' "$payload" | jq -r '.trigger // "unknown"' 2>/dev/null) || trigger=unknown
[ -n "$trigger" ] || trigger=unknown

REPO=${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}

out=""
add() { out="${out}${1}
"; }

add "COMPACTION (${trigger}). The repository is the durable state; this context is not."
add ""

dirty_total=0
if git -C "$REPO" rev-parse --git-dir > /dev/null 2>&1; then
    br=$(timeout 5 git -C "$REPO" symbolic-ref --short HEAD 2>/dev/null || echo '(detached)')
    sha=$(timeout 5 git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')
    dirty=$(timeout 10 git -C "$REPO" status --short 2>/dev/null)
    if [ -n "$dirty" ]; then
        dirty_total=$(printf '%s\n' "$dirty" | wc -l)
        add "UNCOMMITTED -- compaction will NOT preserve this: $REPO ($br @ $sha)"
        add "$(printf '%s\n' "$dirty" | sed 's/^/    /')"
    else
        add "clean: $REPO ($br @ $sha)"
    fi

    # Worktrees hold in-progress work that is easy to forget across a summary.
    wt=$(timeout 5 git -C "$REPO" worktree list 2>/dev/null | tail -n +2)
    [ -n "$wt" ] && { add ""; add "worktrees in play:"; add "$(printf '%s\n' "$wt" | sed 's/^/    /')"; }
else
    add "NOT A GIT CHECKOUT: $REPO -- nothing here can report what is uncommitted."
fi

# A ~4.5 h build the summary should not silently drop, and which also means the
# build tree must not be edited (guard.sh rule 7).
builds=$(timeout 5 docker ps --format '{{.Names}} {{.Status}} {{.Image}}' 2>/dev/null | grep -i kas)
[ -n "$builds" ] && { add ""; add "BUILD RUNNING (do not edit the build tree):"; add "    $builds"; }

add ""
add "Where the state lives, in reading order:"
add "    README.md                       what this repository is, and the build/flash/OTA paths"
add "    CLAUDE.md                       the working rules, and which document owns which fact"
add "    CONTRIBUTING.md                 the gates, the conventions, and the review checklist"
add "    docs/README.md                  the index: every document and the question it answers"
add "    docs/issue_investigation/       one directory per investigation, TEMPLATE.md + R1-R3"
add "    local/                          gitignored operator notes, keys, raw captures"
add ""
add "Before relying on the summary: anything above marked UNCOMMITTED is a finding"
add "that exists only in the context being discarded. Write it down first."

# PreCompact output accepts only the standard fields (continue / suppressOutput /
# systemMessage). hookSpecificOutput.additionalContext is NOT valid for this event
# -- emitting it fails schema validation ("(root): Invalid input") on every firing,
# so a hook written that way never runs at all. The durable state this hook is
# about is disk, so the full block is written there and a one-line summary that IS
# shown points at it.
snapshot="${HOME}/.claude/precompact-snapshot-meta-wisekiosk.md"
mkdir -p "$(dirname "$snapshot")" 2>/dev/null
printf '%s\n' "$out" > "$snapshot" 2>/dev/null

if [ "$dirty_total" -gt 0 ]; then
    msg="Compacting with ${dirty_total} uncommitted change(s) in meta-wisekiosk -- findings not yet on disk will be lost. Full pre-compaction snapshot written to ${snapshot} -- read it if the summary looks thin."
else
    msg="Compacting; meta-wisekiosk is clean, state is on disk. Pre-compaction snapshot: ${snapshot}."
fi

jq -nc --arg m "$msg" '{systemMessage:$m}' 2>/dev/null || printf '%s\n' "$msg"
