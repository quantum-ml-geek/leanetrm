// Options (Trading): the option chain of a product's expiry at the selected close, read from the product's stored volatility
// surface, with each series' settlement, implied volatility and sensitivities as its fit stored them. A product with no
// surface at the close says so and sends the person to Vol surfaces, where a close is calibrated. Runs after the Vol
// surfaces suite of the exchange example, which leaves nymex_on calibrated at the latest working snapshot.
const q=JSON.stringify;
const page='#options-page';
const state=`document.querySelector(${q(page)}).dataset.state`;

export async function run({command,evaluate,wait,click,persona,check,idle,fitsWidth,url}){
 await command('Runtime.enable');await command('Page.enable');
 await command('Emulation.setDeviceMetricsOverride',{width:1440,height:1100,deviceScaleFactor:1,mobile:false});
 // Every surface and position read the page makes with its answer; and a switch that answers the next surface read as a
 // close with no surface, which this example's latest snapshot no longer is for either product.
 const {identifier}=await command('Page.addScriptToEvaluateOnNewDocument',{source:`
  window.optionCalls=[];window.optionsUnfitted=false;const send=window.fetch;
  window.fetch=async(input,init)=>{
   const path=String(typeof input==='string'?input:input.url),call=/[/](vol-surfaces[/]read|options[/]positions)$/.exec(path);
   if(!call)return send(input,init);
   const record={path:call[1],body:init?.body?JSON.parse(init.body):null};window.optionCalls.push(record);
   const response=await send(input,init);record.status=response.status;record.answer=await response.clone().json().catch(()=>null);
   if(call[1]==='vol-surfaces/read'&&response.ok&&window.optionsUnfitted)
    return new Response(JSON.stringify({...record.answer,state:'notFitted',surface:null,revision:null,job:null}),{status:200,headers:{'Content-Type':'application/json'}});
   return response;
  };`});
 const calls=path=>`window.optionCalls.filter(c=>c.path===${q(path)})`;
 const settled=(expression,ms)=>wait(expression,ms).catch(async error=>{throw Error(error.message+' · observed '+q(await evaluate(
  `({state:${state},error:document.querySelector('#options-error')?.textContent,calls:window.optionCalls.slice(-3).map(c=>[c.path,c.status,c.answer?.state??c.answer?.code])})`)));});
 const chip=product=>`document.querySelector('.options-product[data-product=${product}]')`;
 async function choose(product){
  await settled(`!!${chip(product)}&&${idle}`,30000);
  const reads=await evaluate(`${calls('vol-surfaces/read')}.length`);
  await click(`.options-product[data-product=${product}]`);
  await settled(`${calls('vol-surfaces/read')}.length>${reads}&&${calls('vol-surfaces/read')}.at(-1).status!==undefined&&${state}!=='loading'`,30000);
 }
 try{
  await command('Page.navigate',{url:url+'/?example=exchange'});await wait("document.querySelectorAll('.curve-button').length>0&&"+idle,60000);
  await persona('viewer');
  await check('Options is not listed for a market reader without Read trades',"document.querySelector('#nav-options')?.hidden===true");
  await persona('risk');
  await check('Options is listed in Trading for a reader of market data and trades',
   "(()=>{const n=document.querySelector('#nav-options');return !!n&&!n.hidden&&!!n.closest('#nav-group-trading');})()");
  await click('#example');await click('#nav-options');
  await settled(`document.querySelectorAll('.options-product').length>1&&${idle}`,30000);
  await check('the page is titled Options under Trading, names the working snapshot it reads and chooses no product',
   `document.querySelector('#page-title').textContent==='Options'&&document.querySelector('#page-section').textContent==='TRADING'&&
    document.querySelector('${page} .vol-eyebrow').textContent==='Working snapshot'&&/2026/.test(document.querySelector('#options-here').textContent)&&
    [...document.querySelectorAll('.options-product')].map(c=>c.dataset.product).sort().join()==='nymex_lo,nymex_on'&&!document.querySelector('.options-product[aria-pressed=true]')&&
    !!document.querySelector('#options-placeholder').offsetParent&&${calls('vol-surfaces/read')}.length===0`,
   `[document.querySelector('#page-title').textContent,document.querySelector('${page} .vol-hero').textContent,${state}]`);
  await check('the views not built yet are disabled and say Coming soon',
   `document.querySelector('#options-view-chain').getAttribute('aria-pressed')==='true'&&['positions','strategy'].every(view=>(b=>b.disabled&&/Coming soon/.test(b.textContent))(document.querySelector('#options-view-'+view)))`);

  await choose('nymex_on');
  await settled(`${state}==='fitted'&&!!document.querySelector('#options-chain tbody tr')`,30000);
  const surface=await evaluate(`${calls('vol-surfaces/read')}.at(-1).answer.surface`);
  const live=surface.expiries.filter(e=>e.status!=='option_expired'),first=live[0];
  const listed=new Set(surface.series.filter(s=>s.series.expiryAt===first.expiryAt).map(s=>s.series.strike));
  await check('the chain reads the stored surface and the held lots at the selected context, with the model stated',
   `(r=>r.status===200&&r.body.product==='nymex_on'&&r.body.model==='smile_quadratic_log_moneyness_v1'&&r.body.context.convention==='futures_option_premium_v1')(${calls('vol-surfaces/read')}.at(-1))&&
    (p=>p.status===200&&p.body.model==='smile_quadratic_log_moneyness_v1'&&Array.isArray(p.answer.held))(${calls('options/positions')}.at(-1))`,
   `${calls('options/positions')}.at(-1)`);
  await check('the chain opens on the first live expiry with one row per strike it lists and the at-the-money strike marked',
   `document.querySelectorAll('#options-expiries .vol-close-chip').length===${live.length}&&
    document.querySelector('#options-expiries [aria-current=true]').dataset.expiry===${q(first.expiryAt)}&&
    document.querySelectorAll('#options-chain tbody tr').length===${listed.size}&&
    [...document.querySelectorAll('#options-chain tr.options-atm')].map(r=>r.dataset.strike).join()===${q(first.atTheMoneyStrike??'')}&&
    document.querySelector('#options-facts').textContent.includes(${q(first.underlyingCode)})`,
   `[document.querySelectorAll('#options-chain tbody tr').length,[...document.querySelectorAll('#options-chain tr.options-atm')].map(r=>r.dataset.strike),document.querySelector('#options-facts').textContent]`);
  // Each side's delta is the stored figure to two decimals: a call's between 0 and 1, a put's between -1 and 0.
  const solved=surface.series.filter(s=>s.series.expiryAt===first.expiryAt&&s.analytics?.delta.value!=null);
  const shownDelta=code=>`[...document.querySelectorAll('#options-chain td[data-series=${q(code).slice(1,-1)}]')].map(td=>td.textContent)`;
  const call=solved.find(s=>s.series.right==='call'),put=solved.find(s=>s.series.right==='put');
  await check('each side shows its stored delta to two decimals, calls mirrored about the strike',
   `${q(!!call&&!!put)}&&(c=>c.length===7&&Math.abs(Number(c[4])-${Number(call?.analytics.delta.value)})<=0.005+1e-9&&/^0[.]\\d\\d$/.test(c[4]))(${shownDelta(call?.series.code??'')})&&
    (p=>p.length===7&&Math.abs(Number(p[2])-${Number(put?.analytics.delta.value)})<=0.005+1e-9&&/^-0[.]\\d\\d$/.test(p[2]))(${shownDelta(put?.series.code??'')})`,
   `[${shownDelta(call?.series.code??'')},${shownDelta(put?.series.code??'')}]`);
  await check('a figure the fit could not state is a dash that says why, never a zero',
   `[...document.querySelectorAll('#options-chain td.options-missing-figure')].every(td=>td.textContent==='—'&&td.title.length>0)&&
    ![...document.querySelectorAll('#options-chain td.numeric')].some(td=>/^-?0(\\.0+)?$/.test(td.textContent)&&!td.classList.contains('options-held'))`);
  await check('the page states what its figures are and that Risk reports keep their own',
   "/Per unit of quote/.test(document.querySelector('#options-basis').textContent)&&/option_sensitivities_layers_v1/.test(document.querySelector('#options-basis').textContent)");
  await check('the chain fits the page width',fitsWidth);

  await click(`#options-chain td[data-series="${call.series.code}"]`);
  await check('choosing a series shows its stored figures and offers its surface',
   `document.querySelector('#options-readout').textContent.includes(${q(call.series.code)})&&!!document.querySelector('#options-open-surface')&&
    document.querySelectorAll('#options-chain td.options-selected').length===7`,"document.querySelector('#options-readout').textContent");
  await click('#options-open-surface');
  await settled("document.querySelector('#page-title').textContent==='Vol surfaces'&&document.querySelector('.vol-product-card[aria-pressed=true]')?.dataset.product==='nymex_on'",30000);
  await check('Open on Vol surfaces opens the product\'s surface','true');

  // A close with no surface: the page says so and offers Vol surfaces, and draws no chain.
  await evaluate('window.optionsUnfitted=true');
  await click('#nav-options');await settled(`${state}==='notFitted'`,30000);
  await check('a product not calibrated at this close shows that and no chain',
   `!!document.querySelector('#options-missing').offsetParent&&/not calibrated at this close/.test(document.querySelector('#options-missing').textContent)&&
    !document.querySelector('#options-chain')?.offsetParent&&document.querySelector('#options-calibrate').textContent==='Calibrate on Vol surfaces →'`,
   "document.querySelector('#options-missing').textContent");
  await evaluate('window.optionsUnfitted=false');
  await click('#options-calibrate');
  await settled("document.querySelector('#page-title').textContent==='Vol surfaces'&&document.querySelector('.vol-product-card[aria-pressed=true]')?.dataset.product==='nymex_on'",30000);
  await check('the calibrate link opens the product on Vol surfaces','true');
 }finally{await command('Page.removeScriptToEvaluateOnNewDocument',{identifier});}
}
