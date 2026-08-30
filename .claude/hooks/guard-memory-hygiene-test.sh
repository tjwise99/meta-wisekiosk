#!/usr/bin/env bash
# Self-test for .claude/hooks/guard-memory-hygiene.py. Run by `just guards` and
# by CI, so an edit that widens the patterns into legal prose, or narrows them
# past the narration they exist to catch, fails the build.
#
# Every case runs the hook BINARY over a real PreToolUse payload on stdin. A
# unit-test of the regexes would pass while the path scoping, the MultiEdit
# shape or the JSON decision were broken -- which are three of the four ways
# this hook can silently stop working.
#
# Both directions, per the repo's rule: the must-ASK cases are the exact lines
# that motivated this guard, and the must-PASS cases are real text from durable
# memories that quote the same vocabulary legitimately. A guard that fires on a
# durable rule about PR hygiene is worse than no guard -- the rules ARE the
# thing memory is for.
#
# PASS and NO-OP look identical on stdout, so the hook announces an in-scope
# scan on stderr under KIOSK_HOOK_TRACE and the scoping cases assert on that.
# Without it "the content was clean" and "the hook never looked at this path"
# are the same observation.
#
# Paths here are fixtures. No board address, hostname or identity appears --
# this repository is PUBLIC. Boards are named by ROLE.
set -uo pipefail

H="$(cd "$(dirname "$0")" && pwd)/guard-memory-hygiene.py"
MEM="/home/fixture/.claude/projects/-home-fixture-meta-wisekiosk/memory/lesson.md"
LOCALNOTE="/home/fixture/meta-wisekiosk/local/bench-notes.md"
REPODOC="/home/fixture/meta-wisekiosk/docs/cve-and-sbom.md"

export KIOSK_HOOK_TRACE=1

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0; fail=0

# jq-constructed, never hand-built JSON: a payload containing a double quote
# would break the string and the hook would match an empty document -- the case
# would report PASS while measuring nothing.
w() { jq -nc --arg f "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }
ed() { jq -nc --arg f "$1" --arg c "$2" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"x",new_string:$c}}'; }
me() { jq -nc --arg f "$1" --arg c "$2" '{tool_name:"MultiEdit",tool_input:{file_path:$f,edits:[{old_string:"x",new_string:"harmless"},{old_string:"y",new_string:$c}]}}'; }

# $1=label $2=expect(ASK|PASS|NOOP) $3=payload
#
# grep -c and compare, never `| grep -q`: -q exits on the first hit, the
# producer dies of SIGPIPE at 141, and pipefail returns that -- the test would
# be false precisely when the pattern matches.
t() {
  out=$(printf '%s' "$3" | python3 "$H" 2>"$T/err"); rc=$?
  err=$(cat "$T/err")
  asked=$(printf '%s' "$out" | grep -c '"permissionDecision": "ask"')
  scanned=$(printf '%s' "$err" | grep -c 'memory-hygiene: scanned')
  if [ $rc -ne 0 ]; then
      got="ERR($rc)"
  elif [ "$asked" -ne 0 ]; then
      got=ASK
  elif [ -n "$out" ]; then
      got="OTHER"
  elif [ "$scanned" -ne 0 ]; then
      got=PASS      # in scope, scanned, nothing to report
  else
      got=NOOP      # out of scope: the hook never looked
  fi
  if [ "$got" = "$2" ]; then r="ok  "; pass=$((pass+1)); else r="FAIL"; fail=$((fail+1)); fi
  printf '%s expected=%-5s got=%-6s %s\n' "$r" "$2" "$got" "$1"
  if [ "$got" != "$2" ]; then
      printf '        stdout: %s\n' "${out:-<empty>}" | head -n 2
      printf '        stderr: %s\n' "${err:-<empty>}" | head -n 2
  fi
}

echo "--- must ASK: session-transient ticket status in memory ---"
# THE defect. This is the shape that filled thirteen memory files with state a
# merge falsified the same week.
t "mergeable + un-merged" ASK "$(w "$MEM" 'PR #83 is MERGEABLE, still un-merged (human-gated)')"
t "merge-ready roll-up"   ASK "$(w "$MEM" 'C#71 delta-triage IMPLEMENTED -- PR #77 merge-ready & un-merged.')"
t "awaiting owner merge"  ASK "$(w "$MEM" 'PR #59 done, both bench runs complete, awaiting owner merge')"
t "ALL-CAPS label"        ASK "$(w "$MEM" 'PR #51 MERGED (squash 34a917b), issue #46 CLOSED 2026-08-26.')"
t "lowercase label"       ASK "$(w "$MEM" 'Follow-ups: #63 closed, #66 merged, #78 open.')"
t "dated status header"   ASK "$(w "$MEM" '## STATUS 2026-08-30')"
# A word between the number and the status walks past the tight label shape, and
# the shouted spelling is as common in a roll-up as the tight one.
t "SHOUTED, word between" ASK "$(w "$MEM" 'cascade: #47 template MERGED, then #46 build-stamp landed.')"
t "blocked_by narration"  ASK "$(w "$MEM" 'Residual triage carved out as #84, blocked_by #72.')"
t "still open"            ASK "$(w "$MEM" 'The doc-links section-citation gap (#79) is still open.')"
t "ready to merge, cited" ASK "$(w "$MEM" 'PR #82 is ready to merge; CI all-green.')"
# ISOLATING cases: one detector each, no other tell on the line. The obvious
# spellings above are caught by two detectors at once, so deleting a term from
# one of them left the suite fully green -- redundant coverage and "the term is
# still checked" are the same observation without these.
t "un-merged, alone"      ASK "$(w "$MEM" 'Everything on #83 landed, but it sits un-merged.')"
t "mergeable, alone"      ASK "$(w "$MEM" 'The layer-currency work on #72 came back mergeable.')"
t "merge-ready, alone"    ASK "$(w "$MEM" 'The delta-triage tooling on #71 sits merge-ready this week.')"
# The edit shapes. A hook that reads only `content` goes silent on every Edit,
# and Edit is how a status line gets APPENDED to a memory that already exists.
t "Edit new_string"       ASK "$(ed "$MEM" 'PR #83 is MERGEABLE, still un-merged (human-gated)')"
t "MultiEdit edits[]"     ASK "$(me "$MEM" 'PR #83 is MERGEABLE, still un-merged (human-gated)')"
# Buried in an otherwise legitimate memory: the line is what is scanned, not the
# file's overall character.
t "status inside a rule"  ASK "$(w "$MEM" "$(printf 'Owner rule: code is the living proof of what is built now.\n\nPR #77 merge-ready & un-merged, awaiting owner.\n')")"

