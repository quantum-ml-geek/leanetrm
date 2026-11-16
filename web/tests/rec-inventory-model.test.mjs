import test from 'node:test';
import assert from 'node:assert/strict';
import {recInventoryAction,recContext} from '../dist/rec-inventory-model.js';

test('receipt transport preserves exact serials without converting them to browser numbers',()=>{
 const result=recInventoryAction('receipt',{lotId:'lot',productCode:'selected-product',registryLotReference:'external-lot',vintageFrom:'2031-01-01',vintageTo:'2032-01-01',from:'9223372036854775700',to:'9223372036854775701',receiptKind:'confirmed',evidenceSource:'selected-source',evidenceReference:'supplied-document'});
 assert.deepEqual(result,{kind:'receipt',lotId:'lot',productCode:'selected-product',registryLotReference:'external-lot',vintageFrom:'2031-01-01',vintageTo:'2032-01-01',from:'9223372036854775700',to:'9223372036854775701',receiptKind:'confirmed',evidenceSource:'selected-source',evidenceReference:'supplied-document'});
});
test('each inventory transition sends its own closed native action shape',()=>{
 const common={lotId:'lot',from:'1',to:'3',deliveryId:'delivery',allocationId:'allocation',allocationRevision:2,destinationId:'destination',evidenceSource:'source',evidenceReference:'document',beneficiaryKind:'legal_entity',beneficiaryId:'party',beneficiaryRevision:4,purposeCode:'selected-purpose'};
 assert.deepEqual(recInventoryAction('allocate',common),{kind:'allocate',lotId:'lot',from:'1',to:'3',deliveryId:'delivery'});
 assert.deepEqual(recInventoryAction('release',common),{kind:'release',lotId:'lot',from:'1',to:'3',allocationId:'allocation',allocationRevision:2});
 assert.deepEqual(recInventoryAction('transfer',common),{kind:'transfer',lotId:'lot',from:'1',to:'3',allocationId:'allocation',allocationRevision:2,destinationId:'destination',evidenceSource:'source',evidenceReference:'document'});
 assert.deepEqual(recInventoryAction('retire',common),{kind:'retire',lotId:'lot',from:'1',to:'3',beneficiaryKind:'legal_entity',beneficiaryId:'party',beneficiaryRevision:4,purposeCode:'selected-purpose',evidenceSource:'source',evidenceReference:'document'});
 assert.throws(()=>recInventoryAction('issue',common),/supported inventory action/);
});
test('inventory context keeps business date and certified knowledge separate from a financial close',()=>{
 const retained={effectiveOn:'2031-01-01',knownThrough:8,knownAt:'2031-01-02T00:00:00Z',contextId:'certificate'};
 assert.deepEqual(recContext('2031-01-01','retained',retained),{effectiveOn:'2031-01-01',knowledgeMode:'retained',retained,convention:'rec_business_date_end_utc_v1'});
 assert.throws(()=>recContext('2031-01-01','retained',null),/exact retained context/);
 assert.throws(()=>recContext('2031-01-01','current',retained),/current context/);
});
