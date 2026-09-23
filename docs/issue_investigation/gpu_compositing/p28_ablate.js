// Subsystem-ablation probe (meta-wisekiosk #100, Run 39). Installed at ~/.surf/script.js.
//
// The residual ~1s stall is a full GC from PROMOTED (medium-lived) allocation, on a ~40s cadence
// that surfaces at the rotation scroll-start. The marquee's per-frame TRANSIENT allocation was
// falsified (Run 37). The remaining promoted suspects are the periodic subsystems. The instrumented
// bundle gates each behind window.__abl:
//   __abl.rotation -> the 8s rotation tick's derived recompute is skipped (marquee cycle untouched)
//   __abl.clock    -> the 1s clock re-read/re-format is skipped
// This probe interleaves three conditions in ONE capture (drift-cancelled): N none, R rotation off,
// C clock off. If a condition's >250ms fraction is markedly lower than N, that subsystem's
// allocation drives the stall. The app's own skip counters (window.__ablRotSkip/__ablClkSkip) are
// read back per condition as the landing check. Exfil AB| through document.title, read with xprop.
(function () {
  if (window.__kp28) return; window.__kp28 = 1;
  // warmup 20s, then 50s arms cycling N,R,C three times (each condition gets 150s total, spanning
  // several ~40s GC cadences, sampled early/mid/late so drift cancels).
  var EDGE = [0, 20, 70, 120, 170, 220, 270, 320, 370, 420];
  var ARMS = ['W', 'N', 'R', 'C', 'N', 'R', 'C', 'N', 'R', 'C'];

  var RAF = window.requestAnimationFrame.bind(window);
  var prev = performance.now(), t0 = prev;
  var frames = 0, big = 0;
  var cond = { N: mk(), R: mk(), C: mk() };
  function mk() { return { n: 0, s: 0, mx: 0, big: 0, rs: 0, cs: 0 }; }
  var bigList = [];
  var prevRot = 0, prevClk = 0;

  function armAt(elMs) {
    var s = elMs / 1000;
    for (var i = ARMS.length - 1; i >= 0; i--) if (s >= EDGE[i]) return ARMS[i];
    return 'W';
  }

  function tick(now) {
    var dt = now - prev; prev = now;
    var el = now - t0;
    var a = armAt(el);
    // select the ablation for the frames about to render (warmup runs the normal path)
    window.__abl = { rotation: a === 'R', clock: a === 'C' };
    // landing: how many rotation/clock ticks the app skipped since the last probe frame
    var curRot = window.__ablRotSkip | 0, curClk = window.__ablClkSkip | 0;
    var dRot = curRot - prevRot, dClk = curClk - prevClk;
    prevRot = curRot; prevClk = curClk;

    frames++;
    if (dt > 250) { big++; if (bigList.length < 60) bigList.push([Math.round(el / 100) / 10, Math.round(dt), a]); }
    if (a === 'N' || a === 'R' || a === 'C') {
      var r = cond[a];
      r.n++; r.s += dt; if (dt > r.mx) r.mx = dt; if (dt > 250) r.big++; r.rs += dRot; r.cs += dClk;
    }
    RAF(tick);
  }
  RAF(tick);

  function mean(s, n) { return n ? Math.round(s / n) : 0; }
  window.setInterval(function () {
    var el = Math.round((performance.now() - t0) / 1000);
    function cstr(k) { var r = cond[k]; return k + ':' + r.n + '.' + r.big + '.' + mean(r.s, r.n) + '.' + r.mx + '.' + r.rs + '.' + r.cs; }
    var bl = bigList.map(function (e) { return e[0] + ':' + e[1] + e[2]; }).join(',');
    document.title = 'AB|' + el + '|f' + frames + '|big' + big +
      '|' + cstr('N') + '|' + cstr('R') + '|' + cstr('C') + '|B' + bl;
  }, 2000);
})();
