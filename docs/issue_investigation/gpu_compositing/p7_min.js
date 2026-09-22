(function () {
  if (window.__kp) return;
  window.__kp = 1;

  // MINIMAL probe: a bare requestAnimationFrame frame-time loop and nothing else.
  //
  // p4_a.js -- every prior capture -- wraps scrollWidth/clientWidth/offsetWidth/
  // getBoundingClientRect/getComputedStyle with performance.now() pairs, wraps rAF,
  // setTimeout, setInterval and queueMicrotask, and runs a subtree MutationObserver plus
  // two querySelectorAll sweeps per title write. All of that lands inside
  // WebKitWebProcess, so Test B (which measured X) cannot exclude it.
  //
  // This variant removes ALL of it. If the ~1/s frames>250ms floor survives here, the
  // floor is not the instrumentation. If it collapses, it was.
  var t0 = performance.now();
  var prev = t0;
  var frames = 0, sum = 0, mx = 0, bigTotal = 0;
  var EDGES = [50, 100, 250, 500, 1000, 2000];
  var hist = [0, 0, 0, 0, 0, 0, 0];
  var big = [];

  var rAF = window.requestAnimationFrame.bind(window);

  function tick(now) {
    var dt = now - prev;
    prev = now;
    frames++;
    sum += dt;
    if (dt > mx) mx = dt;

    var b = 0;
    while (b < EDGES.length && dt >= EDGES[b]) b++;
    hist[b]++;

    if (dt > 250) {
      bigTotal++;
      big.push(Math.round((now - t0) / 100) / 10 + ':' + Math.round(dt));
      if (big.length > 14) big.shift();
    }
    rAF(tick);
  }
  rAF(tick);

  setInterval(function () {
    var el = performance.now() - t0;
    document.title =
      'MP|' + Math.round(el / 1000) +
      '|f' + frames +
      '|av' + Math.round(sum / Math.max(frames, 1)) +
      '|mx' + Math.round(mx) +
      '|BT' + bigTotal +
      '|H' + hist.join('.') +
      '|B' + big.join(',');
  }, 2000);
})();
