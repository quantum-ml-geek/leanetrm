export async function run({command,wait,click,set,submit,check,evaluate,idle,url,shot}){
  await command('Runtime.enable');await command('Page.enable');await command('Emulation.setDeviceMetricsOverride',{width:1440,height:1050,deviceScaleFactor:1,mobile:false});
  await command('Page.navigate',{url:url+'/'});await wait("document.querySelectorAll('.curve-button').length>0&&"+idle);
  await click('#example');await click('#nav-power');
  await check('Power TOUs lists the published ISO products for readers without authoring tools',"document.querySelectorAll('#tou-list tbody tr').length>=7&&document.querySelector('#tou-list').textContent.includes('Mon–Sat HE07–HE22')&&document.querySelector('#tou-editor').hidden");
  await check('power choices come from the catalog, with no typed holiday list',"document.querySelectorAll('#power-block option:not([value=\"\"])').length===3&&document.querySelectorAll('#power-minutes option:not([value=\"\"])').length===4&&document.querySelectorAll('#power-labels option').length===2&&['pjm','nyiso','isone','miso','spp','ercot','caiso'].every(code=>document.querySelector('#power-product option[value='+code+']'))&&!document.querySelector('#power-holiday-dates')");
  await check('economic TOU choices start unselected rather than assumed',"['power-product','power-block','power-minutes'].every(id=>document.querySelector('#'+id).value==='')");
  await set('#power-product','pjm');await set('#power-block','all');await set('#power-minutes','60');
  await check('index classifications are typed or chosen, never prefilled',"document.querySelector('#power-price-type').value===''&&document.querySelectorAll('#power-price-types option').length===2");
  await set('#power-price-type','Test');await set('#power-timing','End of day');
  await check('native power page loads both editable weekday grids',"document.querySelectorAll('#power-normal-grid tbody tr').length===7&&document.querySelectorAll('#power-holiday-grid tbody tr').length===7&&!document.querySelector('#power-form').hidden");
  await evaluate("(()=>{const s=document.querySelector('#power-contract');s.value=[...s.options].find(o=>o.textContent.startsWith('2021-03-01')).value;s.dispatchEvent(new Event('change'));})()");
  await submit('#power-form');
  await check('power example uses real curve price and March DST hours',"document.querySelector('#power-summary').textContent.includes('743 hours')&&document.querySelector('#power-summary').textContent.includes('7430 MWh')&&document.querySelector('#error').hidden");
  await set('#power-product','miso');await submit('#power-form');
  await check('MISO comparison visibly retains 744 hours',"document.querySelector('#power-summary').textContent.includes('744 hours')");
  await set('#power-product','pjm');await set('#power-block','peak');await submit('#power-form');
  await check('reference calendar holiday removes a peak weekday and is shown',"document.querySelector('#power-summary').textContent.includes('352 hours')&&document.querySelector('#power-holiday-note').textContent.includes('Mar 15, 2021')");
  await set('#power-labels','HB');await submit('#power-form');
  await check('HB display is available without shifting hours',"document.querySelector('#power-summary').textContent.includes('352 hours')&&document.querySelector('#power-intervals').textContent.includes('HB07')");
  await click('#power-normal-grid button[aria-pressed="true"]');
  await check('editing a cell invalidates the prior result',"document.querySelector('#power-result').hidden");
  await check('power screen contains no GUIDs',"!/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(document.querySelector('#power-page').innerText)");
  await shot('power-tou-standalone');
  await click('#nav-market');await check('original curve management remains available',"!document.querySelector('#market-page').hidden&&document.querySelectorAll('.curve-button').length===11");
}
