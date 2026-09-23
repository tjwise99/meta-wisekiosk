(function () {
  if (window.__kc) return;
  window.__kc = 1;

  // PAINT CONTAINMENT on the park cards, measured against the frame-stall rate.
  //
  // The residual stall is ~450ms and full-viewport in extent. If it is WebKit
  // escalating to a whole-viewport software repaint, then making each card a
  // paint-containment boundary bounds the escalation to one card -- about a
  // quarter of the viewport, ~110ms -- which is under the 250ms visible-stall
  // threshold. The prediction is that frames>250ms/s falls toward zero. If the
  // rate does not move, the escalation is not card-bounded.
  //
  // CONTAINMENT IS APPLIED AS AN INLINE STYLE PROPERTY, NOT A STYLESHEET. The
  // page CSP is `style-src 'self'; style-src-attr 'unsafe-inline'`, so an
  // injected <style> element is dropped while an inline style property survives.
  //
  // Cards re-render on a flip, so the ensure loop runs every frame and every
  // current card is checked; the write happens only when the inline value
  // differs, so a steady card set costs reads and no writes. `writes` is
  // exfiltrated: if it climbs with `frames`, the loop is rewriting rather than
  // settling and the run is perturbed by its own instrumentation.
  //
  // THE LANDING READ IS WHAT KEEPS A NULL HONEST. Once per ~2s, one card's
  // COMPUTED contain is read back. land=0 means containment never took effect,
  // and a flat stall rate under land=0 says nothing about the hypothesis.
  // `sup` is the same guard one level down: a build without the property would
  // otherwise fail the inline-value comparison every frame and churn forever, so
  // support is probed once and the ensure loop is skipped when it is absent.
  //
  // Frame timing is p7_min.js's and nothing more -- dt, mean, max, frames>250ms,
  // a histogram and the big-frame timestamps for phase against the 8s flip. No
  // wrapped getters, no MutationObserver, no per-element getComputedStyle in the
  // per-frame path; those land inside WebKitWebProcess and confound the metric
  // that decides this.
  //
  // The ensure loop and the landing read run inside the rAF callback, so their
  // cost is attributed to the FOLLOWING frame's dt, as with any style write.
  //
  // Payload tag is KC|. The MP|/PF|/FVP| parsers do not read it --
  // parse_contain.py does.

  // KNOB -- the containment level under test. 'paint' is the hypothesis as
  // stated; 'layout paint' and 'strict' are the stronger variants to try
  // between runs. One run per value; the value is exfiltrated with the sample.
  var CONTAIN = 'paint';

  var SEL = '[data-pwt-card]';
  var LAND_EVERY_MS = 2000;
  var EDGES = [50, 100, 250, 500, 1000, 2000];
  var KEEP_BIG = 14;

  var rAF = window.requestAnimationFrame.bind(window);

  // A value that reads back as containment: the expanded serialisation lists
  // `paint`, and a build may keep `strict`/`content` as the shorthand keyword.
  function landed(cv) {
    if (!cv || cv === 'none') return 0;
    if (cv.indexOf('paint') >= 0) return 1;
    if (cv.indexOf('strict') >= 0 || cv.indexOf('content') >= 0) return 1;
    return cv === CONTAIN ? 1 : 0;
  }

  function tok(s) {
    return String(s).replace(/\s+/g, '+').replace(/[^a-zA-Z+]/g, '');
  }

  function start() {
    var support = 1;
    try {
      var probe = document.createElement('div');
      probe.style.setProperty('contain', CONTAIN);
      if (probe.style.getPropertyValue('contain') === '') support = 0;
    } catch (e) {
      support = 0;
    }

    var t0 = performance.now();
    var prev = t0;
    var frames = 0, sum = 0, mx = 0, bigTotal = 0;
    var hist = [0, 0, 0, 0, 0, 0, 0];
    var big = [];
    var cards = 0, writes = 0;
    var land = 0, cv = '';
    var landAt = t0;

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
        if (big.length > KEEP_BIG) big.shift();
      }

      var els = document.querySelectorAll(SEL);
      cards = els.length;
      if (support) {
        for (var i = 0; i < cards; i++) {
          var st = els[i].style;
          if (st.getPropertyValue('contain') !== CONTAIN) {
            st.setProperty('contain', CONTAIN);
            writes++;
          }
        }
      }

      if (now - landAt >= LAND_EVERY_MS) {
        landAt = now;
        cv = cards ? getComputedStyle(els[0]).contain || '' : '';
        land = landed(cv);
      }

      rAF(tick);
    }
    rAF(tick);

    setInterval(function () {
      var el = performance.now() - t0;
      var sec = Math.round(el / 1000);
      document.title =
        'KC|' + sec +
        '|f' + frames +
        '|av' + Math.round(sum / Math.max(frames, 1)) +
        '|mx' + Math.round(mx) +
        '|BT' + bigTotal +
        '|RT' + (Math.round(1000 * bigTotal / Math.max(sec, 1)) / 1000) +
        '|C' + cards + '.' + writes +
        '|L' + land + '.' + support +
        '|CV' + tok(cv) +
        '|CN' + tok(CONTAIN) +
        '|H' + hist.join('.') +
        '|B' + big.join(',');
    }, 2000);
  }

  if (document.body) start();
  else document.addEventListener('DOMContentLoaded', start);
})();
