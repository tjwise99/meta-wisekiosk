# Hardening — the Yocto kiosk

> **Retired 2026-08-13.** This document was a hardening and nightly-incremental-backup proposal for
> the shelved Raspbian SL16G card — `/opt/chromium-72`, `/home/pi/.cache`, `mmClient.sh`, Chromium 72
> on EOL Stretch. That card is no longer the running device, so the proposal is moot. Anything worth
> keeping as history belongs to `raspbian-card.md` (kiosk-reference), not here.
>
> Backup for the running device is [`backup-recovery.md`](backup-recovery.md); the durable state it
> backs up is `/data`, a few kilobytes of config, not a card image, and there is no nightly job for
> it today.

## What is actually open, on the running device

Two hardening gaps are real and tracked as GitHub issues on this repo — not proposed here:

| Issue | Gap |
|---|---|
| **#7 root password / debug-tweaks** | The image ships `debug-tweaks`: an empty root password and `PermitRootLogin`. Deferred by the owner, 2026-08-13. `STATUS.md` (kiosk-reference) has the options and the recovery constraint any change has to preserve — a second device that still needs unauthenticated access until its key is installed. |
| **#6 public RAUC signing key** | The private key is committed in this public repo, and its certificate is this device's keyring, so anyone can sign a bundle the kiosk accepts. Rotation is sequenced, not a deletion. |

The two compound each other: while #7 leaves an unauthenticated root shell reachable on the LAN,
fixing #6 alone buys nothing.

Do not re-propose either without asking the owner — see the issues for current status and the
reopening conditions.
