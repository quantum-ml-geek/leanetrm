// Standard payment coordinates are stored as UTC instants internally. Their
// contractual date is displayed without applying a user's presentation zone.
function requireDate(value:string){
 if(!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value+'T00:00:00Z'))||new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value)
  throw Error('Choose a valid payment date.');
 return value;
}
export function paymentDateValue(value:string){
 if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|\+00:00)$/.test(value))throw Error('A payment coordinate must be supplied in UTC.');
 if(!Number.isFinite(Date.parse(value))||new Date(value).toISOString().slice(0,19)!==value.slice(0,19))
  throw Error('Supply a valid UTC payment coordinate.');
 return requireDate(value.slice(0,10));
}
export function displayPaymentDate(value:string){
 return new Intl.DateTimeFormat('en',{year:'numeric',month:'short',day:'numeric',timeZone:'UTC'}).format(new Date((value.length===10?requireDate(value):paymentDateValue(value))+'T00:00:00Z'));
}
export function paymentDateInput(input:HTMLInputElement){
 let original:string|undefined;
 return {
  set(value:string){input.value=paymentDateValue(value);original=value;},
  clear(){input.value='';original=undefined;},
  refresh(){},
  async instant(){const date=requireDate(input.value);return original&&paymentDateValue(original)===date?original:date+'T00:00:00Z';}
 };
}

// Presentation of standard contractual evidence only. Publication, fixing and
// actual-cash event instants keep their own fields and remain unchanged.
export function contractDateEvidence(value:unknown):unknown{
 if(Array.isArray(value))return value.map(contractDateEvidence);
 if(value===null||typeof value!=='object')return value;
 const record=value as Record<string,unknown>;
 return Object.fromEntries(Object.entries(record).map(([key,item])=>{
  const payment=key==='paymentAt'||key==='PaymentAt'||key==='valueAt'&&record.kind==='Payment';
  return payment?[key==='PaymentAt'?'PaymentDate':'paymentDate',item===null?null:displayPaymentDate(String(item))]:[key,contractDateEvidence(item)];
 }));
}
