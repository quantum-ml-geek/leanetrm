type RecordValue=Record<string,unknown>;
type OperatorQuantityReview={facts:[string,string][];tables:{label:string;columns:string[];rows:string[][]}[]};

// Every quantity, prefix contribution and gross cash amount comes from the
// managed/native review. This view never recomputes rounding or balances.
export function operatorQuantityReview(details:RecordValue,selection:RecordValue,instant:(at:string)=>string):OperatorQuantityReview{
 const bad=()=>Error('Reread the exact operator claims, settlement prefixes, cash and bank review.');
 const object=(value:unknown):RecordValue=>{if(!value||typeof value!=='object'||Array.isArray(value))throw bad();return value as RecordValue;};
 const text=(value:unknown)=>{if(typeof value!=='string'||!value.trim())throw bad();return value;};
 const integer=(value:unknown)=>{if(typeof value!=='number'||!Number.isSafeInteger(value)||value<1)throw bad();return String(value);};
 const boolean=(value:unknown)=>{if(typeof value!=='boolean')throw bad();return value;};
 const nullable=(value:unknown)=>value===null?'None':text(value);
 const nullableRevision=(value:unknown)=>value===null?'None':integer(value);
 const date=(value:unknown)=>value===null?'None':instant(text(value));
 const rows=(value:unknown)=>{if(!Array.isArray(value))throw bad();return value.map(object);};
 const index=(value:unknown,key:string)=>{const all=rows(value),map=new Map(all.map(row=>[text(row[key]),row]));if(map.size!==all.length)throw bad();return map;};
 const allocation=(value:unknown)=>value==='preserve_unallocated_source_quantity_v1'?'Preserve unused source quantity':
  value==='withdraw_all_source_allocations_v1'?'Withdraw every source allocation':(()=>{throw bad();})();
 const outcome=object(details.outcome),cashout=object(selection.cashout),unit=text(details.quantityUnit),currency=text(details.currency),changed=boolean(details.willChange);
 boolean(details.alreadyRecorded);
 if(selection.implementation!=='gas_operator_quantity_reconciliation_v1'||cashout.ordering!=='replay_original_settlement_publication_prefix_v1')throw bad();
 const selected=index(selection.claims,'claimId'),sources=index(details.sources,'claimId'),retained=index(outcome.claims,'claimId');
 const selectedUses=index(selection.consumptions,'consumptionId'),currentUses=index(outcome.consumptions,'consumptionId');
 const root=text(selection.rootClaimId),account=text(outcome.accountId);
 if(!selected.has(root)||outcome.rootClaimId!==root||selected.size!==sources.size||selected.size!==retained.size||
  selectedUses.size!==currentUses.size||[...selectedUses.keys()].some(id=>!currentUses.has(id)))throw bad();
 const claims:string[][]=[],prefixes:string[][]=[],choices:string[][]=[],fixings:string[][]=[],dependencies:string[][]=[],cash:string[][]=[],bank:string[][]=[],uses:string[][]=[];
 const reviewedUses=new Map<string,string>();
 const effect=(value:unknown)=>boolean(value)?changed?'Record correction':'Previously recorded correction':'Existing fact acknowledged';
 const settlementOwners=new Map<string,string>(),cashIds=new Set<string>(),bankIds=new Set<string>();
 for(const[id,chosen]of selected){
  const source=sources.get(id),current=retained.get(id);if(!source||!current||source.accountId!==account)throw bad();
  const claim=object(source.claim);if(claim.id!==id)throw bad();
  const accounts=index(source.accounts,'id'),evidence=index(source.evidence,'id'),observations=index(source.observations,'id');
  const document=(key:unknown)=>{const row=evidence.get(text(key));if(!row||!accounts.has(text(row.account_id)))throw bad();return row;};
  const accountLabel=(key:unknown)=>{const row=accounts.get(text(key));if(!row)throw bad();return text(row.code);};
  const claimDocument=document(chosen.evidenceId);if(claimDocument.account_id!==account)throw bad();
  const label=accountLabel(account)+' / '+text(claimDocument.source_key);
  claims.push([label,integer(claim.expectedRevision),text(claim.quantity),text(claim.remainingQuantity),text(chosen.quantity),allocation(chosen.sourceAllocation),
   integer(current.acknowledgedRevision),integer(current.currentRevision),text(current.currentQuantity),effect(current.changed),
   integer(chosen.expectedRevision),integer(claimDocument.revision),text(claimDocument.quantity),instant(text(claim.effective_at)),instant(text(claim.knownAt)),text(chosen.evidenceId),id]);
  const chosenSteps=index(chosen.settlements,'settlementId'),sourceSteps=index(source.settlements,'id'),currentSteps=index(current.settlements,'settlementId');
  if(chosenSteps.size!==sourceSteps.size||chosenSteps.size!==currentSteps.size)throw bad();
  for(const[stepId,original]of sourceSteps){
   const step=chosenSteps.get(stepId),head=currentSteps.get(stepId);if(!step||!head||settlementOwners.has(stepId))throw bad();settlementOwners.set(stepId,id);
   const selectedDocument=document(step.evidenceId),documentLabel=accountLabel(selectedDocument.account_id)+' / '+text(selectedDocument.source_key);
   prefixes.push([text(original.quantity),text(step.quantity),text(head.currentQuantity),nullable(head.cashAmount),label,documentLabel,
    integer(original.originalPublicationOrder),instant(text(original.effectiveAt)),allocation(step.sourceAllocation),integer(head.acknowledgedRevision),
    integer(head.currentRevision),text(head.cumulativeQuantity),nullable(head.price),nullable(head.exactTotal),nullable(head.roundedTotal),instant(text(original.knownAt)),id,stepId]);
   choices.push([label,stepId,integer(step.expectedRevision),documentLabel,integer(selectedDocument.revision),text(selectedDocument.quantity),text(step.evidenceId),
    nullable(step.sourceObservationId),nullableRevision(step.expectedReceiptRevision),nullableRevision(step.expectedConsumptionRevision),nullable(step.lotId),nullable(step.reservationId),allocation(step.sourceAllocation)]);
   if(step.sourceObservationId!==null){
    const observed=observations.get(text(step.sourceObservationId));if(!observed)throw bad();
    fixings.push([label,stepId,text(observed.source_code),text(observed.role).replaceAll('_',' '),instant(text(observed.observed_at)),text(observed.value),text(observed.id)]);
   }
  }
  for(const row of rows(source.positions))dependencies.push([id,text(row.id),'Identified stock or obligation',text(row.quantity),integer(row.expectedRevision)]);
  for(const row of rows(source.consumptions))dependencies.push([id,text(row.id),'Recorded stock use',text(row.quantity),integer(row.expectedRevision)]);
  const stock=index(source.positions,'id');
  for(const[useId,original]of index(source.consumptions,'id'))if(selectedUses.has(useId)){
   const use=selectedUses.get(useId)!,head=currentUses.get(useId)!;
   const selectedStock=stock.get(text(use.lotId)),originalStock=stock.get(text(original.lotId)),selectedDocument=document(use.evidenceId),originalDocument=document(original.evidenceId);
   if(original.editable!==true||!selectedStock||!originalStock||selectedStock.account_id!==originalStock.account_id||
    selectedDocument.account_id!==selectedStock.account_id||originalDocument.account_id!==originalStock.account_id)throw bad();
   if(use.reservationId!==null){const reservation=index(source.reservations,'id').get(text(use.reservationId));if(!reservation||reservation.lot_id!==use.lotId)throw bad();}
   const values=[text(original.kind).replaceAll('_',' '),text(original.quantity),text(use.quantity),text(head.currentQuantity),
    boolean(use.retracted)?'Withdraw recorded quantity':'Keep recorded quantity',boolean(head.retracted)?'Withdrawn':'Active',
    accountLabel(selectedStock.account_id)+' / '+text(selectedDocument.source_key),integer(original.expectedRevision),instant(text(original.effectiveAt)),instant(text(original.knownAt)),
    text(original.evidenceId),text(original.lotId),nullable(original.reservation_id),
    integer(use.expectedRevision),allocation(use.sourceAllocation),
    integer(selectedDocument.revision),text(selectedDocument.quantity),text(use.evidenceId),text(use.lotId),nullable(use.reservationId),
    integer(head.acknowledgedRevision),integer(head.currentRevision),
    text(head.evidenceId),text(head.lotId),nullable(head.reservationId),effect(head.changed),useId];
   const signature=JSON.stringify([original.effectiveAt,original.knownAt,original.evidenceId,original.lotId,original.reservation_id,original.kind,original.expectedRevision,original.quantity,values]),prior=reviewedUses.get(useId);if(prior!==undefined&&prior!==signature)throw bad();
   if(prior===undefined){reviewedUses.set(useId,signature);uses.push(values);}
  }
  const claimCash=new Set<string>();
  for(const row of rows(source.cash)){
   const cashId=text(row.id);if(cashIds.has(cashId)||row.position_id!==id||text(row.currency_code)!==currency)throw bad();cashIds.add(cashId);claimCash.add(cashId);
   cash.push([id,cashId,text(row.amount),currency.toUpperCase(),instant(text(row.due_at)),instant(text(row.effective_at))]);
  }
  for(const row of rows(source.payments)){
   const bankId=text(row.id);if(bankIds.has(bankId)||!claimCash.has(text(row.fee_id)))throw bad();bankIds.add(bankId);
   bank.push([id,text(row.fee_id),text(row.business_key),integer(row.revision),text(row.amount),currency.toUpperCase(),instant(text(row.paid_at)),nullable(row.evidence)]);
  }
 }
 if(reviewedUses.size!==selectedUses.size)throw bad();
 const changes=index(outcome.cashChanges,'cashId');
 const adjustments=[...changes.values()].map(row=>{
  if(settlementOwners.get(text(row.settlementId))!==text(row.positionId)||text(row.currency)!==currency)throw bad();
  return [text(row.positionId),text(row.settlementId),text(row.cashId),text(row.amount),currency.toUpperCase(),instant(text(row.dueAt)),instant(text(row.effectiveAt))];
 });
 return {facts:[['Effect',changed?'Record operator claim, settlement and stock-use corrections':'Existing operator fact acknowledged · no new effect'],
  ['Quantity unit',unit],['Currency',currency.toUpperCase()],['Root operator claim',root],
  ['Correction contract','Preserve claims, settlements and original cash'],
  ['Cashout ordering','Keep original settlement order and cumulative rounding'],['Adjustment due',date(cashout.adjustmentDueAt)],['Correction evidence',text(selection.evidence)]],
  tables:[{label:'Reviewed operator claims',columns:['Account / claim document','Source revision','Source signed quantity','Source remaining quantity',changed?'Reviewed quantity':'Acknowledged quantity','Source allocation','Acknowledged revision','Current revision','Retained current quantity','Effect','Reviewed revision','Selected document revision','Observed document quantity','Original effective time','Source known time','Selected document','Claim identity'],rows:claims},
   {label:'Reviewed settlement prefixes',columns:['Source quantity',changed?'Reviewed quantity':'Acknowledged quantity','Retained current quantity','Retained cash contribution','Account / claim document','Account / settlement document','Original settlement order','Original effective time','Source allocation','Acknowledged revision','Current revision','Retained cumulative quantity','Applied price','Exact prefix total','Rounded prefix total','Source known time','Claim identity','Settlement identity'],rows:prefixes},
   {label:'Reviewed ordinary stock uses',columns:['Use','Source quantity',changed?'Reviewed quantity':'Acknowledged quantity','Retained current quantity','Quantity decision','Retained quantity state','Account / selected use document','Source revision','Original effective time','Source known time','Source document','Source stock','Source reservation','Reviewed revision','Source allocation','Document revision','Observed document quantity','Selected document','Selected stock','Selected reservation','Acknowledged revision','Current revision','Retained document','Retained stock','Retained reservation','Effect','Use identity'],rows:uses},
   {label:'Selected settlement source and counterparts',columns:['Account / claim document','Settlement','Reviewed revision','Account / selected document','Document revision','Observed document quantity','Evidence','Final observation','Receipt revision','Recorded use revision','Funding stock','Reservation','Source allocation'],rows:choices},
   {label:'Selected final cashout fixings',columns:['Account / claim document','Settlement','Source','Role','Observed time','Observed quote','Observation identity'],rows:fixings},
   {label:'Claim dependency quantities',columns:['Claim','Native position or use','Source fact','Stated quantity','Financial revision'],rows:dependencies},
   {label:'Recorded cash memberships',columns:['Claim','Cash membership','Amount','Currency','Due','Effective'],rows:cash},
   {label:'Recorded bank payment history',columns:['Claim','Cash membership','Business reference','Revision','Amount','Currency','Observed payment time','Evidence'],rows:bank},
   {label:changed?'Cash adjustments':'Recorded cash adjustments',columns:['Claim','Settlement','Cash membership','Amount','Currency','Due','Effective'],rows:adjustments}]};
}
