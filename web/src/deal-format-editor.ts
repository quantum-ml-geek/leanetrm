import {amountText,prepareAmountDisplay,displayPrecision,initialDisplayPrecision,type DisplayPrecision} from './amount-display.js';
type Api=<T>(path:string,body?:unknown)=>Promise<T>;
type Selection={role:string;revision:number;format:DisplayPrecision};
export function dealFormatEditor(host:HTMLElement,o:{api:Api;act:(work:()=>Promise<void>)=>Promise<void>;busy:()=>boolean;changed:()=>Promise<void>}){
 let generation=0,tradeId='',canSave=false,rows:Selection[]=[];
 const fieldset=document.createElement('fieldset'),title=document.createElement('legend'),note=document.createElement('p'),controls=document.createElement('div'),reload=document.createElement('button'),status=document.createElement('p');
 title.textContent='Deal & side display precision';note.className='field-help';note.textContent='Shared current presentation for this deal. Each side role keeps its own precision. Futures prices follow the tick size; calculations and exports retain exact values. These controls also format historical rows; they do not change historical financial inputs.';
 reload.type='button';reload.className='secondary';reload.textContent='Reload precision';status.setAttribute('role','status');fieldset.append(title,note,controls,reload,status);host.replaceChildren(fieldset);host.hidden=true;
 let context:Record<string,unknown>={};let roles:string[]=[];
 const policy=(role='trade')=>rows.find(r=>r.role===role)?.format??initialDisplayPrecision();
 function render(){
  controls.replaceChildren();
  for(const row of rows.filter(r=>roles.includes(r.role))){const section=document.createElement('section'),heading=document.createElement('h4'),fields=document.createElement('div'),save=document.createElement('button');heading.textContent=row.role==='trade'?'Trade totals':row.role==='fixed'?'Fixed side':'Floating side';fields.className='schedule-fields';
   const inputs=new Map<string,HTMLInputElement>();for(const [key,label] of [['money','Money / PV'],['price','Prices'],['quantity','Quantities'],['factor','Factors']]){const wrap=document.createElement('div'),name=document.createElement('label'),input=document.createElement('input');input.id=host.id+'-'+row.role+'-'+key;input.type='number';input.min='0';input.max='18';input.required=true;input.value=String(row.format[key as keyof DisplayPrecision]);name.htmlFor=input.id;name.textContent=label+' · decimal places';inputs.set(key,input);wrap.append(name,input);fields.append(wrap);}
   save.type='button';save.textContent='Save '+heading.textContent.toLowerCase()+' precision';save.dataset.role=row.role;save.onclick=()=>void o.act(async()=>{
    const started=generation;status.textContent='';const format=displayPrecision(Object.fromEntries([...inputs].map(([key,input])=>[key,Number(input.value)])));
    if([...inputs.values()].some(input=>input.value===''||!input.checkValidity()))throw Error('Choose 0–18 decimal places.');
    try{const result=await o.api<Selection>('trade-formats/save',{tradeId,role:row.role,expectedRevision:row.revision,format});if(started!==generation)return;row.format=result.format;row.revision=result.revision;await o.changed();if(started!==generation)return;status.textContent='Precision saved for this deal.';render();}
    catch(error){if(started===generation)status.textContent='Reload precision to check the current saved values before trying again.';throw error;}
   });section.append(heading,fields,save);controls.append(section);
  }sync();
 }
 function sync(){fieldset.disabled=o.busy()||!tradeId;controls.querySelectorAll<HTMLInputElement|HTMLButtonElement>('input,button').forEach(n=>n.disabled=o.busy()||!canSave);reload.disabled=o.busy()||!tradeId;}
 async function load(id:string,selected:Record<string,unknown>,editable:boolean,parts:string[]){const started=++generation;tradeId=id;context=selected;canSave=editable;roles=parts;rows=[];host.hidden=true;status.textContent='';const response=await o.api<{roles:Selection[]}>('trade-formats/read',{tradeId,context});if(started!==generation)return;rows=response.roles;render();host.hidden=false;}
 reload.onclick=()=>void o.act(async()=>{await load(tradeId,context,canSave,roles);await o.changed();});
 return{load,sync,policy,reset(){generation++;tradeId='';rows=[];host.hidden=true;controls.replaceChildren();status.textContent='';},
  async prepare(payload:unknown,role='trade',tick?:string){await prepareAmountDisplay(payload,body=>o.api<string[]>('amounts/display',body),tick,policy(role));},
  text(value:string,kind:keyof DisplayPrecision,role='trade',tick?:string){return amountText(value,kind,tick,policy(role));}};
}
