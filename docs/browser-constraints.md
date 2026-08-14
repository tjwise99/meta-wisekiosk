# Browser constraints on an ARMv6 kiosk

> **Chromium is out of scope entirely (owner, 2026-08-10), and the device now runs `surf` on
> WebKitGTK from a Yocto image.** The Chromium ceiling analysis below is therefore **history rather
> than constraint** — the condition [`yocto-ota-plan.md`](yocto-ota-plan.md) set for that transition
> (a new engine measured on the board) was met on 2026-08-11. It is kept because the *reasoning* about
> ARMv6, ES-module boundaries and CSP still applies to anything rendering on this hardware, and
> because the SL16G rollback card still runs Chromium 72.

Everything here is measured against the actual display host, not inferred from release notes. Where a
measurement contradicted a plausible inference, the measurement won and the inference is a trap.

## The ceiling is Chromium 72, not 60

> **Corrected 2026-08-06.** This document previously stated 60 was the ceiling with no upgrade path.
> Wrong. The evidence below is measured on the device.

The kiosk shipped with **Chromium 60.0.3112.89** (2017); the real ceiling is the package
`chromium-browser 72.0.3626.121-0+rpt4` (2019), the last Chromium built for ARMv6.

- **It is ARMv6.** The package ships *two* binaries and `/usr/bin/chromium-browser` picks between them
  on `uname -m`:

  | Binary | `Tag_CPU_arch` | Selected when |
  |---|---|---|
  | `chromium-browser` | **v6** | `armv6l` — this Pi |
  | `chromium-browser-v7` | v7 | everything else |

  Read with `readelf -A`, the selected binary reports **`Tag_CPU_arch: v6`**; the `-v7` variant reports
  v7.
- **It is already on the device.** All four debs have sat in `/var/cache/apt/archives` since
  2019-06-17, auto-downloaded by `apt-daily.timer` and never installed (installed binaries still have
  2017 mtimes; `rpi-chromium-mods` is still `20180302`). No repository access needed.
- **Dependencies are satisfied.** All 24 runtime deps installed at satisfying versions; only the codecs
  package was missing, and that is cached too.
- **It runs.** `--version` exits 0 and every shared library resolves.

Two things the old text got right for the wrong reason:

- **Do not reimage.** Buster was the last release with an ARMv6 Chromium, and that Chromium is 72.
  Bullseye's Chromium (>104) is ARMv7-built; Bookworm 32-bit installs on a Zero W but ships no ARMv6
  browser.
- **The archive the device is configured against is dead.**
  `raspbian.raspberrypi.org/raspbian stretch` returns 404, but
  `archive.raspberrypi.org/debian stretch` — the one holding Chromium — is **live**, and the cache
  makes even that moot. The stretch archive itself moved rather than vanished; see
  [`pi-inventory.md`](pi-inventory.md) §"Package archives and what can be installed".

## What each browser lacks

The **72** column is measured on the device by feature detection under the real binary. "Needs" is when
the feature shipped in Chrome.

**JavaScript syntax — a parse error, so nothing runs.** A single `??=` anywhere fails the **whole
module** at parse time, with no partial degradation and nothing in the UI to say so.

| Feature | Needs | 60 | 72 |
|---|---|---|---|
| **ES modules** (`<script type="module">`) | **61** | ✗ *the killer on 60* | ✓ |
| `nomodule` attribute | 61 | ✗ | ✓ |
| class fields | 72 | ✗ | ✓ |
| optional chaining `?.` | 80 | ✗ | ✗ |
| nullish coalescing `??` | 80 | ✗ | ✗ |
| logical assignment `??=` `\|\|=` `&&=` | 85 | ✗ | ✗ |
| static blocks | 94 | ✗ | ✗ |

On 60, Chrome ignores `type="module"` entirely — no error, no execution, blank screen. **On 72 that
barrier is gone**, which is what makes dropping `@vitejs/plugin-legacy` possible.

**Runtime APIs — a TypeError, so it dies mid-render.** Bundlers lower *syntax*; they do not add
*APIs*.

| API | Needs | 60 | 72 |
|---|---|---|---|
| `Promise.allSettled` | 76 | ✗ | ✗ |
| `String.prototype.replaceAll` | 85 | ✗ | ✗ |
| `Array.prototype.at` | 92 | ✗ | ✗ |
| `Object.hasOwn` | 93 | ✗ | ✗ |
| `structuredClone` | 98 | ✗ | ✗ |

