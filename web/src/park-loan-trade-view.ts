import type {Holding} from './desk-model.js';
import {displayInstant} from './market-view.js';
import type {DetailRead} from './position-panel.js';
import {renderPhysicalSections} from './physical-instrument.js';
import {setupTicket,ticketBookingRetained,type TicketHandle} from './ticket-controller.js';
import type {TicketTrade} from './ticket-types.js';

type Api=<T>(path:string,body?:unknown,signal?:AbortSignal)=>Promise<T>;
const product='physical_gas_park_loan',convention='physical_gas_fixed_quantity_v4';
type ParkLoanTrade=TicketTrade&{measureLabel:string;ownershipNote:string;overviewSections:{label:string;values:{label:string;value:string}[]}[]};

// The exact selected trade stays inspectable after performance begins. Saved
// terms use the backend's description; native lifecycle actions retain their own
// authority, previews and request recovery in the Lifecycle workspace.
export async function readParkLoanView(api:Api,context:Record<string,unknown>,h:Holding,o:{actor:()=>string;lifecycle?:()=>void}):Promise<DetailRead>{
 const selected={tradeId:h.tradeId,bindingId:h.bindingId,revision:Number(h.revision)};
 const requested:Record<string,unknown>={...context,convention};
 const detail=await api<ParkLoanTrade>('tickets/trade',{context:requested,product,...selected});
 if(detail.draft.product!==product||detail.snapshotId!==requested.snapshotId||!detail.context?.contextId||!detail.context.effectiveOn||!detail.context.knownAt||
  requested.knowledgeMode==='retained'&&detail.context.contextId!==requested.contextId)
  throw Error('The Park and loan response does not match its selected product, snapshot and context. Refresh the Blotter.');
 if(typeof detail.measureLabel!=='string'||!detail.measureLabel||typeof detail.ownershipNote!=='string'||!detail.ownershipNote||
  !Array.isArray(detail.overviewSections)||!detail.overviewSections.length||detail.overviewSections.some(section=>typeof section.label!=='string'||!section.label||!Array.isArray(section.values)||
   section.values.some(row=>typeof row.label!=='string'||!row.label||typeof row.value!=='string')))
  throw Error('The Park and loan response did not identify its native balances, value measure and ownership. Refresh the Blotter.');
 const certified={...requested,knowledgeMode:'retained',contextId:detail.context.contextId};
 let ticket:TicketHandle|undefined;
 return {amend:{allowed:false,reason:detail.actions.amend.reason},view:zone=>({
  termsLabel:'Park and loan terms',
  terms:[{title:'Park and loan',rows:[['Trade',h.tradeReference],['Instrument',h.instrumentReference],['Book',h.book],['Value measure',detail.measureLabel],['Ownership',detail.ownershipNote]]}],
  termsContent:host=>{
   const content=document.createElement('div'),ticketHost=document.createElement('div');content.className='park-loan-terms';content.append(ticketHost);host.append(content);
   ticket=setupTicket(ticketHost,{api,context:()=>certified,product,opened:selected,readOnly:true,presentation:'terms',instant:at=>displayInstant(at,zone),zone:()=>zone,actor:o.actor});
   renderPhysicalSections(content,detail.overviewSections.map(section=>({title:section.label,rows:section.values.map(row=>[row.label,row.value])})));
   return ()=>{ticket?.destroy();ticket=undefined;content.remove();};
  },
  history:[{title:`Revision ${h.revision}`,rows:[['Booked',displayInstant(h.executedAt,zone)],['Booker',h.trader??''],['Trade date',h.booking.tradeDate??'Unavailable']]}],
  actions:o.lifecycle?[{id:'park-loan-lifecycle',label:'Open lifecycle actions',run:o.lifecycle}]:[],
 })};
}

/** The first installed service profile uses the shared description-driven entry and retained booking protocol. */
export function setupParkLoanTicket(o:{api:Api;source:()=>{snapshotId:string};historical:()=>boolean;actor:()=>string;instant:(at:string)=>string;zone:()=>string;onBooked:(tradeId:string)=>Promise<void>}){
 const root=document.getElementById('park-loan-page')!,host=document.createElement('div');host.id='park-loan-ticket';root.replaceChildren(host);
 let ticket:TicketHandle|undefined;
 const reset=()=>{ticket?.destroy();ticket=undefined;};
 const ticketContext=()=>({...o.source(),convention,knowledgeMode:'current'});
 return {root,reset,
  async begin(){
   reset();
   if(o.historical())throw Error('Return to working data to enter a Park and loan trade.');
   ticket=setupTicket(host,{api:o.api,context:ticketContext,product,instant:o.instant,zone:o.zone,actor:o.actor,booked:r=>void o.onBooked(r.tradeId)});
  },
  async inspect(){
   throw Error('Park and loan amendments require an installed continuity profile. Inspect the retained terms from the Blotter.');
  },
  unsaved:()=>!!ticket?.unsaved(),
  pending:()=>!!ticket?.pending()||ticketBookingRetained(product,o.actor),
  sync:()=>{},
 };
}
