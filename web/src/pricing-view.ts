import {type CurveResult,type Point} from './market-view.js';

export type PricingNode={id:string;curve:string;contractId:string;deliveryFrom:string;deliveryTo:string;value:string;quote:string;rule:'direct'|'add'|'scale_add';use:'variable'|'frozen';source:string|null;role:string|null;inputs:{slot:'base'|'spread';id:string}[];multiplier:{value:string;observationId:string|null;valueSpecification:string|null}|null;lineage:string[]};
export type PricingGraph={nodes:PricingNode[];depth:Map<string,number>;root:PricingNode};
const unavailable=()=>Error('The pricing breakdown is missing or inconsistent. Refresh and try again.');

// This view follows actual server evaluations. It never calculates prices,
// guesses a source month, infers exposure or substitutes a missing mark.
export function pricingGraph(result:CurveResult,point:Point):PricingGraph {
  if(result.kind==='rates'||!point.contractId||!result.trace)throw unavailable();
  const indexed=new Map(result.trace.map(n=>[n.id,n]));
  if(indexed.size!==result.trace.length)throw unavailable();
  const roots=result.trace.filter(n=>n.curve===result.curve&&n.contractId===point.contractId&&n.use==='variable');
  if(roots.length!==1)throw unavailable();
  const root=roots[0];
  if(root.value!==point.value||root.quote!==point.quote||root.deliveryFrom!==point.deliveryFrom||root.deliveryTo!==point.deliveryTo||
     [...root.lineage].sort().join('|')!==[...point.lineage].sort().join('|'))throw unavailable();
  const nodes:PricingNode[]=[],depth=new Map<string,number>(),visiting=new Set<string>();
  function visit(node:PricingNode):number {
    if(visiting.has(node.id))throw unavailable();
    if(depth.has(node.id))return depth.get(node.id)!;
    visiting.add(node.id);
    if(!['direct','add','scale_add'].includes(node.rule)||!['variable','frozen'].includes(node.use)||
      (node.rule==='direct'&&(node.inputs.length!==0||node.multiplier!==null))||
      (node.rule!=='direct'&&(node.inputs.length!==2||new Set(node.inputs.map(i=>i.slot)).size!==2||!node.inputs.some(i=>i.slot==='base')||!node.inputs.some(i=>i.slot==='spread')))||
      (node.rule==='scale_add')!==(node.multiplier!==null))throw unavailable();
    let level=0;
    for(const input of node.inputs){const source=indexed.get(input.id);if(!source)throw unavailable();level=Math.max(level,visit(source)+1);}
    visiting.delete(node.id);depth.set(node.id,level);nodes.push(node);return level;
  }
  visit(root);return {nodes,depth,root};
}
export function pricingEquation(node:PricingNode,graph:PricingGraph){
  if(node.rule==='direct')return node.use==='frozen'?'Published final settlement':node.role==='daily_settlement'?'Published daily settlement':'Supplied mark';
  const source=(slot:'base'|'spread')=>graph.nodes.find(n=>n.id===node.inputs.find(i=>i.slot===slot)?.id)??(()=>{throw unavailable();})();
  return `${node.rule==='scale_add'?node.multiplier!.value+' × ':''}${source('base').value} + (${source('spread').value}) = ${node.value}`;
}
