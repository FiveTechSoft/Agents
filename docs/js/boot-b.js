(function(){var last=0;try{last=+sessionStorage.getItem('coiupd')||0;}catch(e){}fetch('version.txt?t='+Date.now(),{cache:'no-store'}).then(function(r){return r.text();}).then(function(v){v=(v||'').trim();var seen='';try{seen=sessionStorage.getItem('ver')||'';}catch(e){}
if(v&&v!==seen&&(Date.now()-last>8000)){
  // never reload mid-session: it kills SSH sessions, running agents and unsaved state.
  // also skip right after page load (first 12s): the user may already be starting something.
  var busy=false;
  try{ busy=(typeof workN!=='undefined'&&workN>0)||(typeof activeSsh!=='undefined'&&!!activeSsh)||(performance.now()<12000); }catch(e){}
  if(busy){ return; }
  try{sessionStorage.setItem('coiupd',Date.now());}catch(e){}
  var q;try{var p=new URLSearchParams(location.search);p.set('u',Date.now());q='?'+p.toString();}catch(e){q='?u='+Date.now();}
  location.replace(location.pathname+q+location.hash);
}else{try{sessionStorage.setItem('ver',v);}catch(e){}}}).catch(function(){});})();
