// Rotation-driver split probe (meta-wisekiosk #100, Run 40). Installed at ~/.surf/script.js.
//
// Run 39 proved the rotation tick drives the residual full-GC stall (ablating it -> 0). This splits
// which part: the marquee re-registration's window.matchMedia (each call makes a document-retained
// MediaQueryList) vs the per-tick derived recompute. Three conditions interleaved in one capture:
//   N none          -- real matchMedia, rotation on   (baseline)
//   M matchmedia     -- cached matchMedia, rotation on (isolates the matchMedia allocation)
//   R rotation-off   -- rotation frozen                (zero control from Run 39)
// If M's >250ms fraction drops to ~R's, matchMedia is the driver and caching it is the fix. If M
// stays ~N, the derived recompute is the driver instead. Landing from the app's counters:
// window.__mmReal (uncached matchMedia calls) and window.__ablRotSkip. Exfil SP| via document.title.
(function () {
  if (window.__kp29) return; window.__kp29 = 1;
  var EDGE = [0, 20, 70, 120, 170, 220, 270, 320, 370, 420];
  var ARMS = ['W', 'N', 'M', 'R', 'N', 'M', 'R', 'N', 'M', 'R'];
  var RAF = window.requestAnimationFrame.bind(window);
  var prev = performance.now(), t0 = prev;
  var frames = 0, big = 0;
  var cond = { N: mk(), M: mk(), R: mk() };
  function mk() { return { n: 0, s: 0, mx: 0, big: 0, mmr: 0, rsk: 0 }; }
  var bigList = [];
  var prevMM = 0, prevRot = 0;

  function armAt(elMs) {
    var s = elMs / 1000;
    for (var i = ARMS.length - 1; i >= 0; i--) if (s >= EDGE[i]) return ARMS[i];
    return 'W';
  }
  function tick(now) {
    var dt = now - prev; prev = now;
    var el = now - t0;
    var a = armAt(el);
    window.__abl = { matchmedia: a === 'M', rotation: a === 'R' };
    var curMM = window.__mmReal | 0, curRot = window.__ablRotSkip | 0;
    var dMM = curMM - prevMM, dRot = curRot - prevRot;
    prevMM = curMM; prevRot = curRot;
    frames++;
    if (dt > 250) { big++; if (bigList.length < 60) bigList.push([Math.round(el / 100) / 10, Math.round(dt), a]); }
    if (a === 'N' || a === 'M' || a === 'R') {
      var r = cond[a];
      r.n++; r.s += dt; if (dt > r.mx) r.mx = dt; if (dt > 250) r.big++; r.mmr += dMM; r.rsk += dRot;
    }
    RAF(tick);
  }
  RAF(tick);
  function mean(s, n) { return n ? Math.round(s / n) : 0; }
  window.setInterval(function () {
    var el = Math.round((performance.now() - t0) / 1000);
    function cstr(k) { var r = cond[k]; return k + ':' + r.n + '.' + r.big + '.' + mean(r.s, r.n) + '.' + r.mx + '.' + r.mmr + '.' + r.rsk; }
    var bl = bigList.map(function (e) { return e[0] + ':' + e[1] + e[2]; }).join(',');
    document.title = 'SP|' + el + '|f' + frames + '|big' + big +
      '|' + cstr('N') + '|' + cstr('M') + '|' + cstr('R') + '|B' + bl;
  }, 2000);
})();
