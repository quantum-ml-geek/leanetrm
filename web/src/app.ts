import {setupPowerView} from './power-view.js';
import {setupAdministration} from './admin-view.js';
import {type Context,setupDateEditor} from './date-editor.js';
import {renderRegularTable,clearTableFilters} from './regular-table.js';
import {curveWorkbook,rateWorkbook,renderWorkbook} from './curve-workbook.js';
import {type PricingGraph,pricingGraph,pricingEquation} from './pricing-view.js';
import {type Row,type Frame,type Workspace,type CurveResult,type PriceHistory,val,publicText,friendly,curveName,exactRow,commodityName,marketType,marketGroups,displayInstant,deliveryMonth,frameOptions,quoteUnit,publicColumns,timeLabels,marketTypeName,allCurves,marketCategory,categoryName,displayDate,pointDate,pointIdentity,deliveryLabel,historyPriceLabel} from './market-view.js';
import {dataSections} from './data-sections.js';
import {type Preferences,newPreferences,loadPreferences,savePreferences,validTimeZone} from './preferences.js';
import {setupShortcutEditor,scheduleErrorMessage} from './shortcut-view.js';
import {setupTouProducts} from './tou-products.js';

const $=<T extends HTMLElement=HTMLElement>(id:string):T=>{const node=document.getElementById(id);if(!node)throw Error('This page could not load. Please refresh.');return node as T;};
const select=(id:string)=>$<HTMLSelectElement>(id);
const text=(id:string,value:string)=>{$(id).textContent=publicText(value);};
function el<K extends keyof HTMLElementTagNameMap>(tag:K,content?:string){const node=document.createElement(tag);if(content!==undefined)node.textContent=publicText(content);return node;}
function choose(id:string,options:{value:string;name:string}[],value:string){const node=select(id);node.replaceChildren(...options.map(o=>{const option=el('option',o.name);option.value=o.value;return option;}));node.value=value;}
let csrf='',workspace:Workspace|undefined,curve='',result:CurveResult|undefined,contract='',historyData:PriceHistory|undefined,pricingContract='',showAllContracts=false,input='',draftFor='',busy=false,page='market';
let contextDirty=false,contextOpen=false,currentProfile='',administrationScope='',permissions:string[]=[],profiles:{id:string;name:string;description?:string}[]=[];
const can=(permission:string)=>permissions.includes(permission);
const historicalContext=()=>(workspace as (Workspace & {context?:Context})|undefined)?.context;
const canCorrect=()=>can('ImportObservations')&&!historicalContext();
let prefs:Preferences=newPreferences(Intl.DateTimeFormat().resolvedOptions().timeZone);
const data=()=>{if(!workspace)throw Error('Market data is still loading.');return workspace;};
const frame=()=>{const found=data().frames.find(f=>f.id===select('snapshot').value);if(!found)throw Error('Choose a market date above.');return found;};
const selectedCurve=()=>exactRow(allCurves(data()),'code',curve);
const nameOf=(code:string)=>curveName(code,data());
const isRates=()=>!!curve&&marketType(selectedCurve(),data())==='rates';
const row=(table:string,key:string,value:string,reference=false)=>exactRow((reference?data().references:data().definitions)[table],key,value);
const observation=(id:string)=>exactRow(data().observations,'id',id);
const instant=(value:string)=>displayInstant(value,prefs.timeZone);
const unit=(quote:string)=>quoteUnit(quote,data());
function notice(message:string){text('notice',message);$('notice').hidden=false;}
function persist(){try{savePreferences(localStorage,currentProfile,prefs);}catch{notice('Your changes work for this visit, but this browser could not save your preferences.');}}
function loadProfile(){clearTableFilters();try{prefs=loadPreferences(localStorage,currentProfile,Intl.DateTimeFormat().resolvedOptions().timeZone);}catch{prefs=newPreferences(Intl.DateTimeFormat().resolvedOptions().timeZone);notice('Your saved profile could not be loaded. This visit uses your browser’s time zone. You can save your preferences in Profile.');}}
function syncControls(){
  document.querySelectorAll<HTMLButtonElement|HTMLInputElement|HTMLSelectElement|HTMLTextAreaElement>('button,input,select,textarea').forEach(n=>n.disabled=busy);
  if(!busy){$('save').toggleAttribute('disabled',!canCorrect());select('snapshot').disabled=!['market','power'].includes(page);}
  for(const id of ['source-contract','pricing-contract'])select(id).disabled=busy||showAllContracts||!result?.points.length;
  for(const id of ['source-all','pricing-all'])$<HTMLButtonElement>(id).disabled=busy||!result||!result.points.length||(result.points.length<2&&!showAllContracts);
  document.body.setAttribute('aria-busy',String(busy));renderContextPanel();
}
// The chip always states which market view is in force; the panel edits it.
function renderContextPanel(){
  const context=historicalContext(),state=contextDirty?'pending':context?'historical':'current',chip=$('context-toggle');
  chip.dataset.state=state;chip.hidden=!can('ReadMarketData')||page==='admin';
  text('context-chip-label',state==='pending'?'Market view not applied':context?`Historical · ${displayDate(context.effectiveOn)}`:'Current inputs');
  const open=!chip.hidden&&(contextOpen||contextDirty);$('date-context').hidden=!open;chip.setAttribute('aria-expanded',String(open));
}
async function api<T>(path:string,body?:unknown):Promise<T>{
  let response:Response;
  try{response=await fetch('/api/'+path,{method:body===undefined?'GET':'POST',credentials:'same-origin',headers:body===undefined?{}:{'Content-Type':'application/json','X-Preview-CSRF':csrf},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});}
  catch{throw Object.assign(Error(body!==undefined?'We could not confirm the result. Refresh and check the saved changes before saving again.':'The app could not connect. Please refresh the page.'),{code:'response_unknown'});}
  if(!response.ok){const error=await response.json().catch(()=>({code:'request_failed'}));const messages:Record<string,string>={power_historical:'Return to current inputs to use the unsaved power example. Historical clock publication is not supported yet.',power_units:'This example needs an outright curve quoted per MWh.',settlement_coverage:'The selected mask has no intervals or the fixing coverage is incomplete.',clock_tzdb:'The installed time-zone rules differ from the product clock’s declared release, or cannot be verified. Calculations are blocked until they match.',clock_rule:'This product’s market clock is incomplete or unknown in reference data.',power_calendar:'The settlement index calendar does not cover this whole delivery period.',tou_definition:'Supply a lowercase code, a name, a market clock and an ordered peak window.',tou_conflict:'This TOU product changed or its code is already used. Reload before editing.',clock_reference:'Choose a market clock from this workspace’s reference data.',power_index:'This curve needs a single settlement index with matching commodity, currency and unit.',power_input:'Complete the product, units and classification choices.',access_denied:'This demo user can’t make that change. You can switch users in Profile → Preview access.',revision_conflict:'This price has already changed. Refresh and choose the version you want in Price changes.',mutation_outcome_unknown:'We could not confirm whether your change was saved. Refresh and check the saved changes before saving again.',numeric_format:'Enter a number with no commas or spaces, using up to 18 decimal places.',missing_value:'Enter a new value before saving.',definition_rejected:'This value does not meet the contract’s price rules. Check the allowed range and settlement increment in Reference data.',snapshot_missing:'Choose an available market date.',request_token:'Please refresh the page before making this change.',request_cancelled:'This took too long. Please refresh and try again.',admin_conflict:'This account changed or the login name is already registered. Refresh accounts before editing.',last_administrator:'Keep at least one current administrator in this workspace.',self_access_change:'Another administrator must remove your administrative access.',admin_input:'Enter a name, login, identity kind and explicit roles.',admin_limit:'This preview has reached its account limit.',administration_outcome_unknown:'We could not confirm the change. Check accounts and recent access changes, then retry the retained request if necessary.'};throw Object.assign(Error(scheduleErrorMessage(error.code)??messages[error.code]??'The app could not complete that request. Please refresh and try again.'),{code:error.code});}
  return response.json() as Promise<T>;
}
async function act(work:()=>Promise<void>){
  // Context changes, writes and reads are serialized. Never retry a mutation.
  if(busy)return;busy=true;syncControls();$('error').hidden=true;text('status','Loading…');
  // The status line reports work in progress and failures; pages describe themselves.
  try{await work();text('status','');}
  catch(error){text('error',error instanceof Error?error.message:'Something went wrong. Please refresh the page.');$('error').hidden=false;text('status','Please check the message above.');}
  finally{busy=false;syncControls();}
}
function action(name:string,run:()=>Promise<void>){const button=el('button',name);button.disabled=busy;button.type='button';button.onclick=()=>void act(run);return button;}
function table(target:string,headers:string[],rows:(string|HTMLElement)[][],numeric:number[]=[]){
  const revision=data().definitions.revisions[0];
  const referenceScope=[data().profile,page,select('reference-table').value,revision.reference_catalog_id,revision.reference_revision_id];
  const marketScope=[data().profile,curve,result?.snapshotId??'',target==='history-values'?contract:'',target==='revisions'?input:'',...(['inputs','mappings'].includes(target)?[showAllContracts?'all':pricingContract]:[])];
  renderRegularTable($(target),target,JSON.stringify(target==='reference'?referenceScope:marketScope),headers,rows,numeric,()=>busy);
}

