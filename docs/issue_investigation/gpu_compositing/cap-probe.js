// Capability probe: which in-page GC instruments does this WebKit expose?
(function () {
  var m = performance.memory;
  var a = m ? m.usedJSHeapSize : null;
  var junk = []; for (var i = 0; i < 200000; i++) junk.push({ x: i, s: 's' + i }); junk = null;
  var b = m ? m.usedJSHeapSize : null;
  var s = 'CAP|pm:' + (m
        ? ('used' + (m.usedJSHeapSize / 1e6).toFixed(1) + '/tot' + (m.totalJSHeapSize / 1e6).toFixed(1)
           + '/lim' + (m.jsHeapSizeLimit / 1e6).toFixed(0) + '/moved' + ((b - a) / 1e6).toFixed(2))
        : 'NONE')
    + '|FinalizationRegistry:' + (typeof FinalizationRegistry)
    + '|WeakRef:' + (typeof WeakRef)
    + '|gc:' + (typeof window.gc)
    + '|qMt:' + (typeof queueMicrotask)
    + '|' + (navigator.userAgent.match(/AppleWebKit\/[\d.]+/) || ['ua?'])[0];
  // keep re-asserting so the app's own document.title cannot clobber it
  window.setInterval(function () { document.title = s; }, 1000);
  document.title = s;
})();
