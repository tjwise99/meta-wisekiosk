// meta-wisekiosk #100, Run 48 (rotation-interval lever). Same >250ms stall detector as p30_baseline.js
// (S[...]), PLUS a landing check for the rotation interval itself: it polls a tour row's text every
// 500ms and records the wall-clock time of each change (R[...]), so one capture carries both the beat
// cadence and the ACTUAL rotation period the config produced. Exfil via document.title, read with xprop.
(function () {
  if (window.__kp31) return; window.__kp31 = 1;
  var RAF = window.requestAnimationFrame.bind(window);
  var prev = performance.now(), t0 = prev;
  var frames = 0, big = 0, mx = 0;
  var stalls = [];
  function tick(now) {
    var dt = now - prev; prev = now; frames++; if (dt > mx) mx = dt;
    if (dt > 250) { big++; if (stalls.length < 120) stalls.push([Math.round((now - t0) / 100) / 10, Math.round(dt)]); }
    RAF(tick);
  }
  RAF(tick);
  // Rotation landing check: first tour row's text; record each change time (seconds since t0).
  var rots = [], lastText = null;
  window.setInterval(function () {
    var el = document.querySelector('[data-pwt-tour-row]');
    var txt = el ? el.textContent.replace(/\s+/g, ' ').trim() : null;
    if (txt !== null && lastText !== null && txt !== lastText && rots.length < 80) {
      rots.push(Math.round((performance.now() - t0) / 100) / 10);
    }
    lastText = txt;
  }, 500);
  window.setInterval(function () {
    var el = Math.round((performance.now() - t0) / 1000);
    document.title = 'BL|' + el + '|f' + frames + '|big' + big + '|mx' + Math.round(mx) +
      '|S[' + stalls.map(function (e) { return e[0] + ':' + e[1]; }).join(',') + ']' +
      '|R[' + rots.join(',') + ']';
  }, 2000);
})();
