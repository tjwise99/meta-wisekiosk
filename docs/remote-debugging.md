# Debugging a display you cannot see

No keyboard, no visible console, and a screen whose *correct* state is a black background —
indistinguishable from every failure mode. "Working", "browser crashed", "JavaScript threw" and "X
never started" all look the same from the room. Everything here replaces looking at the screen with
reading something definite.

## Recipe 1 — Read the browser directly

Everything else is inference; this is evidence.

Enable the DevTools endpoint in the launcher:
`chromium-browser --kiosk --remote-debugging-port=9222 --app=http://host:8080`
It binds to `127.0.0.1` only, so reach it over SSH rather than exposing it.

```bash
ssh pi@KIOSK 'curl -s http://127.0.0.1:9222/json/version'   # real browser version
ssh pi@KIOSK 'curl -s http://127.0.0.1:9222/json'           # each page's webSocketDebuggerUrl
```

> **The two endpoints come up minutes apart, and confusing them looks like total failure.**
> `/json/version` answers as soon as the browser process is up; `/json` has no `page` target until the
> tab exists — a ~8 minute gap for Chromium 72 cold. A poll written against `/json` alone reported
> `NO_CDP_TARGET` throughout and read as "the browser never started". Poll `/json/version` for
> liveness, `/json` for readiness.

Reload and capture the console with `cdp.py` (kiosk-reference) — no dependencies, runs on
Python 3.5 (so **no f-strings**):

```bash
cat tools/cdp.py | ssh pi@KIOSK 'cat > /home/pi/cdp.py
WS=$(curl -s http://127.0.0.1:9222/json \
  | python3 -c "import sys,json; t=[x for x in json.load(sys.stdin) if x.get(\"type\")==\"page\"]; print(t[0][\"webSocketDebuggerUrl\"])")
python3 /home/pi/cdp.py 40 "$WS"'
```

Stage helpers in `/home/pi`, not `/tmp` — `/tmp` is cleared on reboot, and a vanished helper produces a
`No such file or directory` that reads as a broken kiosk. This recipe originally used `/tmp/cdp.py`.

It enables `Runtime`, `Log`, `Page`, `Network`, issues `Page.reload`, then prints exceptions, console
calls, error/warning log entries and failed requests. **This is what ended the investigation** — hours
of inferring from socket states produced nothing; the first CDP run named the fault in one line.

> **Why not a tunnel?** `ssh -L 9222:127.0.0.1:9222 -N` is the obvious approach and did not bind
> reliably here. Running the client on the Pi sidesteps it.

## Recipe 2 — Infer state from TCP when you have nothing else

From a machine that can see the server:

```bash
netstat -an | grep '<KIOSK_IP>' | grep ':8080' | awk '{print $4}' | sort | uniq -c
```

| Pattern | Means |
|---|---|
| No connections | Browser not running, or not attempting |
| **1** connection → `FIN_WAIT_2`/`TIME_WAIT` | Fetched the HTML only. Scripts never ran — parse failure or module ignored |
| **3** connections, then closed | Fetched HTML + JS. Scripts fetched but did not execute — **CSP** or an early throw |
| **1** `ESTABLISHED`, sustained | Rendering correctly, one multiplexed socket. **The healthy state** |
| **9** `ESTABLISHED`, sustained | Rendering, one connection per module — the pre-2026-08-06 bug signature |

"1" appears twice with opposite meanings: a single connection that *closes* is failure, one that
*stays* `ESTABLISHED` is success. State and persistence discriminate, not the count.

> **The last row was originally written as "Many `ESTABLISHED`, sustained → Rendering", i.e. a health
> signal.** It was the bug: nine connections is one per module, exceeding the six-per-origin limit and
> never upgrading off long-polling. Reading it as success hid the largest bring-up cost on this device
> for an entire session. **When the count is what you are reading, ask what the *right* count is.**

## Recipe 3 — Find a device whose address you do not know

