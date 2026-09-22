// Baseline arm: probe4.tmpl.js with no ablation. The capture of record for runs A, A2
// and the remount-removal after-run, and the 'full instrumentation' arm of the
// instrumentation-stripped comparison against p7_min.js.
(function () {
  if (window.__kp) return;
  window.__kp = 1;

  var t0 = performance.now();
  var layoutMs = 0, layoutN = 0, jsMs = 0;

  function wrapGetter(proto, prop) {
    var d = Object.getOwnPropertyDescriptor(proto, prop);
    if (!d || !d.get) return;
    var orig = d.get;
    Object.defineProperty(proto, prop, {
      configurable: true,
      enumerable: d.enumerable,
      get: function () {
        var a = performance.now();
        var v = orig.call(this);
        layoutMs += performance.now() - a;
        layoutN++;
        return v;
      }
    });
  }

  function wrapMethod(obj, name) {
    var orig = obj[name];
    if (typeof orig !== 'function') return;
    obj[name] = function () {
      var a = performance.now();
      var v = orig.apply(this, arguments);
      layoutMs += performance.now() - a;
      layoutN++;
      return v;
    };
  }

  ['scrollWidth', 'scrollHeight', 'clientWidth', 'clientHeight'].forEach(function (p) {
    wrapGetter(Element.prototype, p);
  });
  ['offsetWidth', 'offsetHeight', 'offsetTop', 'offsetLeft'].forEach(function (p) {
    wrapGetter(HTMLElement.prototype, p);
  });
  wrapMethod(Element.prototype, 'getBoundingClientRect');
  wrapMethod(window, 'getComputedStyle');

  function timed(fn) {
    return function () {
      var a = performance.now();
      try { return fn.apply(this, arguments); }
      finally { jsMs += performance.now() - a; }
    };
  }

  var origRaf = window.requestAnimationFrame.bind(window);
  var origSetTimeout = window.setTimeout.bind(window);
  var origSetInterval = window.setInterval.bind(window);

  window.requestAnimationFrame = function (cb) {
    return origRaf(typeof cb === 'function' ? timed(cb) : cb);
  };
  window.setTimeout = function (cb) {
    var rest = Array.prototype.slice.call(arguments, 1);
    return origSetTimeout.apply(null, [typeof cb === 'function' ? timed(cb) : cb].concat(rest));
  };
  window.setInterval = function (cb) {
    var rest = Array.prototype.slice.call(arguments, 1);
    return origSetInterval.apply(null, [typeof cb === 'function' ? timed(cb) : cb].concat(rest));
  };
  var origQmt = window.queueMicrotask ? window.queueMicrotask.bind(window) : null;
  if (origQmt) {
    window.queueMicrotask = function (cb) {
      return origQmt(typeof cb === 'function' ? timed(cb) : cb);
    };
  }



  var rotN = 0, lastRotT = -1e9, pendingRot = 0, firstRotT = 0;

  var mo = new MutationObserver(function (recs) {
    var n = 0;
    for (var i = 0; i < recs.length; i++) {
      var r = recs[i];
      if (r.addedNodes.length === 0 && r.removedNodes.length === 0) continue;
      var tgt = r.target;
      if (tgt && tgt.closest && tgt.closest('[data-pwt-ride-name]')) {
        n += r.addedNodes.length + r.removedNodes.length;
      }
    }
    if (n === 0) return;
    var t = performance.now() - t0;
    pendingRot += n;
    if (t - lastRotT > 1500) {
      if (rotN === 0) firstRotT = t;
      rotN++;
      lastRotT = t;
    }
  });

  function observe() {
    if (document.body) {
      mo.observe(document.body, { childList: true, subtree: true });
    } else {
      origSetTimeout(observe, 200);
    }
  }
  observe();

  var EDGES = [50, 100, 250, 500, 1000, 2000];
  var hist = [0, 0, 0, 0, 0, 0, 0];

  // Frame cost binned by seconds elapsed since the last rotation remount.
  var PH = 9;
  var phMs = [], phN = [], phBig = [];
  for (var i = 0; i < PH; i++) { phMs.push(0); phN.push(0); phBig.push(0); }

  // Frame cost binned by absolute 10 s window, to expose drift and the 5 min poll.
  var WIN = 10000, wMs = [], wN = [];

  var big = [], bigTotal = 0, frames = 0, sumFrame = 0, maxFrame = 0, top = [];
  var prev = performance.now();
  var THRESH = 250;

  function tick(now) {
    var dt = now - prev;
    prev = now;
    var el = now - t0;
    frames++;
    sumFrame += dt;
    if (dt > maxFrame) maxFrame = dt;

    var b = 0;
    while (b < EDGES.length && dt >= EDGES[b]) b++;
    hist[b]++;

    var ph = Math.floor((el - lastRotT) / 1000);
    if (ph < 0) ph = PH - 1;
    if (ph >= PH) ph = PH - 1;
    phMs[ph] += dt; phN[ph]++;

    var w = Math.floor(el / WIN);
    while (wMs.length <= w) { wMs.push(0); wN.push(0); }
    wMs[w] += dt; wN[w]++;

    if (dt > THRESH) {
      bigTotal++;
      phBig[ph]++;
      var rec =
        Math.round(el / 100) / 10 + ':' +
        Math.round(dt) + ':' +
        Math.round(jsMs) + ':' +
        Math.round(layoutMs) + ':' +
        layoutN + ':' +
        Math.round((el - lastRotT) / 100) / 10;
      big.push(rec);
      if (big.length > 14) big.shift();
      top.push([dt, rec]);
      top.sort(function (x, y) { return y[0] - x[0]; });
      if (top.length > 8) top.length = 8;
    }
    layoutMs = 0; layoutN = 0; jsMs = 0; pendingRot = 0;
    origRaf(tick);
  }
  origRaf(tick);

  function meanList(ms, n) {
    var o = [];
    for (var i = 0; i < ms.length; i++) o.push(n[i] ? Math.round(ms[i] / n[i]) : 0);
    return o.join('.');
  }

  origSetInterval(function () {
    var rows = document.querySelectorAll('[data-pwt-ride-name]').length;
    var mq = document.querySelectorAll('.ride-name-text.marquee').length;
    var el = performance.now() - t0;
    document.title =
      'KP|' + Math.round(el / 1000) +
      '|f' + frames +
      '|mx' + Math.round(maxFrame) +
      '|av' + Math.round(sumFrame / Math.max(frames, 1)) +
      '|M' + mq + '/' + rows +
      '|ROT' + rotN + '@' + Math.round((el - firstRotT) / Math.max(rotN - 1, 1)) +
      '|H' + hist.join('.') +
      '|PM' + meanList(phMs, phN) +
      '|PN' + phN.join('.') +
      '|PB' + phBig.join('.') +
      '|W' + meanList(wMs, wN) +
      '|BT' + bigTotal +
      '|T' + top.map(function (e) { return e[1]; }).join(',') +
      '|B' + big.join(',');
  }, 2000);
})();
