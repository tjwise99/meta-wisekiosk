(function () {
  if (window.__kp) return;
  window.__kp = 1;

  // Kill ALL CSS animation in the live app, interleaved, and verify it actually applied.
  //
  // This is Run 8's arm B done properly. That arm injected
  // `animation:none !important` and measured no change, but recorded no in-band proof the
  // rule ever took effect -- its own write-up calls it "unmeasured" for exactly that reason.
  // The rule goes in through insertRule on an existing same-origin sheet, because the page's
  // CSP (`style-src 'self'`) drops an injected <style> element.
  //
  // The app stays VISIBLE in every arm. The only variable is whether animations run.
  var WARM = 20, ARMLEN = 80, NSLOT = 5;
  var COND = [0, 1, 0, 1, 0];        // 0 = animations on, 1 = animations off

  var t0 = performance.now(), prev = t0;
  var frames = 0, sum = 0, mx = 0, bigTotal = 0;
  var EDGES = [50, 100, 250, 500, 1000, 2000];
  var hist = [0, 0, 0, 0, 0, 0, 0];
  var big = [];

  var sF = [0,0,0,0,0], sMs = [0,0,0,0,0], sBig = [0,0,0,0,0];
  var sAppW = [-1,-1,-1,-1,-1], sMq = [-1,-1,-1,-1,-1], sAnim = ['x','x','x','x','x'];
  var curSlot = -2, ruleIdx = -1, sheetOk = 0;

  var appEl = null;
  var rAF = window.requestAnimationFrame.bind(window);

  function slotOf(elMs) {
    var s = elMs / 1000;
    if (s < WARM) return -1;
    var k = Math.floor((s - WARM) / ARMLEN);
    return (k >= 0 && k < NSLOT) ? k : -1;
  }

  function setAnimOff(off) {
    var sh;
    try { sh = document.styleSheets[0]; } catch (e) { return; }
    if (!sh) return;
    if (off) {
      if (ruleIdx >= 0) return;
      try {
        ruleIdx = sh.insertRule('*,*::before,*::after{animation:none !important;}',
                                sh.cssRules.length);
        sheetOk = 1;
      } catch (e) { ruleIdx = -1; sheetOk = -1; }
    } else if (ruleIdx >= 0) {
      try { sh.deleteRule(ruleIdx); } catch (e) {}
      ruleIdx = -1;
    }
  }

  function applySlot(k) {
    if (!appEl && document.body) {
      appEl = document.getElementById('app') || document.body.firstElementChild;
    }
    setAnimOff(k >= 0 && COND[k] === 1);
  }

  function tick(now) {
    var dt = now - prev;
    prev = now;
    var el = now - t0;
    frames++; sum += dt; if (dt > mx) mx = dt;

    var b = 0;
    while (b < EDGES.length && dt >= EDGES[b]) b++;
    hist[b]++;

    var k = slotOf(el);
    if (k !== curSlot) { curSlot = k; applySlot(k); }
    if (k >= 0) {
      sF[k]++; sMs[k] += dt;
      if (dt > 250) sBig[k]++;
    }

    if (dt > 250) {
      bigTotal++;
      big.push(Math.round(el / 100) / 10 + ':' + Math.round(dt));
      if (big.length > 14) big.shift();
    }
    rAF(tick);
  }
  rAF(tick);

  setInterval(function () {
    var el = performance.now() - t0;
    if (!appEl && document.body) {
      appEl = document.getElementById('app') || document.body.firstElementChild;
    }

    if (curSlot >= 0) {
      var aw = appEl ? Math.round(appEl.getBoundingClientRect().width) : -1;
      if (aw > sAppW[curSlot]) sAppW[curSlot] = aw;

      // The landing check run B never had: read the COMPUTED animationName off a real
      // marquee row. 'none' proves the rule applied; a keyframes name proves it did not.
      var rows = document.querySelectorAll('.ride-name-text.marquee');
      if (rows.length > sMq[curSlot]) sMq[curSlot] = rows.length;
      var a = 'norow';
      if (rows.length) {
        var nm = window.getComputedStyle(rows[0]).animationName;
        a = (!nm || nm === 'none') ? 'OFF' : 'ON';
      }
      sAnim[curSlot] = a;
    }

    function s(i) {
      return 'f' + sF[i] + ':b' + sBig[i] +
             ':m' + (sF[i] ? Math.round(sMs[i] / sF[i]) : 0) +
             ':aw' + sAppW[i] + ':mq' + sMq[i] + ':an' + sAnim[i];
    }

    document.title =
      'AN|slot' + curSlot + '|sheet' + sheetOk +
      '|S0_' + s(0) + '|S1_' + s(1) + '|S2_' + s(2) +
      '|S3_' + s(3) + '|S4_' + s(4) + '|' +
      'MP|' + Math.round(el / 1000) +
      '|f' + frames +
      '|av' + Math.round(sum / Math.max(frames, 1)) +
      '|mx' + Math.round(mx) +
      '|BT' + bigTotal +
      '|H' + hist.join('.') +
      '|B' + big.join(',');
  }, 2000);
})();
