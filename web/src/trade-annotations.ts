export type Trader={id:string;revision:number;code:string;name:string};
export type PartyChoice=Trader;
export type PartyCatalog={legalEntities:PartyChoice[];counterparties:PartyChoice[]};
export type Booking={tradeDate:string|null;legalEntityId:string|null;legalEntityRevision:number|null;counterpartyId:string|null;counterpartyRevision:number|null;legalEntity?:string|null;counterparty?:string|null};
export type Annotation=Booking&{booking?:Booking;traderId:string|null;traderRevision:number|null;memo:string|null;trader?:string|null;traderCode?:string|null};

// A trader is business attribution. Selecting one never changes the session user.
export function tradeAnnotations(prefix:string){
 const select=document.getElementById(prefix+'-trader') as HTMLSelectElement,memo=document.getElementById(prefix+'-memo') as HTMLTextAreaElement;
 const date=document.getElementById(prefix+'-trade-date') as HTMLInputElement,entity=document.getElementById(prefix+'-legal-entity') as HTMLSelectElement,party=document.getElementById(prefix+'-counterparty') as HTMLSelectElement;
 let initialMemo:string|null=null;
 const key=(id:string,revision:number)=>JSON.stringify([id,revision]);
 return{
  populate(traders:Trader[],catalog:PartyCatalog,state?:Partial<Annotation>){
   select.replaceChildren(new Option('Unassigned',''),...traders.map(t=>new Option(`${t.name} · ${t.code}`,key(t.id,t.revision))));
   if(state?.traderId&&state.traderRevision){const value=key(state.traderId,state.traderRevision);if(!Array.from(select.options).some(o=>o.value===value))select.append(new Option(`${state.trader??'Retained trader'} · version ${state.traderRevision}`,value));select.value=value;}
   initialMemo=state?.memo??null;memo.value=initialMemo??'';
   const booking=state?.booking??state;
   date.value=booking?.tradeDate??'';
   function choices(select:HTMLSelectElement,rows:PartyChoice[],id:string|null|undefined,revision:number|null|undefined,label:string|null|undefined){
    select.replaceChildren(new Option('Choose…',''),...rows.map(p=>new Option(`${p.name} · ${p.code}`,key(p.id,p.revision))));
    if(id&&revision){const value=key(id,revision);if(!Array.from(select.options).some(o=>o.value===value))select.append(new Option(`${label??'Retained party'} · version ${revision}`,value));select.value=value;}
   }
   choices(entity,catalog.legalEntities,booking?.legalEntityId,booking?.legalEntityRevision,booking?.legalEntity);
   choices(party,catalog.counterparties,booking?.counterpartyId,booking?.counterpartyRevision,booking?.counterparty);
  },
  read():Annotation{const [traderId,traderRevision]=select.value?JSON.parse(select.value):[null,null];const [legalEntityId,legalEntityRevision]=entity.value?JSON.parse(entity.value):[null,null];const [counterpartyId,counterpartyRevision]=party.value?JSON.parse(party.value):[null,null];return{tradeDate:date.value||null,legalEntityId,legalEntityRevision,counterpartyId,counterpartyRevision,traderId,traderRevision,memo:memo.value===(initialMemo??'')?initialMemo:memo.value};},
  reset(){select.replaceChildren();entity.replaceChildren();party.replaceChildren();date.value='';memo.value='';initialMemo=null;},
 };
}