```bash
for i in $(seq 1 254); do (ping -c1 -W1 192.168.1.$i >/dev/null 2>&1 &); done; sleep 5
arp -a | grep -i 'b8-27-eb\|dc-a6-32\|e4-5f-01\|28-cd-c1\|2c-cf-67'   # Raspberry Pi OUIs
```

**A device missing from the router's client list is not necessarily offline** — those lists are built
from DHCP leases, so a static or long-leased host can be invisible while perfectly reachable.

## Recipe 4 — Get in when SSH was never enabled

Both work with only the SD card and a Windows machine:

- **Enable SSH:** put an empty file named `ssh` (no extension) in the root of the **FAT boot
  partition**. Raspberry Pi OS enables `sshd` on next boot.
- **Reset a lost password:** `pi` has **passwordless sudo**, so any shell as `pi` runs `sudo passwd pi`
  with no prior credential. Get a shell via keyboard and `Ctrl+Alt+T`; only if the desktop is
  unreachable do you need `init=/bin/sh` appended to `cmdline.txt`.

Ordinary desktop Linux tooling does **not** help read the root filesystem from Windows:

- `wsl --mount` **refuses removable media** — SD readers present as `MediaType: Removable Media` and it
  fails with `Wsl/Service/AttachDisk/MountDisk/HCS/0x8007000f`. No flag combination fixes it.
- It fails with the *same code* if the disk is **offline** in Windows, and a failed attempt leaves it
  offline — so retries fail for a different reason than the first attempt. Always
  `Set-Disk -Number N -IsOffline $false` before retrying.

For read-only ext4 access from Windows, use a dedicated reader (e.g. DiskInternals Linux Reader).

## Recipe 5 — Launch a GUI process over SSH so it survives

Naive `nohup … &` produced a Chromium that died ~40s later with empty logs. The X session's
environment is required — `DBUS_SESSION_BUS_ADDRESS` and `XDG_RUNTIME_DIR` were the missing pieces;
`DISPLAY` alone is not enough.

```bash
# discover from an already-running session process
P=$(pgrep -f 'chromium-browser --start-maximized' | head -1)
tr '\0' '\n' < /proc/$P/environ | grep -E '^(DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR)='

export DISPLAY=:0 XAUTHORITY=/home/pi/.Xauthority \
       XDG_RUNTIME_DIR=/run/user/1000 \
       DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
setsid bash -c "chromium-browser ... > /tmp/kiosk.log 2>&1" < /dev/null > /dev/null 2>&1 &
disown
```

**When in doubt, reboot instead.** A reboot exercises the real autostart path; a fault in your launch
method is indistinguishable from a fault in the thing you are testing.

## Recipe 6 — Scan a build for browser compatibility

```bash
python3 tools/scan-bundle.py --target 72 dist/assets/*.js dist/assets/*.css
```

Reports the minimum Chrome version implied by syntax, runtime APIs and CSS. Use it to **verify** a
build-target change rather than trusting the flag. The target is **72**; this recipe previously said
60. Paths are relative to two different repositories — `tools/` here, `dist/assets/` in the MagicMirror
checkout — so give at least one an absolute path.

`--html index.html` additionally counts `type=module`, `nomodule` and inline `<script>` blocks: the
check that catches a build shipping **both** bundles, and that tells you how many CSP hashes a strict
`script-src 'self'` needs.

## Recipe 7 — Stop paying a key exchange per command

A debugging session is dozens of small SSH commands, and on this device each one is not free: the
key exchange runs on the same saturated 1GHz ARM11 core the browser renders on. Handshake cost is
**kiosk load**, not just your latency.

`ssh` multiplexing opens one connection and reuses it. `kiosk-ssh.sh` (kiosk-reference)
wraps it:

```bash
tools/kiosk-ssh.sh 'uptime -p'              # command
tools/kiosk-ssh.sh 'bash -s' <<'EOF'        # script, still one round trip
systemctl is-active kiosk-rngd
cut -d' ' -f1 /proc/loadavg
EOF
tools/kiosk-ssh.sh --close                  # drop the master; also expires after 30m
```

