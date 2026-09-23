// Marquee-allocation toggle probe (meta-wisekiosk #100, Run 37). Installed at ~/.surf/script.js.
//
// Tests whether the residual ~1300ms GC stall is driven by the marquee's per-frame allocation
// (marquee-clock.ts:62, `for (const [column, distance] of columns)` over a Map — ~3 short-lived
// objects per column per frame). The instrumented bundle carries BOTH loop bodies in step(),
// switched per frame by window.__mqAlloc, producing byte-identical motion either way:
//   __mqAlloc !== false  -> ALLOC path  (current Map destructuring; allocates)
//   __mqAlloc === false  -> CLEAN path  (indexed array; allocates nothing)
// step() bumps window.__mqAllocFrames / window.__mqCleanFrames so which path ran is observable,
// not assumed.
//
// This probe palindrome-interleaves ALLOC (arm A) and CLEAN (arm C) in ONE page load, so the
// board's ~30% within-run drift cancels. If the >250ms frame fraction is markedly higher in the
// ALLOC arms AND the landing counters confirm each arm ran its intended path, the stall tracks the
// marquee allocation and the source fix is validated. Frame timing is the bare rAF loop (p7_min).
// Exfil MQ| through document.title, read with xprop.
(function () {
  if (window.__kp25) return;
  window.__kp25 = 1;

  // Warmup 20s (discard: page load is not steady state), then 80s arms. ALLOC first so a palindrome
  // A,C,A,C,A brackets every CLEAN arm with ALLOC arms and cancels a monotonic drift.
  var EDGE = [0, 20, 100, 180, 260, 340, 420];
  var ARMS = ['W', 'A', 'C', 'A', 'C', 'A'];

  var RAF = window.requestAnimationFrame.bind(window);
  var prev = performance.now(), t0 = prev;
  var frames = 0, sumAll = 0, maxAll = 0, big = 0;
  var BUCK = [50, 100, 250, 500, 1000, 2000];
  var hist = [0, 0, 0, 0, 0, 0, 0];

  // per-arm accumulators, keyed A (ALLOC) / C (CLEAN). aran = frames in this arm where the ALLOC
  // code path actually ran (read from window.__mqAllocFrames delta) -- the in-band landing check.
  var arm = { A: mk(), C: mk() };
  function mk() { return { n: 0, s: 0, mx: 0, big: 0, aran: 0 }; }

  var bigList = [];               // [t, dt, armLetter]
  var prevAllocFrames = 0;

  function armAt(elMs) {
    var s = elMs / 1000;
    for (var i = ARMS.length - 1; i >= 0; i--) if (s >= EDGE[i]) return ARMS[i];
    return ARMS[0];
  }

  function tick(now) {
    var dt = now - prev; prev = now;
    var el = now - t0;
    var a = armAt(el);

    // the manipulation: select the marquee's loop body for the frames about to render. Warmup runs
    // the ALLOC (production-default) path.
    window.__mqAlloc = (a === 'C') ? false : true;

    // landing: did the ALLOC code path run since the last probe frame?
    var curAlloc = window.__mqAllocFrames | 0;
    var allocRan = curAlloc > prevAllocFrames ? 1 : 0;
    prevAllocFrames = curAlloc;

    frames++; sumAll += dt; if (dt > maxAll) maxAll = dt;
    var b = 0; while (b < BUCK.length && dt >= BUCK[b]) b++;
    hist[b]++;
    if (dt > 250) { big++; if (bigList.length < 40) bigList.push([Math.round(el / 100) / 10, Math.round(dt), a]); }

    if (a === 'A' || a === 'C') {
      var r = arm[a];
      r.n++; r.s += dt; if (dt > r.mx) r.mx = dt; if (dt > 250) r.big++; r.aran += allocRan;
    }
    RAF(tick);
  }
  RAF(tick);

  function mean(s, n) { return n ? Math.round(s / n) : 0; }

  window.setInterval(function () {
    var el = performance.now() - t0;
    var N = document.querySelectorAll('.marquee').length;
    function armStr(k) { var r = arm[k]; return k + ':' + r.n + '.' + r.big + '.' + mean(r.s, r.n) + '.' + r.mx + '.' + r.aran; }
    var bl = bigList.map(function (e) { return e[0] + ':' + e[1] + e[2]; }).join(',');
    document.title =
      'MQ|' + Math.round(el / 1000) +
      '|f' + frames + '|av' + mean(sumAll, frames) + '|mx' + Math.round(maxAll) + '|BT' + big +
      '|N' + N +
      '|' + armStr('A') + '|' + armStr('C') +
      '|H' + hist.join('.') +
      '|B' + bl;
  }, 2000);
})();
