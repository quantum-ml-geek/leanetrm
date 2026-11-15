// Test-only bridge for existing logical-response assertions. Reads still execute
// once through the production submission endpoint and complete on the real SSE.
function installAsyncReadProbe(){
 if(window.__asyncReadProbeInstalled)return;
 const routes={
  'curve.evaluate.v1':'evaluate','curve.history.v1':'history','curve.shapes.v1':'market/curve-shapes',
  'trading.directory.v1':'trading/directory','trading.freshness.v1':'trading/freshness','trading.positions.v1':'trading/positions',
  'trading.position.v1':'trading/position','trading.workspace.v1':'trading/workspace','trading.blotter.v1':'trading/blotter',
  'futures.editor.v1':'futures/editor','swaps.editor.v1':'swaps/editor',
  'portfolio.risk.catalog.v1':'portfolio/risk/catalog','portfolio.risk.calculate.v1':'portfolio/risk',
  'portfolio.risk.scope.v1':'portfolio/risk/scope','portfolio.risk.history.v1':'portfolio/risk/history',
  'portfolio.risk.statistical.setup.v1':'portfolio/risk/statistical/setup',
  'portfolio.risk.parametric.calculate.v1':'portfolio/risk/parametric','portfolio.risk.parametric.summary.v1':'portfolio/risk/parametric/summary',
  'portfolio.risk.historical.calculate.v1':'portfolio/risk/historical','portfolio.risk.historical.summary.v1':'portfolio/risk/historical/summary',
  'portfolio.risk.historical.sample.v1':'portfolio/risk/historical/sample','portfolio.risk.monte_carlo.calculate.v1':'portfolio/risk/monte-carlo'
 };
 const pending=new Map(),delivering=new Map(),forwarded=new WeakSet(),ticket=Symbol('actual SSE payload'),NativeSource=window.EventSource,nativeFetch=window.fetch;
 const key=request=>request.channelId+'/'+request.requestId;
 const payloadResponse=value=>Response.json(value.state==='completed'?value.result:value.error??{code:'async_read_cancelled',message:'Read cancelled.'},
  {status:value.state==='completed'?200:value.state==='cancelled'?499:value.error?.code==='access_denied'?403:422});
 async function replacePayload(value,response){
  if(response.ok){
   if(value.state!=='completed')throw Error('A probe cannot turn a refused server read into a successful result.');
   return {...value,result:await response.json()};
  }
  const raw=await response.text();let error;try{error=JSON.parse(raw);}catch{}
  const {result,...envelope}=value;
  return {...envelope,state:value.state==='cancelled'?'cancelled':'failed',error:{code:error?.code??'request_failed',message:error?.message??(raw||'Synthetic read refusal')}};
 }
 function logicalRequest(input,init,request){
  const address=new URL(typeof input==='string'?input:input.url,location.href),base=address.pathname.slice(0,-'async-reads'.length);
  let route=routes[request.operation],method='POST';
  if(request.operation==='portfolio.risk.jobs.list.v1'){route='portfolio/risk/jobs';method='GET';}
  if(request.operation==='portfolio.risk.jobs.read.v1'){route='portfolio/risk/jobs/'+encodeURIComponent(request.body.id);method='GET';}
  if(request.operation==='portfolio.risk.archive.v1'){
   const query=new URLSearchParams({limit:String(request.body.limit)});
   for(const field of ['before','id'])if(request.body[field]!==null)query.set(field,request.body[field]);
   route='portfolio/risk/'+request.body.method.replace('_','-')+'/archive?'+query;method='GET';
  }
  if(!route)throw Error('No browser probe route for '+request.operation);
  return {path:base+route,init:{...init,method,body:method==='POST'?JSON.stringify(request.body):undefined}};
 }
 const baseFetch=async(input,init)=>{
  const address=new URL(typeof input==='string'?input:input.url,location.href),path=address.pathname+address.search;
  if(init&&Object.hasOwn(init,ticket))return init[ticket];
  // A fixture that drops the private response token must fail, never reexecute
  // the business operation through its old HTTP endpoint.
  if(delivering.has(path))throw Error('A response inspector discarded its real SSE payload.');
  let id;
  if(address.pathname.endsWith('/async-reads')&&init?.method==='POST'){
   const request=JSON.parse(init.body);id=key(request);pending.set(id,logicalRequest(input,init,request));
  }
  try{const response=await nativeFetch(input,init);if(id&&response.status!==202)pending.delete(id);return response;}
  catch(error){if(id)pending.delete(id);throw error;}
 };
 window.fetch=baseFetch;
 window.EventSource=class extends NativeSource{
  constructor(url,options){
   super(url,options);
   const address=new URL(String(url),location.href);
   if(!address.pathname.endsWith('/async-reads/events'))return;
   this.probeChannel=address.searchParams.get('channelId');
   this.addEventListener('response',event=>{
    if(forwarded.has(event))return;
    let value;try{value=JSON.parse(event.data);}catch{return;}
    if(!value||typeof value!=='object')return;
    const request=pending.get(key(value));if(!request)return;
    pending.delete(key(value));if(window.fetch===baseFetch)return;
    event.stopImmediatePropagation();
    void (async()=>{
     const {path,init}=request;delivering.set(path,(delivering.get(path)??0)+1);
     try{value=await replacePayload(value,await window.fetch(path,{...init,[ticket]:payloadResponse(value)}));}
     finally{const count=delivering.get(path)-1;if(count)delivering.set(path,count);else delivering.delete(path);}
     if(this.readyState===NativeSource.CLOSED)return;
     const next=new MessageEvent('response',{data:JSON.stringify(value),origin:event.origin,lastEventId:event.lastEventId});
     forwarded.add(next);this.dispatchEvent(next);
    })().catch(error=>{
     if(error.name==='AbortError'&&this.readyState===NativeSource.CLOSED)return;
     (window.__asyncReadProbeErrors??=[]).push(error.message);this.dispatchEvent(new Event('error'));
    });
   });
  }
  close(){
   super.close();
   if(!this.probeChannel)return;
   for(const id of pending.keys())if(id.startsWith(this.probeChannel+'/'))pending.delete(id);
  }
 };
 window.__asyncReadProbeInstalled=true;
}

export const asyncReadProbeScript=`(${installAsyncReadProbe.toString()})();`;
