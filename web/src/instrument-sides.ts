import {overviewTermSections,type PhysicalOverviewSection} from './physical-instrument.js';

export type InstrumentSide={slot:number;sideId:string;label:string;roleLabel:string;directionLabel:string;overviewSections:PhysicalOverviewSection[]};
export type InstrumentSideGroup={instrumentId:string;bindingId:string|null;label:string;sides:InstrumentSide[];fieldGroupId?:string|null};

const object=(value:unknown):value is Record<string,unknown>=>!!value&&typeof value==='object'&&!Array.isArray(value);
const text=(value:unknown):value is string=>typeof value==='string'&&value.trim().length>0;
const closed=(value:unknown,keys:readonly string[],optional:readonly string[]=[])=>object(value)&&keys.every(key=>Object.hasOwn(value,key))&&Object.keys(value).every(key=>keys.includes(key)||optional.includes(key));
export function requireInstrumentSideGroups(value:unknown,retained:boolean,reason?:string|null):InstrumentSideGroup[]{
 const fail=()=>{throw Error('Reread the complete instrument Side memberships and their exact bindings.');};
 if(!Array.isArray(value)||!value.length&&!text(reason)||reason!=null&&(!text(reason)||value.length>0))return fail();
 const groups=new Set<string>();
 for(const group of value){
  if(!closed(group,['instrumentId','bindingId','label','sides'],['fieldGroupId'])||!text(group.instrumentId)||!text(group.label)||group.fieldGroupId!=null&&!text(group.fieldGroupId)||
   (group.bindingId===null?retained:!text(group.bindingId))||!Array.isArray(group.sides)||!group.sides.length)return fail();
  const key=JSON.stringify([group.instrumentId,group.bindingId]);if(groups.has(key))return fail();groups.add(key);
  const slots=new Set<number>();
  for(const side of group.sides){
   if(!closed(side,['slot','sideId','label','roleLabel','directionLabel','overviewSections'])||!Number.isSafeInteger(side.slot)||side.slot<0||side.slot>=group.sides.length||slots.has(side.slot)||
    ![side.sideId,side.label,side.roleLabel,side.directionLabel].every(text)||!Array.isArray(side.overviewSections)||!side.overviewSections.length)return fail();
   slots.add(side.slot);overviewTermSections(side.overviewSections,'UTC');
  }
 }
 return value as InstrumentSideGroup[];
}
// These physical terms endpoints describe one exact selected instrument
// binding. Independent service cash has a different, explicitly grouped read.
export function requireBoundInstrumentSides(value:unknown,bindingId:string):InstrumentSideGroup[]{
 const groups=requireInstrumentSideGroups(value,true);
 if(!text(bindingId)||groups.some(group=>group.bindingId!==bindingId))throw Error('The retained Side composition belongs to another instrument binding.');
 return groups;
}
const node=<K extends keyof HTMLElementTagNameMap>(tag:K,text?:string)=>{const value=document.createElement(tag);if(text!==undefined)value.textContent=text;return value;};
export function renderInstrumentSides(host:HTMLElement,value:unknown,options:{zone:string;retained:boolean;reason?:string|null;disclosure?:boolean}):()=>void{
 const groups=requireInstrumentSideGroups(value,options.retained,options.reason),root=node('section');root.className='instrument-composition';root.setAttribute('aria-label','Instrument sides');
 if(!groups.length){root.append(node('h3','Instrument sides'),node('p',options.reason??undefined));}
 for(const group of groups){
  const section=node('section');section.className='instrument-side-group';section.dataset.instrumentSideGroup=group.instrumentId;section.dataset.bindingId=group.bindingId??'';
  section.append(node('h3',group.label));const deck=node('div');deck.className='instrument-side-deck';
  for(const side of group.sides){
   const card=node('article');card.className='instrument-side';card.dataset.instrumentSideSlot=String(side.slot);card.dataset.sideId=side.sideId;
   card.append(node('h4','Side · '+side.label));const role=node('p',side.roleLabel+' · '+side.directionLabel);role.className='field-help';card.append(role);
   const termsHost=options.disclosure?node('details'):card;if(options.disclosure){termsHost.append(node('summary','Exact Side terms'));card.append(termsHost);}
   for(const terms of overviewTermSections(side.overviewSections,options.zone)){
    const details=node('section');details.append(node('h5',terms.title));const list=node('dl');list.className='side-terms-list';
    for(const [label,value,exact] of terms.rows){const row=node('div');row.className='side-term';const shown=node('dd',value);if(exact!==undefined)shown.title=exact;row.append(node('dt',label),shown);list.append(row);}
    details.append(list);termsHost.append(details);
   }
   deck.append(card);
  }
  section.append(deck);root.append(section);
 }
 host.append(root);return()=>root.remove();
}
