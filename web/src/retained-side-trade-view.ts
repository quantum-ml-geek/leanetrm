import type {Holding} from './desk-model.js';
import type {DetailRead} from './position-panel.js';
import {requireBoundInstrumentSides,renderInstrumentSides,type InstrumentSideGroup} from './instrument-sides.js';
import {displayExactInstant} from './market-view.js';
import {sameUtcInstant} from './user-time.js';
type Api=<T>(path:string,body?:unknown,signal?:AbortSignal)=>Promise<T>;
type Source={snapshotId:string;contextId:string;asOf:string;businessDate:string;knownAt:string};
type Saved={tradeId:string;bindingId?:string;instrumentId:string;revision:number;sideGroups:InstrumentSideGroup[];retainedSource:Source;
 context:{contextId:string;effectiveOn:string;knownAt:string};asOf:string};

export async function readRetainedSideTrade(api:Api,context:Record<string,unknown>,holding:Holding):Promise<DetailRead>{
 const operating=holding.instrumentType==='operating_right';
 if(!operating&&holding.instrumentType!=='rec_forward')throw Error('Select an exact supported retained Side contract.');
 const requested={...context,convention:operating?'trading_workspace_v1':'rec_forward_v1'},revision=Number(holding.revision);
 const result=await api<Saved>(operating?'physical/power-trades/get':'rec/trades/get',{
  context:requested,tradeId:holding.tradeId,revision,...operating?{snapshotId:context.snapshotId,bindingId:holding.bindingId}:{}});
 const source=result.retainedSource;
 if(result.tradeId!==holding.tradeId||result.instrumentId!==holding.bindingId||operating&&result.bindingId!==holding.bindingId||result.revision!==revision||
  !source||source.snapshotId!==context.snapshotId||typeof source.contextId!=='string'||!source.contextId||source.contextId!==result.context?.contextId||
  source.businessDate!==result.context.effectiveOn||!sameUtcInstant(source.asOf,result.asOf)||!sameUtcInstant(source.knownAt,result.context.knownAt)||
  context.knowledgeMode==='retained'&&source.contextId!==context.contextId)
  throw Error('The retained Side response does not match its exact source, trade, binding and revision. Refresh the selected view.');
 const groups=requireBoundInstrumentSides(result.sideGroups,holding.bindingId);
 return{amend:{allowed:false,reason:'This retained contract is read-only. Use its supported workspace for changes.'},view:zone=>({
  termsLabel:'Retained contract Sides',terms:[{title:operating?'Operating-right contract':'REC forward contract',rows:[
   ['Trade',holding.tradeReference],['Instrument',holding.instrumentReference],['Book',holding.book],
   ['Business date',source.businessDate],['As of',displayExactInstant(source.asOf,zone)],['Knowledge cutoff',displayExactInstant(source.knownAt,zone)],
   ...holding.unavailableReason?[['Value unavailable',String(holding.unavailableReason)] as const]:[]]}],
  termsContent:host=>{const content=document.createElement('div');if(operating)content.dataset.operatingSideComposition='';else content.dataset.recSideComposition='';host.append(content);
   const remove=renderInstrumentSides(content,groups,{zone,retained:true});return()=>{remove();content.remove();};},
  history:[{title:`Revision ${holding.revision}`,rows:[['Booked',displayExactInstant(holding.executedAt,zone)],['Booker',holding.trader??''],['Trade date',holding.booking.tradeDate??'Unavailable']]}],
 })};
}