| | Measured 2026-08-06 |
|---|---|
| Cold connect (builds master) | **1.77 s** |
| Warm, per call | **0.083 s** (n=3) |
| Warm, per call (second run) | 0.05 s (n=3) |

**It installs nothing on the Pi** — the master lives on the client — so it cannot touch the lifeline.

Three things that bite:

- **The control socket path caps at ~108 characters.** A long path fails with `too long for Unix
  domain socket` on *every* call, including the first, so it looks like a connection failure rather
  than a path problem. Keep the socket in `~/.ssh/`.
- **Do not add `LogLevel=ERROR` to silence the post-quantum banner.** That banner is expected noise
  on cold connect against this EOL sshd, but suppressing it suppresses genuine connection errors
  too — the same failure as `2>/dev/null` on a probe, below.
- **A master orphaned by a device reboot is the expected stale case** — the wrapper sets
  `ServerAliveInterval=15` / `ServerAliveCountMax=4` so it fails in ~60s rather than hanging. This
  path is **reasoned, not measured here** (it would take a reboot to exercise). If commands stop
  responding after a reboot, run `--close` before diagnosing anything else.

Batching still matters on top of this: prefer one `bash -s` heredoc over ten calls, which is why
`kiosk-probe.sh` (kiosk-reference) is a single round trip by construction.

## Recipe 8 — Read the soak log

`kiosk-soak.sh` (kiosk-reference) appends one line every 5 minutes to
`/home/pi/kiosk-soak.log`, driven by `kiosk-soak.timer`. It exists because soak questions were
being answered from two hand-taken samples hours apart, which cannot separate *flat* from *leaking
slowly*.

`kiosk-soak.sh --summary [N]` — with `N` a sample count, omitted for the whole log. At one sample
per 5 minutes, 12 is the last hour and 288 the last day.

```bash
tools/kiosk-ssh.sh 'kiosk-soak.sh --summary'        # whole log
tools/kiosk-ssh.sh 'kiosk-soak.sh --summary 288'    # last 288 samples = last 24 h
tools/kiosk-ssh.sh 'tail -3 /home/pi/kiosk-soak.log'
```

One sample costs **0.75–0.90 s** on this core, so read the log, do not poll it in a loop.

### The fields

| Key | Is |
|---|---|
| `ts` / `iso` | epoch and local time of the sample |
| `boot` | first 8 of `boot_id`. **Changes = the device rebooted**, and the series either side is not one series |
| `up` | uptime seconds |
| `load1/5/15` | load averages; `load1` includes this sampler's own wake-up |
| `temp` / `thr` | °C, and `vcgencmd get_throttled`. Anything but `0x0` means it throttled *at some point since boot* |
| `memused` / `memavail` | system MB |
| `ent` | entropy pool. Low is expected — `kiosk-rngd` is deliberately off for surf |
| `disk` | percent used on `/` |
| `browser` | comm of the binary the launcher invokes, discovered per sample, never hardcoded |
| `pid` | main browser pid. **Changes = the browser restarted**; `none` = it was not running at all |
| `nproc` | processes in the browser family (surf + WebKit\*, or chromium\*) |
| `rss_main` | RSS of the launcher process only |
| `rss_total` | RSS across the whole family. **This is the memory number that matters** — the renderer is a separate process and holds most of it |

### Reading a summary

```
  samples          81 over 6.7 h
  reboots          0
  browser restarts 0
  samples w/o browser  0
  rss_total range  163988 .. 165592 kB
  rss_total ends   163988 -> 165452 kB (endpoint delta +1464 -- NOT a rate)
  hourly mean       165139 165397 165434 165380 165406 165368 165312
  slope all        +20.2 kB/h  (n=81)
  slope excl hour0 -15.0 kB/h  (n=69)   <-- quote this one
```

Read it in this order:

