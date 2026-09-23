// Allocation-pressure probe: does the residual ~1300ms stall track JS allocation
// (i.e. is it a JavaScriptCore GC pause)? Installed at ~/.surf/script.js.
//
// Palindrome arms over 80s blocks after a 20s warmup: B,A,B,A,B where B = ALLOC
// (allocate and drop garbage every frame) and A = BASELINE (no extra allocation).
// If the >250ms stall rate is markedly higher in the B arms, the stall is
// allocation-driven == GC-consistent. Frame timing is the bare rAF loop (p7_min).
// Exfil AL| through document.title, read with xprop.
(function () {
  if (window.__kp24) return;
  window.__kp24 = 1;

  var ALLOC_OBJECTS = 25000;      // objects allocated & dropped per ALLOC frame (~few MB)
  var EDGE = [0, 20, 100, 180, 260, 340, 420];
  var ARMS = ['W', 'B', 'A', 'B', 'A', 'B'];

  var RAF = window.requestAnimationFrame.bind(window);
  var prev = performance.now(), t0 = prev;
  var frames = 0, sumAll = 0, maxAll = 0, big = 0;
  var BUCK = [50, 100, 250, 500, 1000, 2000];
  var hist = [0, 0, 0, 0, 0, 0, 0];

  // per-arm accumulators, keyed A / B
  var arm = { A: mk(), B: mk() };
  function mk() { return { n: 0, s: 0, mx: 0, big: 0, alloc: 0 }; }

  var bigList = [];               // [t, dt, armLetter]

  function armAt(elMs) {
    var s = elMs / 1000;
    for (var i = ARMS.length - 1; i >= 0; i--) if (s >= EDGE[i]) return ARMS[i];
    return ARMS[0];
  }

  function tick(now) {
    var dt = now - prev; prev = now;
    var el = now - t0;
    var a = armAt(el);

    // the manipulation: allocate garbage only in ALLOC (B) arms
    var did = 0;
    if (a === 'B') {
      var junk = [];
      for (var i = 0; i < ALLOC_OBJECTS; i++) junk.push({ a: i, s: 'x' + i, arr: [i, i, i] });
      junk = null;
      did = 1;
    }

    frames++; sumAll += dt; if (dt > maxAll) maxAll = dt;
    var b = 0; while (b < BUCK.length && dt >= BUCK[b]) b++;
    hist[b]++;
    if (dt > 250) { big++; if (bigList.length < 40) bigList.push([Math.round(el / 100) / 10, Math.round(dt), a]); }

    if (a === 'A' || a === 'B') {
      var r = arm[a];
      r.n++; r.s += dt; if (dt > r.mx) r.mx = dt; if (dt > 250) r.big++; r.alloc += did;
    }
    RAF(tick);
  }
  RAF(tick);

  function mean(s, n) { return n ? Math.round(s / n) : 0; }

  window.setInterval(function () {
    var el = performance.now() - t0;
    function armStr(k) { var r = arm[k]; return k + ':' + r.n + '.' + r.big + '.' + mean(r.s, r.n) + '.' + r.mx + '.' + r.alloc; }
    var bl = bigList.map(function (e) { return e[0] + ':' + e[1] + e[2]; }).join(',');
    document.title =
      'AL|' + Math.round(el / 1000) +
      '|f' + frames + '|av' + mean(sumAll, frames) + '|mx' + Math.round(maxAll) + '|BT' + big +
      '|' + armStr('A') + '|' + armStr('B') +
      '|H' + hist.join('.') +
      '|B' + bl;
  }, 2000);
})();
