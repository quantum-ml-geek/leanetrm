import test from 'node:test';
import assert from 'node:assert/strict';
import {browserAvailable,browserTestTimeout,withBrowserPage} from './browser-page.mjs';

// The Options page drawn in a real browser over synthetic reads: no application runtime, account or database is attached.
const page='<link rel="stylesheet" href="/app.css"><section id="options-page"></section>';
const setup=`
 const {setupOptions}=await import('/options-view.js');
 const expiry='2027-01-26T19:30:00+00:00',model='smile_quadratic_log_moneyness_v1';
 const measure=(value,missing=null)=>({value,missing});
 const analytics=delta=>({value:'0.167',priceBump:'0.012',delta:measure(delta),gamma:measure('1.987955334753591876'),vega:measure('0.001634163476493991'),theta:measure('-0.00412')});
 const series=(code,right,strike,inTheMoney,extra={})=>({series:{code,right,strike,expiryAt:expiry,underlyingCode:'ng_f27',settlement:'0.1670',outcome:'solved',marketVolatility:'0.4512'},
  logMoneyness:'0',fitted:'0.45',richCheap:'0.0012',fitPoint:true,inTheMoney,analytics:analytics(right==='call'?'0.523':'-0.477'),...extra});
 const surface={modelId:model,strikeAxis:['3','3.25'],
  sensitivities:{policy:'option_sensitivities_layers_v1',ticks:1,priceSteps:2,volatilityBump:'0.01',clockSource:'request',clockZone:'UTC',dayTo:'2026-10-17T17:00:00+00:00'},
  expiries:[{expiryAt:expiry,underlyingCode:'ng_f27',futures:'3.01',status:'fitted',parameters:{a:'0.45',b:'-0.1',c:'0.8'},points:5,rmsResidual:'0.001',maxAbsResidual:'0.002',grid:[],atTheMoneyStrike:'3',daysToExpiry:'102.104'}],
  series:[series('c3','call','3',false),series('p3','put','3',false),series('c325','call','3.25',false,{analytics:{...analytics('0.3'),vega:measure(null,'sensitivity_unstable')}}),series('p325','put','3.25',true)]};
 const figure=(amount,missing=null)=>({amount,missing});
 const positions={model,held:[{series:'c3',openLots:'2'}],totals:[{currency:'USD',value:figure('4000.000000000000000000'),theta:figure(null,'theta_days_differ')}],
  groups:[{underlyingSeries:'ng_f27',expiryAt:expiry,product:'synthetic_on',productName:'Synthetic gas options',definitionRevisionId:'definition-held',currency:'USD',quantityUnit:'MMBtu',
    sensitivities:surface.sensitivities,
    rows:[{tradeId:'t1',bindingId:'b1',tradeReference:'TR-000001',bookId:'bk',book:'Synthetic options',series:'c3',right:'call',strike:'3',openLots:'2',state:'analysed',reason:null,
      value:figure('3340.000000000000000000'),delta:figure('10460.000000000000000000'),gamma:figure('39759.106695071837520000'),vega:figure('32.683269529879820000'),theta:figure('-82.400000000000000000')}],
    subtotal:{value:figure('3340.000000000000000000'),delta:figure('10460.000000000000000000'),gamma:figure('39759.106695071837520000'),vega:figure('32.683269529879820000'),theta:figure('-82.400000000000000000')}},
   {underlyingSeries:'cl_g27',expiryAt:'2027-02-23T19:30:00+00:00',product:'synthetic_lo',productName:'Synthetic crude options',definitionRevisionId:'definition-other',currency:'USD',quantityUnit:'bbl',sensitivities:null,
    rows:[{tradeId:'t2',bindingId:'b2',tradeReference:'TR-000002',bookId:'bk',book:'Synthetic options',series:'lo70',right:'call',strike:'70',openLots:'4',state:'notCalibrated',reason:'not_calibrated',
      value:figure(null,'not_calibrated'),delta:figure(null,'not_calibrated'),gamma:figure(null,'not_calibrated'),vega:figure(null,'not_calibrated'),theta:figure(null,'not_calibrated')}],
    subtotal:{value:figure(null,'incomplete'),delta:figure(null,'incomplete'),gamma:figure(null,'incomplete'),vega:figure(null,'incomplete'),theta:figure(null,'incomplete')}}]};
 const calls=[],opened=[],booked=[];let fitted=true,failPositions=false;
 const api=async(path,body)=>{
  calls.push(path.split('?')[0]);
  if(path.startsWith('reference/catalog'))return {definitionRevisionId:'definition-a',rows:[{code:'synthetic_on',name:'Synthetic gas options'},{code:'synthetic_lo',name:'Synthetic crude options'}],hasMore:false};
  if(path==='options/positions'){if(failPositions)throw Object.assign(Error('The positions could not be read.'),{code:'synthetic_failure'});return positions;}
  if(path==='vol-surfaces/read')return {definitionRevisionId:'definition-a',snapshotId:'synthetic-close',model,state:fitted?'fitted':'notFitted',job:null,surface:fitted?surface:null};
  throw Error('unexpected read '+path);
 };
 const options=setupOptions({api,context:()=>({snapshotId:'synthetic-close',convention:'futures_option_premium_v1',knowledgeMode:'current'}),zone:()=>'UTC',
  frames:{here:()=>({closeId:null,at:'2026-10-16T17:00:00Z',close:null}),sessionName:code=>code},
  openSurface:(product,definition,series)=>opened.push([product,definition,series??null]),book:series=>booked.push(series)});
 const $=selector=>document.querySelector(selector),all=selector=>[...document.querySelectorAll(selector)];
 const tick=()=>new Promise(resolve=>setTimeout(resolve,0)),state=()=>$('#options-page').dataset.state;
`;
const browser=(name,body,expected)=>test(name,{skip:!browserAvailable,timeout:browserTestTimeout},()=>withBrowserPage(page,async evaluate=>{
 assert.deepEqual(await evaluate(`(async()=>{${setup}${body}})()`),expected);
}));