1. **`reboots` and `browser restarts` first.** Non-zero means the memory series is two series and no
   rate across it means anything; `--summary` refuses to print one.
2. **`samples w/o browser`.** Non-zero means the kiosk was actually down at those samples.
3. **`hourly mean`.** This is the shape. Warm-up rising then flat looks nothing like a genuine climb,
   and the two have identical endpoints.
4. **`slope excl hour0`** — the figure to quote. Warm-up is not a leak.

A healthy window looks like the one above: hourly means inside a ~±150 kB band on a ~165 MB working
set, and a slope whose sign is not stable between windows.

> **Do not use "the slope survives excluding warm-up" as the leak test — it gives false positives,
> and this section used to say exactly that.** On 2026-08-08 a 22.8 h window read `slope excl hour0`
> **+127.8 kB/h** with near-monotonic hourly means, and there was no leak. Segmented, it was eight
> hours flat (+24.9 kB/h), a 1.4 MB step over two hours (+438.2 kB/h), then six hours flat
> (+34.4 kB/h). One line through a step function reports the step as a rate — the endpoint-delta bug
> in different clothes, a summary statistic assuming a shape the data does not have.

**Read the hourly means for flat stretches before trusting any slope.** A leak does not hold still
for eight hours and then hold still again at a new level; it accumulates. The flat stretches are what
distinguish the two, not the fitted rate.

**A step usually has a cause outside the browser, so check the page before suspecting the renderer.**
That one was the theme parks opening: every DisneyWaitTimes row went from `Closed` to a live wait
time between 08:00 and 10:00, which is more DOM and more text. Screenshot both sides of a step and
compare content — the same screenshot the liveness check already needs.

> **But a content-caused step does not have to reverse when the content does, so finding the cause
> settles less than it looks.** When the parks closed the rows went back to `Closed` and `rss_total`
> stayed **1.66 MB above** the matched closed-state window 24 h earlier — the allocator keeps the
> pages rather than returning them. Identifying the content explains the step's *timing* and says
> nothing about whether it recurs.
>
> **So compare matched content states 24 h apart, never before-and-after the step.** A before/after
> comparison spans the content change, which guarantees a difference and answers a question nobody
> asked. Closed-state against closed-state is the comparison that distinguishes a one-time working-set
> expansion from a daily ratchet.

### Things that bite

- **The endpoint delta is not a rate, and it is the trap this tool was built around.** On the first
  real 6.5 h window an endpoint estimator read **+192.6 kB/h** — 4.6 MB/day, indistinguishable from a
  slow leak — while the true fit was **+21.4**, and **−15.8** excluding warm-up. The first sample
  merely happened to be the lowest. `--summary` still prints the endpoint delta, labelled `NOT a
  rate`, because seeing it next to the fit is what makes the difference legible.
- **A two-point series returns `n/a`, not a fit.** A line through two points is the endpoint
  estimator wearing a hat.
- **`load1` is contaminated by the sampler itself.** Do not read peak `load1` as kiosk load.
- **Gaps in `ts` are missed samples.** Consecutive differences should be ~301 s; anything larger
  means the timer did not fire and the window has a hole in it.
- **None of this can detect a frozen page.** Every field here would look identical if the display had
  been showing a stale render for hours — process alive, memory flat, load normal. Liveness is a
  separate check: screenshot the kiosk and compare the rendered clock against `date` on the device,
  and confirm fetched data (the METAR observation ID) has advanced. On the Yocto image the capture
  path has its own trap — [`remote-debugging.md`](remote-debugging.md) §"Recipe 9 — Screenshot the Yocto kiosk, and read the capture correctly".

Earlier windows are archived beside the live log as `kiosk-soak.log.pre-*`; they are kept because
they are the evidence for the findings above, not because they are still accumulating.

## Recipe 9 — Screenshot the Yocto kiosk, and read the capture correctly

The liveness check Recipe 8 ends on needs pixels. Getting them here has already cost one session to a
misdiagnosis — read the history note below before assuming which tool is available.

