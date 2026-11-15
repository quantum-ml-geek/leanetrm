import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {workspaceProbeScript} from '../../tests/browser/workspace-probe.mjs';

const channel='00000000-0000-4000-8000-000000000001';
function harness(){
 const native=[];
 class Source extends EventTarget{
  static CONNECTING=0;static OPEN=1;static CLOSED=2;
  constructor(url,options){super();this.url=url;this.withCredentials=options?.withCredentials??false;this.readyState=1;native.push(this);}
  close(){this.readyState=2;}
 }
 const calls=[],window={EventSource:Source,location:{href:'http://synthetic.test/'}};
 const transport=window.fetch=async(path,init)=>{const request=JSON.parse(init.body);calls.push({path,init,request});return new Response(JSON.stringify({channelId:request.channelId,requestId:request.requestId,state:'accepted'}),{status:202});};
 const context=vm.createContext({window,location:window.location,URL,URLSearchParams,Response,Event,MessageEvent,EventTarget,DOMException,JSON,Map,Set,Promise});
 vm.runInContext(workspaceProbeScript,context);
 const source=new window.EventSource('/api/async-reads/events?channelId='+channel,{withCredentials:true}),received=[];
 source.addEventListener('response',event=>received.push(JSON.parse(event.data)));
 const emit=(id,result={value:id},state='completed')=>native[0].dispatchEvent(new MessageEvent('response',{data:JSON.stringify({protocol:'async_reads_v1',channelId:channel,requestId:id,operation:'curve.evaluate.v1',snapshotId:'selected',state,...(state==='completed'?{result}:{error:result})})}));
 const request=(id,signal)=>({method:'POST',body:JSON.stringify({channelId:channel,requestId:id,operation:'curve.evaluate.v1',body:{snapshotId:'selected',curve:id}}),signal});
 const tick=async()=>{for(let i=0;i<8;i++)await new Promise(resolve=>setImmediate(resolve));};
 return {window,context,native,calls,transport,source,received,emit,request,tick};
}

test('logical inspectors corrupt the real correlated SSE result, while HTTP remains one acknowledgement',async()=>{
 const h=harness(),seen=[];
 const read=h.window.fetch=h.window.__workspaceProbe(h.window.fetch,async(path,init,send)=>{
  if(path==='/api/evaluate')seen.push({path,body:JSON.parse(init.body)});const response=await send(path,init);
  if(path!=='/api/evaluate')return response;
  const result=await response.json();return new Response(JSON.stringify({...result,value:'edited'}),{status:200});
 });
 const ack=await read('/api/async-reads',h.request('one'));
 assert.equal(ack.status,202);assert.equal(h.received.length,0);
 h.emit('one');await h.tick();
 assert.deepEqual(seen,[{path:'/api/evaluate',body:{snapshotId:'selected',curve:'one'}}]);
 assert.equal(h.calls.length,1);assert.equal(h.calls[0].path,'/api/async-reads');
 assert.equal(h.received[0].result.value,'edited');assert.equal(h.received[0].requestId,'one');
});

test('separate requests complete out of order without exchanging their inspectors',async()=>{
 const h=harness();
 const read=h.window.fetch=h.window.__workspaceProbe(h.window.fetch,async(path,init,send)=>{
  const response=await send(path,init);if(path!=='/api/evaluate')return response;
  const result=await response.json();return Response.json({...result,selected:JSON.parse(init.body).curve});
 });
 await Promise.all(['first','second'].map(id=>read('/api/async-reads',h.request(id))));
 h.emit('second');h.emit('first');await h.tick();
 assert.deepEqual(h.received.map(r=>[r.requestId,r.result.selected]),[['second','second'],['first','first']]);
 assert.equal(h.calls.length,2);
});

test('an inspector can hold one real completion independently and keeps its abort signal',async()=>{
 const h=harness(),controller=new AbortController();let release,heldSignal;
 const read=h.window.fetch=h.window.__workspaceProbe(h.window.fetch,async(path,init,send)=>{
  if(path==='/api/evaluate'&&JSON.parse(init.body).curve==='held'){heldSignal=init.signal;await new Promise(resolve=>release=resolve);}
  return send(path,init);
 });
 await read('/api/async-reads',h.request('held',controller.signal));h.emit('held');
 await read('/api/async-reads',h.request('other'));h.emit('other');await h.tick();
 assert.equal(h.calls.length,2);assert.equal(h.received[0].requestId,'other');
 assert.equal(heldSignal,controller.signal);controller.abort();assert.equal(heldSignal.aborted,true);
 release();await h.tick();assert.equal(h.calls.length,2);assert.equal(h.received[1].requestId,'held');
});

test('injected refusal changes the actual SSE completion without reexecuting the read',async()=>{
 const h=harness(),read=h.window.fetch=h.window.__workspaceProbe(h.window.fetch,async(path,init,send)=>path==='/api/evaluate'?Response.json({code:'access_denied'},{status:403}):send(path,init));
 const response=await read('/api/async-reads',h.request('denied'));
 assert.equal(response.status,202);h.emit('denied');await h.tick();
 assert.equal(h.calls.length,1);assert.equal(h.received[0].state,'failed');assert.equal(h.received[0].error.code,'access_denied');assert.equal(h.received[0].result,undefined);
});

