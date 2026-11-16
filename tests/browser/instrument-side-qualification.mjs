import {copyFile,mkdtemp} from 'node:fs/promises';
import {dirname,join} from 'node:path';
import {tmpdir} from 'node:os';

const q=JSON.stringify;
let artifacts;

// Compare the actual authorized response with the rendered membership cards.
// Literal role/count expectations remain with each product scenario below.
export async function sideCards(driver,host,response,{label,retained=false,roles,bindings,slots}={}){
 const groups=response?.sideGroups,reason=response?.sideGroupsReason;
 if(!Array.isArray(groups)||(!groups.length&&!(typeof reason==='string'&&reason.length))||groups.length&&reason!=null)
  throw Error('Expected complete actual Side groups or an explicit absence: '+label);
 if(roles&&JSON.stringify(groups.flatMap(group=>group.sides.map(side=>side.roleLabel)))!==JSON.stringify(roles))
  throw Error('Actual Side roles differ from the independent product expectation: '+label);
 if(bindings&&JSON.stringify(groups.map(group=>group.bindingId))!==JSON.stringify(bindings))
  throw Error('Actual Side groups changed their retained native bindings: '+label);
 if(slots&&JSON.stringify(groups.map(group=>group.sides.length))!==JSON.stringify(slots))
  throw Error('Actual Side membership counts differ from the booked product: '+label);
 if(groups.some(group=>retained?typeof group.bindingId!=='string':group.bindingId!==null))
  throw Error('Draft and retained Side ownership must remain explicit: '+label);
 await driver.check(label,`(()=>{
  const host=document.querySelector(${q(host)}),groups=${q(groups)},reason=${q(reason??null)};
  if(!host)return false;
  const cards=[...host.querySelectorAll('[data-instrument-side-group]')];
  if(cards.length!==groups.length)return false;
  if(!groups.length)return !!reason&&host.textContent.includes(reason)&&!host.querySelector('[data-instrument-side-slot]');
  return groups.every((group,index)=>{
   const card=cards[index];
   if(card.dataset.instrumentSideGroup!==group.instrumentId||card.dataset.bindingId!==(group.bindingId??'')||
    !card.textContent.includes(group.label)||group.fieldGroupId!=null&&card.closest('[data-ticket-field-group]')?.dataset.ticketFieldGroup!==group.fieldGroupId)return false;
   const members=[...card.querySelectorAll('[data-instrument-side-slot]')];
   return members.length===group.sides.length&&group.sides.every((side,slot)=>{
    const member=members[slot];
    if(member.dataset.instrumentSideSlot!==String(side.slot)||member.dataset.sideId!==side.sideId||
     ![side.label,side.roleLabel,side.directionLabel].every(text=>member.textContent.includes(text)))return false;
    return side.overviewSections.every(section=>member.textContent.includes(section.label)&&section.values.every(value=>{
     const rows=[...member.querySelectorAll('.side-term')],row=rows.find(row=>row.querySelector('dt')?.textContent===value.label),shown=row?.querySelector('dd');
     return shown&&(value.kind==='instant'?shown.title===value.value&&shown.textContent.length>0:shown.textContent===value.value);
    }));
   });
  });
 })()`, `({error:document.querySelector('#error')?.textContent,composition:document.querySelector(${q(host)})?.textContent})`);
}

export async function captureSideTerms(driver){
 await driver.command('Page.addScriptToEvaluateOnNewDocument',{source:`window.instrumentSideReads=[];{const send=window.fetch;window.fetch=async(input,init)=>{const response=await send(input,init),path=new URL(typeof input==='string'?input:input.url,location.href).pathname;if(['/api/trading/gas','/api/trading/crude','/api/trading/lng'].includes(path)&&response.headers.get('content-type')?.includes('application/json'))instrumentSideReads.push({path,status:response.status,request:JSON.parse(init.body),result:await response.clone().json()});return response;};}`});
}

export async function retainedSideTerms(driver,kind){
 await driver.wait(`window.instrumentSideReads?.some(read=>read.path===${q('/api/trading/'+kind)}&&read.status===200)&&${driver.idle}`,60000);
 return driver.evaluate(`instrumentSideReads.findLast(read=>read.path===${q('/api/trading/'+kind)}&&read.status===200).result`);
}

export async function serviceFieldGroups(driver,host,ids,label){
 await driver.check(label,`JSON.stringify([...document.querySelectorAll(${q(host+' [data-ticket-field-group]')})].map(group=>group.dataset.ticketFieldGroup))===${q(JSON.stringify(ids))}`);
}

export async function sidePhone(driver,host,artifact){
 await driver.command('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
 const member=host+' [data-instrument-side-slot]',disclosure=member+' details:not([open])>summary';
 if(await driver.evaluate(`!!document.querySelector(${q(disclosure)})`))await driver.click(disclosure);
 await driver.evaluate(`document.querySelector(${q(member)}).scrollIntoView({block:'start'})`);
 await driver.check('the phone capture shows an actual Side role and its exact terms',`(()=>{
  const card=document.querySelector(${q(member)}),visible=node=>{if(!node)return false;const box=node.getBoundingClientRect();return box.width>0&&box.top>=0&&box.bottom<=document.documentElement.clientHeight&&node.contains(document.elementFromPoint(box.left+box.width/2,box.top+box.height/2));};
  return !!card&&[card.querySelector('h4'),card.querySelector('.field-help'),card.querySelector('.side-term')].every(visible);
 })()`);
 await driver.check('actual retained Side cards and their exact terms fit a phone viewport',`(${driver.fitsWidth})&&[...document.querySelectorAll(${q(host+' [data-instrument-side-slot]')})].every(card=>{const box=card.getBoundingClientRect();return box.width>0&&box.left>=0&&box.right<=innerWidth;})`);
 await driver.shot(artifact);
 if(!artifacts){artifacts=await mkdtemp(join(tmpdir(),'openetrm-side-browser-'));console.log('SIDE_BROWSER_ARTIFACTS='+artifacts);}
 await copyFile(join(dirname(process.argv[2]),artifact+'.png'),join(artifacts,artifact+'.png'));
 await driver.command('Emulation.setDeviceMetricsOverride',{width:1440,height:1100,deviceScaleFactor:1,mobile:false});
}