There is no `scrot` and no `fbgrab` on this image. **`import -window root`** (imagemagick,
`/usr/bin/import`) is the verified-working capture path:

```sh
ssh root@<addr> 'date "+%H:%M:%S"; import -window root /data/shot.png'   # /tmp is tmpfs; /data survives
scp root@<addr>:/data/shot.png . && ssh root@<addr> 'rm -f /data/shot.png'
```

No post-processing needed — `import` writes correct, opaque pixels directly. Verified 2026-08-12
evening: 1824×984, 8-bit grayscale, opaque, `min=0 max=255 mean=4.4` — matching this recipe's own
healthy-capture signature below.

A healthy mirror capture reads `rgb min=0 max=255 mean≈4` — black background, sparse light text. A
*mean* near zero is normal and is not evidence of a blank screen; `min == max` is.

**Then compare content against live data, which is the whole point** — the rendered clock against the
`date` taken in the same command, and the METAR observation ID against the current cycle. A frozen
render passes every check in Recipe 8. Verified this way 2026-08-12 evening: clock read `7:35:48 pm,
Wednesday August 12 2026` against `date` in the same command returning `19:35:48`; METAR
`KDAB 122253Z`, the current cycle; wait times varied; font rendered as Roboto Condensed, not DejaVu.

> **History: `fbgrab` was misdiagnosed as broken, removed from the image on that diagnosis, and only
> then was the real defect found.** Early in the Yocto bring-up, `fbgrab` returned a wholly white PNG
> against a screen that was demonstrably rendering the kiosk correctly, and that was read as "not a
> usable capture path." On that diagnosis, `fbgrab` was dropped from `IMAGE_INSTALL` in
> `meta-wisekiosk` (2026-08-11 00:19, `2277899`), swapped for `imagemagick`. **Twenty hours later**
> (2026-08-11 20:04, `kiosk-reference` `f07d697`) the real defect was found: `fbgrab` writes RGBA with
> every alpha byte 0, so a naive viewer composites the image onto white — the tool was fine, the
> reader was wrong. `fbgrab-fix.py` (kiosk-reference) was written to strip the bogus
> alpha and diagnose which failure a capture actually has. **The correction landed only in the docs**
> — the image manifest never regained `fbgrab`, so this recipe went on prescribing a tool the image
> does not ship. `fbgrab` is not installed on this image, and `tools/fbgrab-fix.py` is not needed for
> the `import`-based path above; both are kept only as a record of the failure mode, in case `fbgrab`
> ever returns to the image.

## Recipe 10 — Profile the boot: is the core busy, blocked, or queued?

`kiosk-bootprof` is **in the image but not enabled** — it costs ~240 ms of the boot it measures.
Enable, reboot, read, disable.

```bash
ssh root@<kiosk> 'systemctl enable --now kiosk-bootprofile && systemctl reboot'
# it samples to uptime 150, then writes one file
ssh root@<kiosk> 'ls -la /data/boot-cpu-io.*.txt'
scp root@<kiosk>:/data/boot-cpu-io.<boot_id>.txt .
ssh root@<kiosk> 'journalctl -b <boot_id_without_dashes> -o short-monotonic' > boot-cpu-io.<boot_id>.journal.txt
python3 tools/analyze-boot-cpu-io.py boot-cpu-io.<boot_id>.txt
ssh root@<kiosk> 'systemctl disable kiosk-bootprofile'
```

Name the journal file `<same-stem>.journal.txt` beside the samples — the analyzer looks for exactly
that and derives each window's edges from it. Without it you get hardcoded defaults, which are wrong
the moment anything moves. `journalctl -b` wants the boot ID **without dashes**; `-b -1` does not
work on this image at all (every boot shares a pre-timesync first-entry timestamp).

**Reading it.** Three numbers decide what a change can buy:

| Column | Means |
|---|---|
| `busy%` ~100 with `idle%` 0.00 | core saturated — only removing work helps |
| `idle%` / `iowait%` above zero | slack here; overlapping work can use it |
| `scheduling headroom` | idle + iowait over the boot — a **hard ceiling** on any reorder |

