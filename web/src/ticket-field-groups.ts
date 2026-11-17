import type {InstrumentSideGroup} from './instrument-sides.js';

export type TicketFieldGroup={id:string;label:string;kind:'agreement'|'side_terms'|'independent_instrument_terms';fields:string[]};
const fail=()=>{throw Error('Reread the complete ticket field groups and their declared Side mappings.');};
export function ticketFieldGroups(description:{tradeFields:{id:string}[];fieldGroups?:TicketFieldGroup[]|null;sideGroupsRequired?:boolean;sides?:readonly unknown[]}):TicketFieldGroup[]|undefined{
 if(description.fieldGroups==null){if(description.sideGroupsRequired&&!description.sides?.length&&description.tradeFields.length)fail();return;}
 if(!Array.isArray(description.fieldGroups))return fail();
 const fields=new Set(description.tradeFields.map(field=>field.id)),seen=new Set<string>(),groups=new Set<string>();
 if(fields.size!==description.tradeFields.length)return fail();
 for(const group of description.fieldGroups){
  if(!group||Object.keys(group).length!==4||typeof group.id!=='string'||!group.id.trim()||typeof group.label!=='string'||!group.label.trim()||
   !['agreement','side_terms','independent_instrument_terms'].includes(group.kind)||groups.has(group.id)||!Array.isArray(group.fields)||!group.fields.length)return fail();
  groups.add(group.id);
  for(const id of group.fields){if(!fields.has(id)||seen.has(id))return fail();seen.add(id);}
 }
 if(seen.size!==fields.size)return fail();
 return description.fieldGroups;
}
export function requireSideGroupMappings(groups:readonly InstrumentSideGroup[],fields:readonly TicketFieldGroup[]|undefined):void{
 if(groups.some(group=>group.fieldGroupId!=null&&!fields?.some(field=>field.id===group.fieldGroupId)))fail();
}