test('stacked inspectors transform one actual SSE frame from inner to outer',async()=>{
 const h=harness(),wrap=(transport,suffix)=>h.window.__workspaceProbe(transport,async(path,init,send)=>{
  const response=await send(path,init);if(path!=='/api/evaluate')return response;
  const result=await response.json();return Response.json({...result,value:result.value+suffix});
 });
 h.window.fetch=wrap(wrap(h.window.fetch,'-inner'),'-outer');await h.window.fetch('/api/async-reads',h.request('stacked'));
 h.emit('stacked');await h.tick();assert.equal(h.calls.length,1);assert.equal(h.received[0].result.value,'stacked-inner-outer');
});

test('unobserved events and native connection semantics stay intact after repeated installation',async()=>{
 const h=harness(),Source=h.window.EventSource;vm.runInContext(workspaceProbeScript,h.context);
 assert.equal(h.window.EventSource,Source);assert.equal(Source.OPEN,1);assert.equal(h.source.withCredentials,true);assert.equal(h.source.readyState,1);
 h.emit('unobserved');assert.equal(h.received[0].result.value,'unobserved');
 let errors=0;h.source.addEventListener('error',()=>errors++);h.native[0].dispatchEvent(new Event('error'));assert.equal(errors,1);
 h.source.close();assert.equal(h.source.readyState,2);
 const other=new Source('/api/market/live/events?selection=one');let updates=0;other.addEventListener('response',()=>updates++);
 h.native[1].dispatchEvent(new MessageEvent('response',{data:'not a read envelope'}));assert.equal(updates,1);
});

test('observed terminal failures remain failures',async()=>{
 const h=harness(),read=h.window.fetch=h.window.__workspaceProbe(h.window.fetch,async(path,init,send)=>send(path,init));
 await read('/api/async-reads',h.request('failure'));h.emit('failure',{code:'access_denied',message:'Denied synthetic selection'},'failed');await h.tick();
 assert.equal(h.received[0].state,'failed');assert.deepEqual(h.received[0].error,{code:'access_denied',message:'Denied synthetic selection'});assert.equal(h.received[0].result,undefined);
});

test('a legacy fetch inspector sees an actual GET result under the selected API root',async()=>{
 const h=harness(),send=h.window.fetch,seen=[];
 h.window.fetch=async(input,init)=>{const response=await send(input,init);if(input.includes('/portfolio/risk/jobs/'))seen.push({input,method:init.method,body:init.body,data:await response.clone().json()});return response;};
 const request={channelId:channel,requestId:'job',operation:'portfolio.risk.jobs.read.v1',body:{id:'synthetic-job'}};
 await h.window.fetch('/examples/exchange/api/async-reads',{method:'POST',body:JSON.stringify(request)});
 h.native[0].dispatchEvent(new MessageEvent('response',{data:JSON.stringify({...request,protocol:'async_reads_v1',snapshotId:null,state:'completed',result:{id:'synthetic-job',state:'complete'}})}));await h.tick();
 assert.deepEqual(seen,[{input:'/examples/exchange/api/portfolio/risk/jobs/synthetic-job',method:'GET',body:undefined,data:{id:'synthetic-job',state:'complete'}}]);
 assert.equal(h.calls.length,1);assert.equal(h.calls[0].path,'/examples/exchange/api/async-reads');
});

test('discarding the private payload token fails the probe without sending a duplicate business HTTP read',async()=>{
 const h=harness(),send=h.window.fetch;let errors=0;h.source.addEventListener('error',()=>errors++);
 h.window.fetch=(input,init)=>send(input,input==='/api/evaluate'?{method:init.method,body:init.body}:init);
 await h.window.fetch('/api/async-reads',h.request('lost-token'));h.emit('lost-token');await h.tick();
 assert.equal(h.calls.length,1);assert.equal(errors,1);assert.equal(h.received.length,0);
 assert.match(h.window.__asyncReadProbeErrors[0],/discarded its real SSE payload/);
});

test('an inspector cannot turn a real server failure into success',async()=>{
 const h=harness(),send=h.window.fetch;let errors=0;h.source.addEventListener('error',()=>errors++);
 h.window.fetch=(input,init)=>input==='/api/evaluate'?Promise.resolve(Response.json({value:'forged'})):send(input,init);
 await h.window.fetch('/api/async-reads',h.request('failure'));h.emit('failure',{code:'access_denied',message:'Denied'},'failed');await h.tick();
 assert.equal(h.received.length,0);assert.equal(errors,1);assert.equal(h.calls.length,1);
 assert.match(h.window.__asyncReadProbeErrors[0],/cannot turn a refused server read/);
});

test('malformed native SSE remains visible to the production validator',async()=>{
 const h=harness(),raw=[];h.source.addEventListener('response',event=>raw.push(event.data));
 // This additional listener models the production validator, which must see
 // inconsistent native frames rather than the probe throwing before delivery.
 h.native[0].dispatchEvent(new MessageEvent('response',{data:'null'}));
 assert.deepEqual(raw,['null']);
});
