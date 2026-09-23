(function () {
  if (window.__fz) return;
  window.__fz = 1;

  // ENGINE vs CONTENT, decided by freezing the page.
  //
  // The residual ~450ms full-viewport stall is engine-dominated but its trigger
  // is undecided. This probe stops the app's clock: every live timer is cleared
  // and `requestAnimationFrame`, `setInterval` and `setTimeout` are replaced by
  // no-ops, so no app callback can reschedule and the DOM stops changing. The
  // app's rAF loop runs its in-flight frame and then ends, because the next
  // `requestAnimationFrame` it calls is the no-op.
  //
  // The probe keeps measuring because it captures the REAL scheduler into `RAF`
  // BEFORE the neuter and drives its own loop and its own ~2s exfil from it. It
  // never calls `window.requestAnimationFrame`, `setInterval` or `setTimeout`
  // after the freeze; `clearInterval`/`clearTimeout` are left intact so the
  // page's own loop teardown still works.
  //
  // Stalls that survive a frozen page are the engine repainting a page nothing
  // touched -- nothing the frontend can reach. Stalls that go to zero are driven
  // by the app's own DOM updates.
  //
  // THE FROZEN FLAG GATES THE VERDICT. A result on a page that did not actually
  // freeze is meaningless -- an app that captured `requestAnimationFrame` into a
  // local before this probe loaded keeps running, and the neuter cannot reach
  // it. So a content signature is sampled every ~2s: `document.body.innerText`
  // length plus the clock's `.seconds` text, which Clock.svelte rewrites once a
  // second (p5_clock.js). `frozen=1` only when consecutive samples never differ;
  // any change reports `frozen=0` with the change count, and parse_freeze.py
  // refuses a verdict on it.
  //
  // THE SAMPLING FRAME'S COST IS NOT CHARGED TO THE ENGINE. `innerText` forces
  // layout, and WebKit does that after the rAF callback returns, so the cost
  // lands in the FOLLOWING frame's dt -- at ~0.5/s, enough to fake the very rate
  // this probe reads. That frame is excluded from `frames`, the histogram and
  // the stall count, and is exfiltrated separately as `S<big>.<frames>`.
  //
  // Frame timing is p7_min.js's and nothing more -- dt, mean, max, frames>250ms,
  // a 7-bucket histogram and the big-frame timestamps. The probe changes no
  // visible DOM: `document.title` is not rendered on this titlebar-less kiosk,
  // so a static page has nothing to repaint unless WebKit repaints it unasked.
  //
  // Payload tag is FZ|. The MP|/FVP|/KC| parsers do not read it --
  // parse_freeze.py does.

  var CLOCK_SEL = '.seconds';
  var SAMPLE_MS = 2000;
  var SETTLE_MS = 1000;   // first sample; earlier samples catch load-time churn
  var MIN_SAMPLES = 3;    // >=2 comparisons before `frozen` means anything
  var CLEAR_MAX = 200000;
  var EDGES = [50, 100, 250, 500, 1000, 2000];
  var KEEP_BIG = 14;

  // Captured before the neuter, and the only scheduler the probe uses.
  var RAF = window.requestAnimationFrame.bind(window);
  var CLEAR_I = window.clearInterval.bind(window);
  var CLEAR_T = window.clearTimeout.bind(window);

  function freeze() {
    for (var i = 1; i < CLEAR_MAX; i++) {
      CLEAR_I(i);
      CLEAR_T(i);
    }
    window.requestAnimationFrame = function () { return 0; };
    window.setInterval = function () { return 0; };
    window.setTimeout = function () { return 0; };
  }

  function signature() {
    var n = -1, t = '';
    try {
      n = (document.body.innerText || '').length;
    } catch (e) {
      n = -1;
    }
    try {
      var el = document.querySelector(CLOCK_SEL);
      if (el) t = (el.textContent || '').replace(/\s+/g, '');
    } catch (e) {
      t = '';
    }
    return n + '/' + t;
  }

  function start() {
    freeze();

    var t0 = performance.now();
    var prev = t0;
    var frames = 0, sum = 0, mx = 0, bigTotal = 0;
    var hist = [0, 0, 0, 0, 0, 0, 0];
    var big = [];
    var sigFrames = 0, sigBig = 0, afterSig = false;
    var samples = 0, changes = 0, last = null;
    var sampleAt = t0 + SETTLE_MS;

    function title(now) {
      var sec = Math.round((now - t0) / 1000);
      var frozen = (samples >= MIN_SAMPLES && changes === 0) ? 1 : 0;
      document.title =
        'FZ|' + sec +
        '|f' + frames +
        '|av' + Math.round(sum / Math.max(frames, 1)) +
        '|mx' + Math.round(mx) +
        '|BT' + bigTotal +
        '|RT' + (Math.round(1000 * bigTotal / Math.max(sec, 1)) / 1000) +
        '|Z' + frozen + '.' + changes + '.' + samples +
        '|S' + sigBig + '.' + sigFrames +
        '|H' + hist.join('.') +
        '|B' + big.join(',');
    }

    function tick(now) {
      var dt = now - prev;
      prev = now;

      if (afterSig) {
        afterSig = false;
        sigFrames++;
        if (dt > 250) sigBig++;
      } else {
        frames++;
        sum += dt;
        if (dt > mx) mx = dt;

        var b = 0;
        while (b < EDGES.length && dt >= EDGES[b]) b++;
        hist[b]++;

        if (dt > 250) {
          bigTotal++;
          big.push(Math.round((now - t0) / 100) / 10 + ':' + Math.round(dt));
          if (big.length > KEEP_BIG) big.shift();
        }
      }

      if (now >= sampleAt) {
        sampleAt = now + SAMPLE_MS;
        var s = signature();
        samples++;
        if (last !== null && s !== last) changes++;
        last = s;
        title(now);
        afterSig = true;
      }

      RAF(tick);
    }
    RAF(tick);
  }

  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start);
})();
