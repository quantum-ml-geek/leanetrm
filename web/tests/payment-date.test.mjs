import test from 'node:test';
import assert from 'node:assert/strict';
import {displayPaymentDate,paymentDateInput,paymentDateValue} from '../dist/payment-date.js';

test('standard payment dates do not change with the display timezone',()=>{
 const at='2027-01-20T00:00:00+00:00';
 for(const zone of ['America/Chicago','Pacific/Honolulu','Pacific/Kiritimati']){
  assert.equal(displayPaymentDate(at),'Jan 20, 2027',zone);
  assert.equal(displayPaymentDate('2027-01-20T23:59:59.123456Z'),'Jan 20, 2027',zone);
 }
 assert.equal(displayPaymentDate('2027-01-20'),'Jan 20, 2027');
 assert.throws(()=>displayPaymentDate('2027-02-30'),/valid payment date/);
 assert.throws(()=>displayPaymentDate('2027-01-20T00:00:00-06:00'),/UTC/);
});

test('payment coordinates reject invalid times without rounding valid fractional precision',()=>{
 for(const value of ['2041-02-02T99:99:99Z','2041-02-02T24:00:00Z','2041-02-02T23:60:00Z','2041-02-02T23:59:60Z'])
  assert.throws(()=>paymentDateValue(value),/valid UTC/);
 assert.equal(paymentDateValue('2041-02-02T23:59:59.123456Z'),'2041-02-02');
});

test('payment editing retains an unchanged coordinate and serializes a new date without time-zone resolution',async()=>{
 const field={value:''};const input=paymentDateInput(field);
 input.set('2027-01-20T18:00:00.123456Z');
 assert.equal(field.value,'2027-01-20');input.refresh();
 assert.equal(await input.instant(),'2027-01-20T18:00:00.123456Z');
 field.value='2027-02-02';assert.equal(await input.instant(),'2027-02-02T00:00:00Z');
 input.clear();await assert.rejects(input.instant(),/payment date/);
 field.value='2027-02-30';await assert.rejects(input.instant(),/payment date/);
});

test('native settlement evidence shows original dates and retains correction and actual-event instants',async()=>{
 const {contractDateEvidence}=await import('../dist/payment-date.js');
 const at='2027-02-05T00:00:00Z',fixing='2027-02-05T12:00:00Z',correction='2027-02-06T18:00:00Z';
 const original={occurrences:[{contractual_due:at,completion_at:fixing}],determinations:[
  {ordinal:1,due_at:at,evidence:{publishedAt:fixing}},{ordinal:2,due_at:correction}],payments:[{effective_at:fixing}]};
 const saved=JSON.stringify(original),shown=contractDateEvidence(original);
 assert.deepEqual(shown,{occurrences:[{contractual_payment_date:'Feb 5, 2027',completion_at:fixing}],determinations:[
  {ordinal:1,due_date:'Feb 5, 2027',evidence:{publishedAt:fixing}},{ordinal:2,due_at:correction}],payments:[{effective_at:fixing}]});
 assert.equal(JSON.stringify(original),saved);
});
