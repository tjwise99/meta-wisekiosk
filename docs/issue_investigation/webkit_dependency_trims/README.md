# WebKit dependency trims — two closed routes

`at-spi2-core` holds ~11.9 MB of RSS on a 437 MB board for accessibility nothing on this kiosk uses,
which makes it the largest single RAM win available that is not the browser itself. There is no
route to removing it, and the reason is the same dependency graph that makes touching `dbus` as
expensive as touching `systemd`. This records both closed routes so neither is re-investigated.

## Configuration under test

The image as built: `webkitgtk3` with `systemd` in `DISTRO_FEATURES`, `at-spi2-registryd` (6.3 MB)
and `at-spi-bus-launcher` (5.6 MB) resident in the kiosk session. Neither is started by a systemd
unit, so neither appears in a per-unit CPU or memory table.

Two removal routes were examined: a build-side removal of the `at-spi2-core` package, and a runtime
neutralisation of the daemons from the kiosk launcher's environment.

## How the test was performed

The build side was traced through the recipes themselves — `DEPENDS`, `PROVIDES` and the
`PACKAGECONFIG` third field — and the cost of a change was estimated with
`bitbake -S printdiff` against a `DISTRO_FEATURES` edit.

The runtime side was tested on the device: `NO_AT_BRIDGE=1` and `GTK_A11Y=none` were added to the
launcher and the board rebooted. Whether the variables reached the process was confirmed by reading
`/proc/<surf pid>/environ` rather than assumed from the edit, and the surviving processes were
attributed by reading their `PPid`.

## Metrics

The chain from `systemd` to WebKit, and what a `bitbake -S printdiff` estimate of it is worth, are
recorded at
[`packagegroup-base.bbappend`](../../../meta-wisekiosk/recipes-core/packagegroups/packagegroup-base.bbappend),
next to the edit whose cost it decides. Two hops that look like the path and are not: `at-spi2-core`'s
own `inherit systemd` adds only `systemd-systemctl-native`, a native helper; and `gtk+3` reaches
systemd through `atk` as well, so it is a parallel branch rather than the route. Every hop is a
genuine upstream dependency; nothing this repository does creates it.

**Route 1, build-side removal: closed.** `at-spi2-core` PROVIDES `atk`, which `webkitgtk3`
build-depends on, so removing the package takes WebKit's build with it.

**Route 2, runtime neutralisation: closed.** All three at-spi processes returned unchanged after the
reboot. The environment variables were not ignored — they reached the process — but they suppress
the in-process atk bridge, which is a different thing from the daemons. `at-spi-bus-launcher` runs
with `PPid 1` because it is started by D-Bus activation through
`/usr/share/dbus-1/services/org.a11y.Bus.service`, not by surf's GTK. Nothing set in the launcher's
environment can prevent that.

**Cost of touching `dbus`.** `bitbake -S printdiff` for a `DISTRO_FEATURES:remove` reports only
`systemd:do_configure` and `packagegroup-base:do_package` as unusable, with zero WebKit tasks, and
builds touching systemd have run ~11 minutes with no WebKit rebuild. That is the observation, not a
licence: why it cannot be read as a guarantee is at the recipe comment linked above. A `dbus` change
carries the same multi-hour WebKit-rebuild exposure as a `systemd` change.

## Changes configured as a result

None. Nothing in the layer touches `dbus`, and the launcher is the image copy — the runtime arm was
reverted.

One option remains untried and is declined: masking the D-Bus activation file for
`org.a11y.Bus.service`. It risks GTK blocking on a failed activation, for ~12 MB on a board with
320 MB available.

The dependency chain as stated here is the one recorded at
[`kiosk-hardware_1.0.bb`](../../../meta-wisekiosk/recipes-core/kiosk-hardware/kiosk-hardware_1.0.bb),
which is why that recipe is a separate recipe rather than a systemd bbappend.