`#M` lines are a module first-seen timeline. That is what found the camera stack loading ahead of
`brcmfmac`, and it is the only view of it — module loads mostly do not log:

```bash
grep '^#M ' boot-cpu-io.*.txt | tail -n +2 | awk '{printf "%7.2f  %s\n", $2, $3}' | sort -n
```

**Its own cost is in the header** (`self_cpu_us=`), so the instrument never has to be inferred.
`late_samples=` should be 0; anything else means the core was too busy to hold the sample grid. It
does not cover the first ~7 s — systemd cannot start a unit before it starts.

## Recipe 11 — Time to complete display, not to `load_finished`

`measure-surf.sh` is in the image. Complete display is when the weather icons render — the only
endpoint a viewer sees, and deliberately **not** `loadEventEnd`: the modules keep fetching after
surf's load event.

```bash
ssh root@<kiosk> '/usr/bin/measure-surf.sh 115'   # sleeps to uptime 115, then reads once
```

It reports the **monotonic** form, `uptime_at_exec + load_started + performance.now()`. Do not compute
it from wall clock: this board has no RTC and no `fake-hwclock`, so every boot starts in the past and
`timesyncd` only steps it forward once the network is up, so an epoch-based figure can read ~30 s low.

Nothing is polled during startup. The page self-timestamps into its own window title, so reading it
late does not change the value — an earlier version polled `xprop` every 2 s and inflated the number
it was reading.

**The gap between `load_finished` and complete display is 3.5–6.5 s and belongs to the page, not the
boot.** Baseline spread across three boots is 2.24 s, so treat any complete-display delta under ~2 s
as noise.

## Gotchas that cost real time

- **`pgrep -f <pattern>` matches your own command line** over SSH, so `ps -p $(pgrep …)` echoes your own
  shell. Use `pgrep -x`, or match the binary path.
- **Linux truncates process names to 15 characters** — `pgrep -x chromium-browser` finds nothing
  because the name is `chromium-browse`. Use `-f` with a path pattern.
- **Editing a shell script while bash is executing it** makes the running shell read new content from
  its old byte offset. Kill the process before rewriting its script.
- **Backgrounded SSH commands often return exit 1** even when the work succeeded. Verify by querying
  state afterwards, not by the exit code.
- **Chromium does not log JS console output to stderr by default**, and `--enable-logging=stderr --v=1`
  destabilised the browser here. CDP is the reliable path.
- **A browser cache can serve you a stale failure.** Use `Page.reload` with `ignoreCache: true`, and
  treat the first error after a config change with suspicion.
- **Never put `2>/dev/null` on a probe** — it converts a broken *check* into something
  indistinguishable from a broken *kiosk*. Three false "the kiosk is down" calls in one session.
- **`/tmp` is cleared on reboot**, taking any helper staged there with it.
- **`mmClient.sh` sleeps 10s between browser restarts.** A single `pgrep` landing in that gap reads as
  "the kiosk is down".
- **The clock jumps mid-boot**, so early journal timestamps are not comparable with later ones. On the
  Raspbian card `fake-hwclock` restores a stale time and `timesyncd` corrects it; on the Yocto device
  there is no RTC and no `fake-hwclock` — every boot starts in the past and only `timesyncd` moves it
  forward. Anchor on process start times or `boot_id`. If a before/after pair matches to three
  decimals, you measured the same boot.

## Iteration loop

Once the debug port exists, a frontend change is seconds rather than a reboot:

1. Rebuild the frontend (`npm run build`).
2. If the server bind-mounts `dist`, no image rebuild is needed:
   `-v /path/frontend/dist:/app/frontend/dist:ro`. **But** anything computed from the build at server
   startup — CSP hashes — still needs a container restart.
3. Reload and read the console via `cdp.py`.
4. Only reboot the kiosk to confirm the unattended path before declaring done.
