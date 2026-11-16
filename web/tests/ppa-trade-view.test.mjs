import test from 'node:test';
import assert from 'node:assert/strict';
import {withSideSchedules} from '../dist/position-schedules.js';
import {ppaCutoff,readPpaView} from '../dist/ppa-trade-view.js';
test('PPA inspection retains database microseconds when adapting a common context cutoff',()=>{
 assert.equal(ppaCutoff('2026-10-26T12:34:56.1234560+00:00'),'2026-10-26T12:34:56.123456+00:00');
 assert.equal(ppaCutoff('2026-10-26T12:34:56.123456Z'),'2026-10-26T12:34:56.123456Z');
});
test('a PPA position offers its backend schedule under the same pinned read without fetching interval detail eagerly',async()=>{
 const calls=[],terms={definitionRevisionId:'definition',referenceCatalogId:'reference',referenceRevisionId:'revision',currency:'usd',delivery:{from:'2026-03-01',to:'2026-04-01'},memberships:[]};
 const read=await readPpaView(async(path,body)=>{calls.push({path,body});return {head:{revision:2},bindings:[{binding_id:'binding',instrument_id:'instrument',coverage_from:'2026-03-01T05:00:00Z',coverage_to:'2026-04-01T04:00:00Z'}],instruments:[{instrumentId:'instrument',terms}],history:[]};},
  {snapshotId:'close'}, {tradeId:'trade',bindingId:'binding',revision:'2',pendingActuals:'require_actuals_v1'},'2026-02-28T12:00:00.1234560Z');
 assert.equal(typeof withSideSchedules(read,async()=>{}, {snapshotId:'close'},{tradeId:'trade',bindingId:'binding',revision:'2',instrumentType:'ppa'},()=>{}).view('UTC').schedules,'function');
 assert.deepEqual(calls.map(c=>c.path),['ppa/editor']);
 assert.equal(calls[0].body.knownAt,'2026-02-28T12:00:00.123456Z');
});

test('unpriced PPA saved memberships remain visible from the pure retained editor read',async()=>{
 const calls=[],terms={delivery:{from:'2032-03-01',to:'2032-04-01'},memberships:[
  {role:'energy_delivery',ordinal:0,coefficient:'1',side:{kind:'floating',quantity:{kind:'volume'},location:'synthetic_point',indexPrice:{curve:'synthetic_missing_mark'},fixedPrice:null}},
  {role:'strike_payment',ordinal:0,coefficient:'-1',side:{kind:'fixed',quantity:{kind:'slots'},location:null,indexPrice:null,fixedPrice:{kind:'flat',price:'-20',quantity:'mwh'}}}]};
 const holding={tradeId:'trade',bindingId:'binding',revision:'3',pendingActuals:'require_actuals_v1',unavailableReason:'Missing market observation'};
 const read=await readPpaView(async(path,body)=>{calls.push({path,body});assert.equal(path,'ppa/editor');return {head:{revision:3},bindings:[{binding_id:'binding',instrument_id:'instrument',coverage_from:'2032-03-01T00:00:00Z',coverage_to:'2032-04-01T00:00:00Z'}],instruments:[{instrumentId:'instrument',terms}],history:[]};},
  {snapshotId:'selected-frame'},holding,'2032-02-29T18:00:00Z');
 const shown=read.view('America/Chicago').terms;
 assert.deepEqual(shown.slice(1).map(section=>section.title),['Power','Fixed price']);
 assert.deepEqual(shown[1].rows.find(([label])=>label==='Direction'),['Direction','Receive']);
 assert.deepEqual(shown[2].rows.find(([label])=>label==='Direction'),['Direction','Pay']);
 assert.equal(holding.unavailableReason,'Missing market observation');assert.equal(calls.length,1);
});
