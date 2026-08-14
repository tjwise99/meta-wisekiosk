# Mirror deployment (the server side)

What the kiosk points *at*. The Pi is [`pi-inventory.md`](pi-inventory.md). State as of 2026-08-05
23:30 — a **stopgap** on the Windows/WSL workstation after the unraid server died; a replacement is
planned.

## Container

| | |
|---|---|
| Image | `magicmirror:chrome72` (**local build**, not GHCR) |
| Source | `~/MagicMirror` @ `fix/kiosk-chromium60-compat` (PR #121) — see caveat |
| Config on host | `~/magicmirror-config/config.js` |
| Config in container | `/app/backend/config/config.js` |
| Published | host `8080` → container `8080`, serves at `http://192.168.1.3:8080` |

```bash
docker run -d --name magicmirror --restart unless-stopped \
  -p 8080:8080 \
  -v /home/tjwise/magicmirror-config/config.js:/app/backend/config/config.js:ro \
  magicmirror:chrome72
```

> **Superseded 2026-08-06:** previously recorded as `magicmirror:chrome60`. `docker ps` shows
> `magicmirror:chrome72`, a newer local build carrying the module-only bundle. **Which branch built it
> is not recorded anywhere** — the `Source` row names the branch that produced the *earlier* image.
> Open item in `STATUS.md` (kiosk-reference).

> **Do not `docker pull ghcr.io/tjwise99/magicmirror:latest` over this.** The published image lacks
> the compatibility fixes and will black-screen the kiosk.

Engine is **Docker Desktop** (WSL integration), which publishes ports onto the Windows host — so no
`netsh portproxy` and no `.wslconfig` changes. Docker Desktop is in the Windows `Run` key, so the
container returns after a reboot via `--restart unless-stopped`.

For fast frontend iteration, bind-mount the build: `-v ~/MagicMirror/frontend/dist:/app/frontend/dist:ro`.
**CSP hashes are computed at server startup**, so a rebuild still needs a container restart.

## Config

`~/magicmirror-config/config.js` was reconstructed from `~/config_legacy.js` — the original was deleted
with the old repo and is gitignored, so it was never in git. Only change: dropping the `MMM-` prefix
from three module names (`OpenMeteo`, `DisneyWaitTimes`, `AviationWeather`), which the updated image
bundles unprefixed. Ride lists and the CheckWX API key carried over byte-identical.

Modules: `clock`, `OpenMeteo` (lat `<LAT>` / lon `<LON>`), six `DisneyWaitTimes` instances,
`AviationWeather` (`<METAR_STATION>` METAR) — nine in total. The CheckWX key is live and embedded in
the config.

## Networking

| | |
|---|---|
| Host address | `192.168.1.3` via **DHCP reservation** on a `<ROUTER_MODEL>` |
| Windows NIC MAC | `<WORKSTATION_MAC>` (adapter `Ethernet 2`) |
| DHCP pool | `192.168.1.2` – `192.168.1.200` |
| Firewall | inbound TCP 8080, rule `MagicMirror 8080` |

`http://192.168.1.3:8080` is baked into `~/mmClient.sh`, so the server must answer on that address.
A reservation is how — **the adapter stays on DHCP**.

> **Do not set a static IP with `netsh interface ipv4 add address`.** On a DHCP adapter it silently
> converts the interface to static and discards the DHCP-supplied gateway and DNS, taking the machine
> off the internet. This happened.
>
> `<ROUTER_VENDOR>` gotcha: a reservation **outside the DHCP pool is silently ignored**. The pool
> started at `.100`, so reserving `.3` did nothing until the start was lowered to `.2`.

**When the replacement server arrives:** delete the reservation, give the new box `192.168.1.3`, and
the kiosk needs no change.

## Module data sources

Both verified live 2026-08-05: **CheckWX** (`api.checkwx.com`, aviation METAR, needs the API key) and
**themeparks.wiki** (`api.themeparks.wiki/v1`, wait times, keyless).

`DisneyWaitTimes` reads **only** `queue.STANDBY.waitTime`. An attraction publishing only
`SINGLE_RIDER` or `PAID_STANDBY` renders blank rather than erroring, and `filterRides` matches names
by **exact string**, so any upstream rename silently drops a ride.

## Two server-side costs, both fixed 2026-08-06

Evidence kept because it is what made the case for the fix.

**Nine socket.io connections instead of one.** The backend broadcasts per namespace (`node_helper.ts`:
`io.of(this.name).emit(...)`), but the frontend's `moduleSocket()` passed `forceNew: true`, so each of
the nine module instances opened its own transport — past the browser's six-per-origin limit,
handshakes queuing ~7s each, never upgrading off XHR long-polling.

> **Superseded 2026-08-06:** fixed. The deployed bundle no longer passes `forceNew` from app code.
> Result is **1** session upgrading to WebSocket at ~4s — the Raspbian card notes (kiosk-reference `raspbian-card.md`) §"Results".

**Nothing was compressed.** Assets were served `identity`:

| Asset | Bytes |
|---|---|
| `index-legacy-*.js` | 132,888 |
| `index-*.js` | 101,225 |
| `polyfills-legacy-*.js` | 85,080 |
| `index-*.css` | 27,476 |

~347KB over Wi-Fi to a 1GHz ARM11, uncompressed. One Express middleware.

> **Superseded 2026-08-06:** fixed. `Content-Encoding: gzip` is present and the legacy bundle is gone.
> Those four assets are the **pre-fix** build; the shipped bundle is now **103,578 B identity / 35,086 B
> gzip**. Both sets are real measurements of different builds — chronological, not corrective.

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
