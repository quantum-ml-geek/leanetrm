import test from 'node:test';
import assert from 'node:assert/strict';
import {sideDirection,swapPaymentQuote} from '../dist/swap-trade-review.js';

const quotes=[
 {currencyCode:'synthetic_usd',quantityCode:'synthetic_energy',currency:'USD',unit:'MWh',quoteMultiplier:'100'},
 {currencyCode:'synthetic_usd',quantityCode:'synthetic_energy',currency:'USD',unit:'MWh',quoteMultiplier:'1'}
];
const side=multiplier=>({payments:[{resets:[{currency:{code:'synthetic_usd'},quantity:{code:'synthetic_energy'},multiplier}]}]});
test('independent floating sides display their own contractual quote multiplier',()=>{
 assert.deepEqual(swapPaymentQuote(side('100'),quotes),{currency:'USD',unit:'MWh',quoteMultiplier:'100'});
 assert.deepEqual(swapPaymentQuote(side('1'),quotes),{currency:'USD',unit:'MWh',quoteMultiplier:'1'});
});
test('retained quote evidence stays visible when friendly labels are unavailable',()=>{
 assert.deepEqual(swapPaymentQuote(side('100'),[]),{currency:'synthetic_usd',unit:'synthetic_energy',quoteMultiplier:'100'});
});

test('a side reads Pay or Receive for the backend\'s coefficients of -1 and 1, and states any other coefficient as it is',()=>{
 assert.deepEqual(['-1','1','2','-0.5'].map(sideDirection),['Pay','Receive','coefficient 2','coefficient -0.5']);
});

test('pricing rows retain each averaging observation, exact weight and contribution under its own payment',async()=>{
 const {swapPricingRows}=await import('../dist/swap-trade-review.js');
 const input={payments:[{paymentDate:'2027-02-10',resets:[
  {from:'2027-01-01',to:'2027-01-02',weight:'1/31',price:'-2',cashContribution:'-2/31',fixingState:'Actual'},
  {from:'2027-01-02',to:'2027-01-03',weight:'2/31',price:'3',cashContribution:'6/31',fixingState:'Projected'}]},
  {paymentDate:'2027-03-10',resets:[{from:'2027-02-01',to:'2027-03-01',weight:'1',price:'4',cashContribution:'4',fixingState:'Projected'}]}]};
 assert.deepEqual(swapPricingRows(input),[
  ['2027-02-10','2027-01-01','2027-01-02','1/31','-2','Actual','-2/31'],
  ['2027-02-10','2027-01-02','2027-01-03','2/31','3','Projected','6/31'],
  ['2027-03-10','2027-02-01','2027-03-01','1','4','Projected','4']]);
});
