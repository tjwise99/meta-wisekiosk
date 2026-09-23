// Plain long baseline (meta-wisekiosk #100, Run 41). No ablation — window.__abl left unset, so the
// app runs normally. Records >250ms stall timestamps to characterize the bursty arrival and give a
// same-session reference for the JSC GC-tuning test. Exfil BL| via document.title, read with xprop.
(function () {
  if (window.__kp30) return; window.__kp30 = 1;
  var RAF = window.requestAnimationFrame.bind(window);
  var prev = performance.now(), t0 = prev;
  var frames = 0, big = 0, sum = 0, mx = 0;
  var stalls = [];
  var BUCK = [50, 100, 250, 500, 1000, 2000], hist = [0, 0, 0, 0, 0, 0, 0];
  function tick(now) {
    var dt = now - prev; prev = now; frames++; sum += dt; if (dt > mx) mx = dt;
    var b = 0; while (b < BUCK.length && dt >= BUCK[b]) b++; hist[b]++;
    if (dt > 250) { big++; if (stalls.length < 120) stalls.push([Math.round((now - t0) / 100) / 10, Math.round(dt)]); }
    RAF(tick);
  }
  RAF(tick);
  window.setInterval(function () {
    var el = Math.round((performance.now() - t0) / 1000);
    document.title = 'BL|' + el + '|f' + frames + '|big' + big + '|av' + (frames ? Math.round(sum / frames) : 0) +
      '|mx' + Math.round(mx) + '|H' + hist.join('.') +
      '|S[' + stalls.map(function (e) { return e[0] + ':' + e[1]; }).join(',') + ']';
  }, 2000);
})();
