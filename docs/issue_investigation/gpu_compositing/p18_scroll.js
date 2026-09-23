// scrollLeft-vs-transform marquee probe -- is scrolling the clipped container cheaper to
// paint than translating the text inside it? Installed at ~/.surf/script.js, same as
// p13_steps.js and p16_duration.js.
//
// The claim under test is a paint-cost one. A transform animation redraws the whole moved
// box every frame; a scroll of the same box can be served by shifting the pixels already
// there and repainting only the sliver newly exposed at the edge. If that holds on this
// board, N scrolling rows cost far less per frame than N translating ones.
//
//   arm T  TRANSFORM  no override; the row keeps ParkCard.svelte's
//                     `animation: pwt-marquee <D-proportional>s linear infinite`, which
//                     drives `transform: translateX(--pwt-marquee-distance)`.
//   arm S  SCROLL     `animation-name: none !important` and `transform: none !important`
//                     on the text, and the probe drives `.ride-name`'s scrollLeft itself.
//
// Arms run W,T,S,T,S,T over 0-20,20-100,100-180,180-260,260-340,340-420 s -- a palindrome,
// so within-run drift cancels between the two arms rather than loading onto one.
//
// Arm S reproduces arm T's motion rather than inventing one: PX_PER_S, MOVE_FRACTION,
// MIN_S and the four keyframe phases are ParkCard.svelte's own, so both arms move each row
// the same distance at the same pixel velocity on the same cycle. A different speed would
// change the repainted area per second and the arms would not be comparable at all.
//
// `animation-name`, not the `animation` shorthand: the app publishes each row's cycle
// length as an INLINE `animation-duration` (ParkCard.svelte's marquee action). Writing the
// shorthand would erase that value, and removing it on the way back to arm T would leave
// the row on the stylesheet's flat 8 s cycle -- arm T would then be measuring a marquee the
// app never renders. The longhand cancels the animation and leaves the duration alone.
//
// MEASUREMENT IS DELIBERATELY THIN AND IDENTICAL ACROSS ARMS. The frame loop counts rAF
// deltas and nothing else. It does not read computed style on any row, because a per-row
// style flush scales with N and is exactly the cost this probe is trying to attribute to
// the mechanism. Each arm's per-frame work is: one querySelectorAll, two style-ATTRIBUTE
// reads per row (no flush), and in arm S one `scrollLeft` write per row. `getComputedStyle`
// occurs in this file in two places only -- distOf's cache-miss path and sample() -- and
// neither runs per frame in steady state.
//
// Each row's overflow distance is read ONCE PER ARM and cached on the element against a
// generation counter bumped at every arm change. The app publishes it inline, so the cached
// read is usually a style-attribute read; the computed fallback exists for a row that has
// lost the inline value. A row that gains `.marquee` mid-arm, which the tour's re-sort does
// routinely, fills its own cache entry on the frame it appears.
//
// Landing is sampled at SAMPLE_MS, not per frame, and the sample does the SAME work in both
// arms so it cannot bias one. Arm S lands when every row's computed transform AND computed
// animation-name are 'none' and some sample saw a parent scrollLeft above zero -- the
// override took, and the scroll actually moved. Arm T lands when no row carries this
// probe's inline override and no row's computed transform is 'none'. A block that did not
// land is data about the probe, not about the mechanism, and the parser drops it.
//
// Leaving arm S resets scrollLeft on EVERY `.ride-name`, not just the rows still carrying
// `.marquee`: a row that left the set mid-arm keeps whatever scroll offset it was given,
// and that offset would ride into arm T underneath the resumed transform. The reset runs
// before the overrides are removed, so the CSS animation resumes from a zeroed container.
//
// A caveat the numbers cannot show on their own: scroll offsets quantise to whole pixels in
// ways a transform does not, so part of any arm-S win may be fewer distinct paint positions
// rather than a blit. The per-block max scrollLeft is emitted so the quantisation is at
// least visible. The text keeps `will-change: transform` in both arms -- its compositor
// layer is not a variable here.
//
// Exfiltrates a KP18| payload through document.title -- the page console does not reach the
// journal on this image. Read it back with xprop; parse it with parse_scroll.py. The tag is
// KP18|, not the family's KP3|, because the block record is a different shape (six fields,
// no MOVING/static split) and a parser must refuse it rather than misread it.
(function () {
  if (window.__kp18) return;
  window.__kp18 = 1;

  // ParkCard.svelte's marquee constants and keyframe phases.
  var PX_PER_S = 15;           // px/s; the one speed both arms hold every row to
  var MOVE_FRACTION = 0.84;    // the keyframes move over 4%->88% of the cycle
  var MIN_S = 4;               // s; a short name does not cycle faster than this
  var HOLD0 = 0.04;            // held at home over 0%->4%
  var MOVE_END = 0.88;         // scrolled left over HOLD0->88%
  var SNAP = 0.94;             // held at the end over 88%->94%, then snapped home

  var DIST_VAR = '--pwt-marquee-distance';
  var BLOCK_MS = 20000;
  var SAMPLE_MS = 2000;        // landing sample and title write share this cadence

  // Arm boundaries in seconds; ARMS[i] runs from EDGE[i] to EDGE[i+1].
  var EDGE = [0, 20, 100, 180, 260, 340, 420];
  var ARMS = ['W', 'T', 'S', 'T', 'S', 'T'];

  var t0 = performance.now();
  var prev = t0;
  var frames = 0, sumFrame = 0, maxFrame = 0;
  var mqSeen = 0, rowsSeen = 0;
  var lastDist = '';           // the row distances seen at the last sample

  var blocks = [];             // one record per 20 s block
  var cur = null;
  var lastArm = '';
  var gen = 0;                 // bumped at every arm change; invalidates the distance cache

  // Past the last edge the page keeps whatever the final arm applied, so the label stays
  // truthful; cut the capture at 420 s to keep the arms balanced.
  function armAt(elMs) {
    var s = elMs / 1000;
    for (var i = ARMS.length - 1; i >= 0; i--) {
      if (s >= EDGE[i]) return ARMS[i];
    }
    return ARMS[0];
  }

  function newBlock(idx, arm) {
    return {
      i: idx, arm: arm, land: 1,
      n: 0, s: 0, mx: 0,      // frames, summed frame time, worst frame
      smp: 0,                 // landing samples taken in this block
      sx: 0                   // largest parent scrollLeft any sample saw
    };
  }

  // The row's overflow distance in px, cached for the life of the current arm. 0 when the
  // app has published none, which leaves the row measured but never scrolled.
  function distOf(el) {
    if (el.__p18g === gen) return el.__p18d;
    var v = el.style.getPropertyValue(DIST_VAR);
    if (!v) v = getComputedStyle(el).getPropertyValue(DIST_VAR);
    var n = parseFloat(v);
    el.__p18d = isFinite(n) ? Math.abs(n) : 0;
    el.__p18g = gen;
    return el.__p18d;
  }

  // Where arm S puts this row's scroll offset at elapsed time tSec, following the app's own
  // cycle: held home, scrolled left at PX_PER_S, held at the end, snapped home. Derived from
  // the distance alone, so a row cannot ratchet itself off the cycle frame after frame.
  function scrollAt(d, tSec) {
    var dur = Math.max(MIN_S, d / (PX_PER_S * MOVE_FRACTION));
    var p = (tSec % dur) / dur;
    if (p < HOLD0) return 0;
    if (p < MOVE_END) return d * (p - HOLD0) / (MOVE_END - HOLD0);
    if (p < SNAP) return d;
    return 0;
  }

  // Bring one row to the arm's desired inline state, writing only when it is not already
  // there. The match test asks whether the inline value NAMES none, not whether it equals
  // the string this probe wrote: the engine is free to re-serialize, and an exact compare
  // that never matched would write every frame -- precisely the style-dirtying this guard
  // exists to avoid. Both reads are of the style ATTRIBUTE and force no layout.
  function ensureArm(el, arm) {
    var an = el.style.getPropertyValue('animation-name');
    var tf = el.style.getPropertyValue('transform');
    if (arm === 'S') {
      if (an.indexOf('none') < 0) {
        el.style.setProperty('animation-name', 'none', 'important');
      }
      if (tf.indexOf('none') < 0) {
        el.style.setProperty('transform', 'none', 'important');
      }
      return;
    }
    if (an) el.style.removeProperty('animation-name');
    if (tf) el.style.removeProperty('transform');
  }

  // Every container zeroed on the way out of arm S, including rows that have since lost
  // `.marquee` -- their offset would otherwise ride into arm T under the resumed transform.
  function onArmChange(from) {
    gen++;
    if (from !== 'S') return;
    var ps = document.querySelectorAll('[data-pwt-ride-name]');
    for (var i = 0; i < ps.length; i++) ps[i].scrollLeft = 0;
  }

  var origRaf = window.requestAnimationFrame.bind(window);
  var origSetInterval = window.setInterval.bind(window);

  function tick(now) {
    var dt = now - prev;
    prev = now;
    var el = now - t0;
    frames++; sumFrame += dt;
    if (dt > maxFrame) maxFrame = dt;

    var arm = armAt(el);
    var rows = document.querySelectorAll('.ride-name-text.marquee');
    mqSeen = rows.length;

    if (arm !== lastArm) { onArmChange(lastArm); lastArm = arm; }

    var bi = Math.floor(el / BLOCK_MS);
    if (!cur || cur.i !== bi) {
      if (cur) blocks.push(cur);
      cur = newBlock(bi, arm);
    }
    cur.n++; cur.s += dt;
    if (dt > cur.mx) cur.mx = dt;

    var tSec = el / 1000;
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i];
      ensureArm(r, arm);
      if (arm !== 'S') continue;
      var d = distOf(r);
      var par = r.parentNode;
      if (d && par) par.scrollLeft = scrollAt(d, tSec);
    }

    origRaf(tick);
  }
  origRaf(tick);

  // The only computed-style read on the row set, and it runs at SAMPLE_MS in BOTH arms so
  // its cost cannot land on one of them.
  function sample() {
    if (!cur) return;
    var rows = document.querySelectorAll('.ride-name-text.marquee');
    var ds = [];
    cur.smp++;
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i];
      var cs = getComputedStyle(r);
      var tNone = (cs.transform === 'none');
      var aNone = ((cs.animationName || '') === 'none');
      var par = r.parentNode;
      var sl = par ? par.scrollLeft : 0;
      if (sl > cur.sx) cur.sx = sl;
      ds.push(Math.round(distOf(r)));
      if (cur.arm === 'S') {
        if (!tNone || !aNone) cur.land = 0;
      } else if (cur.arm === 'T') {
        if (tNone) cur.land = 0;
        if (r.style.getPropertyValue('animation-name')) cur.land = 0;
        if (r.style.getPropertyValue('transform')) cur.land = 0;
      }
    }
    lastDist = ds.join('.');
  }

  function mean(s, n) { return n ? Math.round(s / n) : 0; }

  origSetInterval(function () {
    sample();
    var elms = performance.now() - t0;
    var all = blocks.concat(cur ? [cur] : []);
    var bs = all.map(function (b) {
      // The emitted flag is the WHOLE landing rule: the in-band disagreement check, at
      // least one sample to have checked it, and for arm S a scroll that actually moved.
      var land = (b.land && b.smp > 0 && (b.arm !== 'S' || b.sx > 0)) ? 1 : 0;
      return b.i + b.arm + land + ',' + b.n + ',' + Math.round(b.s) + ',' +
             Math.round(b.mx) + ',' + b.smp + ',' + Math.round(b.sx);
    }).join(';');
    rowsSeen = document.querySelectorAll('[data-pwt-ride-name]').length;
    document.title =
      'KP18|' + Math.round(elms / 1000) +
      '|f' + frames +
      '|av' + mean(sumFrame, frames) +
      '|mx' + Math.round(maxFrame) +
      '|M' + mqSeen + '/' + rowsSeen +
      '|D' + lastDist +
      '|B' + bs;
  }, SAMPLE_MS);
})();
