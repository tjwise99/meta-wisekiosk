(function () {
  if (window.__kp) return;
  window.__kp = 1;

  // Localise the ~1/s WebKit render stall by reducing the page IN PLACE, measured with the
  // minimal probe proven in Test C (bare rAF loop; no wrapped getters, no MutationObserver).
  //
  // Conditions: 0 = full app, 1 = one CSS transform animation only, 2 = nothing moving.
  // Slot order is a PALINDROME 0,1,2,1,0 -- with linear drift, each condition's mean is then
  // drift-centred, so the ~30% within-run drift this board shows cannot masquerade as an effect.
  //
  // The app is HIDDEN (display:none), not destroyed: the palindrome has to restore it for the
  // final arm. display:none removes it from layout and paint entirely, which is the rendering
  // cost under test. Its JS keeps running -- see the caveat in the write-up.
  var WARM = 20, ARMLEN = 80, NSLOT = 5;
  var COND = [0, 1, 2, 1, 0];

  var t0 = performance.now(), prev = t0;
  var frames = 0, sum = 0, mx = 0, bigTotal = 0;
  var EDGES = [50, 100, 250, 500, 1000, 2000];
  var hist = [0, 0, 0, 0, 0, 0, 0];
  var big = [];

  var sF = [0,0,0,0,0], sMs = [0,0,0,0,0], sBig = [0,0,0,0,0];
  var sAppW = [-1,-1,-1,-1,-1], sTestW = [-1,-1,-1,-1,-1], sAnim = ['x','x','x','x','x'];
  var curSlot = -2, mech = 'pending';

  var appEl = null, testEl = null, anim = null;
  var rAF = window.requestAnimationFrame.bind(window);

  function slotOf(elMs) {
    var s = elMs / 1000;
    if (s < WARM) return -1;
    var k = Math.floor((s - WARM) / ARMLEN);
    return (k >= 0 && k < NSLOT) ? k : -1;
  }

  function ensure() {
    if (!document.body) return;
    if (!appEl) appEl = document.getElementById('app') || document.body.firstElementChild;
    if (!testEl) {
      testEl = document.createElement('div');
      testEl.id = '__floorbox';
      // FULL-VIEWPORT and text-heavy, so the painted/rasterised area is comparable to the
      // app's rather than a 240x80 patch. The previous run hid ~99% of the painted pixels
      // along with the app, which conflates "this app's content" with "painting a screenful".
      testEl.style.cssText =
        'position:fixed;left:0;top:0;width:100vw;height:100vh;' +
        'background:linear-gradient(160deg,#101018,#202030);color:#b0b0c0;' +
        'font:15px sans-serif;line-height:1.35;overflow:hidden;' +
        'z-index:2147483647;padding:8px;box-sizing:border-box;';
      var html = '';
      for (var i = 0; i < 420; i++) {
        html += '<div>floor probe row ' + i +
                ' \u2014 Guardians of the Galaxy: Cosmic Rewind ' + (40 + (i % 60)) + '</div>';
      }
      testEl.innerHTML = html;
      document.body.appendChild(testEl);
      // @keyframes through an EXISTING same-origin sheet: the page's CSP is
      // `style-src 'self'`, which drops an injected <style> element but does not stop
      // insertRule on a stylesheet already loaded from the same origin.
      try {
        var sh = document.styleSheets[0];
        sh.insertRule(
          '@keyframes __floorspin{0%{transform:translateX(0)}' +
          '50%{transform:translateX(-40px)}100%{transform:translateX(0)}}',
          sh.cssRules.length);
        mech = 'css';
      } catch (e) {
        mech = 'waapi';   // Web Animations API needs no stylesheet at all
      }
    }
  }

  function setAnim(on) {
    if (!testEl) return;
    if (on) {
      if (mech === 'css') {
        testEl.style.animation = '__floorspin 8s ease-in-out infinite';
        testEl.style.willChange = 'transform';
      } else if (!anim) {
        anim = testEl.animate(
          [{ transform: 'translateX(0)' },
           { transform: 'translateX(-40px)' },
           { transform: 'translateX(0)' }],
          { duration: 8000, iterations: Infinity });
      }
    } else {
      if (mech === 'css') {
        testEl.style.animation = 'none';
        testEl.style.willChange = 'auto';
      } else if (anim) {
        anim.cancel();
        anim = null;
      }
      testEl.style.transform = 'none';
    }
  }

  function applySlot(k) {
    ensure();
    var c = (k >= 0) ? COND[k] : 0;
    if (appEl) {
      if (c === 0) appEl.style.removeProperty('display');
      else appEl.style.setProperty('display', 'none', 'important');
    }
    if (testEl) {
      if (c === 0) { testEl.style.setProperty('display', 'none', 'important'); setAnim(false); }
      else { testEl.style.removeProperty('display'); setAnim(c === 1); }
    }
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
    ensure();

    // Landing check, sampled live: is the app actually gone, and is the box actually animating?
    if (curSlot >= 0) {
      var aw = appEl ? Math.round(appEl.getBoundingClientRect().width) : -1;
      var tw = testEl ? Math.round(testEl.getBoundingClientRect().width) : -1;
      if (aw > sAppW[curSlot]) sAppW[curSlot] = aw;
      if (tw > sTestW[curSlot]) sTestW[curSlot] = tw;
      var a = 'x';
      if (testEl) {
        if (mech === 'css') {
          a = (window.getComputedStyle(testEl).animationName || 'none');
          if (a !== 'none') a = 'css';
        } else {
          a = testEl.getAnimations ? ('wa' + testEl.getAnimations().length) : 'wa?';
        }
      }
      sAnim[curSlot] = a;
    }

    function s(i) {
      return 'f' + sF[i] + ':b' + sBig[i] +
             ':m' + (sF[i] ? Math.round(sMs[i] / sF[i]) : 0) +
             ':aw' + sAppW[i] + ':tw' + sTestW[i] + ':an' + sAnim[i];
    }

    document.title =
      'FA|slot' + curSlot + '|mech' + mech +
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
