# Screen capture — `fbgrab` against `imagemagick import`

The kiosk has one liveness check that no process-level sampler can replace: look at the pixels and
compare what they say against live data. `fbgrab` reads as broken and is not: the defect is in the
alpha channel of what it writes, not in the pixels. This records what each capture path produces
and how to read it, so the misreading is not made twice.

## Configuration under test

Two capture paths against the running kiosk's framebuffer on the Pi Zero W:

- `fbgrab`, reading `/dev/fb0` directly;
- `import -window root` from imagemagick, against the X root window.

The kiosk renders through the legacy `bcm2708_fb` framebuffer, black background with sparse light
text.

## How the test was performed

Each tool captured a screen that was demonstrably rendering the kiosk correctly, and the resulting
PNG was inspected channel by channel rather than by eye in a viewer. Content was then checked
against live data taken in the same command — the rendered clock against `date` on the device, and
the METAR observation ID against the current cycle — so that a stale render cannot pass as a healthy
one.

## Metrics

`fbgrab` writes **RGBA with every alpha byte 0**. A naive viewer composites that onto white, which
is why the capture read as a wholly white PNG against a screen that was rendering correctly. The
pixel data was intact the whole time; only the alpha channel was wrong.

`import -window root` writes correct opaque pixels with no post-processing. Verified capture,
2026-08-12: 1824×984, 8-bit grayscale, opaque, `min=0 max=255 mean=4.4`.

The healthy signature for this display is `rgb min=0 max=255 mean≈4` — a mean near zero is normal on
a black background and is **not** evidence of a blank screen. **`min == max` is.**

Content check on the same capture: the clock read `7:35:48 pm, Wednesday August 12 2026` against
`date` returning `19:35:48` in the same command; METAR `<METAR_STATION> 122253Z`, the current cycle;
wait times varied; font rendered as Roboto Condensed rather than the DejaVu fallback.

## Changes configured as a result

`imagemagick` stays in `IMAGE_INSTALL:append` in
[`kiosk-zero-w.yaml`](../../../kiosk-zero-w.yaml) as the only working capture path on this image.
`fbgrab` is not in the image and is not restored: nothing needs it once `import` writes correct
pixels, and its absence is the record of the trade.

The capture, the blank-screen signature and the content-against-`date` check are scripted at
[`kiosk-screenshot.sh`](../../../tools/kiosk-screenshot.sh), so the reading rule cannot be applied
from memory.
