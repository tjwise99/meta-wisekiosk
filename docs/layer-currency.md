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
carrying a `repos:` block, and merges those blocks the way kas does. A pin added to an existing
include, or in a new one, is covered the day it lands with no change here. The report prints the
files it read, so what it covered is on the page beside what it found.

## Reading the output

One line per pinned repository, `behind` first:

```
behind   poky       scarthgap (chain default)  <pinned sha> -> <head sha>  https://git.yoctoproject.org/git/poky
current  meta-rauc  scarthgap                  <pinned sha>               https://github.com/rauc/meta-rauc.git
```

**`current`** means the pin *is* the branch head. **`behind`** means the head has moved off it, and
the two SHAs say from where to where.

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

**It compares SHAs, not ancestry.** `behind` says the head is not the pinned commit. It does not say
the pin is an ancestor of that head, how many commits separate them, or what those commits contain.
Establishing that needs a clone, which is the cost this check exists to avoid. A force-push or a
rewritten branch produces the same `behind` as a hundred ordinary commits.

**It compares pins, not recipe versions.** The unit here is the repository: a pinned SHA against a
branch head. A repo sitting exactly on its head still carries whatever recipe versions that branch
froze, and on an LTS branch those are deliberately old — so `current` on every line says the pins are
fresh, not that the software in the image is. Answering the recipe question needs a configured build
tree to query, which is the cost this check exists to avoid, and it is tracked separately as
**#81 scoped `devtool check-upgrade-status` target**.

**It says nothing about what being behind is worth.** A pin behind by one documentation commit and a
pin behind by a quarter of security backports report identically. Reading the log between the two
SHAs is the next step, and it is a person's, not this script's — the same division the CVE tooling
keeps in [`cve-and-sbom.md`](cve-and-sbom.md) §"Reading the CVE report".

**It needs network, and it is point-in-time.** Every run asks the remotes fresh; there is no cached
answer and no offline mode. Nothing is stored between runs either, so this reports a *state* and
never a delta — it cannot tell you that poky moved since you last looked, only where it is now.

## Outcomes

Two, and they are the ones the rest of the audit group holds to.

A report **exits 0 whatever it finds**. Repositories behind their branch head are findings, not
failures: nothing here gates a build, a flash or a pull request, and a pin is behind on purpose right
up until somebody decides otherwise.

A report it cannot complete **refuses and exits 2**, printing why. That covers everything between the
question and the answer: PyYAML absent, an include file that will not parse, a `commit:` that is
missing or not a full object name, a pin with no `url:` to compare it against, no branch resolvable,
an entry shaped in a way it does not recognise, and any `git ls-remote` that fails, stalls, or
answers with a ref that is not the one asked for.

There is no third outcome and no skipped state. A repository quietly dropped from the report would
read exactly like one that is current, so nothing is ever dropped quietly.

## When a pin is behind

[`layers-and-kas.md`](layers-and-kas.md) §"Bumping the upstream pin" is the procedure. This check
finds the pins worth that work; it does not do it, and it never edits a file.
