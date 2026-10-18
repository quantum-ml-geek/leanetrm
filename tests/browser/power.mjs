export async function run({command,wait,click,set,submit,check,evaluate,idle,url,shot}){
  await command('Runtime.enable');await command('Page.enable');await command('Emulation.setDeviceMetricsOverride',{width:1440,height:1050,deviceScaleFactor:1,mobile:false});
  await command('Page.navigate',{url:url+'/'});await wait("document.querySelectorAll('.curve-button').length>0&&"+idle);
  const basis=async kind=>{await evaluate("(()=>{const s=document.querySelector('#power-quantity-basis');s.value=[...s.options].find(o=>o.textContent.startsWith("+JSON.stringify(kind==='flat_power'?'Flat MW':'Total MWh')+")).value;s.dispatchEvent(new Event('change'));})()");};
  await click('#example');await click('#nav-power');
  await check('native power page loads both editable weekday grids',"document.querySelectorAll('#power-normal-grid tbody tr').length===7&&document.querySelectorAll('#power-holiday-grid tbody tr').length===7&&!document.querySelector('#power-form').hidden");
  await evaluate("(()=>{const s=document.querySelector('#power-contract');s.value=[...s.options].find(o=>o.textContent.startsWith('2021-03-01')).value;s.dispatchEvent(new Event('change'));})()");
  await basis('flat_power');await submit('#power-form');
  await check('power example uses real curve price and March DST hours',"document.querySelector('#power-summary').textContent.includes('743 hours')&&document.querySelector('#power-summary').textContent.includes('7,430.000 MWh')&&document.querySelector('#error').hidden");
  await basis('total_energy');await set('#power-mw','1');await set('#power-allocation','flat_rate');await set('#power-quantity-precision','6');await set('#power-price-precision','6');await submit('#power-form');
  await check('total-energy entry preserves one MWh and displays explicit interval units',"document.querySelector('#power-summary').textContent.includes('1.000000 MWh')&&document.querySelector('#power-intervals').innerText.includes('MWh')");
  await check('local price precision applies to interval cells while exact prices remain available',"[...document.querySelectorAll('#power-intervals td[title]')].some(c=>/\\d+\\.\\d{6} USD\\/MWh/.test(c.textContent)&&/^-?\\d+(\\.\\d+)?$/.test(c.title))");
  await basis('flat_power');await set('#power-mw','10');
  await set('#power-product','miso');await submit('#power-form');
  await check('MISO comparison visibly retains 744 hours',"document.querySelector('#power-summary').textContent.includes('744 hours')");
  await set('#power-product','pjm');await set('#power-block','peak');await set('#power-holiday-dates','2021-03-15');await submit('#power-form');
  await check('holiday mask removes a supplied peak weekday',"document.querySelector('#power-summary').textContent.includes('352 hours')");
  await set('#power-labels','HB');await submit('#power-form');
  await check('HB display is available without shifting hours',"document.querySelector('#power-summary').textContent.includes('352 hours')&&document.querySelector('#power-intervals').textContent.includes('HB07')");
  await click('#power-normal-grid button[aria-pressed="true"]');
  await check('editing a cell invalidates the prior result',"document.querySelector('#power-result').hidden");
  await check('power screen contains no GUIDs',"!/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(document.querySelector('#power-page').innerText)");
  await shot('power-tou-standalone');
  await click('#nav-market');await check('original curve management remains available',"!document.querySelector('#market-page').hidden&&document.querySelectorAll('.curve-button').length===11");
  await click('#nav-power');await basis('flat_power');await submit('#power-form');
  await check('power has a cached result before permission refresh',"!document.querySelector('#power-result').hidden");
  const cookies=new Map();let csrf='';
  async function sideApi(path,body){
    const response=await fetch(url+'/api/'+path,{method:body===undefined?'GET':'POST',headers:{Origin:url,...(cookies.size?{Cookie:[...cookies.values()].join('; ')}:{}),...(body===undefined?{}:{'Content-Type':'application/json','X-Preview-CSRF':csrf})},body:body===undefined?undefined:JSON.stringify(body)});
    for(const cookie of response.headers.getSetCookie()){const part=cookie.split(';')[0];cookies.set(part.slice(0,part.indexOf('=')),part);}
    const data=await response.json();if(data.csrfToken)csrf=data.csrfToken;if(response.status!==200)throw Error('Synthetic access update failed: '+response.status);return data;
  }
  await sideApi('bootstrap');await sideApi('profile',{profile:'admin'});
  const viewer=(await sideApi('admin')).members.find(m=>m.login==='viewer');
  const changed=await sideApi('admin/update',{operationId:crypto.randomUUID(),id:viewer.id,expectedVersion:viewer.version,name:viewer.name,enabled:true,roles:[]});
  try{
    await click('#profile-open');
    await check('profile refresh after actual revocation clears every business panel',"document.querySelector('#power-page').hidden&&document.querySelector('#power-result').hidden&&document.querySelector('#power-intervals').children.length===0&&!document.querySelector('#no-access-page').hidden&&document.querySelector('#profile-access').textContent.includes('No workspace access')");
    await click('#profile-close');
  }finally{await sideApi('admin/update',{operationId:crypto.randomUUID(),id:viewer.id,expectedVersion:changed.version,name:viewer.name,enabled:true,roles:viewer.roles});}
  await click('#profile-open');
  await check('profile refresh restores currently granted access with the right user label',"document.querySelector('#profile-label').textContent==='Viewer'&&document.querySelector('#profile-access').textContent.includes('Read Market Data')&&document.querySelector('#no-access-page').hidden");await click('#profile-close');

}
