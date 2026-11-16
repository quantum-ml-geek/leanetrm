import {publicText} from './market-view.js';
import {chainExpiries,chainRows,measureReason,type Cell,type ChainSide} from './options-chain.js';
import {decimalText,hereHeading,volModel,type FuturesReadRequest,type SurfaceExpiry,type SurfaceSeries,type VolSurfaceFrames,type VolSurfaceResult} from './vol-surface-view.js';

// Options (Trading): the option chain of a product's expiry at the selected close, from the product's stored volatility
// surface. Every settlement, volatility and sensitivity is the backend's, as the surface's fit stored it; the page chooses
// what to show and formats it. A product with no surface at this close shows that, never another close's figures.
type Api=<T>(path:string,body?:unknown)=>Promise<T>;
type Job={state:string}|null;
type SurfaceRead={definitionRevisionId:string;snapshotId:string;model:string;state:'fitted'|'notFitted';job:Job;surface:VolSurfaceResult|null};
type ProductPage={definitionRevisionId:string;rows:Record<string,string|number|null>[];hasMore:boolean};
/** The open lots held in each series, as the positions read states them. */
type PositionsRead={model:string;held:{series:string;openLots:string}[]};

const active=(job:Job)=>!!job&&['queued','running','cancellation_requested'].includes(job.state);
const messageOf=(error:unknown)=>error instanceof Error?error.message:String(error);
const codeOf=(error:unknown)=>(error as {code?:string}).code;
function el<K extends keyof HTMLElementTagNameMap>(tag:K,className?:string,text?:string){
 const node=document.createElement(tag);if(className)node.className=className;if(text!==undefined)node.textContent=publicText(text);return node;
}
const button=(className:string,text:string,id?:string)=>{const b=el('button',className,text);b.type='button';if(id)b.id=id;return b;};
// Trailing zeros of an exact price, as a label shows it.
const trimmed=(value:string)=>value.includes('.')?value.replace(/0+$/,'').replace(/\.$/,''):value;

/**
 * The Options page. `refresh` reads the option products at the context, the chosen product's stored surface and the lots
 * held; `open` shows a product's chain at an expiry and series, as a link from its surface does; `reset` clears what an
 * earlier context showed. `openSurface` opens the product's volatility surface, where a close is calibrated.
 */
