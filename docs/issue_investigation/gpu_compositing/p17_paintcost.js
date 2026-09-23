// Paint-cost marquee probe -- is the marquee's per-frame cost TEXT GLYPH RASTERISATION?
// Installed at ~/.surf/script.js, same as p13_steps.js.
//
// Measurement is p12's and p13's, unchanged: every rAF frame reads each marquee row's
// live computed translateX and tags the frame MOVING or STATIC by whether any row moved
// more than EPS. What differs from p13 is the arm-B manipulation and its landing check.
//
//   arm A  BASELINE  no override; the row paints its glyphs as the stylesheet says.
//   arm B  FILL      `color: transparent !important` plus
//                    `background-color: #4a4ad0 !important` on every
//                    `.ride-name-text.marquee`. No glyph is rasterised, but the same
//                    box over the same area still paints -- a solid rectangle instead
//                    of text -- under the same marquee translateX animation. It is the
//                    cheap injectable stand-in for blitting a pre-rendered bitmap of
//                    the row: same geometry, same motion, no text raster.
//
// So the question this probe answers is whether a bitmap approach is worth building.
// THE SIGNAL IS THE A -> B **MOVING** MEAN DELTA, not the SCORE line: if glyph raster
// is what each moving frame is paying for, arm B's moving frames get much cheaper. If
// the moving mean barely moves, the cost is elsewhere -- geometry, layer upload,
// compositing -- and a pre-rendered bitmap buys nothing. parse_steps.py is reused as-is
// and labels arm B "STEPS" (here it is FILL) and prints a SCORE built from the OVERALL
// frame-weighted mean, which is p13's question, not this one; read the MOVING line.
//
// Arms run W,A,B,A,B,A over 0-20,20-100,100-180,180-260,260-340,340-420 s -- a
// palindrome, so within-run drift cancels between the two arms rather than loading
// onto one of them.
//
// Landing is checked IN BAND over the WHOLE current row set: each frame reads
// getComputedStyle() on every live marquee row. Arm B clears the block's land flag the
// moment any row's computed colour is not fully transparent or its computed background
// is not the fill; arm A, the moment any row's colour IS transparent, which is what
// proves removeProperty restored the stylesheet's colour rather than leaving the
// override on. A block that did not land is data about the probe, not about paint cost,
// and the parser drops it. An empty row set never clears the flag on its own -- there is
// nothing to disagree.
//
// The inline state is maintained every frame but WRITTEN ONLY ON DIFFERENCE, as in p13:
// each row's inline colour is read first (style.getPropertyValue -- no forced layout)
// and the pair is written only when it does not already match the arm. This picks up a
// row that gains `.marquee` mid-arm, which the tour's re-sort does routinely, while
// leaving steady state untouched -- an unconditional per-frame write would dirty style
// and load arm B with a cost that is the probe's, not the fill's. The two properties are
// written and removed together, so the inline colour alone decides the pair's state and
// one read settles it. The app publishes only a custom property inline on these rows
// (--pwt-marquee-distance, p16_duration.js), so an inline colour on a marquee row can
// only be this probe's own.
//
// Exfiltrates a KP3| payload through document.title -- the page console does not reach
// the journal on this image, and the prefix stays KP3| so parse_steps.py reads it
// unchanged. Read it back with xprop.
(function () {
  if (window.__kp17) return;
  window.__kp17 = 1;

  var FILL = '#4a4ad0';        // arm B's solid fill
  var FILL_RGB = [74, 74, 208];

  var EPS = 0.02;              // px; below this a row counts as not moving
  var BLOCK_MS = 20000;
  var MAXR = 9;                // movingCount buckets 0..8

  // Arm boundaries in seconds; ARMS[i] runs from EDGE[i] to EDGE[i+1].
  var EDGE = [0, 20, 100, 180, 260, 340, 420];
  var ARMS = ['W', 'A', 'B', 'A', 'B', 'A'];

  var t0 = performance.now();
  var prev = performance.now();
  var frames = 0, sumFrame = 0, maxFrame = 0;

  var lastTx = [];             // per-row previous translateX
  var rowsSeen = 0, mqSeen = 0;

  // buckets by number of rows moving this frame
  var rN = [], rS = [];
  for (var i = 0; i < MAXR; i++) { rN.push(0); rS.push(0); }

  var blocks = [];             // one record per 20 s block
  var cur = null;

  // Past the last edge the page keeps whatever the final arm applied, so the label
  // stays truthful; cut the capture at 420 s to keep the arms balanced.
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
      n: 0, s: 0,             // all frames in block
      mn: 0, ms: 0,           // moving frames
      sn: 0, ss: 0,           // static frames
      px: 0                   // total px moved in block
    };
  }

  function txOf(cs) {
    var t = cs.transform;
    if (!t || t === 'none') return 0;
    // matrix(a, b, c, d, tx, ty) | matrix3d(...16)
    var p = t.slice(t.indexOf('(') + 1, -1).split(',');
    if (p.length === 6) return parseFloat(p[4]);
    if (p.length === 16) return parseFloat(p[12]);
    return 0;
  }

  // [r, g, b, a] from a CSS colour, or null when it is not one. The keyword
  // `transparent` and the computed form rgba(0, 0, 0, 0) both have to read the same:
  // the engine is free to re-serialize either the inline value or the computed one.
  function rgbaOf(v) {
    var s = ('' + (v || '')).trim();
    if (!s) return null;
    if (s === 'transparent') return [0, 0, 0, 0];
    var i = s.indexOf('(');
    if (i < 0) return null;
    var p = s.slice(i + 1, s.lastIndexOf(')')).split(/[\s,\/]+/);
    var n = [];
    for (var j = 0; j < p.length; j++) {
      var x = parseFloat(p[j]);
      if (isFinite(x)) n.push(x);
    }
    if (n.length < 3) return null;
    return [n[0], n[1], n[2], n.length > 3 ? n[3] : 1];
  }

  function isClear(v) {
    var c = rgbaOf(v);
    return !!c && c[3] === 0;
  }

  function isFill(v) {
    var c = rgbaOf(v);
    return !!c && c[0] === FILL_RGB[0] && c[1] === FILL_RGB[1] &&
           c[2] === FILL_RGB[2] && c[3] === 1;
  }

  // Bring one row to the arm's desired inline state, writing only when it is not
  // already there. The match test asks whether the inline colour is TRANSPARENT, not
  // whether it equals the string this probe wrote: an exact compare that never matched
  // a re-serialized value would write every frame -- precisely the style-dirtying this
  // guard exists to avoid. The fill is removed with the colour it was written with.
  function ensureArm(el, arm) {
    var have = el.style.getPropertyValue('color');
    if (arm === 'B') {
      if (!isClear(have)) {
        el.style.setProperty('color', 'transparent', 'important');
        el.style.setProperty('background-color', FILL, 'important');
      }
    } else if (have) {
      el.style.removeProperty('color');
      el.style.removeProperty('background-color');
    }
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

    var bi = Math.floor(el / BLOCK_MS);
    if (!cur || cur.i !== bi) {
      if (cur) blocks.push(cur);
      cur = newBlock(bi, arm);
    }
    cur.n++; cur.s += dt;

    var moving = 0, pxsum = 0;
    for (var i = 0; i < rows.length; i++) {
      // Maintain first, then read: the computed value has to reflect this frame's
      // desired state for the landing flag to be about the arm rather than the lag.
      ensureArm(rows[i], arm);
      var cs = getComputedStyle(rows[i]);
      if (arm === 'B') {
        if (!isClear(cs.color) || !isFill(cs.backgroundColor)) cur.land = 0;
      } else if (arm === 'A') {
        if (isClear(cs.color)) cur.land = 0;
      }
      var tx = txOf(cs);
      var was = (i < lastTx.length) ? lastTx[i] : tx;
      var d = Math.abs(tx - was);
      if (d > EPS) { moving++; pxsum += d; }
      lastTx[i] = tx;
    }
    lastTx.length = rows.length;

    var rb = moving < MAXR ? moving : MAXR - 1;
    rN[rb]++; rS[rb] += dt;

    cur.px += pxsum;
    if (moving > 0) { cur.mn++; cur.ms += dt; }
    else { cur.sn++; cur.ss += dt; }

    origRaf(tick);
  }
  origRaf(tick);

  function mean(s, n) { return n ? Math.round(s / n) : 0; }
  function pair(ns, ss) {
    var o = [];
    for (var i = 0; i < ns.length; i++) o.push(ns[i] + ':' + mean(ss[i], ns[i]));
    return o.join('.');
  }

  origSetInterval(function () {
    var el = performance.now() - t0;
    var all = blocks.concat(cur ? [cur] : []);
    var bs = all.map(function (b) {
      return b.i + b.arm + b.land + ',' + b.n + ',' + mean(b.s, b.n) + ',' +
             b.mn + ',' + mean(b.ms, b.mn) + ',' +
             b.sn + ',' + mean(b.ss, b.sn) + ',' + Math.round(b.px);
    }).join(';');
    rowsSeen = document.querySelectorAll('[data-pwt-ride-name]').length;
    document.title =
      'KP3|' + Math.round(el / 1000) +
      '|f' + frames +
      '|av' + mean(sumFrame, frames) +
      '|mx' + Math.round(maxFrame) +
      '|M' + mqSeen + '/' + rowsSeen +
      '|R' + pair(rN, rS) +
      '|B' + bs;
  }, 2000);
})();
