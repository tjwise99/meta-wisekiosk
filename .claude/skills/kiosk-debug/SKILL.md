---
name: kiosk-debug
description: >-
  Diagnose a running wisekiosk device that has no keyboard, no visible console and a display
  whose correct state is a black screen. Decides which instrument to reach for — TCP-state
  inference, a screenshot, a soak read, or a boot profile — and drives the tools/kiosk-*.sh
  scripts behind them. Invoke when the kiosk is unreachable, blank, stale, suspected of
  leaking memory, or slow to come up, and when a boot-time change needs measuring.
---

# Debugging a display you cannot see

The device has no keyboard and no console anyone can read, and the screen itself cannot report
its own state — [`tools/kiosk-tcp-state.sh`](../../../tools/kiosk-tcp-state.sh)'s header says
which faults it hides. Every tool here exists to replace looking at the screen with reading
something definite.

## Which instrument answers which question

| Question | Reach for | Why this one |
|---|---|---|
| Is the browser fetching the page at all, and did its scripts run? | [`tools/kiosk-tcp-state.sh`](../../../tools/kiosk-tcp-state.sh) | Socket state distinguishes "never connected", "fetched HTML only" and "rendering" without touching the device. Needs no access to the kiosk — run it on the host serving the page. |
| Is the screen showing the right thing, right now? | [`tools/kiosk-screenshot.sh`](../../../tools/kiosk-screenshot.sh) | The only check that can catch a *frozen* render. Nothing process-level can. |
| Is memory flat, or climbing over hours? | `kiosk-soak.sh --summary` on the device, via [`tools/kiosk-ssh.sh`](../../../tools/kiosk-ssh.sh) | The sampler already runs; the answer is in `/data/kiosk-soak.log`, and its own header says how to read it. |
| Where is boot time going, and would reordering work help? | [`tools/kiosk-bootprofile.sh`](../../../tools/kiosk-bootprofile.sh) | Only source of per-window CPU/I-O and the module timeline. Costs a reboot and ~3 minutes. |
| The device is not answering and its address is unknown | [`tools/kiosk-find.sh`](../../../tools/kiosk-find.sh) | The router's client list is DHCP leases, so a reachable host can be missing from it. |

Reach for the cheapest instrument that can *fail*. TCP state and a screenshot cost seconds and
no reboot; a boot profile costs a boot of the thing you are debugging.

Every one of these opens an SSH connection to the device, so batch reads through `kiosk-ssh.sh`
rather than issuing them one at a time; its header says what a connection costs and how it is
reused. During a boot profile the connection is itself an instrument — see
[`meta-wisekiosk/recipes-core/kiosk-bootprof/README.md`](../../../meta-wisekiosk/recipes-core/kiosk-bootprof/README.md).

## Ordering a diagnosis

1. **Is it reachable?** If not, `kiosk-find.sh` on the LAN before assuming it is down — and if
   it answers there but not over SSH, close a stale multiplex master (`kiosk-ssh.sh <host>
   --close`) before diagnosing anything else.
2. **Is it rendering?** `kiosk-screenshot.sh`. A blank result and a correct-but-stale result are
   different faults with the same appearance, which is why the script takes the device clock in
   the same call as the pixels.
3. **If it is not rendering, is it fetching?** `kiosk-tcp-state.sh` from the serving host
   separates "the browser is not running" from "the page will not execute".
4. **If it is rendering but degraded**, read the soak log before rebooting. A reboot destroys
   the only series that could have told you what was happening.

## Tips that cost real time to learn

- **`pgrep -f <pattern>` matches your own command line** over SSH, so it finds your shell and
  reports the process as running. Use `pgrep -x`, or match the binary path.
- **Sample twice before believing a one-shot read.** One sample cannot tell a state from a
  moment.
- **Read `kiosk-ssh.sh`'s header before writing a probe of your own.** What it says about
  silencing output and about exit codes is what turns a broken check into a false alarm.
