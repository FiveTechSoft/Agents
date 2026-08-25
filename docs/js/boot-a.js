window.coi={
  // COEP credentialless only where supported (Chromium). Firefox/Safari don't parse it
  // and end up blocking cross-origin subresources -> use require-corp there (the SW
  // injects CORP:cross-origin on intercepted responses, and jsdelivr/unpkg send it anyway).
  coepCredentialless:()=>{ var ua=navigator.userAgent; return !(/firefox/i.test(ua) || (/safari/i.test(ua) && !/chrome|chromium|edg/i.test(ua))); },
  shouldRegister:()=>true,
  doReload:function(){ window.location.reload(); } };

// Guarded reload for the COI service worker: never kill SSH sessions, running
// agents or the first seconds of a visit. coi-serviceworker.min.js calls
// window.__coiReload() instead of its own doReload when this is defined.
window.__coiReload=function(){
  var busy=false, fresh=false;
  try{
    busy=(typeof workN!=='undefined'&&workN>0)||(typeof activeSsh!=='undefined'&&!!activeSsh);
    fresh=performance.now()<15000;
  }catch(e){}
  if(busy||fresh){
    if(!fresh){ setTimeout(function(){ try{ window.__coiReload(); }catch(e){ window.location.reload(); } },5000); }
    return;
  }
  window.location.reload();
};
