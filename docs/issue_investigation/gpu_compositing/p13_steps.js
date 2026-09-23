// steps() marquee probe -- does discretising the marquee's timing function cut
// per-frame repaint cost? Installed at ~/.surf/script.js, same as p12_motion.js.
//
// Measurement is p12's, unchanged: every rAF frame reads each marquee row's live
// computed translateX and tags the frame MOVING or STATIC by whether any row moved
// more than EPS. What is added is an interleaved A/B arm schedule and an in-band
// landing check.
//
//   arm A  BASELINE  no override; the stylesheet's `animation: ... ease-in-out`
//                    timing function applies.
//   arm B  STEPS     `animation-timing-function: steps(K, jump-none) !important`
//                    set on the style attribute of every `.ride-name-text.marquee`.
//
// Arms run W,A,B,A,B,A over 0-20,20-100,100-180,180-260,260-340,340-420 s -- a
// palindrome, so within-run drift cancels between the two arms rather than loading
// onto one of them.
//
// Landing is checked IN BAND over the WHOLE current row set: each frame reads
// getComputedStyle().animationTimingFunction on every live marquee row and clears the
// block's land flag the moment any row disagrees with the arm that is supposed to be
// applied. A block that did not land is data about the probe, not about steps(), and
// the parser drops it. An empty row set never clears the flag on its own -- there is
// nothing to disagree.
//
// The inline state is maintained every frame but WRITTEN ONLY ON DIFFERENCE: each row's
// current inline value is read first (style.getPropertyValue -- no forced layout) and
// setProperty/removeProperty runs only when it does not already match the arm. This
// picks up a row that gains `.marquee` mid-arm, which the tour's re-sort does routinely,
// while leaving steady state untouched -- an unconditional per-frame write would dirty
// style and load arm B with a cost that is the probe's, not steps().
//
// Exfiltrates a KP3| payload through document.title -- the page console does not
// reach the journal on this image. Read it back with xprop.
(function () {
  if (window.__kp3) return;
  window.__kp3 = 1;

  var K = 10;                  // steps() step count -- change between captures

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

  // Bring one row to the arm's desired inline state, writing only when it is not
  // already there. The match test asks whether the inline value NAMES steps(), not
  // whether it equals the string this probe wrote: the engine is free to re-serialize
  // the value, and an exact compare that never matches would write every frame --
  // precisely the style-dirtying this guard exists to avoid. K is fixed for the
  // lifetime of an install, so an inline steps() can only be this probe's own.
  function ensureArm(el, arm) {
    var have = el.style.getPropertyValue('animation-timing-function');
    if (arm === 'B') {
      if (have.indexOf('steps') < 0) {
        el.style.setProperty(
          'animation-timing-function', 'steps(' + K + ', jump-none)', 'important');
      }
    } else if (have) {
      el.style.removeProperty('animation-timing-function');
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
      if (arm !== 'W') {
        var stepped = (cs.animationTimingFunction || '').indexOf('steps') >= 0;
        if (stepped !== (arm === 'B')) cur.land = 0;
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
