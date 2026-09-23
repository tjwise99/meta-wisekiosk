// Track max marquee overflow per ride name across the full tour rotation.
(function(){
  if(window.__ovf) return; window.__ovf=1;
  var seen={};                       // name -> max |distance| px
  function scan(){
    var rows=document.querySelectorAll('.ride-name-text.marquee');
    for(var i=0;i<rows.length;i++){
      var d=rows[i].style.getPropertyValue('--pwt-marquee-distance')
            ||getComputedStyle(rows[i]).getPropertyValue('--pwt-marquee-distance');
      var px=Math.abs(parseFloat(d))||0;
      var n=(rows[i].textContent||'').replace(/[|;=]/g,' ').slice(0,22);
      if(!seen[n]||px>seen[n]) seen[n]=px;
    }
    var keys=Object.keys(seen).sort(function(a,b){return seen[b]-seen[a];});
    var mx=keys.length?seen[keys[0]]:0;
    var top=keys.slice(0,12).map(function(k){return k+'='+Math.round(seen[k]);});
    document.title='OVF|'+keys.length+'|max'+Math.round(mx)+'|'+top.join(';');
  }
  setInterval(scan,700); scan();
})();
