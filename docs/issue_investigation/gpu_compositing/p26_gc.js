// GC ground-truth probe (meta-wisekiosk #100, Run 38). Installed at ~/.surf/script.js.
//
// performance.memory is absent on this WebKit (605.1.15), but FinalizationRegistry is present.
// A finalizer fires only after a GC reclaims its token, so we detect GC events in-band:
//   - Sentinel objects are held in a ring for ~SURVIVE_S seconds -> they survive many cheap Eden
//     collections and are PROMOTED to the old generation. When the ring overwrites one it becomes
//     old-generation garbage, reclaimable only by a FULL (old-gen) collection -- the ~1s pause.
//   - Its finalizer then fires; a burst of finalizer callbacks marks a full GC, timestamped.
// The same probe times every frame and records >250ms stalls with timestamps. If the stall
// timestamps line up with the finalizer bursts, the residual stall IS a full GC (ground truth).
// Exfil GC2| through document.title, read with xprop.
(function () {
  if (window.__kp26) return; window.__kp26 = 1;
  var t0 = performance.now(), prev = t0;
  var frames = 0, big = 0, finalizeCount = 0, lastFin = -1e9;
  var stalls = [];    // [t(0.1s), dt(ms)] for frames > 250ms
  var gcEvents = [];  // t(0.1s) of each finalizer burst (>=1 old-gen sentinel reclaimed => full GC)

  var reg = new FinalizationRegistry(function () {
    var now = performance.now();
    finalizeCount++;
    if (now - lastFin > 250) { if (gcEvents.length < 240) gcEvents.push(Math.round((now - t0) / 100) / 10); }
    lastFin = now;
  });

  // One promoted sentinel per second, dropped SURVIVE_S later so only a full GC frees it.
  var SURVIVE_S = 40, ring = new Array(SURVIVE_S), seq = 0;
  window.setInterval(function () {
    var s = { seq: seq, pad: new Array(40).join('x') };
    reg.register(s, seq);
    ring[seq % SURVIVE_S] = s;   // overwrites the sentinel from SURVIVE_S s ago -> old-gen garbage
    seq++;
  }, 1000);

  var RAF = window.requestAnimationFrame.bind(window);
  function tick(now) {
    var dt = now - prev; prev = now; frames++;
    if (dt > 250) { big++; if (stalls.length < 240) stalls.push([Math.round((now - t0) / 100) / 10, Math.round(dt)]); }
    RAF(tick);
  }
  RAF(tick);

  window.setInterval(function () {
    var el = Math.round((performance.now() - t0) / 1000);
    var st = stalls.map(function (e) { return e[0] + ':' + e[1]; }).join(',');
    document.title = 'GC2|' + el + '|f' + frames + '|big' + big + '|fin' + finalizeCount +
      '|S[' + st + ']|G[' + gcEvents.join(',') + ']';
  }, 2000);
})();
