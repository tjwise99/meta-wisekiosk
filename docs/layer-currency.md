# Layer currency

This answers one question: **has upstream moved past the commits this image is pinned to?**

The image is built from upstream repositories, each frozen at a `commit:` in `includes/`. Pinning them
is deliberate, for the reasons [`layers-and-kas.md`](layers-and-kas.md) §"Bumping the upstream pin"
gives — but nothing about a pin expires. It sits at whatever a person last typed, and the branch it
came from keeps moving without saying so. On a stable branch that movement is mostly backported
fixes, so a pin left alone long enough is an image that is missing them.

Dependabot cannot see this. It reads package manifests, and a kas `commit:` is not one;
[`../.github/dependabot.yml`](../.github/dependabot.yml) says so itself. This check is the substitute.

## Running it

```sh
just currency
```

[`../tools/layer-currency.py`](../tools/layer-currency.py) asks each remote for the head of the
branch that repo tracks. It needs network — no build, no checkout, no `sources/` tree — and it takes
a few seconds.

Both the pins and the files holding them are found at run time: it scans `includes/` for YAML
carrying a `repos:` block, and merges those blocks by name. A pin added to an existing
include, or in a new one, is covered the day it lands with no change here. The report prints the
files it read, so what it covered is on the page beside what it found.

Two files describing one repository merge into a single entry, which is what lets `meta-autonomos` be
pinned in one file and gain a layer in another. Two files giving that repository a *different* `url:`,
`commit:` or `branch:` refuse instead: kas settles that by include-chain order, this does not read the
chain, and guessing which pin wins is how a report comes back confident and wrong.

## Reading the output

One line per pinned repository, `behind` first:

```
behind  poky  scarthgap (chain default)  <pinned sha> -> <head sha>  contributes 88 recipes  https://git.yoctoproject.org/git/poky
          behind by 69 commits
behind  meta-virtualization  scarthgap (chain default)  <pinned sha> -> <head sha>  contributes 0 (dependency only)  https://git.yoctoproject.org/meta-virtualization
current  meta-rauc  scarthgap  <pinned sha>  contributes 1 recipe  https://github.com/rauc/meta-rauc.git
```

**`current`** means the pin *is* the branch head. **`behind`** means the head has moved off it, and
the two SHAs say from where to where.

### The contribution column

`behind` lines are ranked by it, so the first line is the pin worth reading. It is joined from the
newest CVE manifest's `LAYER` field: for each repository, the recipes carrying CVE records across the
layers that repository contributes. The join is **layer → repo**, not name to name — one repository
holds several layers (`poky` → `meta`, `meta-poky`, `meta-yocto-bsp`; `meta-openembedded` → four), and
a repository declaring no `layers:` block contributes its own directory as one layer named after it,
which is how `meta-raspberrypi` and `meta-lts-mixins` reach `bblayers.conf`.

`contributes 0 (dependency only)` is the case worth having. `meta-virtualization` is pinned and
enabled and owns **no** record in this image's manifest — it exists to satisfy a `LAYERDEPENDS`, not
to ship software, and bumping it moves nothing. Without the column it reports identically to poky
going behind.

It says `dependency only` rather than `unused` deliberately: the axis is CVE attribution, and a layer
can contribute a `.bbappend` or a class that changes the image without owning a record. Where no
audit build exists the column reads `contribution unknown` for every repository, and the report says
so once at the bottom rather than reporting zeros it did not measure.

### The distance line

Where `sources/` happens to hold a clone of a repository that is `behind`, a second line says how far:
`behind by N commits`, or a warning that **the pin is NOT an ancestor of the head** — a rewritten or
force-pushed branch, which is a materially different situation from a hundred ordinary commits.

This is strictly opportunistic. `sources/` is a clone the build already made, so the distance costs
nothing where it exists, and `check` still promises no checkout: an absent or unfetched clone prints
`the clone predates this head` and the report is otherwise unchanged. Nothing here fetches.

The branch is printed because most repos do not name one. Those inherit the chain default that
`defaults.repos.branch` in `includes/base.yaml` sets, and a repo that took it is marked
`(chain default)` — so a pin compared against the wrong branch is visible in the report rather than
buried in the inference behind it. The repos that do name a branch are the ones tracking something
other than the LTS release, and the report names it for them too.

