// Interleaved exfil-cadence test: does the floor track how often the probe pokes X's
// WM_NAME? FAST/SLOW/FAST title cadence in one continuous capture, every other piece of
// instrumentation byte-identical to p4_a.js. The probe counts its own writes per arm
// (tw) so the manipulation is verified rather than assumed. parse_title.py reads it.
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


  // ABLATION: vary ONLY the document.title write cadence. Everything else -- the rAF
  // instrumentation, the wrapped getters, the MutationObserver -- is untouched, so the
  // single variable is how often the probe pokes X's WM_NAME.
  // Arms: 0-20 warmup (excluded), 20-140 FAST1 (1000ms), 140-260 SLOW (4000ms), 260-380 FAST2 (1000ms).
  // Stock p4_a.js writes every 2000ms (0.5/s); FAST is 1/s, SLOW is 0.25/s -- a 4x span.
  var TITLE_MS = [1000, 4000, 1000];
  var aF = [0, 0, 0], aMs = [0, 0, 0], aBig = [0, 0, 0], aTW = [0, 0, 0];
  var curArm = -2;

  function armOf(elMs) {
    var s = elMs / 1000;
    if (s < 20) return -1;
    if (s < 140) return 0;
    if (s < 260) return 1;
    if (s < 380) return 2;
    return -1;
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

    var arm = armOf(el);
    curArm = arm;
    if (arm >= 0) {
      aF[arm]++; aMs[arm] += dt;
      if (dt > THRESH) aBig[arm]++;
    }

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

  // 200 ms base tick that only *checks* the clock; the title is written when the current
  // arm's period is due. The check itself is two number comparisons -- no DOM, no X.
  var lastWrite = -1e9;
  origSetInterval(function () {
    var el = performance.now() - t0;
    var a = armOf(el);
    var period = (a >= 0) ? TITLE_MS[a] : 2000;
    if (el - lastWrite < period) return;
    lastWrite = el;
    if (a >= 0) aTW[a]++;

    var rows = document.querySelectorAll('[data-pwt-ride-name]').length;
    var mq = document.querySelectorAll('.ride-name-text.marquee').length;

    function armStr(i) {
      return 'f' + aF[i] + ':b' + aBig[i] + ':tw' + aTW[i] +
             ':m' + (aF[i] ? Math.round(aMs[i] / aF[i]) : 0);
    }

    document.title =
      'KA|arm' + curArm +
      '|FAST1_' + armStr(0) + '|SLOW_' + armStr(1) + '|FAST2_' + armStr(2) + '|' +
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
  }, 200);
})();
