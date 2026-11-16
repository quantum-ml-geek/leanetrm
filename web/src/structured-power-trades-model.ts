export type OperatingParty={id:string;revision:number;name?:string;code?:string};
export type OperatingBookFields={bookId:string;legalEntity:OperatingParty|null;counterparty:OperatingParty|null;reason:string;convention:string};
export function operatingBooking(operationId:string,fields:OperatingBookFields,plan:unknown){
 if(!plan||typeof plan!=='object'||!(plan as {valuation?:unknown}).valuation)throw Error('Review a valued operating plan before booking.');
 if(!fields.legalEntity?.id||!Number.isInteger(fields.legalEntity.revision)||fields.legalEntity.revision<1)throw Error('Choose the exact legal entity revision.');
 if(!fields.counterparty?.id||!Number.isInteger(fields.counterparty.revision)||fields.counterparty.revision<1)throw Error('Choose the exact counterparty revision.');
 if(!operationId||!fields.bookId||!fields.reason.trim()||!fields.convention)throw Error('Complete the book, reason and explicit operating-right convention.');
 return {operationId,tradeId:null,expectedRevision:0,bookId:fields.bookId,legalEntityId:fields.legalEntity.id,legalEntityRevision:fields.legalEntity.revision,counterpartyId:fields.counterparty.id,counterpartyRevision:fields.counterparty.revision,reason:fields.reason,convention:fields.convention,plan};
}
export const unchangedOperatingReview=(reviewed:unknown,current:unknown)=>JSON.stringify(reviewed)===JSON.stringify(current);
