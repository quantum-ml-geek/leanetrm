import {ticketFieldGroups,type TicketFieldGroup} from './ticket-field-groups.js';

export type FieldGroupLayout={fields:string[];groups:TicketFieldGroup[]};
export function mountFieldGroupLayout(host:HTMLElement,layout:FieldGroupLayout,controls:ReadonlyMap<string,HTMLElement>):void{
 const fail=()=>{throw Error('Reread the complete backend field layout for this selected contract.');};
 if(!layout||Object.keys(layout).length!==2||!Array.isArray(layout.fields)||!layout.fields.length||
  layout.fields.some(id=>typeof id!=='string'||!controls.has(id))||new Set(layout.fields).size!==layout.fields.length||
  new Set(controls.values()).size!==controls.size)return fail();
 const groups=ticketFieldGroups({tradeFields:layout.fields.map(id=>({id})),fieldGroups:layout.groups,sideGroupsRequired:true,sides:[]});
 if(!groups)return fail();
 const deck=document.createElement('div');deck.className='entry-side-deck';
 for(const group of groups){
  const card=document.createElement('fieldset');card.className=group.kind==='agreement'?'ticket-field-group':'ticket-field-group instrument-side';
  card.dataset.fieldLayoutGroup=group.id;card.dataset.fieldGroupKind=group.kind;
  const legend=document.createElement('legend');legend.textContent=group.label;card.append(legend);
  const fields=document.createElement('div');fields.className='schedule-fields';for(const id of group.fields)fields.append(controls.get(id)!);
  card.append(fields);deck.append(card);
 }
 const inactive=document.createElement('div');inactive.hidden=true;inactive.dataset.fieldLayoutInactive='';
 for(const [id,control]of controls)if(!layout.fields.includes(id))inactive.append(control);
 host.replaceChildren(deck,inactive);
}