`replaceAll` is the one that bites — **Svelte 5's own runtime calls it**, so any Svelte 5 app needs it
polyfilled regardless of your code. **The upgrade to 72 does not help**; the polyfill stays.

**CSS — degrades quietly, which is worse.** CSS custom properties (49) are fine on both.

| Feature | Needs | 60 | 72 | Effect when missing |
|---|---|---|---|---|
| **flex `gap`** | 84 | ✗ | ✗ | Ignored — elements sit flush |
| **grid `gap`** | 57 | ✓ | ✓ | — |
| `clamp()` / `min()` / `max()` | 79 | ✗ | ✗ | Declaration dropped |
| `aspect-ratio` | 88 | ✗ | ✗ | Ignored |
| `inset` shorthand | 87 | ✗ | ✗ | Ignored |
| `:is()` | 88 | ✗ | ✗ | Selector never matches |
| `:has()` | 105 | ✗ | ✗ | Selector never matches |
| CSS nesting | 112 | ✗ | ✗ | Rules dropped |

> **`CSS.supports("gap", "1px")` returns `true` on Chromium 72 and is a false positive.** The query
> parses the property without a layout context, and `gap` has been valid on *grid* since 57. Measured
> geometry, two 100px boxes with `gap:50px`: `display:flex` → **0px**, `display:grid` → 50px. Never
> accept a feature query as evidence here; measure `offsetLeft`. Useful consequence: fix outstanding
> `gap` rules by moving those containers to **`display:grid`**, needing no margin fallbacks.

## Is Chromium required? WebKitGTK 2.18 runs this frontend — with two shims

Tested on the device 2026-08-06. **It works**, and the gap is two symbols, not an engine rewrite.

**What is actually installable.** `legacy.raspbian.org` carries `firefox-esr` 52.9, `epiphany-browser`
3.22.7, `midori` 0.5.11, `surf` 0.7, `netsurf-gtk` 3.6. Two disqualify immediately: Gecko 52 predates
ES modules (Firefox 60) and this build is module-only with **zero** `nomodule` scripts; netsurf and
dillo have no usable JS engine.

