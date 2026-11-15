// Hold delivery of real correlated server replies; no calculation is replaced.
export async function run({command,evaluate,wait,click,set,persona,check,idle,url}){
 await command('Page.enable');await command('Runtime.enable');
 const fixture=await command('Page.addScriptToEvaluateOnNewDocument',{source:`(()=>{
  const send=window.fetch.bind(window),NativeSource=window.EventSource;
  window.__reads={posts:[],acks:[],held:[],hold:sessionStorage.getItem('synthetic-held-startup-read')?[sessionStorage.getItem('synthetic-held-startup-read')]:[],responses:[],sources:0,release(){for(const item of this.held.splice(0))item.source.dispatchEvent(new MessageEvent('response',{data:item.data}));}};
  sessionStorage.removeItem('synthetic-held-startup-read');
  window.fetch=async(input,init)=>{
   const path=new URL(String(input),location.href).pathname;
   if(path==='/api/async-reads'&&init?.method==='POST')__reads.posts.push(JSON.parse(init.body));
   const response=await send(input,init);
   if(path==='/api/async-reads'&&init?.method==='POST')__reads.acks.push({status:response.status,body:await response.clone().json()});
   return response;
  };
  window.EventSource=class extends EventTarget{
   constructor(url){super();if(!String(url).includes('/async-reads/events'))return new NativeSource(url);this.source=new NativeSource(url);__reads.sources++;
    for(const type of ['ready','response'])this.source.addEventListener(type,event=>{
     if(type==='response'){const response=JSON.parse(event.data);__reads.responses.push(response);const index=__reads.hold.indexOf(response.operation);if(index>=0){__reads.hold.splice(index,1);__reads.held.push({source:this,data:event.data});return;}}
     this.dispatchEvent(new MessageEvent(type,{data:event.data}));
    });this.source.addEventListener('error',()=>this.dispatchEvent(new Event('error')));
   }close(){this.source.close();}
  };
 })()`});
 const choose=name=>evaluate(`document.querySelector('.curve-button[data-curve="'+${JSON.stringify(name)}+'"]')?.click()`);
 try{
  await command('Page.navigate',{url});await wait(idle,30000);await persona('risk');
  await click('#nav-market');
  const selected=await evaluate("[...document.querySelector('#snapshot').options].find(o=>o.textContent.includes('Dec 18')).value");
  await set('#snapshot',selected);await wait(idle,30000);
  const curves=await evaluate("[...document.querySelectorAll('.curve-button')].slice(0,2).map(button=>button.dataset.curve)");
  if(curves.length!==2)throw Error('The synthetic workbench needs two explicit curve choices.');
  await evaluate("__reads.hold.push('curve.evaluate.v1')");await choose(curves[0]);
  await wait("__reads.held.length===1",30000);
  await check('a real pending SSE curve leaves navigation and other curves usable',
   "!document.querySelector('#nav-futures').disabled&&[...document.querySelectorAll('.curve-button')].every(button=>!button.disabled)&&document.querySelector('#market-page').dataset.readState==='pending'");
  await choose(curves[1]);await wait("document.querySelector('#market-page').dataset.readState!=='pending'&&document.querySelector('#contracts tbody tr')",30000);
  const latest=await evaluate("document.querySelector('#contracts').textContent");await evaluate('__reads.release()');
  await check('superseded curve completion cannot replace the selected curve',`document.querySelector('#contracts').textContent===${JSON.stringify(latest)}&&document.querySelector('#error').hidden`);
  // Returning to Market can build its retained selection before an explicit
  // new choice. That page-owned build has the same supersession rule.
  await evaluate("__reads.hold.push('curve.evaluate.v1')");await choose(curves[0]);await wait('__reads.held.length===1',30000);
  await evaluate("document.querySelector('#nav-risk-runs').click()");await wait("!document.querySelector('#risk-page').hidden",30000);
  await evaluate('__reads.release()');await wait(idle,30000);
  await evaluate("__reads.hold.push('curve.evaluate.v1');document.querySelector('#nav-market').click()");await wait('__reads.held.length===1',30000);
  await choose(curves[1]);await wait("document.querySelector('#contracts tbody tr')&&document.querySelector('#contracts').textContent==="+JSON.stringify(latest),30000);
  await evaluate('__reads.release()');await wait(idle,30000);
  await check('an automatic retained-curve read cannot post a stale error over a newer explicit selection',`document.querySelector('#contracts').textContent===${JSON.stringify(latest)}&&document.querySelector('#error').hidden`,"({error:document.querySelector('#error').textContent,read:document.querySelector('#market-page').dataset.readState})");
  await check('read submissions acknowledge without embedding their calculation result',
   "__reads.posts.some(p=>p.operation==='curve.evaluate.v1')&&__reads.acks.every(a=>a.status===202&&a.body.state==='accepted'&&!('result' in a.body))");
  await evaluate("__reads.hold.push('trading.freshness.v1');document.querySelector('#nav-futures').click()");await wait('__reads.held.length===1',30000);
  await check('initial trade freshness is local to the blotter and does not disable Risk navigation',"!document.querySelector('#nav-risk-var').disabled&&document.querySelector('#futures-page').dataset.readState==='pending'");
  await evaluate("document.querySelector('#nav-risk-var').click();__reads.release()");
  await wait("document.querySelector('#risk-page').dataset.readState!=='pending'&&!document.querySelector('#risk-page').hidden",30000);
  await wait("document.querySelector('#risk-history-panel').dataset.readState==='ready'",30000);
  await click('#nav-risk-runs');
  // Refresh the workspace so VaR needs a fresh setup; hold only its catalogue.
  await click('#risk-workspace-refresh');await wait("document.querySelector('#risk-page').dataset.readState!=='pending'",30000);
  await evaluate("__reads.hold.push('portfolio.risk.catalog.v1');document.querySelector('#nav-risk-var').click()");await wait('__reads.held.length===1',30000);
  await check('VaR setup receives an independent SSE result while report navigation remains usable',
   "document.querySelector('#risk-history-panel').dataset.readState==='pending'&&!document.querySelector('#nav-risk-runs').disabled&&!document.querySelector('#nav-futures').disabled");
  await evaluate("document.querySelector('#nav-risk-runs').click();__reads.release()");
  await wait("document.querySelector('#risk-history-panel').dataset.readState==='ready'",30000);
  await check('late VaR setup does not navigate away from the selected report view',"document.querySelector('#nav-risk-runs').classList.contains('active')&&document.querySelector('#error').hidden");
  await set('#risk-workspace-trade-mode','selected');await wait(idle,30000);
  const trade=await evaluate("[...document.querySelector('#risk-workspace-trades').options].find(option=>option.textContent.includes(' · Futures')).value");
  await set('#risk-workspace-trades',trade);await wait(idle,30000);await click('#nav-risk-var');
  await wait("document.querySelector('#risk-history-panel').dataset.readState==='ready'",30000);
  const calendar=await evaluate("[...document.querySelector('#risk-history-calendar').options].find(option=>option.value&&JSON.parse(option.value).code==='weekdays_utc').value");
  await set('#risk-history-calendar',calendar);
  await evaluate("__reads.hold.push('portfolio.risk.calculate.v1');document.querySelector('#risk-parametric-run').click()");
  await wait("__reads.held.some(item=>JSON.parse(item.data).operation==='portfolio.risk.calculate.v1')",60000);
  await check('a real Run VaR result can wait while the rest of the workbench remains usable',
   "!document.querySelector('#nav-market').disabled&&!document.querySelector('#nav-risk-runs').disabled&&document.querySelector('#risk-parametric-fields').disabled&&document.querySelector('#workspace-risk-report').getAttribute('aria-busy')==='true'");
  await evaluate("document.querySelector('#nav-risk-runs').click();__reads.release()");await wait(idle,30000);
  await check('completed VaR keeps the explicitly selected report-history view',"document.querySelector('#nav-risk-runs').classList.contains('active')&&document.querySelector('#error').hidden");
  await check('actual curves, trades and risk reads share the admitted transport',
   "['curve.evaluate.v1','trading.freshness.v1','trading.directory.v1','portfolio.risk.scope.v1','portfolio.risk.catalog.v1'].every(operation=>__reads.posts.some(post=>post.operation===operation))");
  const origin=await evaluate("sessionStorage.setItem('synthetic-held-startup-read','trading.directory.v1');performance.timeOrigin");
  await command('Page.reload');await wait(`performance.timeOrigin!==${origin}&&window.__reads?.held.length===1`,30000);
  await evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
  await check('native startup readiness waits for the actual initial Risk scope result',"document.querySelector('#risk-page').dataset.readState==='pending'&&performance.getEntriesByName('leanetrm:workspace-ready','mark').length===0");
  await evaluate('__reads.release()');await wait("performance.getEntriesByName('leanetrm:workspace-ready','mark').length===1&&"+idle,30000);
 }finally{await evaluate('__reads?.release()').catch(()=>{});await command('Page.removeScriptToEvaluateOnNewDocument',{identifier:fixture.identifier});}
}
