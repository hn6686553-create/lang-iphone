(() => {
  'use strict';
  const create = name => document.createElementNS('http://www.w3.org/1999/xhtml', name);
  const post = value => window.webkit.messageHandlers.page.postMessage(value);
  let frame, flow, style, blocks=[], options, last, timer, resizeTimer, restoring=false, ready=false;
  function mount() {
    if (frame) return;
    for(const el of document.querySelectorAll('iframe,frame,object,embed,script,form,meta[http-equiv="refresh" i]')) el.remove();
    const h=document.head || document.documentElement.insertBefore(create('head'),document.body);
    let viewport=h.querySelector('meta[name=viewport]') || h.appendChild(create('meta'));
    viewport.setAttribute('name','viewport'); viewport.setAttribute('content','width=device-width,initial-scale=1');
    frame=create('div'); frame.id='hs-window'; flow=create('main'); flow.id='hs-prose';
    while(document.body.firstChild) flow.appendChild(document.body.firstChild);
    frame.appendChild(flow); document.body.appendChild(frame); style=create('style'); h.appendChild(style);
    blocks=Array.from(flow.querySelectorAll('p,h1,h2,h3,h4,li,figure,pre,blockquote,dt,dd'));
    frame.addEventListener('scroll',()=>{clearTimeout(timer);timer=setTimeout(report,110)},{passive:true});
    flow.addEventListener('click',event=>{
      const a=event.target.closest && event.target.closest('a[href]');
      if(!a)return;
      const raw=a.getAttribute('href') || '';
      if(raw.startsWith('#')){event.preventDefault(); let id=raw.slice(1);try{id=decodeURIComponent(id)}catch(e){};seek({fragment:id}); report();}
    });
    let start=null;
    frame.addEventListener('touchstart',e=>{start=e.touches.length===1 ? [e.touches[0].clientX,e.touches[0].clientY] : null},{passive:true});
    frame.addEventListener('touchend',e=>{
      if(!start || !options.paged || window.getSelection()?.toString())return;
      const x=e.changedTouches[0].clientX-start[0], y=e.changedTouches[0].clientY-start[1]; start=null;
      if(Math.abs(x)>45 && Math.abs(x)>Math.abs(y)*1.5) post({step:x<0?1:-1});
    },{passive:true});
    window.addEventListener('resize',()=>{const keep=last;clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{if(options)configure(options,keep||{});},160)});
    for(const img of flow.querySelectorAll('img')) img.addEventListener('load',()=>{if(ready&&!restoring)report()},{once:true});
  }
  function configure(o, location) {
    mount(); options=o; restoring=true;
    const gap=o.margin*2, width=Math.max(64,innerWidth-gap);
    const height=Math.max(40,innerHeight-30);
    const css=[
      'html,body{margin:0!important;padding:0!important;width:100%!important;height:100%!important;overflow:hidden!important;-webkit-text-size-adjust:100%!important}',
      'html,body,#hs-window,#hs-prose{background:'+o.bg+'!important;color:'+o.ink+'!important}',
      '#hs-window{position:absolute!important;inset:14px '+o.margin+'px 16px!important;overflow:'+ (o.paged?'hidden':'hidden auto') +'!important;overscroll-behavior:contain}',
      '#hs-prose{display:block!important;box-sizing:border-box!important;margin:0!important;padding:0!important;width:100%!important;max-width:none!important;'+(o.paged?'height:'+height+'px!important;column-fill:auto!important;column-width:'+width+'px!important;column-gap:'+gap+'px!important;':'height:auto!important;')+'}',
      '#hs-prose,#hs-prose :where(*:not(svg):not(svg *)){font-family:'+o.font+'!important;line-height:'+o.leading+'!important;background-color:transparent!important;color:'+o.ink+'!important;max-width:100%!important}',
      '#hs-prose,#hs-prose :where(p,span,body,div,article,section,li,blockquote,td,pre){font-size:'+o.size+'px!important}',
      '#hs-prose p{margin:0 0 .78em!important;widows:2;orphans:2;overflow-wrap:anywhere}',
      '#hs-prose h1,#hs-prose h2,#hs-prose h3{line-height:1.2!important;margin:.25em 0 .65em!important;break-after:avoid}',
      '#hs-prose h1{font-size:1.65em!important} #hs-prose h2{font-size:1.4em!important} #hs-prose h3{font-size:1.15em!important}',
      '#hs-prose img,#hs-prose svg{max-width:100%!important;max-height:'+Math.floor(height*.85)+'px!important;object-fit:contain}',
      '#hs-prose figure{margin:.5em 0!important;break-inside:avoid} #hs-prose pre{white-space:pre-wrap} #hs-prose a{text-decoration:underline}'].join('\n');
    style.textContent=css; frame.getBoundingClientRect(); flow.getBoundingClientRect();
    seek(location||{}); restoring=false;ready=true;report();
    if(document.fonts)document.fonts.ready.then(()=>{if(ready)report()});
  }
  function geometry(){
    const stride=frame.clientWidth+2*options.margin;
    const pages=Math.max(1,Math.ceil((frame.scrollWidth+2*options.margin-2)/stride));
    return {stride,pages,scroll:Math.max(0,frame.scrollHeight-frame.clientHeight)};
  }
  function seek(s) {
    if(!frame||!options)return;
    const g=geometry(), f=Math.max(0,Math.min(1,Number(s.fraction)||0));
    const el=s.fragment?document.getElementById(s.fragment):null;
    if(el && flow.contains(el)){
      const r=el.getBoundingClientRect(),v=frame.getBoundingClientRect();
      if(options.paged)frame.scrollLeft=Math.round((frame.scrollLeft+r.left-v.left)/g.stride)*g.stride;
      else frame.scrollTop+=r.top-v.top;
    } else if(options.paged) frame.scrollLeft=Math.round(f*(g.pages-1))*g.stride;
    else frame.scrollTop=f*g.scroll;
  }
  function report() {
    if(!frame||!options||restoring)return;
    const g=geometry();
    const page=options.paged?Math.max(0,Math.min(g.pages-1,Math.round(frame.scrollLeft/g.stride))):Math.max(0,Math.floor((frame.scrollTop+1)/Math.max(1,frame.clientHeight)));
    const total=options.paged?g.pages:Math.max(1,Math.ceil(frame.scrollHeight/Math.max(1,frame.clientHeight)));
    const fraction=options.paged?(g.pages>1?page/(g.pages-1):0):(g.scroll?frame.scrollTop/g.scroll:0);
    const rect=frame.getBoundingClientRect();
    const at=document.elementFromPoint(rect.left+Math.min(18,rect.width/3),rect.top+15);
    const paragraph=at?blocks.indexOf(at.closest('p,h1,h2,h3,h4,li,figure,pre,blockquote,dt,dd')):-1;
    last={fraction,paragraph}; post({page:page+1,pages:total,fraction,paragraph});
  }
  function step(d) {
    if(!ready)return;
    const g=geometry();
    if(options.paged) {
      const p=Math.round(frame.scrollLeft/g.stride)+d;
      if(p<0||p>=g.pages){post({boundary:d});return;}
      frame.scrollLeft=p*g.stride;
    } else {
      const old=frame.scrollTop;
      frame.scrollTop=Math.max(0,Math.min(g.scroll,old+d*frame.clientHeight*.9));
      if(Math.abs(frame.scrollTop-old)<1){post({boundary:d});return;}
    }
    report();
  }
  window.hienSach={configure,seek:s=>{seek(s);report()},step};
})();
