export async function run({command,evaluate,wait,click,submit,check,idle,url}){
  await command('Runtime.enable');await command('Page.enable');
  const {identifier}=await command('Page.addScriptToEvaluateOnNewDocument',{source:`
    window.__startupRequests=[];window.__startupFormats=[];window.__unusedSourceValues=[];
    const originalFetch=window.fetch;
    window.fetch=async(input,init)=>{
      const path=typeof input==='string'?input:input.url;
      window.__startupRequests.push(path);
      if(path==='/api/amounts/display')window.__startupFormats.push(...JSON.parse(init.body).map(row=>row.value));
      const response=await originalFetch(input,init);
      if(!['/api/workspace','/api/workspace/catalog','/api/evaluate','/api/history'].includes(path)||!response.ok)return response;
      const data=await response.json();
      if(path==='/api/workspace/catalog'){
        window.__startupObservationCount=data.observations.length;window.__startupScope=data.observationScope;
      }else if(path==='/api/workspace'||path==='/api/evaluate'&&data.observationScope==='selected_frame'){
        // Unrendered history must not add formatting round trips. Preserve the
        // real selected sources so normal exact source tables remain exercised.
        for(let i=0;i<2049;i++){
          const value=(10000+i)+'.123456789012345678';window.__unusedSourceValues.push(value);
          data.observations.push({...data.observations[0],id:crypto.randomUUID(),value});
        }
        if(window.__omitSelectedSources&&path==='/api/evaluate'){
          window.__omitSelectedSources=false;delete data.observationScope;delete data.observations;
        }
      }else if(path==='/api/history')data.metadata={value:'987654321.123456789012345678'};
      return new Response(JSON.stringify(data),{status:response.status,headers:response.headers});
    };
  `});
  try{
  await command('Page.navigate',{url:url+'/'});
  await wait("document.querySelectorAll('.curve-button').length>0&&"+idle);
  await check('startup explicitly requests the catalog without observation history',"window.__startupRequests.includes('/api/workspace/catalog')&&!window.__startupRequests.includes('/api/workspace')&&window.__startupScope==='on_demand'&&window.__startupObservationCount===0");
  await check('workspace navigation does not format undisplayed observation history',"!window.__startupRequests.includes('/api/amounts/display')");
  await check('initial profile choices reuse the initial bootstrap',"window.__startupRequests.filter(path=>path==='/api/bootstrap').length===1");
  await click('#profile-open');
  await check('opening Profile still refreshes current profile choices',"window.__startupRequests.filter(path=>path==='/api/bootstrap').length===2&&!document.querySelector('#profile-dialog').hidden&&document.querySelector('#profile-dialog').open");
  await click('#profile-close');
  await click('#example');
  await check('evaluated contract amounts still use managed formatting',"window.__startupRequests.includes('/api/evaluate')&&window.__startupRequests.includes('/api/amounts/display')&&document.querySelector('#contracts tbody tr')&&document.querySelector('#error').hidden");
  await check('thousands of unrendered source versions do not enter formatting requests',"window.__unusedSourceValues.length>=2049&&!window.__startupFormats.some(value=>window.__unusedSourceValues.includes(value))");
  await evaluate("(async()=>{const amounts=await import('/amount-display.js');amounts.selectDisplayPrecision(amounts.initialDisplayPrecision());})()");
  await click('#profile-open');await submit('#preferences-form');
  await check('saving display preferences does not format unrendered source versions',"!window.__startupFormats.some(value=>window.__unusedSourceValues.includes(value))&&document.querySelector('#error').hidden");
  // A cold display cache requires formatting, even after another result was shown.
  await evaluate("(async()=>{const amounts=await import('/amount-display.js');amounts.selectDisplayPrecision(amounts.initialDisplayPrecision());window.__startupRequests=[];})()");
  await click('#contracts tbody tr:first-child button');
  await check('history amounts still use managed formatting',"window.__startupRequests.includes('/api/history')&&window.__startupRequests.includes('/api/amounts/display')&&!document.querySelector('#history-card').hidden&&document.querySelector('#error').hidden");
  await check('history formats displayed points without unrelated metadata',"!window.__startupFormats.includes('987654321.123456789012345678')");
  await evaluate('window.__omitSelectedSources=true');await click('#example');
  await check('missing selected sources fail without stale price or source fallback',"!document.querySelector('#error').hidden&&document.querySelector('#contracts').children.length===0&&document.querySelector('#inputs').children.length===0");
  }finally{
    await command('Page.removeScriptToEvaluateOnNewDocument',{identifier});
  }
}