> **The trap: every installable browser links the *old* engine.** Both `epiphany-browser` (the
> Raspberry Pi build is pinned at `1:3.8.2.0-0rpi28`, epoch-pinned above Debian's 3.22) and `surf` 0.7
> link **`libwebkitgtk-3.0.so.0` — WebKitGTK 2.4.11, from 2014**. The modern `libwebkit2gtk-4.0-37`
> **2.18.6** is installed but no browser package uses it. Testing either browser measures a 2014
> engine and says nothing about 2.18. Check `ldd`, or `/proc/<pid>/maps` for the running process —
> the package name will not tell you.

**Reaching 2.18 needs no build.** `python3-gi` is installed and `gir1.2-webkit2-4.0` is a small
typelib; ~15 lines of Python is a working WebKit2 browser, enough to load the real page offscreen
without disturbing the kiosk.

**Result, against the live mirror:**

| Attempt | Outcome |
|---|---|
| WebKitGTK 2.4.11 (epiphany, surf) | HTML+CSS load, **no script runs** — no ES modules |
| WebKitGTK 2.18.6, unmodified | Bundle **fetched**, no resource errors, **zero DOM** |
| … the error | `ReferenceError: Can't find variable: globalThis` |
| … + `globalThis` shim | `ReferenceError: Can't find variable: queueMicrotask` |
| … + both shims | **`MODS=9 WITHTEXT=9 ICONS=11 ERR<none>`** — renders fully |

Both are **Chrome 71** APIs. The whole incompatibility is ~100 bytes:

```js
if (typeof globalThis === "undefined") { window.globalThis = window; }
if (typeof queueMicrotask === "undefined") { window.queueMicrotask = function (cb) { Promise.resolve().then(cb); }; }
```

> **This is not an argument for the chrome65 branch.** `@vitejs/plugin-legacy` + core-js would also
> supply both symbols, but at ~115KB and the request/socket cost that made it the original performance
> problem. Two shims buy the same compatibility for ~100 bytes.

**Memory, measured while rendering the same page:** WebKit stack 164MB — but 59MB of that is the
Python harness. A native WebKit2 browser is `WebKitWebProcess` 68.5MB + `WebKitNetworkProcess` 33.3MB
= **~102MB against chromium's 188MB across 4 processes**, roughly **45% less**. **Startup speed was not
measured** and is not claimed: the Python harness is not a browser, and comparing it to the kiosk's
boot-to-render path would be comparing two different things.

### Run for real as the kiosk: a dead heat on speed, no memory win without more work

Deployed as the actual kiosk browser (fullscreen `Gtk.Window`, the two shims injected at
`document-start`, same `while true` retry loop, exercised by real reboots), 2026-08-06.

**It renders perfectly** — verified as pixels with `scrot`: clock, six parks, weather and forecast
icons, METAR, fullscreen with no browser chrome. Visually indistinguishable from Chromium.

Time to **complete display** — icons rendered, not `loadEventEnd`, measured the same way for both and
both with the prefetch disabled:

| | Samples | Spread |
|---|---|---|
| Chromium 72 | 70.4 / 71.5 s | 1.1 s |
| WebKitGTK 2.18 | **71.7 / 71.7 / 71.7 s** | **0.0 s** |

**A dead heat.** An earlier read of this claimed WebKit was ~6 s faster; that rested on a single
Chromium sample of 77.7 s taken on a slow boot, against a WebKit number that happened to be n=3.
Comparing a lucky sample with a careful one is how the earlier `nav+32s` error happened too.

| | Chromium 72 | WebKit 2.18 |
|---|---|---|
| Processes | 4 | 3 |
| RSS | 188 MB | 180 MB |
| — of which interpreter | — | **`python3` 81.9 MB** |

> **Corrected: that RSS comparison was measuring the wrong thing.** RSS counts every shared library
> page in full against *each* process, so a 4-process browser double-counts what a 3-process one counts
> three times. **PSS is the fair metric** — each process charged its share. Re-measured with
> `/proc/<pid>/smaps_rollup`:
>
> | | Rss | **Pss** | Private | procs |
> |---|---|---|---|---|
> | Chromium 72 | 263 MB | **180 MB** | 127 MB | 4 |
> | WebKit 2.18 + Python | 152 MB | **88 MB** | 59 MB | 3 |
>
> **WebKit uses 51% less memory, and that win exists as deployed — Python and all.** The earlier
> "180 vs 188 MB, it is noise" reading was an artifact of RSS.

**Removing Python is not the lever it looks like.** A bare `python3` + `gi` + `WebKit2` import is
Pss 12 MB / **Private 8 MB**; the running kiosk process is Pss 28 MB / **Private 14 MB**. So a native C
browser saves **~14 MB**, ~8% of the gap — against 60 packages and **8 display-stack upgrades**
(`dbus`, `libdbus-1-3`, `libglib2.0-0`, `libx11-6`, `libicu57`, `libxml2`) to get
`libwebkit2gtk-4.0-dev` onto a frozen system. The lifeline deny-list is clean, but `dbus`/`glib`/`libx11`
are what the display runs on.

> If it is ever built anyway, **do not install the `-dev` packages**: `apt-get download` them and
> `dpkg-deb -x` into a sysroot under `/home/pi`, then compile natively against those headers. `gcc`,
> `make` and `pkg-config` are already present, so this needs no cross-toolchain and performs **zero**
> dpkg operations. Upstream `surf` 2.0+ targets webkit2gtk; the archived `surf` 0.7 does not.

### Native browser built and run: slower, heavier, and visibly wrong

`surf` 2.0 was patched (the two shims as a `document-start` UserScript, `KioskMode` and
`RunInFullscreen` set) and **built natively on the Pi** — a 36KB binary in 42s, linking
`libwebkit2gtk-4.0.so.37`. It ran as the real kiosk across reboots. All three predictions were wrong.

| Time to complete display | |
|---|---|
| Chromium 72 | **70.4 / 71.5 s** |
| WebKit 2.18 + Python | 71.7 s |
| **Native `surf`** | **80 / 79 s** |

**Removing Python made it ~8s slower, not ~6s faster.** The prediction came from measuring the
interpreter's import cost (~6s) and assuming it was additive. It was not: `surf` starts at boot+34s,
the same as Chromium, so the Python import had been overlapping other startup work rather than
delaying the render.

| Memory (Pss) | |
|---|---|
| Chromium 72 | 180 MB |
| WebKit + Python | **88 MB** |
| Native `surf` | **105 MB** |

**Native was also heavier than Python.** Not a C-versus-interpreter effect — `surf` enables WebKit
features in `config.h` (disk cache, HTML5 database, local storage) that the minimal Python harness
left at leaner defaults. The comparison was never "C vs Python"; it was two different WebKit
configurations.

> **And it renders wrong.** On WebKit 2.18 the ride wait times collide with the ride names — 
> "…Motorbike Adventure™45" with no separation, where Chromium right-aligns the column. A **layout**
> defect from different font metrics and the old-engine flex behaviour this document already records,
> not mere antialiasing. A DOM check (`MODS=9 ICONS=11`) reported perfect health while the screen was
> visibly broken; only looking at the pixels caught it.
>
> **⚠ This no longer reproduces (2026-08-06, re-confirmed on the exact case 2026-08-07).**
> Screenshots of the live kiosk on WebKit, taken both with and without the `local()` alias, show the
> wait-time column right-aligned and separated in **both** arms — same ride content in each, so the
> comparison is clean. The collision was a **weight-400** substitution (ride names are weight 400),
> which installing `fonts-roboto-hinted` closed *before* this check; that attribution is inference,
> since testing it would mean removing the font package. The font-metrics leg of the defect is real
> and is what the alias fixes at weight 300 — but the specific collision recorded above is not
> currently observable.
>
> That first check was weaker than it looked: every row read `Closed`, so it never exercised a long
> name against a *numeric* wait time, which is the case the collision describes. A 2026-08-07
> screenshot taken with the parks open renders **"Hagrid's Magical Creatures Motorbike Adventure™"
> against `60`** — the same ride named above — with the number right-aligned and clear of the name.
> That is the documented case, and it is clean.

**The "visibly incorrect" leg of the WebKit verdict is no longer supported.** It remains slower and
heavier than the Python variant on the measurements below; the render defect that closed the path
does not reproduce. See `STATUS.md` (kiosk-reference) § "The `local()` trap — CLOSED on the device
2026-08-06, still open upstream" — and note that everything in this section was measured in an
environment that no longer exists.

**Recommendation: stay on Chromium 72 — but on narrower grounds than first written.** The memory
gain is real (51% by PSS) and speed is equal. What decides it is an engine 15 months older, and losing CDP — every measurement in this repository comes from Chromium remote
debugging, including the ones that produced this table. The one genuine WebKit advantage is
reproducibility (0.0 s spread across three boots, against Chromium's 1.1 s), which is interesting but
not worth the trade.

> **This recommendation is superseded and is operator opinion, not a decision.** The owner ruled on
> 2026-08-06 that the browser is not settled; `STATUS.md` (kiosk-reference) carries the ruling and the
> reasons this section's comparison can no longer support a conclusion. One of its three legs — the
> render defect — has since failed to reproduce.

**Kept, because it is cheap and now proven:** the two shims are worth carrying in the frontend anyway.
They cost ~100 bytes, they are inert on Chromium, and they keep a second engine viable if Chromium 72
ever becomes untenable.

**What switching would actually cost:** no browser on this box links 2.18, so it means building one
(`surf` 2.0+ targets webkit2gtk and is a single C file; `gcc`, `make`, `pkg-config` and
`libwebkit2gtk-4.0-dev` are all available). Then re-validating layout on a ~Safari 11 engine, losing
CDP — every measurement in this repo comes from Chromium remote debugging — and giving up a known-good
70s render for an unmeasured one.

## Upgrading the browser alone makes things *worse*

Measured 2026-08-06, same build, same page, same device:

| | Chromium 60 | Chromium 72 |
|---|---|---|
| first-paint | 7,906ms | 22,475ms |
| first-contentful-paint | **20,019ms** | **27,498ms** |

Not because 72 is slower — because **the page executes both bundles**:

```
scripts: index-D7e9ysx1.js:module            <- modern bundle, 72 honours type="module"
         polyfills-legacy-3fE0wiOM.js:nomodule
         polyfills-legacy-3fE0wiOM.js:classic  <- legacy path ALSO loaded
window.__vite_is_modern_browser === false
```

Vite's modern-browser probe requires `import.meta.resolve` (~Chrome 105). It throws on 72, so
`__vite_is_modern_browser` is never set and the legacy loader boots the SystemJS bundle — while 72,
unlike 60, *also* runs `type="module"`. Chromium 60 was never in this position because it ignored the
module tag outright.

| Browser | Build | Result |
|---|---|---|
| 60 | legacy | works, FCP ~20s |
| **72** | **legacy** | **works, FCP ~27.5s — both bundles run** |
| 60 | modern-only | blank screen — no ES modules |
| 72 | modern-only | the target |

## Making a modern toolchain produce a compatible build

**Lower the syntax target** and **emit a non-module bundle** were what targeting **Chromium 60**
required, and are what to *remove* when retargeting to 72. **Polyfill runtime APIs** and **let the CSP
execute them** stay either way. For a Vite 8 + Svelte 5 app:

**1. Lower the syntax target** — `build: { target: ["chrome65"] }`. Vite's default is `"modules"`
(~chrome87). Not sufficient alone: it fixes syntax but still emits `type="module"`.

**2. Emit a non-module bundle** — `legacy({ targets: ["chrome >= 60"] })` from `@vitejs/plugin-legacy`,
which clears the Chrome 61 module barrier by emitting a SystemJS bundle plus core-js polyfills under
`<script nomodule>`. Requires `terser`. Cost: 132KB + 85KB polyfills vs 103KB modern.

> **Bundle sizes belong to a build.** **101,225 bytes** for the 2026-08-05 build
> ([`mirror-deployment.md`](mirror-deployment.md)); **103,578 B identity / 35,086 B gzip** for the build
> deployed 2026-08-06 (the Raspbian card notes (kiosk-reference `raspbian-card.md`)). Neither corrects the other.

**3. Polyfill runtime APIs the plugin misses**, as a *classic* inline script so it runs before the
deferred bundle:

```html
<script>
  if (!String.prototype.replaceAll) {
    String.prototype.replaceAll = function (search, replace) {
      if (Object.prototype.toString.call(search) === "[object RegExp]") {
        if (!search.global) throw new TypeError("replaceAll must be called with a global RegExp");
        return this.replace(search, replace);
      }
      return this.split(search).join(replace);
    };
  }
</script>
```

**4. Let the CSP execute those inline scripts.** `plugin-legacy` emits **inline** `<script>` blocks
including `vite-legacy-entry`, the loader that boots the whole legacy bundle; `script-src 'self'`
refuses them and the app silently never starts. Hash them at startup rather than reaching for
`'unsafe-inline'`:

```ts
const html = fs.readFileSync(path.resolve(distPath + "/index.html"), "utf8");
// \ssrc=, NOT \bsrc= — a word boundary matches inside `data-src`, skipping
// plugin-legacy's entry script, i.e. the only one that matters.
const re = /<script(?![^>]*\ssrc\s*=)([^>]*)>([\s\S]*?)<\/script>/gi;
// skip type="application/json" data blocks; hash the rest:
hashes.push("'sha256-" + crypto.createHash("sha256").update(m[2], "utf8").digest("base64") + "'");
```

Recomputing per build keeps the policy strict and self-maintaining.

## Verify, do not hope

`scan-bundle.py` (kiosk-reference) scans built output for features above a chosen
Chrome version and reports the true minimum:

```bash
python3 tools/scan-bundle.py --target 72 dist/assets/*.js dist/assets/*.css
```

A static scan cannot see runtime polyfills, so `String.replaceAll` is an expected hit, not a
regression. Two false positives it accounts for, both of which cost time when hand-grepping:
`(x = y) == null ? .5 : n` (a ternary returning a decimal literal looks like `?.`) and `/()??/ .exec(...)`
(a lazy quantifier in a **regex literal** looks like `??`).

## If you are changing the frontend

The target is **Chromium 72** and the Zero W does not change — see `CLAUDE.md` (kiosk-reference).

- **Set `build.target: ["chrome72"]` and drop `@vitejs/plugin-legacy`.** Removes the SystemJS bundle
  (132KB) and core-js polyfills (85KB) in favour of the 101KB modern module bundle. **Done 2026-08-06.**
- **Removing plugin-legacy also removes the CSP problem** — no inline scripts to hash.
- **Keep the `String.replaceAll` polyfill.** Still absent on 72, still called by Svelte 5's runtime.
- **Use `display:grid` where you want `gap`.**
- **Test here, or against a pinned old-Chromium container.** Toolchain defaults move forward silently;
  a Vite upgrade can raise the default target and break the kiosk with no source change.
