import test from 'node:test';
import assert from 'node:assert/strict';
import {pricingGraph,pricingEquation} from '../dist/pricing-view.js';
const source=(id,curve,value)=>({id,curve,contractId:id+'-contract',deliveryFrom:'2021-01-01',deliveryTo:'2021-02-01',value,quote:'quote',rule:'direct',use:'variable',source:'synthetic',role:'trader_mark',inputs:[],multiplier:null,lineage:[id+'-observation']});
function fixture(){
  const a=source('a','future','3'),b=source('b','basis','0.1'),other=source('other','unrelated','999');
  const root={...source('root','composite','21.1'),rule:'scale_add',inputs:[{slot:'base',id:'a'},{slot:'spread',id:'b'}],multiplier:{value:'7',observationId:'multiplier',valueSpecification:null},lineage:['a-observation','b-observation','multiplier']};
  const point={contractId:root.contractId,deliveryFrom:root.deliveryFrom,deliveryTo:root.deliveryTo,value:root.value,quote:root.quote,lineage:root.lineage};
  return {result:{curve:root.curve,points:[point],trace:[a,b,root,other]},point};
}
test('pricing graph follows exact server links and excludes unrelated contracts',()=>{const {result,point}=fixture(),before=JSON.stringify(result),graph=pricingGraph(result,point);assert.deepEqual(graph.nodes.map(n=>n.id),['a','b','root']);assert.equal(graph.depth.get('root'),1);assert.equal(pricingEquation(graph.root,graph),'7 × 3 + (0.1) = 21.1');assert.equal(JSON.stringify(result),before);});
test('pricing graph does not infer dependencies for all-in supplied marks',()=>{const node=source('own','all_in','29.1'),point={...node};const graph=pricingGraph({curve:'all_in',trace:[node]},point);assert.equal(graph.nodes.length,1);assert.equal(pricingEquation(node,graph),'Supplied mark');});
test('shared dependency is shown once and frozen settlements stay explicit',()=>{const {result,point}=fixture();result.trace[0].use='frozen';result.trace[0].role='daily_settlement';result.trace[2].inputs[1].id='a';const graph=pricingGraph(result,point);assert.deepEqual(graph.nodes.map(n=>n.id),['a','root']);assert.equal(pricingEquation(graph.nodes[0],graph),'Published final settlement');});
test('missing or duplicated trace identities raise instead of inventing a source',()=>{for(const mutate of [r=>r.trace.shift(),r=>r.trace.push(r.trace[0]),r=>r.trace[2].inputs.pop(),r=>r.trace[2].multiplier=null]){const {result,point}=fixture();mutate(result);assert.throws(()=>pricingGraph(result,point),/missing or inconsistent/);}});
test('stale price or delivery evidence cannot be presented as the selected result',()=>{for(const patch of [{value:'22'},{deliveryFrom:'2021-02-01'},{quote:'other'},{lineage:['different']}]){const {result,point}=fixture();assert.throws(()=>pricingGraph(result,{...point,...patch}),/missing or inconsistent/);}});
test('trace cycles raise instead of drawing a plausible dependency path',()=>{const {result,point}=fixture();result.trace[2].inputs[0].id='root';assert.throws(()=>pricingGraph(result,point),/missing or inconsistent/);});
