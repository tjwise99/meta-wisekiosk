<!--
  ISSUE INVESTIGATION TEMPLATE — copy this file to a new directory as README.md,
  fill every field, delete these comments.
  One investigation = one directory. That README.md is the record of record.
  Hard rules:
    R1  Every test run names its BOARD (role) and the IMAGE COMMIT it ran.
    R2  Every script put on a board is either SHIPPED (link its recipe/PR) or ONE-OFF
        (committed in this directory beside this README). Never left only in local/ or hot-swapped
        without a tracked source.
    R3  Runs are NEVER blended. One board × one build × one test = one run. Numbers from different
        runs never share a table.
  Example file names below are backticked, not linked: `just links` resolves every Markdown link
  in the tree, and a link to a capture that does not exist yet fails it. Link them once the real
  files sit beside the README.
-->

# <the question this investigation answers, in one line>

| | |
|---|---|
| **Issue** | #NN &lt;name&gt; |
| **Status** | open · concluded → code change · concluded → no change |
| **Opened / concluded** | YYYY-MM-DD / YYYY-MM-DD |

<one-paragraph abstract: the question, and the answer if concluded. No narration.>

## Test runs

<!-- One row per (board × image build × test). A `### Run N` block below expands each. -->

| Run | Board (role) | Image commit | Harness / scripts | Result (1 line) |
|---|---|---|---|---|
| 1 | bench · Pi Zero W | `<sha>` | `collect.sh` — one-off | |
| 2 | prod · Pi Zero W | `<sha>` | `kiosk-soak` — durable, PR #NN | |

### Run 1 — <board role>, commit `<sha>`

- **Board:** role label only (bench / prod) + hardware model. NO IP, hostname, MAC, or serial — this repo is public.
- **Image commit:** `<full git sha the running image was built from>`, confirmed by `<grep ^meta-wisekiosk /etc/buildinfo on the board, which reads meta-wisekiosk = <branch>:<sha> | built+flashed from this commit on YYYY-MM-DD>`. An unverifiable "probably this build" is not a commit — leave the run out until you can name it.
- **Scripts deployed (each, with disposition):**
  - `<name>` — ONE-OFF, not shipped → committed here beside this README.
  - `<name>` — DURABLE → ships via `<recipe path>`, PR #NN.
- **Procedure:** exact steps — reboot count / sampling cadence / commands / bound conditions. Reproducible from this text alone.
- **Raw capture:** sibling file(s), e.g. `run1-boots.log`.

### Run 2 — …

## Configuration under test

The tree facts the runs rest on. Cite every claim `file:line`.

## Metrics

Per run. One table per run — never merge runs of different board / build / N.

## Findings

What the data shows; each hypothesis tested and its disposition (dropped / open / confirmed), tied to the run that decided it.

## Changes configured as a result

Exactly one durable outcome, stated plainly:
- **Code change** → link the recipe/PR that ships it; or
- **No change** → the decision and why, and that the issue is closed with that rationale.

Every one-off script named above is committed in this directory. Every durable change links to its recipe/PR.
