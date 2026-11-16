import test from 'node:test';
import assert from 'node:assert/strict';
import {operatingParameterFields,comingSoonFields,parseSuppliedPlan,facilityTerms,structuredPreviewRequest} from '../dist/structured-power-model.js';

test('facility fields contain only executable physical inputs',()=>{
  assert.deepEqual(operatingParameterFields('solar').map(x=>x.key),['stage']);
  assert.ok(!operatingParameterFields('thermal').some(x=>/guaranteed|terminal|numerical/i.test(x.key)));
  assert.ok(!operatingParameterFields('battery').some(x=>/opening|terminal|cycle/i.test(x.key)));
  assert.ok(comingSoonFields('battery').some(x=>/degradation/i.test(x)));
});
test('supplied decimal plan transport preserves exact text and refuses ambiguous columns',()=>{
  assert.deepEqual(parseSuppliedPlan('battery','10.000000000001,0,0.9\n0,8.1,1'),[
    {chargeMw:'10.000000000001',dischargeMw:'0',availablePowerFraction:'0.9'},
    {chargeMw:'0',dischargeMw:'8.1',availablePowerFraction:'1'}]);
  assert.deepEqual(parseSuppliedPlan('solar','10,\n12,8'),[{productionMwh:'10',requiredDeliveryMwh:null},{productionMwh:'12',requiredDeliveryMwh:'8'}]);
  assert.throws(()=>parseSuppliedPlan('battery','1,2'),/3 columns/);
  assert.throws(()=>parseSuppliedPlan('thermal','online,10,10,,extra'),/4 columns/);
});
test('saved terms copy exact selected pins and only their selected union',()=>{
  const pins={definitionCatalogId:'dc',definitionRevisionId:'dr',referenceCatalogId:'rc',referenceRevisionId:'rr'};
  const terms=facilityTerms(pins,'solar',{facilityCode:'existing',clockCode:'utc',intervalMinutes:60,powerQuantityCode:null,energyQuantityCode:'mwh',fuelQuantityCode:null},{stage:'delivered'});
  assert.equal(terms.facilityCode,'existing');assert.equal(terms.definitionRevisionId,'dr');
  assert.equal(terms.battery,null);assert.equal(terms.thermal,null);assert.deepEqual(terms.solar,{stage:'delivered'});
});
test('preview unions and dynamic context remain explicit without browser calculations',()=>{
  const request=structuredPreviewRequest({snapshotId:'s',facilityId:'f',facilityVersion:2,kind:'battery',operatingDate:'2040-01-01',firstInterval:1,state:{at:'2040-01-01T00:00:00Z',storedMwh:'1',cumulativeGridThroughputMwh:'3',terminalMinimumMwh:'0',terminalMaximumMwh:'1'},plan:'0,0,1',valuation:null});
  assert.equal(request.snapshotId,'s');assert.equal(request.facilityVersion,2);assert.equal(request.valuation,null);
  assert.deepEqual(request.thermalDispatch,[]);assert.equal(request.thermalState,null);assert.equal(request.solarRight,null);
  assert.equal(request.batteryState.storedMwh,'1');
});

test('unknown save requests stay with their original profile through resets and retries',async()=>{
 const {StructuredPowerPendingStore}=await import('../dist/structured-power-model.js');
 const rows=new Map(),storage={getItem:key=>rows.get(key)??null,setItem:(key,value)=>rows.set(key,value),removeItem:key=>rows.delete(key)};
 const store=new StructuredPowerPendingStore(storage),a=store.select('workspace:alpha');
 a.begin('physical/power-facilities/save',{snapshotId:'first',expectedVersion:0},()=> 'a-request');a.sending();store.save('workspace:alpha',a);
 const b=store.select('workspace:beta');assert.equal(b.command,undefined);
 b.begin('physical/power-facilities/save',{snapshotId:'second',expectedVersion:0},()=> 'b-request');store.save('workspace:beta',b);
 assert.equal(store.select('workspace:alpha').command.operationId,'a-request');
 assert.equal(store.select('workspace:beta').command.operationId,'b-request');
 a.clear();store.save('workspace:alpha',a);assert.equal(new StructuredPowerPendingStore(storage).select('workspace:alpha').command,undefined);
 assert.equal(new StructuredPowerPendingStore(storage).select('workspace:beta').command.operationId,'b-request');
});
