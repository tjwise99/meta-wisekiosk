(function () {
  if (window.__fvp) return;
  window.__fvp = 1;

  // FULL-VIEWPORT REPAINT COST, measured by forcing one.
  //
  // The residual ~1/s stall is engine-dominated and unexplained; the hypothesis
  // under test is that it IS an occasional full-viewport repaint. This probe
  // prices that repaint directly: a fixed overlay covering the whole viewport,
  // whose background-color is changed to a NEW value every FORCE_EVERY frames.
  // A changed computed background-color invalidates the overlay's full rect, so
  // WebKit must repaint the entire viewport; the two colours differ in one blue
  // unit at 3% alpha, so the price is paid and nothing visible changes.
  //
  // ATTRIBUTION IS TO THE FOLLOWING FRAME. The colour is set inside frame N's
  // rAF callback and WebKit repaints AFTER the callback returns, so the repaint
  // lands in frame N+1's dt. Frame N+1 is tagged FORCED; every other frame is
  // BASELINE and carries the page's ordinary marquee/idle cost. FORCED minus
  // BASELINE is the isolated cost of one full-viewport repaint, and that is the
  // number the ~450ms stall is compared against.
  //
  // The overlay is pointer-events:none, so it captures no input: the kiosk page
  // underneath stays operable while the probe runs.
  //
  // Frame 1's dt is measured from script start, not from a preceding frame, so
  // it is counted in `frames` and attributed to neither distribution.
  //
  // A bare rAF loop and nothing else -- no wrapped getters, no per-element
  // getComputedStyle, no MutationObserver (p7_min.js). Those land inside
  // WebKitWebProcess and confound the very cost being priced.
  //
  // Payload tag is FVP|. The KP*/MP*/PF| parsers do not read it --
  // parse_fullpaint.py does.
  var FORCE_EVERY = 20;
  var COLORS = ['rgba(0,0,0,0.03)', 'rgba(0,0,1,0.03)'];
  var KEEP_TOP = 10;

  var rAF = window.requestAnimationFrame.bind(window);

  function start() {
    var ov = document.createElement('div');
    ov.id = 'fvp-overlay';
    ov.style.cssText =
      'position:fixed;inset:0;z-index:2147483647;pointer-events:none;' +
      'background-color:' + COLORS[0] + ';';
    document.body.appendChild(ov);

    var t0 = performance.now();
    var prev = t0;
    var frames = 0;
    var ci = 0;
    var forcedNext = false;
    var forced = [];
    var base = [];

    function tick(now) {
      var dt = now - prev;
      prev = now;
      frames++;

      if (frames > 1) (forcedNext ? forced : base).push(dt);
      forcedNext = false;

      if (frames % FORCE_EVERY === 0) {
        ci = 1 - ci;
        ov.style.backgroundColor = COLORS[ci];
        forcedNext = true;
      }
      rAF(tick);
    }
    rAF(tick);

    function pct(sorted, p) {
      if (!sorted.length) return 0;
      var i = Math.ceil(p * sorted.length) - 1;
      if (i < 0) i = 0;
      return sorted[i];
    }

    function dist(a) {
      var n = a.length;
      if (!n) return 'n:0,mean:0,p50:0,p90:0,max:0';
      var s = a.slice().sort(function (x, y) { return x - y; });
      var sum = 0;
      for (var i = 0; i < n; i++) sum += a[i];
      return 'n:' + n +
        ',mean:' + Math.round(sum / n) +
        ',p50:' + Math.round(pct(s, 0.5)) +
        ',p90:' + Math.round(pct(s, 0.9)) +
        ',max:' + Math.round(s[n - 1]);
    }

    function top(a) {
      var s = a.slice().sort(function (x, y) { return y - x; }).slice(0, KEEP_TOP);
      var out = [];
      for (var i = 0; i < s.length; i++) out.push(Math.round(s[i]));
      return out.join('.');
    }

    setInterval(function () {
      var el = performance.now() - t0;
      document.title =
        'FVP|' + Math.round(el / 1000) +
        '|f' + frames +
        '|FORCED ' + dist(forced) + ',top:' + top(forced) +
        '|BASE ' + dist(base);
    }, 2000);
  }

  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start);
})();
