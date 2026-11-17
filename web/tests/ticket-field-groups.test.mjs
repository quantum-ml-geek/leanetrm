import test from 'node:test';
import assert from 'node:assert/strict';
import {ticketFieldGroups,requireSideGroupMappings} from '../dist/ticket-field-groups.js';

const fieldGroups=[{id:'agreement',label:'Agreement and parties',kind:'agreement',fields:['profile','book']},{id:'rights',label:'Rights Side terms',kind:'side_terms',fields:['package','through']},{id:'fee',label:'Independent fee terms',kind:'independent_instrument_terms',fields:['fee']}];
const description=()=>({tradeFields:['profile','book','package','through','fee'].map(id=>({id})),fieldGroups:structuredClone(fieldGroups)});
test('backend field groups partition existing terms without choosing values or inventing Side identities',()=>{
 assert.deepEqual(ticketFieldGroups(description()),fieldGroups);
 assert.equal(ticketFieldGroups({tradeFields:[{id:'legacy'}]}),undefined);
 assert.equal(ticketFieldGroups({tradeFields:[{id:'legacy'}],fieldGroups:null}),undefined);
});
test('missing, repeated, unknown fields and unknown group kinds refuse a partial or invented layout',()=>{
 for(const mutate of [d=>d.fieldGroups[0].fields.pop(),d=>d.fieldGroups[1].fields.push('book'),d=>d.fieldGroups[0].fields.push('invented'),d=>d.fieldGroups[1].kind='inferred_rights',d=>d.fieldGroups[1].id='agreement',d=>d.fieldGroups[1].fields=[],d=>d.tradeFields.push({id:'book'})]){
  const d=description();mutate(d);assert.throws(()=>ticketFieldGroups(d),/field groups/);
 }
 assert.throws(()=>ticketFieldGroups({tradeFields:[{id:'quantity'}],sides:[],sideGroupsRequired:true}),/field groups/);
});
test('actual instrument groups attach only to their declared field card while preserving several independent bindings on one card',()=>{
 const groups=[{instrumentId:'synthetic-a',bindingId:'synthetic-a-binding',fieldGroupId:'rights'},{instrumentId:'synthetic-b',bindingId:'synthetic-b-binding',fieldGroupId:'rights'},{instrumentId:'synthetic-c',bindingId:'synthetic-c-binding',fieldGroupId:null}];
 requireSideGroupMappings(groups,fieldGroups);
 assert.throws(()=>requireSideGroupMappings([{...groups[0],fieldGroupId:'another-profile'}],fieldGroups),/field groups/);
 assert.throws(()=>requireSideGroupMappings(groups,undefined),/field groups/);
 requireSideGroupMappings([{...groups[0],fieldGroupId:null}],undefined);
});