export function setupOptions(o:{api:Api;context:()=>FuturesReadRequest;zone:()=>string;frames:Pick<VolSurfaceFrames,'here'|'sessionName'>;
 openSurface:(product:string,definitionRevisionId:string,series?:string)=>void}){
 const root=document.getElementById('options-page')!;root.dataset.ownControls='';

 // The close in view, with the page's views beside it.
 const hero=el('header','vol-hero'),hereKind=el('span','vol-eyebrow'),hereTitle=el('h2','vol-here');hereTitle.id='options-here';
 const heroText=el('div');heroText.append(hereKind,hereTitle);
 const views=el('div','options-views');views.setAttribute('role','group');views.setAttribute('aria-label','Views');
 const chainView=button('options-view','Chain','options-view-chain');chainView.setAttribute('aria-pressed','true');
 const soon=(text:string,id:string)=>{const b=button('options-view',text,id);b.disabled=true;b.title='Coming soon';b.append(el('span','options-soon','Coming soon'));return b;};
 views.append(chainView,soon('Positions','options-view-positions'),soon('Strategy','options-view-strategy'));
 hero.append(heroText,views);
 const error=el('p','vol-error');error.id='options-error';error.setAttribute('role','alert');error.hidden=true;

 const productBar=el('nav','options-products');productBar.id='options-products';productBar.setAttribute('aria-label','Option products');
 const placeholder=el('div','vol-placeholder');placeholder.id='options-placeholder';
 placeholder.append(el('span','vol-placeholder-mark'),el('h3',undefined,'Choose an option product'),
  el('p',undefined,'Its chain is read from the volatility surface calibrated at this close.'));
 const missing=el('div','vol-missing');missing.id='options-missing';
 const expiryBar=el('nav','options-expiries');expiryBar.id='options-expiries';expiryBar.setAttribute('aria-label','Expiries');
 const facts=el('dl','options-facts');facts.id='options-facts';
 const tableHost=el('div','options-chain-host');
 const readout=el('aside','vol-card options-readout');readout.id='options-readout';readout.setAttribute('aria-live','polite');
 const basis=el('p','options-basis');basis.id='options-basis';
 const chain=el('section','options-chain-view');chain.append(expiryBar,facts,tableHost,readout,basis);
 root.replaceChildren(hero,error,productBar,placeholder,missing,chain);

 let products:{code:string;name:string}[]=[],moreProducts=false,definition:string|undefined,product='',expiryAt='',selected='',
  shown:SurfaceRead|undefined,held=new Map<string,string>(),generation=0;
 const instant=(at:string)=>new Intl.DateTimeFormat('en',{month:'short',day:'numeric',year:'numeric',hour:'numeric',minute:'2-digit',timeZone:o.zone()}).format(new Date(at));
 const expiryLabel=(e:SurfaceExpiry)=>new Intl.DateTimeFormat('en',{month:'short',day:'numeric',year:'numeric',timeZone:o.zone()}).format(new Date(e.expiryAt));

 function showHere(){
  let here;try{here=o.frames.here();}catch{here=undefined;}
  const heading=hereHeading(here,o.frames.sessionName,o.zone());hereKind.textContent=heading.kind;hereTitle.textContent=heading.title;
 }
 function failed(cause:unknown){
  root.dataset.state='error';error.hidden=false;
  error.textContent=publicText(`${messageOf(cause)}${codeOf(cause)&&!messageOf(cause).includes(codeOf(cause)!)?` (${codeOf(cause)})`:''}`);
  chain.hidden=true;missing.hidden=true;
 }
 function renderProducts(){
  productBar.replaceChildren(...products.map(entry=>{
   const chip=button('options-product','');chip.dataset.product=entry.code;chip.setAttribute('aria-pressed',String(entry.code===product));
   chip.append(el('span','options-product-name',entry.name),el('code','vol-card-code',entry.code));
   chip.onclick=()=>{if(product===entry.code)return;product=entry.code;expiryAt='';selected='';renderProducts();void readProduct();};
   return chip;
  }));
  if(!products.length)productBar.append(el('p','vol-empty-shelf','No option products in the reference data at this date.'));
  else if(moreProducts)productBar.append(el('span','options-more','More products are listed on Vol surfaces.'));
 }

 const cell=(figure:Cell,className='numeric')=>{
  const td=el('td',className,figure.text);if(figure.missing){td.title=measureReason(figure.missing);td.classList.add('options-missing-figure');}return td;
 };
 // One side's cells, call side mirrored so that each side's settlement sits beside the strike.
 function sideCells(side:ChainSide|null,right:'call'|'put'):HTMLTableCellElement[]{
  if(!side)return Array.from({length:7},()=>el('td','options-unlisted'));
  const heldCell=el('td','numeric options-held');if(side.heldLots!==null)heldCell.append(el('span','options-held-lots',side.heldLots));
  const cells=[el('td','numeric options-settle',side.settlement===null?'—':trimmed(side.settlement)),cell(side.impliedVolatility),cell(side.delta),cell(side.gamma),cell(side.vega),cell(side.theta),heldCell];
  for(const td of cells){
   td.dataset.series=side.code;td.dataset.right=right;td.classList.toggle('options-itm',side.inTheMoney===true);td.classList.toggle('options-selected',side.code===selected);
   td.onclick=()=>{selected=side.code;renderChain();};
  }
  return right==='call'?cells.reverse():cells;
 }
 function renderFacts(expiry:SurfaceExpiry){
  const fact=(term:string,value:string,id?:string)=>{const pair=el('div'),dd=el('dd',undefined,value);if(id)dd.id=id;pair.append(el('dt',undefined,term),dd);return pair;};
  facts.replaceChildren(fact('Underlying future',expiry.underlyingCode),fact('Settlement',expiry.futures===null?'—':trimmed(expiry.futures),'options-underlying-settlement'),
   fact('Expiry',instant(expiry.expiryAt)),fact('Days to expiry',expiry.daysToExpiry===null?'—':decimalText(expiry.daysToExpiry,{places:1})));
 }
 function renderReadout(series:SurfaceSeries|undefined){
  readout.replaceChildren(el('h3',undefined,'Selected series'));
  if(!series){readout.append(el('p','vol-readout-empty','Choose a call or a put in the chain to see its figures.'));return;}
  const analytics=series.analytics,list=el('dl');
  const row=(term:string,value:string)=>list.append(el('dt',undefined,term),el('dd',undefined,value));
  const stated=(measure:{value:string|null;missing:string|null}|undefined)=>measure?.value??(`— ${measureReason(measure?.missing??series.series.outcome)}`);
  row('Series',series.series.code);row('Settlement',series.series.settlement===null?'—':trimmed(series.series.settlement));
  row('Value',analytics?trimmed(analytics.value):`— ${measureReason(series.series.outcome)}`);
  row('Delta',stated(analytics?.delta));row('Gamma',stated(analytics?.gamma));row('Vega',stated(analytics?.vega));row('Theta',stated(analytics?.theta));
  if(analytics?.priceBump)row('Futures bump',trimmed(analytics.priceBump));
  const open=button('secondary','Open on Vol surfaces','options-open-surface');open.onclick=()=>o.openSurface(product,definition!,series.series.code);
  readout.append(list,open);
 }
 function renderChain(){
  const surface=shown!.surface!,expiries=chainExpiries(surface);
  if(!expiries.some(e=>e.expiryAt===expiryAt))expiryAt=expiries[0]?.expiryAt??'';
  expiryBar.replaceChildren(...expiries.map(expiry=>{
   const chip=button('vol-close-chip',expiryLabel(expiry));chip.dataset.expiry=expiry.expiryAt;
   if(expiry.expiryAt===expiryAt)chip.setAttribute('aria-current','true');else chip.onclick=()=>{expiryAt=expiry.expiryAt;selected='';renderChain();};
   return chip;
  }));
  const expiry=expiries.find(e=>e.expiryAt===expiryAt);
  if(!expiry){facts.replaceChildren();tableHost.replaceChildren(el('p','vol-empty-shelf','Every listed expiry of this product has passed.'));renderReadout(undefined);basis.textContent='';return;}
  renderFacts(expiry);
  const rows=chainRows(surface,expiryAt,held),table=el('table','options-chain');table.id='options-chain';
  const head=el('thead'),groups=el('tr','options-chain-groups'),names=el('tr');
  const group=(text:string,span:number)=>{const th=el('th',undefined,text);th.colSpan=span;th.scope='colgroup';return th;};
  groups.append(group('Calls',7),group('',1),group('Puts',7));
  const measures=['Settle','IV','Delta','Gamma','Vega','Theta','Held'];
  for(const name of [...[...measures].reverse(),'Strike',...measures]){const th=el('th',name==='Strike'?'options-strike':'numeric',name);th.scope='col';names.append(th);}
  head.append(groups,names);
  const body=el('tbody');
  for(const row of rows){
   const tr=el('tr');tr.dataset.strike=row.strike;tr.classList.toggle('options-atm',row.atTheMoney);
   const strike=el('th','options-strike',trimmed(row.strike));strike.scope='row';if(row.atTheMoney)strike.title='At the money: the listed strike nearest the underlying settlement';
   tr.append(...sideCells(row.call,'call'),strike,...sideCells(row.put,'put'));body.append(tr);
  }
  table.append(head,body);tableHost.replaceChildren(table);
  renderReadout(surface.series.find(s=>s.series.code===selected));
  const stated=surface.sensitivities;
  basis.textContent=stated?`Per unit of quote. Delta per 1.00 of the future’s price, gamma per 1.00 squared, vega per volatility point, theta for one day${stated.dayTo?` to ${instant(stated.dayTo)}`:''}. Held: open lots across your books. Sensitivities are the option model’s own (${stated.policy}); Risk reports keep theirs.`:'';
 }
 function render(){
  const read=shown;
  placeholder.hidden=!!product;error.hidden=true;
  if(!product||!read){chain.hidden=true;missing.hidden=true;root.dataset.state=product?'loading':'idle';return;}
  root.dataset.state=read.state;chain.hidden=read.state!=='fitted';missing.hidden=read.state==='fitted';
  if(read.state==='fitted'){renderChain();return;}
  const name=products.find(p=>p.code===product)?.name??product,text=el('div','vol-missing-text');
  text.append(el('h4',undefined,active(read.job)?`${name} is being calibrated at this close`:`${name} is not calibrated at this close`),
   el('p',undefined,'A chain is read from the surface fitted to one close’s option settlements. It is not carried to another day or session.'));
  const choices=el('div','vol-missing-actions'),go=button('',active(read.job)?'Follow it on Vol surfaces →':'Calibrate on Vol surfaces →','options-calibrate');
  go.onclick=()=>o.openSurface(product,definition!);choices.append(go);
  missing.replaceChildren(el('span','vol-missing-mark'),text,choices);
 }

 // Each read is numbered: an answer to a read that a newer one replaced is dropped.
 async function readProduct(){
  const number=++generation;shown=undefined;render();
  if(!product)return;
  try{
   const context=o.context();
   const [surface,positions]=await Promise.all([
    o.api<SurfaceRead>('vol-surfaces/read',{context,product,model:volModel,definitionRevisionId:definition}),
    o.api<PositionsRead>('options/positions',{context,model:volModel})]);
   if(number!==generation)return;
   if(surface.definitionRevisionId!==definition||surface.model!==volModel||surface.snapshotId!==context.snapshotId||(surface.state==='fitted')!==!!surface.surface||positions.model!==volModel)
    throw Error('The option chain read does not match the selected product, model and context. Refresh and try again.');
   shown=surface;held=new Map(positions.held.map(h=>[h.series,h.openLots]));render();
  }catch(cause){if(number===generation)failed(cause);}
 }
 async function refresh(){
  const number=++generation;showHere();root.dataset.state='loading';error.hidden=true;
  try{
   const params=new URLSearchParams({table:'futures_option_products',snapshotId:o.context().snapshotId,offset:'0',search:''});
   const page=await o.api<ProductPage>('reference/catalog?'+params);
   if(number!==generation)return;
   if(!page.definitionRevisionId)throw Error('The option directory changed. Refresh to read its published definition.');
   definition=page.definitionRevisionId;products=page.rows.map(row=>({code:String(row.code),name:String(row.name)}));moreProducts=page.hasMore;
   renderProducts();
  }catch(cause){if(number===generation)failed(cause);return;}
  await readProduct();
 }
 function reset(){generation++;products=[];definition=undefined;shown=undefined;held=new Map();productBar.replaceChildren();render();}
 return {
  refresh,
  /** Shows a product's chain, at an expiry and with a series selected where they are named. */
  async open(code:string,expiry?:string,series?:string){product=code;expiryAt=expiry??'';selected=series??'';await refresh();},
  leave(){generation++;},
  reset
 };
}