function chart(target:string,points:{x:string;y:string|null}[],description:string){
  const host=$(target);host.classList.remove('empty');const ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg');svg.setAttribute('viewBox','0 0 920 215');svg.setAttribute('role','img');svg.setAttribute('aria-label',publicText(description));
  const title=document.createElementNS(ns,'title');title.textContent=publicText(description);svg.append(title);
  if(!points.some(p=>p.y!==null)){host.replaceChildren(el('p','No prices available.'));return;}
  // Approximate numbers place pixels only. Server values remain exact strings.
  const ys=points.filter(p=>p.y!==null).map(p=>Number(p.y)),lo=Math.min(...ys),hi=Math.max(...ys),range=hi-lo||Math.max(Math.abs(lo)*.01,.01),pad=range*.2;
  const y=(n:number)=>175-(n-lo+pad)/(range+pad*2)*145,x=(i:number)=>64+i*820/Math.max(points.length-1,1);
  function shape(tag:string,attrs:Record<string,string>,value?:string){const n=document.createElementNS(ns,tag);Object.entries(attrs).forEach(([k,v])=>n.setAttribute(k,v));if(value!==undefined)n.textContent=publicText(value);svg.append(n);return n;}
  for(let i=0;i<4;i++){const n=lo-pad+(range+pad*2)*i/3;shape('line',{x1:'57',x2:'899',y1:String(y(n)),y2:String(y(n)),class:'grid'});shape('text',{x:'48',y:String(y(n)+3),'text-anchor':'end'},n.toFixed(3));}
  let connected=false;const path=points.map((p,i)=>{if(p.y===null){connected=false;return '';}const command=connected?'L':'M';connected=true;return `${command} ${x(i)} ${y(Number(p.y))}`;}).join(' ');shape('path',{d:path,class:'plot'});
  points.forEach((p,i)=>{if(p.y===null)return;const c=shape('circle',{cx:String(x(i)),cy:String(y(Number(p.y))),r:'4',class:'point'});const title=document.createElementNS(ns,'title');title.textContent=publicText(`${p.x}: ${p.y}`);c.append(title);if(i===0||i===points.length-1||i%Math.ceil(points.length/6)===0)shape('text',{x:String(x(i)),y:'202','text-anchor':'middle'},p.x);});host.replaceChildren(svg);
}
function clearPrices(){result=undefined;pricingContract='';contract='';historyData=undefined;$('history-card').hidden=true;input='';draftFor='';$('revision-card').hidden=true;text('build-info','');text('price-date','Choose a market date to view prices.');if(curve)renderSummary();$('curve-chart').classList.add('empty');text('curve-chart','Choose a market date above.');$('contracts').replaceChildren();$('inputs').replaceChildren();if(curve)renderDependencies();}
const pages:Record<string,{title:string;section:string;description:string}>={
  market:{title:'Curves & prices',section:'Markets',description:'Forward, futures and rate curves for a market date, with the prices behind them.'},
  power:{title:'Power TOUs',section:'Markets',description:'Apply an hour mask to a power contract and check hours, MWh and settlements.'},
  reference:{title:'Reference data',section:'Markets',description:'Units, currencies, locations, contracts and pricing conventions.'},
  configuration:{title:'Contract definitions',section:'Management',description:'Build contract date definitions from published schedules.'},
  schedules:{title:'Schedules',section:'Markets',description:'Published monthly date schedules and date lookup. Editors draft them; approvers publish.'},
  admin:{title:'Users & access',section:'Management',description:'Manage who can use this workspace and what they can do.'}
};
function setPage(next:string){
  page=next;$('power-page').hidden=next!=='power';select('snapshot').closest<HTMLElement>('.date-control')!.hidden=!['market','power'].includes(next);$('market-page').hidden=next!=='market';$('reference-page').hidden=next!=='reference';$('schedules-page').hidden=next!=='schedules';$('curve-date-editor').hidden=next!=='configuration';$('admin-page').hidden=next!=='admin';$('no-access-page').hidden=true;
  const meta=pages[next];text('page-title',meta.title);text('page-section',meta.section);text('page-description',meta.description);document.title=`${meta.title} · LeanETRM`;
  for(const name of Object.keys(pages))$('nav-'+name).classList.toggle('active',next===name);
  if(next==='reference')renderReference();
  text('status','');syncControls();
}
function showView(view:Preferences['tab']){document.querySelectorAll<HTMLElement>('.view').forEach(n=>n.hidden=n.id!==`view-${view}`);document.querySelectorAll<HTMLButtonElement>('.tab').forEach(b=>{const active=b.dataset.view===view;b.classList.toggle('active',active);b.setAttribute('aria-selected',String(active));});}
function renderLayout(){
  document.body.classList.toggle('sidebar-collapsed',prefs.sidebarCollapsed);document.body.classList.toggle('library-collapsed',prefs.libraryCollapsed);
  const sidebar=$('sidebar-toggle');sidebar.setAttribute('aria-expanded',String(!prefs.sidebarCollapsed));sidebar.setAttribute('aria-label',prefs.sidebarCollapsed?'Expand navigation':'Collapse navigation');sidebar.title=prefs.sidebarCollapsed?'Expand navigation':'Collapse navigation';sidebar.textContent=prefs.sidebarCollapsed?'›':'‹';
  for(const id of ['market-menu','settings-menu']){const group=$<HTMLDetailsElement>(id);group.open=prefs.sidebarCollapsed||!prefs.collapsedMenus.includes(id);group.querySelector('summary')!.hidden=prefs.sidebarCollapsed;}
  const library=$('library-toggle');library.setAttribute('aria-expanded',String(!prefs.libraryCollapsed));library.setAttribute('aria-label',prefs.libraryCollapsed?'Expand curve list':'Collapse curve list');library.title=prefs.libraryCollapsed?'Expand curve list':'Collapse curve list';$('curves').hidden=prefs.libraryCollapsed;
}
function renderFrames(value:string){const context=(data() as Workspace & {context?:Context}).context;const frames=context?data().frames.filter(f=>f.at.slice(0,10)===context.effectiveOn):data().frames;choose('snapshot',[{value:'',name:frames.length?'Choose a date…':'No inputs for this context date'},...frameOptions(frames,prefs.timeZone)],value);select('snapshot').title=`Times shown in ${prefs.timeZone}`;}
function renderBrowse(){
  const commodities=[...new Set(allCurves(data()).map(marketCategory))];
  choose('commodity',[{value:'all',name:'All markets'},...commodities.map(c=>({value:c,name:categoryName(c,data())}))],prefs.commodity);
  if(!commodities.includes(prefs.commodity)&&prefs.commodity!=='all'){select('commodity').append(new Option('Saved commodity unavailable',prefs.commodity));select('commodity').value=prefs.commodity;}
  select('browse-by').value=prefs.browseBy;document.querySelectorAll<HTMLButtonElement>('[data-type]').forEach(b=>{const active=b.dataset.type===prefs.marketType;b.classList.toggle('active',active);b.setAttribute('aria-pressed',String(active));});
  const groups=marketGroups(data(),prefs.browseBy,prefs.commodity,prefs.marketType);text('curve-count',String(groups.reduce((n,g)=>n+g.curves.length,0)));
  const owner=data().profile;
  $('curves').replaceChildren(...groups.map(group=>{const section=el('details'),key=prefs.browseBy+'|'+group.name;section.className='curve-group';section.open=!prefs.collapsedCurveGroups.includes(key);section.append(el('summary',group.name));
    section.ontoggle=()=>{if(!section.isConnected||data().profile!==owner)return;const closed=prefs.collapsedCurveGroups.includes(key);if(closed===!section.open)return;prefs.collapsedCurveGroups=section.open?prefs.collapsedCurveGroups.filter(k=>k!==key):[...prefs.collapsedCurveGroups,key].slice(-64);persist();};
    group.curves.forEach(c=>{const button=el('button');button.className='curve-button'+(c.code===curve?' selected':'');button.disabled=busy;button.setAttribute('aria-pressed',String(c.code===curve));button.append(el('span',nameOf(val(c,'code'))),el('small',marketTypeName(marketType(c,data()))));button.onclick=()=>void act(async()=>{curve=val(c,'code');clearPrices();renderContext();if(select('snapshot').value)await build();});section.append(button);});return section;}));
  if(!groups.length)$('curves').append(el('p','No curves match these choices.'));
}
function renderContext(){
  text('example-help',`${nameOf(data().example.curve)} · ${instant(data().example.at)}`);renderLayout();renderBrowse();$('welcome').hidden=!!curve;$('curve-detail').hidden=!curve;
  $('curve-power').hidden=!curve||marketCategory(selectedCurve())!=='test_power';
  if(curve){const c=selectedCurve(),kind=marketType(c,data());renderSummary();const category=categoryName(marketCategory(c),data());text('curve-kind',category===marketTypeName(kind)?category:`${category} · ${marketTypeName(kind)}`);text('curve-title',nameOf(curve));
    const specification=kind==='rates'?row('interest_rate_definitions','code',val(c,'interest_rate_code'),true):undefined;
    text('unit',specification?`${val(row('currencies','code',val(specification,'currency_code'),true),'display_code')} · % per year`:unit(val(c,'quote_code')));
    text('chart-title',kind==='rates'?'Zero-rate curve':kind==='futures'?'Futures curve':kind==='forwards'?'Forward curve':'Mixed curve');
    text('source-title',kind==='rates'?'Rates behind this curve':'Prices behind this curve');text('source-help',kind==='rates'?'Annual zero rates for the listed maturities.':'Prices and conversion factors for the selected market date.');text('history-help',kind==='rates'?'One maturity, followed over time.':'One contract, followed over time.');
    renderDependencies();if(result)renderInputs();}
  showView(prefs.tab);
}
function inputUnit(series:Row){
  if(data().definitions.rate_curve_points.some(p=>p.curve_code===curve&&p.series_id===series.id))return 'Annual rate (decimal)';
  if(series.quote_code)return unit(val(series,'quote_code'));const spec=row('value_specifications','code',val(series,'value_specification_code'),true);if(spec.kind==='dimensionless')return 'Ratio';
  const a=row('quantity_specifications','code',val(spec,'numerator_quantity_code'),true),b=row('quantity_specifications','code',val(spec,'denominator_quantity_code'),true);return `${commodityName(val(a,'commodity_code'),data())} ${val(row('units','code',val(a,'unit_code'),true),'symbol')} / ${commodityName(val(b,'commodity_code'),data())} ${val(row('units','code',val(b,'unit_code'),true),'symbol')}`;
}
function sourceName(series:Row){
  const rate=data().definitions.rate_curve_points.find(p=>p.curve_code===curve&&p.series_id===series.id);if(rate)return `Zero rate · ${displayDate(val(rate,'maturity'))}`;
  if(!series.contract_id)return 'Conversion factor';
  const direct=data().definitions.curves.filter(c=>c.rule==='direct'&&c.quote_code===series.quote_code&&data().definitions.curve_members.some(m=>m.curve_code===c.code&&m.contract_id===series.contract_id));
  return direct.length===1?nameOf(val(direct[0],'code')):'Market price';
}
function settlementText(){
  const target=row('settlement_targets','code',val(selectedCurve(),'settlement_target_code'),true);
  return target.kind==='future_series'?'Follows this futures contract':`${referenceName('price_index_definitions',val(target,'index_a_code'))}${target.index_b_code?' less '+referenceName('price_index_definitions',val(target,'index_b_code')):''}`;
}
// Convention labels come with the evaluated rate result; the formula below is only drawn for that exact policy.
function rateConvention(){
  if(!result||result.numericalPolicy!=='simple_actual365fixed_rational_to_even_18_v1'||!result.convention)throw Error('This interest-rate convention cannot be displayed yet.');
  return result.convention;
}
function renderSummary(){
  const items:{name:string;value:string;numeric?:boolean}[]=[];
  if(result&&curve){
    const rates=result.kind==='rates',front=result.points[0];
    if(front)items.push({name:rates?'Maturities':'Contracts',value:String(result.points.length)},{name:rates?'First maturity':'Front contract',value:rates?displayDate(pointDate(front)):deliveryLabel(front.deliveryFrom!,front.deliveryTo!)},{name:rates?'First zero rate (%)':'Front price',value:front.value,numeric:true});
    else items.push({name:'Contracts',value:'None remaining'});
    items.push(rates?{name:'Day count',value:rateConvention().dayCount}:{name:'Settlement',value:settlementText()});
  }
  $('curve-summary').hidden=!items.length;
  $('curve-summary').replaceChildren(...items.map(item=>{const group=el('div'),value=el('dd',item.value);if(item.numeric)value.className='numeric';group.append(el('dt',item.name),value);return group;}));
  const context=historicalContext(),banner=$('curve-mode');banner.hidden=!curve||contextDirty||(!context&&!canCorrect());
  banner.dataset.tone=context?'historical':'editor';
  text('curve-mode',context?`Historical view: ${displayDate(context.effectiveOn)}${context.knownAt?`, as known at ${instant(context.knownAt)}`:''}. Prices are read-only; return to current inputs to make changes.`:'You can correct source prices on the Price sources tab. Every earlier version stays available.');
}
function renderPrices(){
  if(!result)return;renderSummary();const rates=result.kind==='rates';if(result.availability==='no_remaining_contracts'){pricingContract='';contract='';historyData=undefined;$('history-card').hidden=true;text('price-date',`Market date: ${instant(result.at)}`);text('build-info','No remaining delivery days');text('curve-chart','No remaining delivery days for this market date.');$('contracts').replaceChildren();renderDependencies();renderInputs();return;}
  chart('curve-chart',result.points.map(p=>({x:rates?displayDate(pointDate(p)):deliveryLabel(p.deliveryFrom!,p.deliveryTo!),y:p.value})),`${nameOf(result.curve)} by ${rates?'maturity':'delivery period'}`);
  text('price-date',`Market date: ${instant(result.at)}`);text('build-info',`${result.points.length} ${rates?(result.points.length===1?'rate sample':'rate samples'):(result.points.length===1?'contract':'contracts')}`);
  table('contracts',rates?['Maturity','Zero rate (%)','Discount factor','']:['Delivery period','Price','Expires',''],result.points.map(p=>[rates?displayDate(pointDate(p)):deliveryLabel(p.deliveryFrom!,p.deliveryTo!),p.value,rates?p.displayDiscountFactor!:instant(p.expiry!),action(rates?'Rate history':'Price history',async()=>{contract=pointIdentity(p);await history();})]),rates?[1,2]:[1]);
  if(historyData)renderHistory();renderDependencies();renderInputs();
}
async function build(){
  if(contextDirty)throw Error('Apply the changed context before viewing prices.');
  const f=frame();if(!curve)throw Error('Choose a curve first.');const next=await api<CurveResult>('evaluate',{snapshotId:f.id,curve});result=next;renderPrices();
}
function renderHistory(){
  if(!result||!historyData)return;const p=result.points.find(p=>pointIdentity(p)===contract);if(!p)throw Error('Please select this sample again.');const rates=result.kind==='rates';$('history-card').hidden=false;text('history-title',`${rates?displayDate(pointDate(p)):deliveryLabel(p.deliveryFrom!,p.deliveryTo!)} · ${rates?'rate':'price'} history`);
  const labels=timeLabels(historyData.points.map(p=>p.at),prefs.timeZone);
  chart('history-chart',historyData.points.map((p,i)=>({x:labels[i],y:p.value})),`${rates?'Rates':'Prices'} over time`);
  table('history-values',['Market date',rates?'Zero rate (%)':'Price'],historyData.points.map((p,i)=>[labels[i],historyPriceLabel(p)]),[1]);
}
async function history(){if(!result||!contract)return;historyData=undefined;$('history-card').hidden=true;historyData=await api<PriceHistory>('history',{snapshotId:result.snapshotId,curve:result.curve,...(result.kind==='rates'?{seriesId:contract}:{contractId:contract})});renderHistory();}
function renderInputs(){
  if(!result||!result.points.length){text('inputs',result?'No price sources are needed for an empty delivery window.':'Choose a market date to view price sources.');text('input-count','');return;}
  const used=new Set(pricingPoints().flatMap(p=>p.lineage));if([...used].some(id=>!frame().observationIds.includes(id)))throw Error('A required source observation is missing from this market date.');const obs=[...used].map(observation);text('input-count',`${obs.length} prices & factors`);
  table('inputs',[isRates()?'Maturity':'Delivery period','Input','Source','Value','Units',''],obs.map(o=>{const series=row('series','id',val(o,'series_id')),c=series.contract_id?row('contracts','id',val(series,'contract_id')):undefined;return [c?deliveryLabel(val(c,'delivery_from'),val(c,'delivery_to')):data().definitions.rate_curve_points.some(p=>p.curve_code===curve&&p.series_id===series.id)?displayDate(val(data().definitions.rate_curve_points.find(p=>p.curve_code===curve&&p.series_id===series.id)!,'maturity')):'All months',sourceName(series),referenceName('sources',val(o,'source_code')),val(o,'value'),inputUnit(series),action(canCorrect()?'Correct price':'View versions',async()=>{input=val(o,'id');renderRevisions();})];}),[3]);renderRevisions();
}
function renderRevisions(){
  if(!input||!frame().observationIds.includes(input)||!pricingPoints().some(p=>p.lineage.includes(input))){$('revision-card').hidden=true;return;}
  const o=observation(input),series=row('series','id',val(o,'series_id'));$('revision-card').hidden=false;text('correction-description',`${sourceName(series)} · ${instant(val(o,'observed_at'))} · ${inputUnit(series)}`);
  const editor=canCorrect();$('correction-form').hidden=!editor;text('changes-title',`${editor?'Correct':'Versions of'} this ${isRates()?'rate':'price'}`);
  text('edit-help',isRates()?'Enter an annual decimal rate: 0.025 means 2.5%. Earlier versions stay available.':'Earlier prices stay available. Saving adds a new version for you to view.');
  if(draftFor!==input){$<HTMLInputElement>('correction-value').value=val(o,'value');draftFor=input;}
  const revisions=data().observations.filter(r=>r.series_id===o.series_id&&r.source_code===o.source_code&&r.source_event_id===o.source_event_id&&r.observed_at===o.observed_at&&r.role===o.role);
  table('revisions',['Version','Value','Saved',''],revisions.map((r,i)=>[i===0?'Original':`Change ${i}`,val(r,'value'),instant(val(r,'received_at')),r.id===input?'Viewing':action('View this version',async()=>{const next=await api<{frame:Frame}>('select-observation',{snapshotId:frame().id,observationId:r.id});clearPrices();await reload(next.frame.id);input=val(r,'id');await build();})]),[1]);
}
function pricingPoint(){
  if(!result)throw Error('Choose a market date first.');
  const point=result.points.find(p=>pointIdentity(p)===pricingContract);
  if(!point)throw Error('Choose a contract for the pricing breakdown.');return point;
}
function pricingPoints(){
  if(!result||!result.points.length)throw Error('The contract pricing details are unavailable.');
  return showAllContracts?result.points:[pricingPoint()];
}
function drawPricingGraph(target:HTMLElement,graph:PricingGraph){
  const ns='http://www.w3.org/2000/svg',svg=document.createElementNS(ns,'svg');
  const levels=Math.max(...graph.depth.values())+1,counts=Array.from({length:levels},(_,i)=>graph.nodes.filter(n=>graph.depth.get(n.id)===i));
  const nodeWidth=220,step=246;const width=levels*step+30,height=Math.max(1,...counts.map(g=>g.length))*130+35;
  svg.setAttribute('viewBox',`0 0 ${width} ${height}`);svg.style.minWidth=`${width}px`;svg.setAttribute('role','img');
  svg.setAttribute('aria-label',publicText(`Source contracts leading to ${nameOf(graph.root.curve)}. Exact values appear in the tables below.`));
  function shape(tag:string,attrs:Record<string,string>,value?:string,parent:Element=svg){const node=document.createElementNS(ns,tag);Object.entries(attrs).forEach(([k,v])=>node.setAttribute(k,v));if(value!==undefined)node.textContent=publicText(value);parent.append(node);return node;}
  const positions=new Map<string,{x:number;y:number}>();
  counts.forEach((group,level)=>group.forEach((node,i)=>positions.set(node.id,{x:12+level*step,y:20+(height-40-group.length*130)/2+i*130})));
  for(const node of graph.nodes){const end=positions.get(node.id)!;for(const input of node.inputs){const start=positions.get(input.id)!;const x=start.x+nodeWidth,y=start.y+59,ex=end.x,ey=end.y+59;
    shape('path',{d:`M ${x} ${y} C ${x+22} ${y}, ${ex-22} ${ey}, ${ex-7} ${ey}`,class:'flow-edge '+input.slot});
    shape('path',{d:`M ${ex-12} ${ey-4} L ${ex-5} ${ey} L ${ex-12} ${ey+4}`,class:'flow-arrow '+input.slot});
}}
  graph.nodes.forEach((node,index)=>{const p=positions.get(node.id)!,g=shape('g',{});const isOutput=node.id===graph.root.id;
    shape('rect',{x:String(p.x),y:String(p.y),width:String(nodeWidth),height:'119',rx:'8',class:'flow-node'+(isOutput?' output':'')},undefined,g);
    shape('text',{x:String(p.x+12),y:String(p.y+19),class:'flow-step'},`${index+1} · ${node.rule==='direct'?(node.use==='frozen'?'Final settlement':'Source price'):isOutput?'Selected contract':'Calculated price'}`,g);
    shape('text',{x:String(p.x+12),y:String(p.y+40),class:'flow-name'},nameOf(node.curve),g);
    shape('text',{x:String(p.x+12),y:String(p.y+57),class:'flow-date'},deliveryLabel(node.deliveryFrom,node.deliveryTo),g);
    shape('text',{x:String(p.x+12),y:String(p.y+80),class:'flow-value'},node.value,g);
    shape('text',{x:String(p.x+12),y:String(p.y+100),class:'flow-unit'},unit(node.quote),g);
    shape('title',{},`${nameOf(node.curve)} · ${displayDate(node.deliveryFrom)} to ${displayDate(node.deliveryTo)} (end excluded): ${pricingEquation(node,graph)}; ${node.value} ${unit(node.quote)}`,g);
    if(node.multiplier)shape('text',{x:String(p.x+nodeWidth-5),y:String(p.y+17),'text-anchor':'end',class:'flow-multiplier'},`× ${node.multiplier.value}`,g);
  });
  const summary=el('div');summary.className='flow-summary';summary.append(el('span',`${nameOf(graph.root.curve)} · ${deliveryLabel(graph.root.deliveryFrom,graph.root.deliveryTo)}`),el('strong',`${graph.root.value} ${unit(graph.root.quote)}`));
  const legend=el('div');legend.className='flow-legend';for(const [label,kind] of [['Base price','base'],['Spread','spread']]){const item=el('span',label);item.className=kind;legend.append(item);}
  const help=el('p','Arrows show the exact base and spread contracts used. Conversion factors appear on the calculation that uses them.');help.className='field-help';target.replaceChildren(summary,legend,svg,help);
}
function renderDependencies(){
  document.body.classList.toggle('showing-all-contracts',showAllContracts&&!!result);
  for(const id of ['source-flow','dependencies','mappings','inputs'])$(id).replaceChildren();$('revision-card').hidden=true;
  for(const id of ['source-all','pricing-all']){text(id,showAllContracts?'Show selected contract':'Show all contracts');$(id).setAttribute('aria-pressed',String(showAllContracts));}
  if(!result||!result.points.length){for(const id of ['source-flow','dependencies'])$(id).replaceChildren(el('p',result?'No remaining delivery days for this market date.':'Choose a market date to see the contract pricing breakdown.'));for(const id of ['source-contract','pricing-contract'])choose(id,[],'');return;}
  if(!result.points.some(p=>pointIdentity(p)===pricingContract))pricingContract=pointIdentity(result.points[0]);
  const points=pricingPoints(),rates=result.kind==='rates',options=result.points.map(p=>({value:pointIdentity(p),name:rates?displayDate(pointDate(p)):deliveryLabel(p.deliveryFrom!,p.deliveryTo!)}));
  for(const id of ['source-contract','pricing-contract'])choose(id,options,pricingContract);
  const sources=document.createDocumentFragment(),dependencies=document.createDocumentFragment();
  if(rates){
    const convention=rateConvention();
    if(showAllContracts){for(const container of [sources,dependencies]){const host=el('section');renderWorkbook(host,rateWorkbook(result));container.append(host);}}
    for(const point of points){
      if(point.annualRate===undefined||point.actualDays===undefined||point.discountFactor===undefined||point.displayDiscountFactor===undefined)throw Error('The rate calculation details are unavailable.');
      if(!showAllContracts)for(const container of [sources,dependencies]){const section=el('section');section.className='contract-flow pricing-flow';section.append(el('h4',displayDate(pointDate(point))));const flow=el('div');flow.className='rate-flow';
        for(const [title,value,detail] of [['Zero rate',`${point.value}%`,'Annual rate'],['Time to maturity',`${point.actualDays} / 365`,convention.dayCount],['Discount factor',point.displayDiscountFactor,convention.compounding]]){const card=el('div');card.className='rate-step';card.append(el('small',title),el('strong',value),el('span',detail));flow.append(card);}
        section.append(flow);container.append(section);}
    }
    table('mappings',['Maturity','Calculation','Discount factor'],points.map(p=>[displayDate(pointDate(p)),`1 ÷ (1 + ${p.annualRate} × ${p.actualDays} / 365)`,p.discountFactor!]),[2]);
  }else{
    const graphs=points.map(point=>pricingGraph(result!,point));
    if(showAllContracts){for(const container of [sources,dependencies]){const host=el('section');renderWorkbook(host,curveWorkbook(result,unit,nameOf));container.append(host);}}
    else for(const graph of graphs)for(const container of [sources,dependencies]){const section=el('section');section.className='contract-flow pricing-flow';drawPricingGraph(section,graph);container.append(section);}
    table('mappings',['Delivery period','Step','Curve','Calculation','Result','Units'],graphs.flatMap(graph=>graph.nodes.map((n,i)=>[deliveryLabel(graph.root.deliveryFrom,graph.root.deliveryTo),String(i+1),`${nameOf(n.curve)} · ${deliveryLabel(n.deliveryFrom,n.deliveryTo)}`,pricingEquation(n,graph),n.value,unit(n.quote)])),[4]);
    $('mappings').append(el('p',`Settlement: ${settlementText()}.`));
  }
  $('source-flow').replaceChildren(sources);$('dependencies').replaceChildren(dependencies);
}

