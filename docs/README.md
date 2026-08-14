# WiseKiosk Zero W — documentation

Field notes on one specific physical kiosk: a Raspberry Pi Zero W (BCM2835, ARMv6) behind
one-way glass, reachable only over SSH. Each file below owns exactly one subject; do not
restate a fact outside its owner.

### Device and hardware
| Doc | What it owns |
|---|---|
| [`pi-inventory.md`](pi-inventory.md) | Hardware, OS, package archives, boot chain |
| [`browser-constraints.md`](browser-constraints.md) | Browser ceiling, features, and build targets |
| [`mirror-deployment.md`](mirror-deployment.md) | The backend the kiosk points at |
| [`provisioning.md`](provisioning.md) | Standing up a new kiosk card from the out-of-tree secrets |

### Boot, performance, and debugging
| Doc | What it owns |
|---|---|
| [`boot-profile-yocto.md`](boot-profile-yocto.md) | Where Yocto boot time goes, and whether the core is busy or blocked |
| [`service-changes.md`](service-changes.md) | Every service masked/disabled/changed, and whether it was justified |
| [`remote-debugging.md`](remote-debugging.md) | Debugging recipes for the live device |

### Image and build
| Doc | What it owns |
|---|---|
| [`image-migration.md`](image-migration.md) | Device changes and where they land in the build tree |
| [`image-trim-recommendations.md`](image-trim-recommendations.md) | What to cut from the Yocto image, ranked by measured cost |
| [`experiment-log.md`](experiment-log.md) | What was tried and did **not** work on the Yocto device |

### OTA and backup
| Doc | What it owns |
|---|---|
| [`yocto-ota-plan.md`](yocto-ota-plan.md) | Yocto image with A/B OTA — **built, delivered, running** |
| [`backup-recovery.md`](backup-recovery.md) | Backup and recovery |
| [`hardening-and-backup-plan.md`](hardening-and-backup-plan.md) | Open hardening items — empty root password (#7) and the committed RAUC signing key (#6) |

### Evidence (research and captured faults)
| File | What it holds |
|---|---|
| [`evidence/README.md`](evidence/README.md) | Condensed findings: the brcmfmac SDIO rx-path patches that shipped, the ramoops/pstore outcome, and the still-live `mmc_rescan` panic |
| `evidence/oops-*.txt` | Raw kernel oopses captured on the device (2026-08-13) |

> **The single deployed instance's live notes live in the separate `kiosk-reference` repo**,
> not here — its `STATUS.md` (current device state, open items, live hazards — read before
> touching the device), the retired-card history in `raspbian-card.md`, and the operator
> working rules in `CLAUDE.md`. Those are referenced by name in the docs above rather than as
> links, because that repo is instance-local and not published.
