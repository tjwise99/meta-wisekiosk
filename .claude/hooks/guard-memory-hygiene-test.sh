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

PROJ="/home/fixture/meta-wisekiosk"
export KIOSK_HOOK_TRACE=1
# `local/` is resolved against the project root, so the scoping cases below mean
# nothing without one -- with it unset every absolute local path would fall out
# of scope and the suite would still read green.
export CLAUDE_PROJECT_DIR="$PROJ"

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
#
# TENV carries extra `env` arguments for the hook under test. The suite exports
# CLAUDE_PROJECT_DIR globally, and the one case that matters most is its
# ABSENCE -- an assignment prefix cannot express an unset, and a prefix on a
# shell FUNCTION persists past the call in bash, which would silently re-point
# every later case.
TENV=()
t() {
  out=$(printf '%s' "$3" | env ${TENV+"${TENV[@]}"} python3 "$H" 2>"$T/err"); rc=$?
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
# The shapes a roll-up is actually WRITTEN in. A separator of one space caught
# none of these, and every one is a handoff an agent would reach for.
t "markdown table row"    ASK "$(w "$MEM" '| PR #83 | merged | the kernel triage |')"
t "bold, then colon"      ASK "$(w "$MEM" '- **#84**: open')"
t "colon, no copula"      ASK "$(w "$MEM" 'Residual triage #84: closed')"
t "em dash, shouted"      ASK "$(w "$MEM" 'Kernel triage #83 — MERGED')"
t "negated"               ASK "$(w "$MEM" 'PR #83 has not been merged yet.')"
t "still in draft"        ASK "$(w "$MEM" 'The #83 branch is still in draft.')"
t "remains open"          ASK "$(w "$MEM" 'PR #83 remains open pending review.')"
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
# The harness passes absolute paths. A guard that goes silent on the one shape
# it did not expect fails open, and silence is the failure mode with no symptom.
t "relative memory path"  ASK "$(w ".claude/projects/p/memory/lesson.md" 'PR #83 is MERGEABLE, still un-merged.')"
t "relative local note"   ASK "$(w "local/bench-notes.md" 'PR #83 still un-merged, awaiting owner merge.')"
t "PR named by URL"       ASK "$(w "$MEM" 'https://github.com/owner/repo/pull/83 is merge-ready and un-merged.')"
t "shouted OPEN"          ASK "$(w "$MEM" 'Roll-up: #84 per-CVE triage OPEN.')"
t "shouted BLOCKED"       ASK "$(w "$MEM" 'Roll-up: #80 residual triage BLOCKED on the currency work.')"
t "pending merge"         ASK "$(w "$MEM" 'PR #83 approved, pending merge.')"
t "awaiting review"       ASK "$(w "$MEM" 'PR #83 awaiting review from the owner.')"

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
# The separator class admits punctuation, which is what makes a table row bind.
# A SENTENCE boundary must not: the status word there starts a new clause and
# says nothing about the ticket before the full stop.
t "sentence boundary"     PASS "$(w "$MEM" 'Reviewed #42. Closed questions are listed in the investigation.')"
t "word between, lower"   PASS "$(w "$MEM" 'The #46 build stamp closes the reproducibility gap.')"
# REFLOW. A line is not a unit of meaning. This is the `no-incomplete-prs` rule
# unwrapped -- the same words that pass at every wrap width, on one long line.
# A line-wide test made a legal lesson a finding on nothing but its formatting,
# which no author could act on and no reviewer could predict.
t "durable rule, one line" PASS "$(w "$MEM" 'Why: an open PR that closes nothing reads as done when it is not. Two violations, same rule: PR #40 (the soak instrument - only the measuring apparatus, closed no issue) and PR #42 (the write-up WITHOUT the fix, presented as mergeable). Both were converted to draft after the fact.')"
# And the other direction at the same length: a shouted label stays a label
# however far it sits from its ticket, so distance alone must not excuse it.
t "shouted, far from tag"  ASK "$(w "$MEM" 'Kernel and CVE tooling on PR #83 (branch cve-triage) pr-ready COMPLETE, CI all-green, MERGEABLE, un-merged.')"

echo "--- must ASK: THE defect, in every format it gets pasted in ---"
# The exemptions below are the only thing that could hide this string, and every
# one of them is one-directional without these cases: removing a blanket
# exemption always breaks a must-PASS case, so a suite holding only must-PASS
# quoted and fenced cases proves the exemption is ACTIVE and never that it is
# correctly SCOPED. Quoting and fencing are the two most natural ways to paste a
# handoff verbatim, which makes them the formats that matter most.
DEFECT='PR #83 is MERGEABLE, still un-merged (human-gated)'
t "defect, bare"          ASK "$(w "$MEM" "$DEFECT")"
t "defect, double-quoted" ASK "$(w "$MEM" "Handoff: \"$DEFECT\"")"
# shellcheck disable=SC2016  # the backticks are the payload
t "defect, backticked"    ASK "$(w "$MEM" "Handoff: \`$DEFECT\`")"
# shellcheck disable=SC2016  # the fence backticks are the payload
t "defect, fenced"        ASK "$(w "$MEM" "$(printf '## Handoff\n\n```\n%s\n```\n' "$DEFECT")")"
# shellcheck disable=SC2016
t "defect, fenced+lang"   ASK "$(w "$MEM" "$(printf '## Handoff\n\n```text\n%s\n```\n' "$DEFECT")")"
# An UNCLOSED fence must not hide the rest of the file. This is the silent shape:
# one stray line, and everything after it goes unread with no symptom.
# shellcheck disable=SC2016
t "defect, unclosed fence" ASK "$(w "$MEM" "$(printf '## Handoff\n\n```\nsome captured output\n\n%s\n' "$DEFECT")")"
t "defect, whole line quoted" ASK "$(w "$MEM" "\"$DEFECT\"")"
# shellcheck disable=SC2016  # the fence backticks are the payload
t "roll-up in a fence"    ASK "$(w "$MEM" "$(printf '## Handoff\n\n```\nSTATUS 2026-08-30\nPR #83 MERGEABLE, un-merged\n```\n')")"
# QUOTED. The useful spelling of this very rule names a ticket inside the
# example -- "never write PR #83 is MERGEABLE into a memory" is the form worth
# keeping, and the vague one is not. A gate that fires on the lesson it teaches
# trains the reader to click through it.
t "rule quotes an example" PASS "$(w "$MEM" 'Owner rule: a memory saying "#83 is merge-ready" is lying by the time you read it.')"
# shellcheck disable=SC2016  # the backticks are the payload, not a substitution
t "rule quotes, backtick"  PASS "$(w "$MEM" 'Never write `PR #83 is MERGEABLE, un-merged` into a memory.')"
# TERMINAL history. A merge cannot be falsified by a later merge, so the date a
# PR landed is durable fact -- the citation the spec names as a must-not-flag.
t "cited with merge date"  PASS "$(w "$MEM" 'The reproducibility gate shipped in PR #51, merged 2026-08-26.')"
t "comma, ordinary prose"  PASS "$(w "$MEM" 'Two violations, same rule: PR #40, closed no issue, and PR #42.')"
# CLAUSE. A ticket cited in one clause is not bound to a status word in another,
# and a line joining them is one sentence away from any legal lesson. Without
# the split these three -- all the SAME durable rule, differently phrased --
# disagreed with each other, which teaches an author to rephrase until the
# prompt stops rather than to move the status to the ticket.
t "citation, other clause" PASS "$(w "$MEM" 'See #46 build stamp for the vardeps trick; the rule is never to record whether a PR is MERGED here.')"
t "rule then precedent"    PASS "$(w "$MEM" 'Never present partial work as mergeable; see #47 template for the precedent that settled it.')"
t "precedent then rule"    PASS "$(w "$MEM" 'Related: never call a non-closing PR merge-ready; the precedent is #47 template.')"
# A fenced block is captured output. A lesson teaching "read state from gh"
# necessarily shows what gh printed.
# A fence is where a roll-up gets pasted, so fenced lines are scanned like any
# other. A lesson quoting captured gh output pays an ask for that -- the
# deliberate cost, taken because the alternative is silent: a single unclosed
# fence would hide every line after it to end of file.
# shellcheck disable=SC2016  # the fence backticks are the payload
t "gh output in a fence"   ASK "$(w "$MEM" "$(printf 'Read state from gh, never from here:\n\n```\n#83  kernel triage  MERGED\n#84  per-CVE triage  OPEN\n```\n')")"
t "clean local capture"   PASS "$(w "$LOCALNOTE" 'Bench board: 24 h soak, RSS flat, display renders at parity with prod.')"

