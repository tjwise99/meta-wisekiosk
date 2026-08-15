# The first boot of a freshly OTA'd slot

Two things fire once, on the first boot of a slot that has just been written, and both distort
anything measured on that boot: units gated on `ConditionNeedsUpdate=`, and OpenSSH host-key
generation. This investigation establishes what they cost and how long the device is unreachable.

## Configuration under test

A RAUC slot immediately after a bundle install, against its own second boot. Two runs, on different
slots and different images: slot A on 2026-08-13 (host keys, `surf` exec), and an OTA'd slot on
2026-08-12 (`ConditionNeedsUpdate=` units, `brcmfmac`/`wlan0`). Both slots carry their own
`machine-id`; `/data` is shared and unchanged across the pair.

`ldconfig`, `systemd-journal-catalog-update` and `systemd-machine-id-commit` are the three units
gated on `ConditionNeedsUpdate=`. They run on a boot that follows a freshly written slot and skip on
every boot after it.

## How the test was performed

Boot 1 and boot 2 of the same slot were compared from the journal in `-o short-monotonic`, with no
change between them other than the reboot. The `ConditionNeedsUpdate=` units were confirmed to skip
on the second boot rather than inferred from the timing difference. Reachability during key
generation was read from the keygen unit's own journal lines against `sshd.socket`'s listen time.

## Metrics

`ConditionNeedsUpdate=` cost, one OTA'd slot, first boot against second:

| | boot 1 (first after OTA) | boot 2 (steady) | Δ |
|---|---|---|---|
| `brcmfmac` | 24.21 s | 23.28 s | −0.93 s |
| `wlan0` | 28.54 s | 26.91 s | −1.63 s |

Roughly 770 ms of CPU is removed by skipping those units, and `wlan0` moves 1.63 s — consistent with
the CPU-saturation finding in [`boot_cpu_saturation`](../boot_cpu_saturation/README.md). **The
mechanism is established; the 1.63 s magnitude is n=1 and is not.** `ldconfig` itself burns 369 ms of
CPU spread across 3.64 s of wall clock: timesliced, not slow.

Host-key generation on slot A's first boot:

```
25.13  Starting OpenSSH Key Generation...
25.77    generating ssh RSA host key...     <- 25.6 s
51.35    generating ssh ECDSA host key...
51.69    generating ssh ED25519 host key...
52.07  Finished OpenSSH Key Generation
```

`sshd.socket` listens at 23.98 s but cannot serve a session until the keys exist, so the device is
**unreachable over SSH for roughly the first 50–80 s after an OTA**. `ping` answers throughout, and
is the check to use in that window. A failed connection there is not a failed update.

That 27 s of key generation runs on the same saturated core as the browser start, so it inflates the
boot it happens on: `surf` exec read 33.05 s on slot A's first boot against 31.26 s on its second,
with zero keygen lines — 1.79 s, measured on a different slot, image and `machine-id` from the
`ConditionNeedsUpdate=` pair above.

## Changes configured as a result

None. The behaviour is upstream systemd and OpenSSH working as designed, and both effects are
one-shot.

The standing consequence is a measurement rule: **take the steady-state number from the second boot,
never the first**, and do not read an unreachable device in the first ~80 s after an OTA as a failed
update. Related but distinct: issue #10 machine-id journald orphan on first OTA is a defect on the
same first-post-OTA boot, not an instance of these two one-shot units.
