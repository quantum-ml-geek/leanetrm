import type {Context} from './date-editor.js';

export type RecDateContext={effectiveOn:string;knowledgeMode:'current'|'retained';retained:Context|null;convention:'rec_business_date_end_utc_v1'};
export function recContext(effectiveOn:string,knowledgeMode:string,retained:Context|null):RecDateContext {
 if(knowledgeMode==='current'){if(retained!==null)throw Error('A current context has no retained certificate.');}
 else if(knowledgeMode==='retained'){if(!retained?.contextId||!retained.knownAt||retained.effectiveOn!==effectiveOn)throw Error('Select the exact retained context for this inventory business date.');}
 else throw Error('Select current or exact retained inventory knowledge.');
 return {effectiveOn,knowledgeMode,retained,convention:'rec_business_date_end_utc_v1'};
}
export type RecActionKind='receipt'|'allocate'|'release'|'transfer'|'retire';
type ActionValues={lotId?:string;productCode?:string;registryLotReference?:string;vintageFrom?:string;vintageTo?:string;from?:string;to?:string;receiptKind?:string;evidenceSource?:string;evidenceReference?:string;deliveryId?:string;allocationId?:string;allocationRevision?:number;destinationId?:string;beneficiaryKind?:string;beneficiaryId?:string;beneficiaryRevision?:number;purposeCode?:string};
// Transport projection only: serials remain strings; range validation, title,
// eligibility and all inventory quantities belong to the authorized backend.
export function recInventoryAction(kind:string,values:ActionValues):Record<string,unknown> {
 const text=(key:keyof ActionValues)=>{const value=values[key];if(typeof value!=='string'||!value)throw Error(`Complete ${key} for the selected inventory action.`);return value;};
 const revision=(key:'allocationRevision'|'beneficiaryRevision')=>{const value=values[key];if(typeof value!=='number'||!Number.isInteger(value)||value<1)throw Error('Select an exact saved revision.');return value;};
 const range=()=>({lotId:text('lotId'),from:text('from'),to:text('to')});
 switch(kind){
  case 'receipt':return {kind,lotId:text('lotId'),productCode:text('productCode'),registryLotReference:text('registryLotReference'),vintageFrom:text('vintageFrom'),vintageTo:text('vintageTo'),from:text('from'),to:text('to'),receiptKind:text('receiptKind'),evidenceSource:text('evidenceSource'),evidenceReference:text('evidenceReference')};
  case 'allocate':return {kind,...range(),deliveryId:text('deliveryId')};
  case 'release':return {kind,...range(),allocationId:text('allocationId'),allocationRevision:revision('allocationRevision')};
  case 'transfer':return {kind,...range(),allocationId:text('allocationId'),allocationRevision:revision('allocationRevision'),destinationId:text('destinationId'),evidenceSource:text('evidenceSource'),evidenceReference:text('evidenceReference')};
  case 'retire':return {kind,...range(),beneficiaryKind:text('beneficiaryKind'),beneficiaryId:text('beneficiaryId'),beneficiaryRevision:revision('beneficiaryRevision'),purposeCode:text('purposeCode'),evidenceSource:text('evidenceSource'),evidenceReference:text('evidenceReference')};
  default:throw Error('Choose a supported inventory action.');
 }
}
