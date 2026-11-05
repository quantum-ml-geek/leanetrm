// One visible view waits for server versions. Replaced views cannot publish a
// late reply; readiness defers changes while the owner is busy or editing.
export function watchVersions(o:{initial:string;current:()=>boolean;ready:()=>boolean;
 read:(version:string,signal:AbortSignal)=>Promise<string>;apply:(version:string)=>Promise<void>;
 failed:(error:unknown)=>boolean;pause:(signal:AbortSignal)=>Promise<void>}){
 const controller=new AbortController(),signal=controller.signal;
 const current=()=>!signal.aborted&&o.current();
 void(async()=>{
  let version=o.initial;
  while(current()){
   await o.pause(signal);if(!current())return;
   if(!o.ready())continue;
   try{
    const next=await o.read(version,signal);if(!current())return;
    if(next===version)continue;
    while(current()&&!o.ready())await o.pause(signal);
    if(!current())return;
    await o.apply(next);version=next;
   }catch(error){if(current()&&!o.failed(error))return;}
  }
 })();
 return()=>controller.abort();
}
