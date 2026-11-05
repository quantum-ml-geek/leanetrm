import {renderSwapObservationInspection} from './swap-observations-view.js';
import {renderRegularTable} from './regular-table.js';
import type {Valuation} from './swap-editor.js';
type Side=Valuation['sides'][number];
type Quote={currency:string;unit:string;quoteMultiplier:string};
type QuoteLabel=Quote&{currencyCode:string;quantityCode:string};
export function swapPaymentQuote(side:Side,quotes:QuoteLabel[]):Quote{
 const price=side.payments[0].resets[0];
 return {currency:quotes.find(q=>q.currencyCode===price.currency.code)?.currency??price.currency.code,
  unit:quotes.find(q=>q.quantityCode===price.quantity.code)?.unit??price.quantity.code,quoteMultiplier:price.multiplier};
}
/** A side's direction as the backend's coefficient states it: Pay for -1, Receive for 1, and any other coefficient as it is. */
export const sideDirection=(coefficient:string)=>coefficient==='-1'?'Pay':coefficient==='1'?'Receive':`coefficient ${coefficient}`;
type Format=(value:string,kind:'quantity'|'money'|'factor'|'price',side:string)=>string;
export function renderSwapTradePayments(section:HTMLElement,prefix:string,side:Side,i:Quote|undefined,busy:()=>boolean,format:Format=(value)=>value){
 const display={text:(value:string,kind:'quantity'|'money'|'factor'|'price',selected=side.kind)=>format(value,kind,selected)};
   const direction=sideDirection(side.coefficient),primary=document.createElement('div');primary.className='table-wrap swap-payment-table';section.append(primary);
   renderRegularTable(primary,`${prefix}-${side.slot}-trade-payments`,JSON.stringify(side),
    ['Delivery start','Delivery end · exclusive','Total quantity','Unit','Direction','Payment date',`Signed cash · ${i?.currency}`,'DF',`Trade PV · ${i?.currency}`],
    side.payments.map(p=>[p.deliveryFrom,p.deliveryTo,p.resolvedQuantity,i?.unit??'',direction,p.paymentDate,p.tradeCashAmount,p.discountFactor,p.tradePresentValue]),[2,6,7,8],busy,
    {displayRows:side.payments.map(p=>[p.deliveryFrom,p.deliveryTo,display.text(p.resolvedQuantity,'quantity'),i?.unit??'',direction,p.paymentDate,display.text(p.tradeCashAmount,'money',side.kind),display.text(p.discountFactor,'factor',side.kind),display.text(p.tradePresentValue,'money',side.kind)])});
   const compact=document.createElement('div');compact.className='swap-payment-summary';
   for(const p of side.payments){const row=document.createElement('p');row.textContent=`${p.deliveryFrom} to ${p.deliveryTo} (exclusive) · total ${display.text(p.resolvedQuantity,'quantity')} ${i?.unit}. ${direction} · signed cash ${display.text(p.tradeCashAmount,'money',side.kind)} ${i?.currency} on ${p.paymentDate}. Discount factor ${display.text(p.discountFactor,'factor',side.kind)} · PV ${display.text(p.tradePresentValue,'money',side.kind)} ${i?.currency}.`;compact.append(row);}section.append(compact);
   if(side.kind==='fixed'&&new Set(side.payments.flatMap(p=>p.resets.map(r=>r.price))).size===1){const price=document.createElement('p');price.className='field-help';price.textContent=`Contractual fixed price: ${display.text(side.payments[0].resets[0].price,'price',side.kind)} ${i?.currency}/${i?.unit}${i?.quoteMultiplier==='1'?'':' × '+i?.quoteMultiplier}`;section.append(price);}
}

/** Every backend pricing observation remains associated with its payment; no averages or cash are computed here. */
export const swapPricingRows=(side:Side)=>side.payments.flatMap(p=>p.resets.map(r=>
 [p.paymentDate,r.from,r.to,r.weight,r.price,r.fixingState,r.cashContribution]));

export function renderSwapPricingRows(host:HTMLElement,prefix:string,side:Side,quote:Quote,zone:string,busy:()=>boolean,format:Format){
 const section=document.createElement('section');section.className='swap-pricing-rows';
 const title=document.createElement('h4');title.textContent=`Pricing rows · ${side.payments.reduce((n,p)=>n+p.resets.length,0)}`;
 const note=document.createElement('p');note.className='field-help';note.textContent='Exact averaging weights and price observations. Cash contributions are per normalized unit; the payment rows include trade quantity and direction.';
 const table=document.createElement('div');table.className='table-wrap swap-contract-prices';section.append(title,note,table);host.append(section);
 const price=`${quote.currency}/${quote.unit}${quote.quoteMultiplier==='1'?'':' × '+quote.quoteMultiplier}`;
 const rows=swapPricingRows(side);
 renderRegularTable(table,`${prefix}-${side.slot}-pricing`,JSON.stringify(rows),
  ['Payment date','Observation start','Observation end · exclusive','Weight',`Price · ${price}`,'State',`Unit cash contribution · ${quote.currency}`],rows,[3,4,6],busy,
  {displayRows:rows.map(r=>r.map((v,n)=>n===3?format(v,'quantity',side.kind):n===4?format(v,'price',side.kind):n===6?format(v,'money',side.kind):v))});
 side.payments.forEach((p,n)=>{if(p.observationSchedule)renderSwapObservationInspection(section,p.observationSchedule,p.paymentDate,`${prefix}-${side.slot}-${n}`,zone,{price,cash:quote.currency,quantity:quote.unit},busy);});
}
