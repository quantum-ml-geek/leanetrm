type Api=<T>(path:string,body?:unknown)=>Promise<T>;
export function localTimeValue(instant:string,zone:string,seconds=false){
  const parts=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(new Date(instant));
  const part=(name:string)=>parts.find(p=>p.type===name)!.value;
  return `${part('year').padStart(4,'0')}-${part('month')}-${part('day')}T${part('hour')}:${part('minute')}${seconds?':'+part('second'):''}`;
}
// Formatting is presentation; the managed resolver determines actual instants.
export function zonedInput(input:HTMLInputElement,zone:()=>string,api:Api){
  const offsets=document.createElement('select');offsets.hidden=true;offsets.setAttribute('aria-label','Repeated local time · choose UTC offset');input.after(offsets);
  let exact:string|undefined,display='',displayZone=zone(),choicesKey='';
  function clearOffset(){offsets.replaceChildren();offsets.hidden=true;choicesKey='';}
  input.addEventListener('input',()=>{exact=undefined;clearOffset();});
  function set(instant:string){exact=instant;displayZone=zone();input.value=localTimeValue(instant,displayZone,input.step==='1');display=input.value;clearOffset();}
  function clear(){exact=undefined;input.value='';display='';displayZone=zone();clearOffset();}
  return {set,clear,refresh(){if(displayZone===zone())return;if(exact)set(exact);else clear();},async instant(){
    if(exact&&input.value===display&&displayZone===zone())return exact;
    const key=JSON.stringify([input.value,zone()]);
    const result=await api<{candidates:{instant:string;offset:string}[]}>('time/inspect',{localTime:input.value,timeZone:zone()});
    if(result.candidates.length===1)return result.candidates[0].instant;
    if(result.candidates.length!==2)throw Error('This local time cannot be resolved.');
    if(choicesKey!==key){choicesKey=key;offsets.replaceChildren(new Option('Clock repeats · choose an offset…',''),...result.candidates.map(c=>new Option('UTC'+c.offset,c.instant)));offsets.hidden=false;}
    if(!result.candidates.some(c=>c.instant===offsets.value))throw Error('That local time occurs twice. Choose its UTC offset before continuing.');
    return offsets.value;
  }};
}