echo "--- must ASK: gitignored local/ working notes ---"
t "local note status"     ASK "$(w "$LOCALNOTE" 'Bench board reflashed. PR #83 still un-merged, awaiting owner merge.')"
t "local nested note"     ASK "$(w "/home/fixture/meta-wisekiosk/local/runs/soak.md" 'PR #59 MERGE-READY & un-merged.')"

echo "--- must PASS: durable rules and lessons that merely CITE a ticket ---"
# Real text from memories that survived the cleanup. Each quotes the status
# vocabulary because the RULE is about it -- flagging these would train the
# owner to click through the prompt, which is how an ask-gate dies.
t "cited as history"      PASS "$(w "$MEM" 'The reproducibility gate shipped in PR #51 build stamp.')"
t "generic rule, quoted"  PASS "$(w "$MEM" 'Never frame such a PR as "ready to merge."')"
t "rule names no ticket"  PASS "$(w "$MEM" 'If a memory names a PR as un-merged, distrust it and run gh.')"
t "no ticket, mergeable"  PASS "$(w "$MEM" 'Never present partial work as mergeable.')"
t "history, wide gap"     PASS "$(w "$MEM" 'Two violations, same rule: PR #40 (the soak instrument) and PR #42.')"
t "closed as a verb"      PASS "$(w "$MEM" 'Represent "issue A cannot proceed until issue B closes" with a native edge.')"
t "blocking edge example" PASS "$(w "$MEM" 'WiseKiosk already does this: #118 blocking #119/#120/#124 for the ADR ordering.')"
t "blocked_by API path"   PASS "$(w "$MEM" 'Use gh api repos/<owner>/<repo>/issues/<n>/dependencies/blocked_by.')"
t "ticket named + name"   PASS "$(w "$MEM" 'See #46 build stamp and SRS026 backend-unreachable state for the pattern.')"
t "pure owner rule"       PASS "$(w "$MEM" 'Owner rule: investigations name the board role and the image commit per run.')"
# Shouted vocabulary with no ticket on the line is a rule ABOUT status, not a
# record of one -- the header of the memory store itself is written this way.
t "SHOUTED, no ticket"    PASS "$(w "$MEM" 'Never record whether a PR is MERGED or CLOSED here; run gh instead.')"
t "clean local capture"   PASS "$(w "$LOCALNOTE" 'Bench board: 24 h soak, RSS flat, display renders at parity with prod.')"

echo "--- must NO-OP: every other path and tool ---"
t "repo doc, same text"   NOOP "$(w "$REPODOC" 'PR #83 is MERGEABLE, still un-merged (human-gated)')"
t "repo CLAUDE.md"        NOOP "$(w "/home/fixture/meta-wisekiosk/CLAUDE.md" 'PR #83 is MERGEABLE, un-merged')"
t "localhost, not local/" NOOP "$(w "/home/fixture/meta-wisekiosk/docs/localnotes.md" 'PR #83 is MERGEABLE, un-merged')"
t "memory, not .md"       NOOP "$(w "/home/fixture/.claude/projects/p/memory/notes.txt" 'PR #83 is MERGEABLE, un-merged')"
t "projects, no memory/"  NOOP "$(w "/home/fixture/.claude/projects/p/plan.md" 'PR #83 is MERGEABLE, un-merged')"
t "Bash tool"             NOOP "$(jq -nc '{tool_name:"Bash",tool_input:{command:"gh pr view 83"}}')"
t "Read tool on memory"   NOOP "$(jq -nc --arg f "$MEM" '{tool_name:"Read",tool_input:{file_path:$f}}')"

echo "--- fail-open: a malformed payload must never interfere ---"
t "not JSON"              NOOP "not json at all"
t "empty stdin"           NOOP ""

echo "--- the ask message must say where status belongs ---"
msg=$(printf '%s' "$(w "$MEM" 'PR #83 is MERGEABLE, still un-merged (human-gated)')" \
      | python3 "$H" 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])' 2>/dev/null)
missing=""
for want in "GitHub ticket" "durable" "CITES"; do
    [ "$(printf '%s' "$msg" | grep -cF -- "$want")" -ne 0 ] || missing="$missing $want"
done
if [ -z "$missing" ]; then
    r="ok  "; pass=$((pass+1))
else
    r="FAIL"; fail=$((fail+1))
fi
printf '%s expected=%-5s got=%-6s the reason names the tracker and the escape hatch%s\n' \
    "$r" "TEXT" "$([ -z "$missing" ] && echo TEXT || echo MISSING)" \
    "$([ -z "$missing" ] && echo "" || echo " -- missing:$missing")"

echo
printf 'pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
