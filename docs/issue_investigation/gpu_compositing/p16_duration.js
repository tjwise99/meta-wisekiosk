// Constant-scroll-speed marquee probe -- does making each row's cycle duration
// proportional to its own overflow distance shrink the per-frame jump that reads as
// judder, without costing frame rate? Installed at ~/.surf/script.js, same as p13_steps.js.
//
// Measurement is p12's and p13's, unchanged: every rAF frame reads each marquee row's
// live computed translateX and tags the frame MOVING or STATIC by whether any row moved
// more than EPS. What differs from p13 is the arm-B manipulation and its landing check.
//
//   arm A  BASELINE  no override; every row keeps the stylesheet's flat 8 s cycle, so a
//                    long name covers its whole overflow in the same 2.8 s of motion a
//                    short one does -- the longer the name, the larger the jump per frame.
//   arm B  CONSTANT  `animation-duration: <D / (PX_PER_S * MOVE_FRACTION)>s !important`
//                    per row, floored at MIN_S, so every row scrolls at PX_PER_S.
//
// D is the row's own overflow distance, published by the app's marquee action as the
// inline custom property --pwt-marquee-distance (e.g. -843px). The arm-B target is
// derived from D alone and never from the duration already applied, so a row cannot
// ratchet itself slower frame after frame.
//
// Arms run W,A,B,A,B,A over 0-20,20-100,100-180,180-260,260-340,340-420 s -- a
// palindrome, so within-run drift cancels between the two arms rather than loading
// onto one of them.
//
// Landing is checked IN BAND over the WHOLE current row set: each frame reads
// getComputedStyle().animationDuration on every live marquee row. Arm B clears the
// block's land flag the moment any row sits further than LAND_TOL from ITS OWN target;
// arm A, further than LAND_TOL from MIN_S. A block that did not land is data about the
// probe, not about the duration lever, and the parser drops it. A row whose D cannot be
// read carries no arm-B target: it is measured but not overridden, and cannot clear the
// flag. An empty row set never clears it -- there is nothing to disagree.
//
// The inline state is maintained every frame but WRITTEN ONLY ON DIFFERENCE, as in p13:
// each row's current inline value is read first (style.getPropertyValue -- no forced
// layout) and setProperty/removeProperty runs only when it does not already match the
// arm. This picks up a row that gains `.marquee` mid-arm, which the tour's re-sort does
// routinely, while leaving steady state untouched -- an unconditional per-frame write
// would dirty style and load arm B with a cost that is the probe's, not the lever's.
//
// The app applies its duration through the `animation:` shorthand in the stylesheet, so
// the inline animation-duration longhand is this probe's alone and a longhand !important
// wins the cascade -- the same route p13's steps() override took. Arm A's landing check,
// every row back at MIN_S, is what proves removeProperty restored the stylesheet's value
// rather than erasing an inline one.
//
// Exfiltrates a KP3| payload through document.title -- the page console does not reach
// the journal on this image. Read it back with xprop.
(function () {
  if (window.__kp16) return;
  window.__kp16 = 1;

  var PX_PER_S = 179;          // px/s; the scroll speed arm B holds every row to
  var MOVE_FRACTION = 0.35;    // the keyframes move over 15%->50% of the cycle
  var MIN_S = 8;               // s; never faster than the stylesheet's base cycle
  var LAND_TOL = 0.2;          // s; computed-vs-target slack for the landing check
  var DUR_EPS = 0.001;         // s; below this the inline duration already matches

  var DIST_VAR = '--pwt-marquee-distance';

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

  // Seconds from a CSS <time>. The computed value carries one entry per animation;
  // the row has a single animation, so the first entry is it.
  function secOf(v) {
    if (!v) return 0;
    var s = ('' + v).split(',')[0].trim();
    var n = parseFloat(s);
    if (!isFinite(n)) return 0;
    return s.slice(-2) === 'ms' ? n / 1000 : n;
  }

  // The row's overflow distance in px, 0 when the app has published none.
  function distOf(el) {
    var v = el.style.getPropertyValue(DIST_VAR);
    if (!v) v = getComputedStyle(el).getPropertyValue(DIST_VAR);
    var n = parseFloat(v);
    return isFinite(n) ? Math.abs(n) : 0;
  }

  // Arm B's duration for this row, 0 when D is unreadable. A function of D only --
  // reading the applied duration here is what would let a row ratchet.
  function targetOf(el) {
    var d = distOf(el);
    if (!d) return 0;
    return Math.round(Math.max(MIN_S, d / (PX_PER_S * MOVE_FRACTION)) * 10) / 10;
  }

  // Bring one row to the arm's desired inline state, writing only when it is not already
  // there, and return the arm-B target this row is to be judged against (0 = none). The
  // match test compares SECONDS, not strings: the engine is free to re-serialize the
  // value, and an exact string compare that never matched would write every frame --
  // precisely the style-dirtying this guard exists to avoid.
  function ensureArm(el, arm) {
    var have = el.style.getPropertyValue('animation-duration');
    if (arm === 'B') {
      var t = targetOf(el);
      if (!t) return 0;        // no distance published: measured, never overridden
      if (Math.abs(secOf(have) - t) > DUR_EPS) {
        el.style.setProperty('animation-duration', t + 's', 'important');
      }
      return t;
    }
    if (have) el.style.removeProperty('animation-duration');
    return 0;
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
      var want = ensureArm(rows[i], arm);
      var cs = getComputedStyle(rows[i]);
      if (arm === 'B') {
        if (want && Math.abs(secOf(cs.animationDuration) - want) > LAND_TOL) cur.land = 0;
      } else if (arm === 'A') {
        if (Math.abs(secOf(cs.animationDuration) - MIN_S) > LAND_TOL) cur.land = 0;
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
