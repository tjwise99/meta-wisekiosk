(function () {
  if (window.__pf) return;
  window.__pf = 1;

  // LAYOUT-vs-PAINT attribution for the ~450ms marquee scroll-start stall.
  //
  // A bare rAF frame-time loop (p7_min.js) plus ONE synchronous layout flush per
  // frame, timed. `offsetHeight` on the root forces style+layout to be computed
  // now, so tForce is the cost of flushing whatever layout this frame had pending.
  // Nothing else is read: no per-element getComputedStyle, no MutationObserver,
  // no querySelectorAll -- those land inside WebKitWebProcess and confound the
  // very cost being attributed.
  //
  // Forcing layout every frame is a DELIBERATE PERTURBATION, and both outcomes
  // are findings:
  //   tForce large on the stall frame  -> the stall is a batched layout flush.
  //   tForce small on the stall frame  -> dt is paint/raster/compositing; a
  //                                       forced-layout timer cannot see it.
  //   no frames >250ms at all          -> flushing continuously dissolved the
  //                                       batch; also a batched-layout result.
  // The run is therefore not a neutral observation of the unperturbed page.
  //
  // longtask entries cross-check the big frames from the engine's own side. The
  // entryType is absent on some WebKit builds; absence is recorded, never faked.
  //
  // Payload tag is PF|. The KP*/MP* parsers do not read it -- parse_profile.py does.
  var t0 = performance.now();
  var prev = t0;
  var frames = 0, sum = 0, mx = 0, big250 = 0;
  var worst = [];
  var KEEP = 14;

  var ltCount = null, ltMax = 0;
  try {
    var types = window.PerformanceObserver && PerformanceObserver.supportedEntryTypes;
    if (types && types.indexOf('longtask') >= 0) {
      ltCount = 0;
      new PerformanceObserver(function (list) {
        var es = list.getEntries();
        for (var i = 0; i < es.length; i++) {
          ltCount++;
          if (es[i].duration > ltMax) ltMax = es[i].duration;
        }
      }).observe({ entryTypes: ['longtask'] });
    }
  } catch (e) {
    ltCount = null;
  }

  var rAF = window.requestAnimationFrame.bind(window);

  function tick(now) {
    var dt = now - prev;
    prev = now;

    var l0 = performance.now();
    void document.documentElement.offsetHeight;
    var tForce = performance.now() - l0;

    frames++;
    sum += dt;
    if (dt > mx) mx = dt;
    if (dt > 250) big250++;

    if (dt > 150) {
      worst.push({ t: Math.round((now - t0) / 100) / 10, dt: dt, f: tForce });
      worst.sort(function (a, b) { return b.dt - a.dt; });
      if (worst.length > KEEP) worst.length = KEEP;
    }
    rAF(tick);
  }
  rAF(tick);

  setInterval(function () {
    var el = performance.now() - t0;
    var w = worst.map(function (e) {
      return e.t + ':' + Math.round(e.dt) + ':' + Math.round(e.f);
    }).join(',');
    document.title =
      'PF|' + Math.round(el / 1000) +
      '|f' + frames +
      '|av' + Math.round(sum / Math.max(frames, 1)) +
      '|mx' + Math.round(mx) +
      '|BIG' + big250 + '250ms' +
      '|LT' + (ltCount === null ? 'NA/NA' : ltCount + '/' + Math.round(ltMax)) +
      '|W' + w;
  }, 2000);
})();