echo "--- must NO-OP: every other path and tool ---"
t "repo doc, same text"   NOOP "$(w "$REPODOC" 'PR #83 is MERGEABLE, still un-merged (human-gated)')"
t "repo CLAUDE.md"        NOOP "$(w "/home/fixture/meta-wisekiosk/CLAUDE.md" 'PR #83 is MERGEABLE, un-merged')"
t "localhost, not local/" NOOP "$(w "$PROJ/docs/localnotes.md" 'PR #83 is MERGEABLE, un-merged')"
# `local/` is the REPO's gitignored note tree, not any directory of that name.
# An unanchored match takes in /usr/local, a vendored tree, and a docs/local/
# a contributor adds for localisation.
t "/usr/local"            NOOP "$(w "/usr/local/share/doc/notes.md" 'PR #83 is MERGEABLE, un-merged')"
t "docs/local in repo"    NOOP "$(w "$PROJ/docs/local/architecture.md" 'PR #83 is MERGEABLE, un-merged')"
t "vendored local/"       NOOP "$(w "$PROJ/node_modules/pkg/local/README.md" 'PR #83 is MERGEABLE, un-merged')"

echo "--- no CLAUDE_PROJECT_DIR: over-broad, never silent ---"
# The anchoring above needs a project root. With none, an absolute path cannot be
# made repo-relative, and the anchored pattern would match NOTHING -- every
# `local/` note leaving scope in silence while memory kept working. Exporting the
# variable for the whole suite would make its absence untestable, and its absence
# IS the failure mode. The chosen behaviour is over-broad, and it is asserted in
# both directions so it stays a decision rather than an accident.
TENV=(-u CLAUDE_PROJECT_DIR)
t "unset: repo local/"    ASK  "$(w "$PROJ/local/bench-notes.md" 'PR #83 is MERGEABLE, un-merged')"
t "unset: /usr/local"     ASK  "$(w "/usr/local/share/doc/notes.md" 'PR #83 is MERGEABLE, un-merged')"
t "unset: clean local/"   PASS "$(w "$PROJ/local/bench-notes.md" 'Bench board: 24 h soak, RSS flat.')"
t "unset: memory still"   ASK  "$(w "$MEM" 'PR #83 is MERGEABLE, still un-merged.')"
t "unset: unrelated doc"  NOOP "$(w "$PROJ/docs/cve-and-sbom.md" 'PR #83 is MERGEABLE, un-merged')"
TENV=()
t "memory, not .md"       NOOP "$(w "/home/fixture/.claude/projects/p/memory/notes.txt" 'PR #83 is MERGEABLE, un-merged')"
t "projects, no memory/"  NOOP "$(w "/home/fixture/.claude/projects/p/plan.md" 'PR #83 is MERGEABLE, un-merged')"
t "Bash tool"             NOOP "$(jq -nc '{tool_name:"Bash",tool_input:{command:"gh pr view 83"}}')"
t "Read tool on memory"   NOOP "$(jq -nc --arg f "$MEM" '{tool_name:"Read",tool_input:{file_path:$f}}')"

echo "--- fail-open: a malformed payload must never interfere ---"
t "not JSON"              NOOP "not json at all"
t "empty stdin"           NOOP ""
# Parseable but structurally wrong. A hook that dies on an unexpected TYPE, not
# only on unparseable bytes, is a hook that gets uninstalled.
t "tool_input is a list"  NOOP "$(jq -nc '{tool_name:"Write",tool_input:[1,2]}')"
t "file_path is null"     NOOP "$(jq -nc '{tool_name:"Write",tool_input:{file_path:null,content:"PR #83 un-merged"}}')"
# In scope, so the trace fires: these must reach a clean verdict, not a crash.
t "content is a number"   PASS "$(jq -nc --arg f "$MEM" '{tool_name:"Write",tool_input:{file_path:$f,content:42}}')"
t "edits is a string"     PASS "$(jq -nc --arg f "$MEM" '{tool_name:"MultiEdit",tool_input:{file_path:$f,edits:"nope"}}')"

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
