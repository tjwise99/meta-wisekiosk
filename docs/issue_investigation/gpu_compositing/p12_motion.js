// MOVING-phase vs STATIC-phase frame-time probe, installed at ~/.surf/script.js.
//
// Every rAF frame, reads each marquee row's live computed translateX and tags the
// frame by how many rows actually moved that frame -- motion is measured, not
// inferred from the keyframe window (the animation is ease-in-out, so velocity
// tapers to zero inside its own moving window).
//
// Blocks of 20 s alternate T (tag: read transforms) and N (no read), pattern
// T,T,T,N. The N blocks measure the probe's own cost and interleave against the
// ~30% within-run drift; MOVING vs STATIC is always compared inside one T block.
//
// Exfiltrates a KP2| payload through document.title -- the page console does not
// reach the journal on this image. Read it back with xprop.
(function () {
  if (window.__kp2) return;
  window.__kp2 = 1;

  var EPS = 0.02;              // px; below this a row counts as not moving
  var BLOCK_MS = 20000;
  var PATTERN = ['T', 'T', 'T', 'N'];
  var MAXR = 9;                // movingCount buckets 0..8

  var t0 = performance.now();
  var prev = performance.now();
  var frames = 0, sumFrame = 0, maxFrame = 0;

  var lastTx = [];             // per-row previous translateX
  var rowsSeen = 0, mqSeen = 0;

  // buckets by number of rows moving this frame
  var rN = [], rS = [];
  for (var i = 0; i < MAXR; i++) { rN.push(0); rS.push(0); }

  // buckets by total px moved this frame (sum |dx| over rows)
  var PXE = [0.02, 0.5, 1, 2, 4, 8];
  var pN = [], pS = [];
  for (var i = 0; i <= PXE.length; i++) { pN.push(0); pS.push(0); }

  var blocks = [];             // one record per 20 s block
  var cur = null;

  function newBlock(idx) {
    return {
      i: idx, ty: PATTERN[idx % PATTERN.length],
      n: 0, s: 0,             // all frames in block
      mn: 0, ms: 0,           // moving frames
      sn: 0, ss: 0,           // static frames
      px: 0                   // total px moved in block
    };
  }

  function txOf(el) {
    var t = getComputedStyle(el).transform;
    if (!t || t === 'none') return 0;
    // matrix(a, b, c, d, tx, ty) | matrix3d(...16)
    var p = t.slice(t.indexOf('(') + 1, -1).split(',');
    if (p.length === 6) return parseFloat(p[4]);
    if (p.length === 16) return parseFloat(p[12]);
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

    var bi = Math.floor(el / BLOCK_MS);
    if (!cur || cur.i !== bi) {
      if (cur) blocks.push(cur);
      cur = newBlock(bi);
    }
    cur.n++; cur.s += dt;

    if (cur.ty === 'T') {
      var rows = document.querySelectorAll('.ride-name-text.marquee');
      mqSeen = rows.length;
      var moving = 0, pxsum = 0;
      for (var i = 0; i < rows.length; i++) {
        var tx = txOf(rows[i]);
        var was = (i < lastTx.length) ? lastTx[i] : tx;
        var d = Math.abs(tx - was);
        if (d > EPS) { moving++; pxsum += d; }
        lastTx[i] = tx;
      }
      lastTx.length = rows.length;

      var rb = moving < MAXR ? moving : MAXR - 1;
      rN[rb]++; rS[rb] += dt;

      var pb = 0;
      while (pb < PXE.length && pxsum >= PXE[pb]) pb++;
      pN[pb]++; pS[pb] += dt;

      cur.px += pxsum;
      if (moving > 0) { cur.mn++; cur.ms += dt; }
      else { cur.sn++; cur.ss += dt; }
    }

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
      return b.i + b.ty + ',' + b.n + ',' + mean(b.s, b.n) + ',' +
             b.mn + ',' + mean(b.ms, b.mn) + ',' +
             b.sn + ',' + mean(b.ss, b.sn) + ',' + Math.round(b.px);
    }).join(';');
    rowsSeen = document.querySelectorAll('[data-pwt-ride-name]').length;
    document.title =
      'KP2|' + Math.round(el / 1000) +
      '|f' + frames +
      '|av' + mean(sumFrame, frames) +
      '|mx' + Math.round(maxFrame) +
      '|M' + mqSeen + '/' + rowsSeen +
      '|R' + pair(rN, rS) +
      '|P' + pair(pN, pS) +
      '|B' + bs;
  }, 2000);
})();