function referenceName(table:string,code:string){const r=row(table,'code',code,true);if(typeof r.name==='string')return r.name.replace(/^Synthetic /,'');if(typeof r.symbol==='string')return r.symbol;if(typeof r.display_code==='string')return r.display_code;return friendly(code);}
const linkedTables:Record<string,string>={commodity_code:'commodities',fuel_commodity_code:'commodities',output_commodity_code:'commodities',currency_code:'currencies',quote_currency_code:'currencies',unit_code:'units',lot_unit_code:'units',from_unit_code:'units',to_unit_code:'units',quote_unit_code:'units',fuel_unit_code:'units',output_unit_code:'units',location_code:'locations',type_code:'location_types',exchange_code:'exchanges',clearing_house_code:'clearing_houses',source_code:'sources',product_code:'futures_products',series_code:'futures_series',clock_code:'clock_rules',market_clock_code:'clock_rules',calendar_code:'calendars',trading_calendar_code:'calendars',quantity_code:'quantity_specifications',basis_code:'measurement_bases',index_a_code:'price_index_definitions',index_b_code:'price_index_definitions',numerator_quantity_code:'quantity_specifications',denominator_quantity_code:'quantity_specifications'};
function referenceValue(r:Row,key:string){
  if(r[key]===null)return '—';const value=val(r,key);if(value==='true'||value==='false')return value==='true'?'Yes':'No';if(linkedTables[key])return referenceName(linkedTables[key],value);
  if(key.endsWith('_at'))return instant(value);if(key==='code')return friendly(value);
  if(/^-?\d+(\.\d+)?$/.test(value)||['name','symbol','display_code','zone_name','series_label','delivery_from','delivery_to','event_date','date','locator','evidence'].includes(key))return value;
  return friendly(value);
}
function renderReference(){
  if(contextDirty)return;
  const groups=dataSections(Object.keys(data().references)),sections=groups.flatMap(g=>g.sections),previous=select('reference-table').value;
  const selected=sections.some(s=>s.value===previous)?previous:sections[0]?.value;
  if(!selected)throw Error('These details are unavailable. Please refresh the page.');
  select('reference-table').replaceChildren(...groups.map(g=>{const group=document.createElement('optgroup');group.label=g.name;group.append(...g.sections.map(s=>{const option=el('option',s.name);option.value=s.value;return option;}));return group;}));select('reference-table').value=selected;
  const group=groups.find(g=>g.sections.some(s=>s.value===selected))!;
  text('data-title',group.sections.find(s=>s.value===selected)!.name);text('data-description',group.description);
  const rows=data().references[selected],columns=publicColumns(rows);table('reference',columns.map(c=>c.name),rows.map(r=>columns.map(c=>referenceValue(r,c.key))));
}
async function reload(selected:string){workspace=await api<Workspace>('workspace');renderFrames(selected);renderContext();renderReference();}
function updateFilters(){
  prefs.browseBy=select('browse-by').value as Preferences['browseBy'];prefs.commodity=select('commodity').value;persist();
  if(curve&&!marketGroups(data(),prefs.browseBy,prefs.commodity,prefs.marketType).some(g=>g.curves.some(c=>c.code===curve))){curve='';clearPrices();}
  renderContext();syncControls();
}
function openProfile(){
  const zones=[...new Set(['UTC',prefs.timeZone,...Intl.supportedValuesOf('timeZone')])];choose('zone',zones.map(z=>({value:z,name:z.replaceAll('_',' ')})),prefs.timeZone);select('preferred-browse').value=prefs.browseBy;$<HTMLDialogElement>('profile-dialog').showModal();
}
$('sidebar-toggle').onclick=()=>{if(busy)return;prefs.sidebarCollapsed=!prefs.sidebarCollapsed;renderLayout();persist();};
$('library-toggle').onclick=()=>{if(busy)return;prefs.libraryCollapsed=!prefs.libraryCollapsed;renderLayout();persist();};
for(const id of ['market-menu','settings-menu'])$<HTMLDetailsElement>(id).ontoggle=()=>{if(!currentProfile||prefs.sidebarCollapsed)return;const closed=prefs.collapsedMenus.includes(id),open=$<HTMLDetailsElement>(id).open;if(closed===!open)return;prefs.collapsedMenus=open?prefs.collapsedMenus.filter(k=>k!==id):[...prefs.collapsedMenus,id];persist();};
$('profile-open').onclick=openProfile;for(const id of ['profile-close','profile-cancel'])$(id).onclick=()=>$<HTMLDialogElement>('profile-dialog').close();
$('preferences-form').onsubmit=event=>{event.preventDefault();void act(async()=>{const zone=select('zone').value;if(!validTimeZone(zone))throw Error('Choose a valid time zone.');const selected=select('snapshot').value;prefs.timeZone=zone;prefs.browseBy=select('preferred-browse').value as Preferences['browseBy'];persist();if(workspace){renderFrames(selected);renderContext();renderPrices();renderReference();schedules.refresh();dateEditor.refresh();}administration.refresh();$<HTMLDialogElement>('profile-dialog').close();});};
async function profileChoices(){const boot=await api<{profiles:{id:string;name:string;description:string}[];customProfiles:{id:string;name:string}[]}>('bootstrap');profiles=[...boot.profiles,...boot.customProfiles.filter(p=>!boot.profiles.some(base=>base.id===p.id))];choose('profile',profiles.map(p=>({value:p.id,name:p.name})),currentProfile);renderIdentity();}
function renderIdentity(){
  const person=profiles.find(p=>p.id===currentProfile),name=person?.name??'Profile';
  text('profile-name',name);text('profile-detail',person?.description??'');text('profile-initials',name.split(/\s+/).map(w=>w[0]).join('').slice(0,2).toUpperCase());
}
async function loadIdentity(){
  curve='';clearPrices();workspace=undefined;permissions=[];choose('snapshot',[{value:'',name:'Choose a date…'}],'');select('snapshot').closest<HTMLElement>('.date-control')!.hidden=true;$('reference').replaceChildren();$('curves').replaceChildren();$('market-page').hidden=true;$('reference-page').hidden=true;$('schedules-page').hidden=true;$('curve-date-editor').hidden=true;$('admin-page').hidden=true;$('date-context').hidden=true;
  permissions=(await api<{permissions:string[]}>('access')).permissions;loadProfile();
  // Navigation follows current permissions; the backend still authorizes every operation.
  const read=can('ReadMarketData'),author=read&&(can('WriteMarketDefinitions')||can('SealMarketDefinitions')),manage=can('ManageAccess')&&can('ManageIdentities');
  for(const id of ['nav-market','nav-power','nav-reference','nav-schedules'])$(id).hidden=!read;
  $('nav-configuration').hidden=!author;$('schedule-inspector').hidden=!author;
  $('nav-admin').hidden=!manage;$('market-menu').hidden=!read;$('settings-menu').hidden=!author&&!manage;
  if(read){workspace=await api<Workspace>('workspace');renderFrames('');renderContext();setPage('market');}
  else if(manage){setPage('admin');await administration.load();renderLayout();}
  else{$('no-access-page').hidden=false;text('page-title','Workspace access');text('page-section','Account');text('page-description','');text('status','This account has no current workspace permissions.');}
}
$('open').onclick=()=>void act(async()=>{power.reset();touProducts.reset();schedules.reset();dateEditor.reset();administration.reset();contextDirty=false;contextOpen=false;text('environment-context-note','Current workspace · exact selected inputs');const next=select('profile').value;await api('profile',{profile:next});currentProfile=next;await loadIdentity();await profileChoices();$<HTMLDialogElement>('profile-dialog').close();});
$('snapshot').onchange=()=>void act(async()=>{clearPrices();if(page==='power'){power.reset();if(select('snapshot').value)await power.load();}else if(select('snapshot').value&&curve)await build();});
$('example').onclick=()=>void act(async()=>{await currentInputs();const f=data().frames.find(f=>data().initialFrameIds.includes(f.id)&&new Date(f.at).getTime()===new Date(data().example.at).getTime());if(!f)throw Error('These sample prices are unavailable.');prefs.commodity='all';prefs.marketType='all';prefs.tab='prices';persist();curve=data().example.curve;clearPrices();renderFrames(f.id);renderContext();await build();});
$('browse-by').onchange=()=>void act(async()=>updateFilters());$('commodity').onchange=()=>void act(async()=>updateFilters());
document.querySelectorAll<HTMLButtonElement>('[data-type]').forEach(b=>b.onclick=()=>void act(async()=>{prefs.marketType=b.dataset.type as Preferences['marketType'];updateFilters();}));
document.querySelectorAll<HTMLButtonElement>('.tab').forEach(b=>b.onclick=()=>{if(busy)return;prefs.tab=b.dataset.view as Preferences['tab'];persist();showView(prefs.tab);});
const schedules=setupShortcutEditor(act,{load:()=>api('schedules'),preview:draft=>api('schedules/preview',draft),keep:draft=>api('schedules/keep',draft),resolve:body=>api('schedules/resolve',body)},()=>busy,()=>prefs.timeZone);
function dirtyContext(){power.reset();contextDirty=true;if(workspace)clearPrices();$('reference').replaceChildren();text('environment-context-note','Context changed · choose View this context to apply it.');renderContextPanel();}
const administration=setupAdministration(act,api,()=>busy,()=>prefs.timeZone,()=>administrationScope+':'+currentProfile,profileChoices);
$('nav-admin').onclick=()=>void act(async()=>{setPage('admin');await administration.load();});
const dateEditor=setupDateEditor(act,api,()=>busy,()=>prefs.timeZone,dirtyContext);
$('date-context').addEventListener('input',dirtyContext);
async function applyContext(){
  const context=await dateEditor.context();
  const snapshot=await api<{context:Context}>('market/context',{effectiveOn:context.effectiveOn,knownAt:context.knownAt,mode:'at',selection:'latest_correction'});
  dateEditor.setContext(snapshot.context);contextDirty=false;clearPrices();await reload('');
  text('environment-context-note','Historical view · latest corrections known at the chosen time. Changes are disabled.');
}
$('apply-view-context').onclick=()=>void act(applyContext);
$('context-toggle').onclick=()=>{if(busy)return;contextOpen=!contextOpen;renderContextPanel();if(contextOpen)$('date-context-on').focus();};
$('context-close').onclick=()=>{if(busy)return;contextOpen=false;renderContextPanel();};
async function currentInputs(){power.reset();await api('market/current',{});contextDirty=false;dateEditor.clearContext();clearPrices();await reload('');text('environment-context-note','Current workspace · exact selected inputs');}
$('current-view-context').onclick=()=>void act(currentInputs);
const power=setupPowerView({api,act,name:nameOf,source:()=>{if(contextDirty)throw Error('Apply the changed market context first.');const f=frame();return {snapshotId:f.id,curve,name:instant(f.at)};}});
const touProducts=setupTouProducts(act,api,()=>busy,()=>prefs.timeZone,async()=>{power.reset();if(select('snapshot').value)await power.load();});
$('nav-power').onclick=$('curve-power').onclick=()=>void act(async()=>{setPage('power');power.reset();await touProducts.load();if(select('snapshot').value)await power.load();});
$('nav-schedules').onclick=()=>{if(busy)return;setPage('schedules');void act(async()=>{await schedules.load();await dateEditor.load();});};
$('nav-configuration').onclick=()=>{if(busy)return;void act(async()=>{if(contextDirty)await applyContext();setPage('configuration');await dateEditor.load();});};$('nav-market').onclick=()=>void act(async()=>{if(contextDirty)await applyContext();setPage('market');});$('nav-reference').onclick=()=>void act(async()=>{if(contextDirty)await applyContext();setPage('reference');});$('reference-table').onchange=()=>{try{renderReference();}catch{notice('These reference details are unavailable. Please choose another category.');}};
for(const id of ['source-contract','pricing-contract'])select(id).onchange=()=>void act(async()=>{pricingContract=select(id).value;input='';draftFor='';renderDependencies();renderInputs();});
for(const id of ['source-all','pricing-all'])$(id).onclick=()=>void act(async()=>{showAllContracts=!showAllContracts;renderDependencies();renderInputs();});
$('history-close').onclick=()=>{$('history-card').hidden=true;historyData=undefined;contract='';};
$('correction-form').onsubmit=event=>{event.preventDefault();void act(async()=>{const current=frame(),next=await api<{frame:Frame;observationId:string}>('corrections',{snapshotId:current.id,observationId:input,value:$<HTMLInputElement>('correction-value').value});clearPrices();await reload(next.frame.id);input=next.observationId;await build();notice('Your change was saved. The market date now shows the corrected prices. Earlier versions are still available.');});};
void act(async()=>{const boot=await api<{csrfToken:string;profiles:{id:string;name:string}[];profile:string|null;runId:string;tenantId:string;workspaceId:string}>('bootstrap');csrf=boot.csrfToken;administrationScope=[boot.runId,boot.tenantId,boot.workspaceId].join(':');
  // Synthetic sign-in is an explicit loopback preview facility only.
  currentProfile=boot.profile??'viewer';if(!boot.profile)await api('profile',{profile:currentProfile});await loadIdentity();await profileChoices();});