browser('the chain draws the stored surface: calls mirrored about the strike, the money marked, a missing figure a dash that says why',`
 await options.refresh();
 const idle={state:state(),products:all('.options-product').map(c=>c.dataset.product),chosen:all('.options-product[aria-pressed=true]').length,placeholder:!$('#options-placeholder').hidden,reads:calls.filter(c=>c==='vol-surfaces/read').length};
 all('.options-product')[0].click();await tick();await tick();
 const row=strike=>all('#options-chain tbody tr').find(r=>r.dataset.strike===strike),cells=(strike,right)=>[...row(strike).querySelectorAll('td[data-right='+right+']')].map(td=>td.textContent);
 const missing=row('3.25').querySelector('td.options-missing-figure');
 return {idle,state:state(),expiry:$('#options-expiries [aria-current=true]').dataset.expiry===expiry,strikes:all('#options-chain tbody tr').map(r=>r.dataset.strike),
  atTheMoney:all('#options-chain tr.options-atm').map(r=>r.dataset.strike),call3:cells('3','call'),put3:cells('3','put'),
  inTheMoney:all('#options-chain td.options-itm').map(td=>td.dataset.series).filter((code,i,list)=>list.indexOf(code)===i),
  missing:[missing.dataset.series,missing.textContent,missing.title],facts:$('#options-facts').textContent,basis:/option_sensitivities_layers_v1/.test($('#options-basis').textContent)&&/Risk reports keep theirs/.test($('#options-basis').textContent)};
`,{idle:{state:'idle',products:['synthetic_on','synthetic_lo'],chosen:0,placeholder:true,reads:0},state:'fitted',expiry:true,strikes:['3','3.25'],atTheMoney:['3'],
 call3:['2','-0.004120','0.001634','1.988','0.52','45.1%','0.167'],put3:['0.167','45.1%','-0.48','1.988','0.001634','-0.004120',''],inTheMoney:['p325'],
 missing:['c325','—','Estimates at the half, whole and double bump did not agree'],facts:'Underlying futureng_f27Settlement3.01ExpiryJan 26, 2027, 7:30 PMDays to expiry102.1',basis:true});

browser('a chosen series can be booked or opened on its surface, and a product with no surface says so and links to where it is calibrated',`
 await options.open('synthetic_on');await tick();
 $('#options-chain td[data-series=p325]').click();
 const readout=$('#options-readout').textContent,selected=all('#options-chain td.options-selected').length;
 $('#options-book').click();$('#options-open-surface').click();
 fitted=false;await options.refresh();await tick();
 const panel={state:state(),shown:!$('#options-missing').hidden&&/not calibrated at this close/.test($('#options-missing').textContent),chain:$('.options-chain-view').hidden};
 $('#options-calibrate').click();
 return {readout:/p325/.test(readout)&&/Delta-0.477/.test(readout),selected,booked,opened,panel};
`,{readout:true,selected:7,booked:['p325'],opened:[['synthetic_on','definition-a','p325'],['synthetic_on','definition-a',null]],panel:{state:'notFitted',shown:true,chain:true}});

browser('positions list the rows, subtotals and totals the backend states with their units, and a product with no surface links to its own definition',`
 await options.refresh();$('#options-view-positions').click();
 const body=underlying=>all('#options-position-table tbody').find(b=>b.dataset.underlying===underlying),text=node=>[...node.querySelectorAll('td,th')].map(c=>c.textContent);
 const gas=body('ng_f27'),crude=body('cl_g27');
 crude.querySelector('.options-position-calibrate').click();
 return {state:state(),products:$('#options-products').hidden,note:gas.querySelector('.options-position-group').textContent,
  row:text(gas.querySelector('tr[data-series=c3]')),subtotal:text(gas.querySelector('.options-position-subtotal')),
  uncalibrated:[crude.querySelector('tr[data-series=lo70]').dataset.state,...text(crude.querySelector('tr[data-series=lo70]')).slice(3)],
  total:text($('#options-position-table .options-position-total')),totalWhy:$('#options-position-table .options-position-total td.options-missing-figure').title,opened};
`,{state:'positions',products:true,note:'ng_f27Synthetic gas options · expires Jan 26, 2027, 7:30 PM · money in USD, delta and gamma in MMBtu · theta for the day to Oct 17, 2026, 5:00 PM',
 row:['TR-000001','Synthetic options','c3','2','3,340.00','10,460','39,759','32.68','-82.40'],subtotal:['Subtotal · ng_f27','3,340.00','10,460','39,759','32.68','-82.40'],
 uncalibrated:['notCalibrated','4','—','—','—','—','—'],total:['Total · USD','4,000.00','','','','—'],totalWhy:'These thetas run to different days, so they are not one sum',
 opened:[['synthetic_lo','definition-other',null]]});

browser('a read that fails is said, and stays said while the person changes view, until a read succeeds',`
 failPositions=true;await options.refresh();
 const failed={state:state(),error:!$('#options-error').hidden&&/could not be read/.test($('#options-error').textContent)};
 $('#options-view-positions').click();const afterPositions={state:state(),error:!$('#options-error').hidden};
 $('#options-view-chain').click();const afterChain={state:state(),error:!$('#options-error').hidden};
 failPositions=false;await options.refresh();
 return {failed,afterPositions,afterChain,recovered:{state:state(),error:!$('#options-error').hidden}};
`,{failed:{state:'error',error:true},afterPositions:{state:'error',error:true},afterChain:{state:'error',error:true},recovered:{state:'idle',error:false}});
