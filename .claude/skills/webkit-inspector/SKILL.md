---
name: webkit-inspector
description: >-
  Drive the kiosk's WebKit remote inspector from the workstation to get GC and heap ground truth the
  page cannot report about itself — which garbage collections fire and when (full vs eden), and what
  classes of object are on the heap or accumulating. Invoke when a stall or slowdown looks like a
  garbage-collection pause, when you need to name what a tick allocates, when performance.memory /
  FinalizationRegistry / JSC_* logging have come back empty on this board, or when a past session
  reports "the inspector doesn't work here." Not for frame timing — the inspector perturbs it; use
  the measure-first in-page probes for fps and stall rate.
---

# The WebKit remote inspector, actually connected

This board runs WebKit 605 (webkit2gtk-4.1). Its JavaScriptCore gives the page **no** self-instrumentation
that survives a saturated core: `performance.memory` is absent, `FinalizationRegistry` callbacks never
fire (no idle turn to deliver them), and `JSC_logGC` / other `JSC_*` options are compiled out. The one
instrument that reports the collector and the heap from the engine is the **remote inspector** — and
several sessions failed to connect to it. The reason is one environment variable, below.

## The one thing that sank every prior attempt

There are two server env vars and they are not interchangeable:

- **`WEBKIT_INSPECTOR_SERVER`** — the `inspector://` variant. A **WebSocket-only** server: a plain
  `GET /` connects at the TCP layer and then **hangs with zero bytes**, forever. Only another WebKit
  browser opening `inspector://host:port` can use it. This is what the launcher sets, and what every
  HTTP-based client (including this repo's own earlier `inspect*.mjs`) waits on until it times out.
- **`WEBKIT_INSPECTOR_HTTP_SERVER`** — serves the **HTML target-list page** at `GET /`, which carries
  the WebSocket path. This is the one a script can drive.

`recipes-core/kiosk-session/files/kiosk-launch` wires `KIOSK_INSPECTOR=1` to the **WS-only** variant,
so following its own "turn it on over SSH" comment gives a server that hangs. Enable the HTTP variant
over the wire instead — no rebuild:

```sh
# on the board, in /data/config/kiosk.conf (the kiosk.service EnvironmentFile)
KIOSK_INSPECTOR=0                                 # stop the launcher binding the WS-only server (same port)
WEBKIT_INSPECTOR_HTTP_SERVER=127.0.0.1:2999       # loopback only — reach it through the tunnel below
# then: systemctl restart kiosk
```

Bound to loopback on purpose; reach it from the workstation with a forward:

```sh
ssh -L 2999:127.0.0.1:2999 -N root@<board>        # resolve <board> from local/device-identity.md
```

Restore `kiosk.conf` (`KIOSK_INSPECTOR=0`, no `WEBKIT_INSPECTOR_HTTP_SERVER`) and restart when done —
the inspector is a listening server and a perturbation, not a thing to leave running on prod.

## The client

[`webkit-inspect.mjs`](webkit-inspect.mjs) runs on the **workstation** (the board has no node); it needs
the tunnel above and Node ≥ 20 (global `fetch` + `WebSocket`). It handles the whole protocol.

| Command | What it gives |
|---|---|
| `node webkit-inspect.mjs eval '<js>'` | `Runtime.evaluate` — read any in-page value (`document.title`, a probe counter, `.marquee` node count) |
| `node webkit-inspect.mjs gc <seconds>` | every garbage collection over the window, **full vs eden**, with the gap between full collections — the GC ground truth |
| `node webkit-inspect.mjs census [topN]` | the heap right now, **bytes + object count per class** (`Object`, `Function`, `Map`, `string`, …) |
| `node webkit-inspect.mjs diff <seconds>` | census, wait, census again — the classes that **grew**; each snapshot forces a GC first, so a survivor is *promoted* growth, which is what paces a full-GC stall |

## The protocol, if you ever hand-roll it

Three facts, each load-bearing and each a departure from the Chrome DevTools Protocol:

- The target list is **HTML at `/`**, not JSON at `/json/list`. The WebSocket path is embedded in the
  Inspect button as `ws=' + window.location.host + '<path>'` — on this board `/socket/1/1/WebPage`.
- Every call is wrapped in **`Target.sendMessageToTarget`** and every reply/event comes back inside a
  **`Target.dispatchMessageFromTarget`** event. Match response ids and read event methods on the
  **inner** message, not the outer envelope. `Target.targetCreated` announces the `targetId` you must
  quote in every wrapper.
- `Heap.garbageCollected` events only flow **between `Heap.startTracking` and `Heap.stopTracking`** —
  `Heap.enable` alone emits nothing. On this build the event's `startTime`/`endTime` read **0**, so the
  client times collections by **arrival wall-clock**, not the engine's stamp.

Heap snapshots are WebKit **HeapSnapshot v2**: `nodes` is a flat array of 4-int records
`[id, size, classNameIndex, flags]`; the class name is `nodeClassNames[classNameIndex]`. Census is a
count and byte-sum per class; a diff of two censuses names what accumulates.

## Gotchas that cost real time

- **One connection at a time.** A hung or half-open connection (an earlier client that timed out, a
  browser tab left open on the port) blocks the server, and then even a correct `GET /` hangs. If the
  server stops answering, `systemctl restart kiosk` clears it — a stuck client, not a broken protocol,
  is the usual cause of "it worked yesterday."
- **It perturbs frame timing.** Attaching the inspector and enabling Heap tracking add main-thread
  work. Trust it for *which* collection fired and *what* is on the heap; do not read fps or stall rate
  off a board with the inspector attached — that is [`measure-first`](../measure-first/SKILL.md)'s job,
  with the page's own rAF probes.
- **The client is on the workstation.** The board has no node, python, curl or socat — only wget and a
  minimal busybox nc. Do discovery and protocol work through the tunnel from here.
- **Record under R1–R3** like any other run ([`../../../CONTRIBUTING.md`](../../../CONTRIBUTING.md)
  §"Documentation conventions"): name the board role and image commit, and commit the client beside the
  investigation if a number depends on it.