`meta-wisekiosk` is excluded and the report says so. It declares neither a `url:` nor a `commit:`,
which is how kas spells "the repository holding this config file" — it is this repo, it carries no
pin, and there is no upstream to ask. An entry missing only one of the two is not that: a pin with no
remote to compare it against is refused, so a dropped `url:` line cannot quietly shrink the report.

## What it cannot see

**The SHA comparison itself is not ancestry.** `behind` means the head is not the pinned commit,
nothing more. Ancestry and distance need a clone, so they are the opportunistic second line described
above and are absent whenever `sources/` is. Where that line is missing, a force-push and a hundred
ordinary commits still produce the same `behind`.

**It compares pins, not recipe versions.** The unit here is the repository: a pinned SHA against a
branch head. A repo sitting exactly on its head still carries whatever recipe versions that branch
froze, and on an LTS branch those are deliberately old — so `current` on every line says the pins are
fresh, not that the software in the image is. Answering the recipe question needs a configured build
tree to query, which is the cost this check exists to avoid, and it is tracked separately as
**#81 scoped `devtool check-upgrade-status` target**.

**The contribution column ranks pins, it does not value the commits in the gap.** A pin behind by one
documentation commit and a pin behind by a quarter of security backports still report identically
where both layers contribute. `gap` below answers the next question; deciding what to do about the
answer stays a person's, the same division the CVE tooling keeps in
[`cve-and-sbom.md`](cve-and-sbom.md) §"Reading the CVE report".

**It needs network, and it is point-in-time.** Every run asks the remotes fresh; there is no cached
answer and no offline mode. Nothing is stored between runs either, so this reports a *state* and
never a delta — it cannot tell you that poky moved since you last looked, only where it is now.

## What a bump would be worth: `gap`

`check` says which pins have moved. `gap` says what moving one back would buy.

```sh
just gap poky            # offline, against sources/ as last fetched
just gap poky --fetch    # update sources/ first
```

It walks `git log <pin>..origin/<branch>` in the clone `sources/` already holds, collects every CVE
id the commit subjects and bodies name, and intersects that with the **unpatched** findings in the
newest CVE manifest. Against the poky pin that is 69 commits naming 56 CVEs, of which **16 unpatched
findings across 5 packages** — `curl`, `expat`, `glib-2.0`, `gnutls`, `nghttp2` — would plausibly
close. It takes about a second and builds nothing.

Two things it deliberately will not do.

**It says "would plausibly close", never "will close".** A CVE named in a commit subject is evidence
of intent, not proof the finding flips. The authoritative answer is bumping the pin and re-running
`just cve-build`, and the report says so on its last line.

**It never fetches unless told to.** Fetching writes to a checked-out tree, and a report that
silently mutated `sources/` would break the no-checkout promise `check` is built on. So `--fetch` is
opt-in and is the only thing in this file that writes anything. The cost is that the clone may be
stale — and an empty range offline is *"upstream has nothing new"* and *"this clone was never fetched
past the pin"* at the same time. Rather than print a `0` that reads as the first, `gap` says the
range is empty and names both, pointing at `--fetch` and at `check`.

Where the clone is missing, the pin is not in it, or the branch ref does not exist, `gap` refuses and
exits 2 rather than reporting an emptier answer than it measured.

## Outcomes

Two, and they are the ones the rest of the audit group holds to.

A report **exits 0 whatever it finds**. Repositories behind their branch head are findings, not
failures: nothing here gates a build, a flash or a pull request, and a pin is behind on purpose right
up until somebody decides otherwise.

A report it cannot complete **refuses and exits 2**, printing why. That covers everything between the
question and the answer: PyYAML absent, an include file that will not parse, a `commit:` that is
missing or not a full object name, a pin with no `url:` to compare it against, no branch resolvable,
one repository pinned two different ways across two files, an entry shaped in a way it does not
recognise, and any `git ls-remote` that fails, stalls, or answers with a ref that is not the one
asked for. For `gap`, add: a repository not pinned at all, no checkout at its `path:`, a `--fetch`
that fails, and a clone holding neither the pin nor the branch ref.

There is no third outcome and no skipped state. A repository quietly dropped from the report would
read exactly like one that is current, so nothing is ever dropped quietly.

## When a pin is behind

[`layers-and-kas.md`](layers-and-kas.md) §"Bumping the upstream pin" is the procedure. This check
finds the pins worth that work; it does not do it, and it never edits a file.
