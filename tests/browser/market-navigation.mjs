export async function run({command,evaluate,wait,click,set,persona,check,idle,url}){
 await command('Runtime.enable');await command('Page.enable');
 const {identifier}=await command('Page.addScriptToEvaluateOnNewDocument',{source:`
  window.__navigationReads=[];const send=window.fetch;window.fetch=async(input,init)=>{
   const path=new URL(typeof input==='string'?input:input.url,location.href).pathname;window.__navigationReads.push(path);
   const response=await send(input,init);
   if(path==='/api/workspace/navigation'&&new URLSearchParams(location.search).has('hold-navigation'))await new Promise(resolve=>window.__releaseNavigation=resolve);
   if(path==='/api/workspace/catalog'&&window.__holdWorkspace){window.__holdWorkspace=false;await new Promise(resolve=>window.__releaseWorkspace=resolve);}
   return response;
  };`});
 try{
  await command('Page.navigate',{url:url+'/'});await wait(idle+"&&document.querySelectorAll('.curve-button').length>0&&performance.getEntriesByName('leanetrm:workspace-ready').length===1");
  await check('initial directory reads only the explicit navigation contract',"window.__navigationReads.includes('/api/workspace/navigation')&&!window.__navigationReads.includes('/api/workspace/catalog')&&!window.__navigationReads.includes('/api/workspace')&&performance.getEntriesByName('leanetrm:workspace-ready').length===1");
  await set('#commodity','test_gas');await check('navigation filters do not hydrate pricing data',"!window.__navigationReads.includes('/api/workspace/catalog')&&document.querySelectorAll('.curve-button').length>0");
  await set('#commodity','all');
  const selected=await evaluate("[...document.querySelector('#snapshot').options].find(o=>o.textContent.includes('Dec 18')).value");
  await set('#snapshot',selected);await wait(idle);
  await check('selecting a market date does not load unused contracts or reference data',"!window.__navigationReads.includes('/api/workspace/catalog')");
  await evaluate("window.__firstPriceStart=performance.now();[...document.querySelectorAll('.curve-button')].find(b=>b.textContent.startsWith('Local power forwards')).click()");await wait(idle);
  await check('first pricing hydrates exact workspace data before displaying prices and sources',"window.__navigationReads.filter(p=>p==='/api/workspace/catalog').length===1&&window.__navigationReads.includes('/api/evaluate')&&document.querySelector('#curve-chart canvas')&&document.querySelector('#inputs tbody tr')&&document.querySelector('#error').hidden");
  console.log('FIRST_PRICING_WITH_HYDRATION_MS='+await evaluate('performance.now()-window.__firstPriceStart'));
  await persona('viewer');await evaluate("[...document.querySelectorAll('.curve-button')].find(b=>b.textContent.startsWith('Local power forwards')).click()");await wait(idle);
  await check('choosing a curve without a date loads its explicit details without manufacturing prices',"document.querySelector('#snapshot').value===''&&!document.querySelector('#curve-detail').hidden&&document.querySelector('#contracts').children.length===0&&document.querySelector('#error').hidden");
  await persona('viewer');await set('#snapshot',selected);await wait(idle);
  await evaluate("window.__holdWorkspace=true;[...document.querySelectorAll('.curve-button')].find(b=>b.textContent.startsWith('Local power forwards')).click()");await wait("typeof window.__releaseWorkspace==='function'");
  await check('workspace hydration stays busy without publishing partial prices',"document.body.getAttribute('aria-busy')==='true'&&document.querySelector('#contracts').children.length===0");
  await evaluate("(()=>{const s=document.querySelector('#snapshot');s.value=[...s.options].find(o=>o.value&&o.value!==s.value).value;window.__releaseWorkspace();})()");await wait(idle);
  await check('late hydration cannot restore prices for a different selected snapshot',"!document.querySelector('#error').hidden&&document.querySelector('#contracts').children.length===0&&document.querySelector('#inputs').children.length===0");
  await evaluate("document.querySelector('#date-context-on').value='2020-12-17';document.querySelector('#date-context-on').dispatchEvent(new Event('input',{bubbles:true}))");
  await click('#profile-open');await click('#preferences-form button[type=submit]');
  await check('presentation refresh after a cancelled hydration never treats navigation as full pricing data',"document.querySelector('#contracts').children.length===0&&document.querySelector('#curve-detail').hidden&&document.querySelector('#error').hidden");
  await persona('viewer');await evaluate('window.__referenceStart=performance.now()');await click('#nav-reference');
  await check('first reference navigation explicitly hydrates its exact pin and unit metadata',"document.querySelector('#reference-page-status').textContent.startsWith('Rows ')&&document.querySelector('#reference tbody tr')&&document.querySelector('#error').hidden");
  console.log('FIRST_REFERENCE_WITH_HYDRATION_MS='+await evaluate('performance.now()-window.__referenceStart'));
  await command('Page.navigate',{url:url+'/?hold-navigation=true'});await wait("typeof window.__releaseNavigation==='function'");
  await evaluate("document.querySelector('#date-context-on').dispatchEvent(new Event('input',{bubbles:true}));window.__releaseNavigation()");await wait(idle);
  await check('a reset during navigation cannot publish a stale directory or startup ready mark',"!document.querySelector('#error').hidden&&document.querySelectorAll('.curve-button').length===0&&performance.getEntriesByName('leanetrm:workspace-ready').length===0&&!window.__navigationReads.includes('/api/workspace/catalog')");
 }finally{await command('Page.removeScriptToEvaluateOnNewDocument',{identifier});}
}
