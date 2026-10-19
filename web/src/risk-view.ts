import {renderDataGrid} from './data-grid.js';
import {renderChart,clearChart} from './chart-view.js';
import {curveName,deliveryLabel,publicText} from './market-view.js';

type Api=<T>(path:string,body?:unknown)=>Promise<T>;
type Factor={seriesId:string;quote:string;curves:string[];deliveryFrom:string;deliveryTo:string;unit:string;value:string};
type Catalog={factors:Factor[];bumpConvention:string;convention:string;numericalPolicy:string};
type Scope={context:unknown;bookIds:string[];portfolioIds:string[]};
type Values={base:string;up:string;down:string;upPnl:string;downPnl:string;delta:string;gamma:string;currency:string;currencyReference:unknown;deltaUnit:string;gammaUnit:string};
type Report={context:{contextId:string};snapshotId:string;heldContracts:number;work:{positionCount:number;uniqueValuations:number;scenarioCount:number;unitPricerCalls:number;rebuiltCurveNodes:number;reusedCurveNodes:number;repeatedInstrumentReferences:number;quantityApplications:number};factors:{factor:Factor;bump:string;totals:{bookId:string;book:string;values:Values}[];positions:{book:string;curve:string;deliveryFrom:string;deliveryTo:string;values:Values}[]}[]};

