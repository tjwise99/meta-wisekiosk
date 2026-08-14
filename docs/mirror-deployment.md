# Mirror deployment (the server side)

What the kiosk points *at*: a MagicMirror backend serving at `http://<MIRROR_IP>:8080`. That
host/port contract is the only thing the device depends on — everything else here is how this one
instance happens to be deployed. The device itself is documented in
[`pi-inventory.md`](pi-inventory.md). State as of 2026-08-05 23:30.

This MagicMirror backend is itself being superseded by WiseKiosk; the device stays.

## Container

| | |
|---|---|
| Image | `magicmirror:chrome72` (local build, not GHCR) |
| Source | `~/MagicMirror` @ `fix/kiosk-chromium60-compat` (PR #121) — which branch actually produced the current image is not recorded |
| Config on host | `~/magicmirror-config/config.js` |
| Config in container | `/app/backend/config/config.js` |
| Published | host `8080` → container `8080`, serves at `http://<MIRROR_IP>:8080` |

```bash
docker run -d --name magicmirror --restart unless-stopped \
  -p 8080:8080 \
  -v ~/magicmirror-config/config.js:/app/backend/config/config.js:ro \
  magicmirror:chrome72
```

**Do not `docker pull ghcr.io/tjwise99/magicmirror:latest` over this.** The published image lacks
the compatibility fixes and will black-screen the kiosk. `--restart unless-stopped` is how it
survives a host reboot.

For fast frontend iteration, bind-mount the build: `-v ~/MagicMirror/frontend/dist:/app/frontend/dist:ro`.
**CSP hashes are computed at server startup**, so a rebuild still needs a container restart.

## Config

`~/magicmirror-config/config.js` is gitignored (never lived in the old repo) — modules must match
what the image bundles unprefixed (`OpenMeteo`, `DisneyWaitTimes`, `AviationWeather`, no `MMM-`
prefix).

Modules: `clock`, `OpenMeteo` (lat `<LAT>` / lon `<LON>`), six `DisneyWaitTimes` instances,
`AviationWeather` (`<METAR_STATION>` METAR) — nine in total. The CheckWX key is live and embedded in
the config.

## Networking

| | |
|---|---|
| Host address | `<MIRROR_IP>` via DHCP reservation on a `<ROUTER_MODEL>` |
| DHCP pool | `<LAN_HOST>` – `<LAN_HOST>` |
| Firewall | inbound TCP 8080, rule `MagicMirror 8080` |

The Yocto device reads its target URL from `KIOSK_URL`, generated into `/data/config/kiosk.conf` and
read by `kiosk.service` — see [`provisioning.md`](provisioning.md). That value must resolve to
`<MIRROR_IP>:8080`; the DHCP reservation is what keeps the address stable across host reboots.

> `<ROUTER_VENDOR>` gotcha: a reservation **outside the DHCP pool is silently ignored**. The pool
> started at `.100`, so reserving `.3` did nothing until the start was lowered to `.2`.

**When the replacement server arrives:** delete the reservation, give the new box `<MIRROR_IP>`, and
the kiosk needs no change.

## Module data sources

Both verified live 2026-08-05: **CheckWX** (`api.checkwx.com`, aviation METAR, needs the API key) and
**themeparks.wiki** (`api.themeparks.wiki/v1`, wait times, keyless).

`DisneyWaitTimes` reads **only** `queue.STANDBY.waitTime`. An attraction publishing only
`SINGLE_RIDER` or `PAID_STANDBY` renders blank rather than erroring, and `filterRides` matches names
by **exact string**, so any upstream rename silently drops a ride.

## Server-side costs

One socket.io session per page (not nine — module instances share a transport), upgrading to
WebSocket at ~4s. Assets are served gzip-compressed (`Content-Encoding: gzip`); the shipped bundle
is **103,578 B identity / 35,086 B gzip**.

## Ride-name drift

`reconcile-rides.py` (kiosk-reference) compares configured names against the
live API. All **83** configured names matched on 2026-08-05.

> **Two different metrics get quoted about rides.** *Name matching* — how many configured names still
> exist upstream — is what this tool reports and what "83 matched" means. *Standby publishing* — how
> many live attractions expose a `queue.STANDBY.waitTime` right now — depends on time of day and is
> what a figure like "33 of 35" means. A closed park drives the second to zero while leaving the first
> at 100%. Always say which one a number is.
>
> The tool writes `tools/reconcile.json` **inside this repo**, overwriting the previous run and
> recording no timestamp. Re-running destroys the prior sample.
