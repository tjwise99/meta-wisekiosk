# Agent working rules — meta-wisekiosk

Working conventions for an AI agent in this repository. **Project facts are not here** — the
[README](README.md) says what this is and how to build, flash and update it, and the index at
[`docs/README.md`](docs/README.md) is authoritative on which document holds what. The gates and the
review checklist are [`CONTRIBUTING.md`](CONTRIBUTING.md), injected at session start by
[`.claude/settings.json`](.claude/settings.json). This file holds only the rules layered on top,
which is why it is short: a rule stated in another document does not belong here as well.

The global rules in `~/.claude/CLAUDE.md` still apply — shell behaviour, delegation, the GitHub
conventions. Nothing here overrides them.

## Where the facts live

One owner per fact. Read the owner; do not restate it here or anywhere else.

| Subject | Owner |
|---|---|
| What this repository is; build, flash, OTA and recovery paths | [`README.md`](README.md) |
| How YAML and recipes become an image, and which commit an image is from | [`docs/layers-and-kas.md`](docs/layers-and-kas.md) |
| Which commit a *running* image was built from | `/etc/buildinfo` on the device |
| Replacing the RAUC signing key, and the order it must happen in | [`docs/rauc-key-rotation.md`](docs/rauc-key-rotation.md) |
| Scanning the image for CVEs, reading the SBOM, and what `CVE_STATUS` means | [`docs/cve-and-sbom.md`](docs/cve-and-sbom.md) |
| Whether the pinned upstream repos have fallen behind their branch heads | [`docs/layer-currency.md`](docs/layer-currency.md) |
| What was tried, what it cost, what was rejected | [`docs/issue_investigation/`](docs/issue_investigation/TEMPLATE.md) |
| The shape every investigation takes, and R1-R3 | [`docs/issue_investigation/TEMPLATE.md`](docs/issue_investigation/TEMPLATE.md) |
| Site configuration — SSID, PSK hash, URL, hostname, machine-id | out-of-tree `~/.config/wisekiosk/secrets.yaml` |
| Which board is prod, which is bench, and their real addresses | gitignored `local/device-identity.md` |
| The RAUC key the fleet trusts | gitignored `local/keys/` |
| The gates, the conventions, and the review checklist | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Every document and the question it answers | [`docs/README.md`](docs/README.md) |

## What will bite you here

- **`just build`, never `kas-container` directly.** kas alone skips
  `tools/write-build-rev.sh`, so a tree that has built before builds against the *previous* commit
  and the reproducibility gate refuses the image at flash time.
- **A full build is ~4.5 h**, and `DISTRO_FEATURES` / `MACHINE_FEATURES` / webkit `PACKAGECONFIG`
  invalidate WebKit and cost that again. Decide before starting.
- **Never destructively test the prod board.** It is wall-mounted and carries the live soak run;
  bench is the OTA, reboot and rollback target. Roles and addresses are in
  `local/device-identity.md` — read them, do not remember them.
  `.claude/hooks/guard.sh` blocks a prod-targeted destructive op, and it is only as good as that file.
- **The RAUC keyring and `compatible` are a one-way lock.** A deployed board refuses a bundle it
  cannot verify and a compatible that is not its own. There is no remote undo; the order in
  [`docs/rauc-key-rotation.md`](docs/rauc-key-rotation.md) is the whole mechanism.
- **`/boot` has no A/B protection.** Kernel and rootfs fall back per slot; `cmdline.txt`,
  `config.txt` and `uboot.env` are shared, so a bad write breaks both slots and needs the card
  pulled. Boot changes ship by OTA.
- **This repository is PUBLIC.** No secret value becomes a build input, and no address, hostname,
  SSID, MAC, serial or machine-id reaches a tracked file — fixtures included.
  `tools/scrub-identity.py --check` is the gate; `tools/ci-guards.sh` catches the RFC1918 half.
- **Every `.md` change passes `just verify`**, and an investigation follows
  [`docs/issue_investigation/TEMPLATE.md`](docs/issue_investigation/TEMPLATE.md) with R1-R3. Cite a
  section by name, never by line number: the named form is gated, a line number is not.

## Halt and ask

Where the tree is silent on something observable — a variable name, a partition, a service ordering,
a threshold, a new file or dependency, which board a step targets — **halt and ask** rather than
inventing it. A plausible invention reviews as normal work while encoding a choice nobody made, and
on this project the cost of a wrong choice is a physical trip to a wall-mounted unit. The same
applies to anything irreversible: a keyring change, a `/boot` write, a reflash. Produce the
inspectable form — the draft, the diff, the command — and let the owner decide.

## Review independence

Code this session wrote cannot be reviewed by this session — independence is a property of context,
not of instruction. Delegate review of your own diffs to a fresh context, handed the diff and the
spec rather than the narrative of what you did. Work you had no part in, you may review inline.