export function setupRisk(options:{api:Api;act:(work:()=>Promise<void>)=>Promise<void>;busy:()=>boolean;canRun:()=>boolean;scope:()=>Scope;onDenied:()=>void}){
  const get=<T extends HTMLElement=HTMLElement>(id:string)=>document.getElementById(id) as T;
  const select=get<HTMLSelectElement>('risk-factor'),bump=get<HTMLInputElement>('risk-bump');
  let catalog:Catalog|undefined,scope:Scope|undefined,lastRequest:unknown;
  let grids:ReturnType<typeof renderDataGrid>[]=[];
  function results(){for(const grid of grids)grid.destroy();grids=[];get('risk-results').replaceChildren();get('risk-plots').querySelectorAll<HTMLElement>('.chart').forEach(panel=>clearChart(panel));get('risk-plots').replaceChildren();get('risk-work').textContent='';get('risk-export').hidden=true;lastRequest=undefined;}
  function reset(){results();catalog=undefined;scope=undefined;select.replaceChildren(new Option('Choose a factor…',''));bump.value='';get('risk-unit').textContent='';get('risk-card').hidden=true;}
  function sync(){get<HTMLFieldSetElement>('risk-fields').disabled=options.busy();get<HTMLButtonElement>('blotter-risk').disabled=options.busy()||!options.canRun();get('blotter-risk').title=options.canRun()?'Revalue selected books under shared market shocks':'Scenario execution requires the Risk Analyst role.';get<HTMLButtonElement>('risk-export').disabled=options.busy()||!lastRequest;get('risk-results').inert=options.busy();}
  async function call<T>(path:string,body:unknown):Promise<T>{try{return await options.api<T>(path,body);}catch(error){results();if((error as {code?:string}).code==='access_denied'){reset();options.onDenied();}throw error;}}
  async function open(){
    reset();scope=structuredClone(options.scope());catalog=await call<Catalog>('futures/risk/catalog',scope);
    select.replaceChildren(new Option('Choose a factor…',''),...catalog.factors.map(f=>new Option(publicText(`${f.curves.map(curveName).join(' / ')} · ${deliveryLabel(f.deliveryFrom,f.deliveryTo)}`),f.seriesId)));
    get('risk-card').hidden=false;sync();get('risk-card').scrollIntoView({block:'start',behavior:'smooth'});
  }
  function render(report:Report){
    results();
    for(const [factorIndex,item] of report.factors.entries()){
      const partitions=new Map<string,typeof item.totals>();
      for(const row of item.totals){const key=JSON.stringify(row.values.currencyReference);const group=partitions.get(key)??[];group.push(row);partitions.set(key,group);}
      for(const [partitionIndex,totals] of [...partitions.values()].entries()){
        const unit=totals[0].values;
        const title=document.createElement('h4');title.textContent=publicText(`${item.factor.curves.map(curveName).join(' / ')} · ${deliveryLabel(item.factor.deliveryFrom,item.factor.deliveryTo)} · absolute bump ±${item.bump} · unit ${item.factor.unit}`);get('risk-results').append(title);
        const host=document.createElement('div');host.className='table-wrap';get('risk-results').append(host);
        const headers=['Book',`Base execution P&L (${unit.currency})`,`Up execution P&L (${unit.currency})`,`Down execution P&L (${unit.currency})`,`Up change (${unit.currency})`,`Down change (${unit.currency})`,`Delta (${unit.deltaUnit})`,`Gamma (${unit.gammaUnit})`];
        const keys=['book','base','up','down','upPnl','downPnl','delta','gamma'];
        grids.push(renderDataGrid(host,`risk-totals-${factorIndex}-${partitionIndex}`,report.snapshotId+report.context.contextId,headers,totals.map(t=>[t.book,t.values.base,t.values.up,t.values.down,t.values.upPnl,t.values.downPnl,t.values.delta,t.values.gamma]),[1,2,3,4,5,6,7],options.busy,{keys,layout:{order:[],widths:{},sort:[]},onLayout:()=>{}}));
        const panel=document.createElement('div');panel.className='chart';get('risk-plots').append(panel);
        renderChart(panel,{title:'Execution P&L change by book',subtitle:`±${item.bump} quoted points · ${item.factor.unit}`,axis:'category',unit:unit.currency,kind:'bar',series:[
          {name:'Up shock',points:totals.map(t=>({x:t.bookId,label:t.book,y:t.values.upPnl}))},
          {name:'Down shock',points:totals.map(t=>({x:t.bookId,label:t.book,y:t.values.downPnl}))},
        ]});
      }
      const details=document.createElement('details'),summary=document.createElement('summary');summary.textContent='Individual holding results';details.append(summary);
      const rows=document.createElement('div');rows.className='table-wrap';details.append(rows);get('risk-results').append(details);
      // Initialize after opening: the virtual grid needs a visible width.
      let ready=false;details.ontoggle=()=>{if(!details.isConnected||!details.open||ready)return;ready=true;const keys=['book','market','contract','currency','base','upPnl','downPnl','delta','deltaUnit','gamma','gammaUnit'];
        grids.push(renderDataGrid(rows,`risk-positions-${factorIndex}`,report.snapshotId,['Book','Market','Contract','Currency','Base execution P&L','Up change','Down change','Delta','Delta unit','Gamma','Gamma unit'],item.positions.map(p=>[p.book,curveName(p.curve),deliveryLabel(p.deliveryFrom,p.deliveryTo),p.values.currency,p.values.base,p.values.upPnl,p.values.downPnl,p.values.delta,p.values.deltaUnit,p.values.gamma,p.values.gammaUnit]),[4,5,6,7,9],options.busy,{keys,layout:{order:[],widths:{},sort:[]},onLayout:()=>{}}));};
    }
    const w=report.work;get('risk-work').textContent=`${w.positionCount} holdings · ${report.heldContracts} held contracts · ${w.uniqueValuations} unit valuations · ${w.scenarioCount} scenarios · ${w.unitPricerCalls} pricer calls · ${w.repeatedInstrumentReferences} additional quantity references · ${w.quantityApplications} quantity applications · ${w.rebuiltCurveNodes} curve nodes evaluated · ${w.reusedCurveNodes} reused. Includes base evaluation.`;
    get('risk-export').hidden=false;
  }
  select.onchange=()=>{results();const factor=catalog?.factors.find(f=>f.seriesId===select.value);get('risk-unit').textContent=factor?`Base input ${factor.value} · bump unit: ${factor.unit}. Absolute symmetric up/down; all other selected inputs stay fixed.`:'';};
  bump.oninput=results;
  get<HTMLFormElement>('risk-form').onsubmit=event=>{event.preventDefault();void options.act(async()=>{
    results();if(!catalog||!scope)throw Error('Open shocks from the current blotter first.');
    const factor=catalog.factors.find(f=>f.seriesId===select.value);if(!factor)throw Error('Choose an exact dated quote input.');
    const request={...scope,bumps:[{seriesId:factor.seriesId,quote:factor.quote,size:bump.value,convention:catalog.bumpConvention}],convention:catalog.convention,numericalPolicy:catalog.numericalPolicy};
    const report=await call<Report>('futures/risk',request);render(report);lastRequest=request;sync();
  });};
  get('risk-export').onclick=()=>void options.act(async()=>{
    if(!lastRequest)throw Error('Run the selected shock before exporting.');const report=await call<Report>('futures/risk',lastRequest);
    const blob=new Blob([JSON.stringify(report,null,2)+'\n'],{type:'application/json'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='leanetrm-risk.json';link.click();URL.revokeObjectURL(url);
  });
  get('risk-close').onclick=reset;
  return {open,reset,sync};
}
