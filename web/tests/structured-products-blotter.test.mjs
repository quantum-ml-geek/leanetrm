import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {positionRows,valueFields} from '../dist/desk-model.js';
import {readPositionFacts} from '../dist/position-facts.js';
import {positionWindowUrl,readPositionWindowUrl} from '../dist/position-window-selection.js';
import {genericPositionView} from '../dist/position-schedules.js';
const fixture=JSON.parse(readFileSync(new URL('./fixtures/desk.json',import.meta.url),'utf8'));

test('operating and REC positions display backend PV through independent Side schedules',()=>{
 for(const [instrumentType,pill] of [['operating_right','RIGHT'],['rec_forward','REC']]){
  const holding={...fixture.holdings[0],instrumentType,marketLabel:'Synthetic independent markets',sideSchedules:true,contractIdentityKind:undefined,quantity:'1',lots:null,direction:'multi_side',fixedPrice:null,mark:null,presentValue:'610',unavailableReason:null,measure:'present_value'};
  const row=positionRows([holding])[0];assert.equal(row.pill,pill);assert.equal(row.value,'610');assert.equal(row.exposure,null);assert.equal(row.priceNote,'By side');assert.equal(row.markNote,'Independent side schedules');assert.deepEqual(valueFields(instrumentType),['mark','presentValue']);
  assert.equal(genericPositionView(holding).amend.allowed,false);
 }
});
test('booked facts and exact separate-window references admit the two registered product families',()=>{
 const context={contextId:'10000000-0000-4000-8000-000000000001',effectiveOn:'2031-01-01',knownAt:'2031-01-02T00:00:00Z'};
 for(const instrumentType of ['operating_right','rec_forward']){
  const position={tradeId:'trade',bindingId:'binding',revision:1,tradeReference:'Synthetic right',bookId:'book',book:'Synthetic book',instrumentType,marketLabel:null,deliveryFrom:null,deliveryTo:null,bookedQuantity:'1',bookedUnit:'right'};
  assert.equal(readPositionFacts({context,asOf:'2031-01-01T00:00:00Z',positions:[position],total:1,nextOffset:null},50).positions[0].instrumentType,instrumentType);
  const selection={snapshotId:'20000000-0000-4000-8000-000000000002',context,asOf:'2031-01-01T00:00:00Z',tradeId:'30000000-0000-4000-8000-000000000003',bindingId:'40000000-0000-4000-8000-000000000004',revision:1,instrumentType,zone:'UTC',example:'baseline',lifecycle:'read_only'};
  assert.deepEqual(readPositionWindowUrl(positionWindowUrl('https://example.invalid/',selection)),selection);
 }
});
