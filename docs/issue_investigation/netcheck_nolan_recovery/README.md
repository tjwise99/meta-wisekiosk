# `kiosk-netcheck` — proving the no-LAN withhold in all three directions

[`kiosk-netcheck`](../../../meta-wisekiosk/recipes-core/kiosk-netcheck/kiosk-netcheck_1.0.bb)
withholds RAUC good-marking when a boot completes normally but comes up with no usable LAN. A check
that withholds is worth nothing unless it has been seen to fire, to stay quiet, and to suppress
itself — this is the record of it doing all three.

## Configuration under test

Runtime install of the check on slot A, 2026-08-13, with slot B holding the previous image and
marked `good`. Three cases:

| Case | Expected behaviour |
|---|---|
| healthy LAN | pass |
| no LAN, partner slot `good` | withhold |
| no LAN, partner slot **not** `good` | mark good anyway |

The no-LAN cases are produced by pointing `TARGET` in `/data/kiosk-netcheck.conf` at an unroutable
address. That fails the *check* while the real network stays up, so the lifeline into the board is
never the thing under test.

## How the test was performed

The script was exercised directly first, then across real reboots, reading `BOOT_A_LEFT` from the
U-Boot environment and unit state from the journal on each boot.

The third case ran against a **stubbed `rauc status --output-format=shell`**, not against a live bad
slot. That substitutes RAUC's output while exercising the real script, the real parser and the real
branch; it does not prove that RAUC reports a genuinely bad slot in the shape the parser expects.
The second case covers that half — it parsed real `rauc status` output and correctly found slot B
`good`. Together the two cover the path; neither covers it alone.

## Metrics

| Case | Observed |
|---|---|
| healthy LAN | exit 0 in 93 ms; gateway answered at 28.4 s of boot |
| no LAN, partner slot `good` | exit 1; `boot-complete` **inactive**, `rauc-mark-good` refused with "Dependency failed", `BOOT_A_LEFT` **3 → 2** |
| no LAN, partner slot not `good` | exit 0, "WITHHOLDING SUPPRESSED" |
| restore, reboot | `BOOT_A_LEFT` back to **3**, all units active, zero failed |

The kiosk stayed `active` with its full browser tree through the failing boot. The blast radius is
exactly one unit, because `rauc-mark-good` is the only thing on this image that requires
`boot-complete.target` and `kiosk.service` does not.

**Cost: `rauc-mark-good` moved 25.9 s → 30.1 s**, because it waits for the LAN. That widens the
window between boot and good-marking during which a watchdog fire consumes a boot attempt.

## Changes configured as a result

None — validated the implementation as built. The check, its ordering against `boot-complete.target`
and its withhold-only design are documented at
[`kiosk-netcheck_1.0.bb`](../../../meta-wisekiosk/recipes-core/kiosk-netcheck/kiosk-netcheck_1.0.bb)
and in the
[script itself](../../../meta-wisekiosk/recipes-core/kiosk-netcheck/files/kiosk-netcheck).
