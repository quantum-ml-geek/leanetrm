export async function run({command,wait,click,set,submit,check,evaluate,idle,url}){
 await command('Runtime.enable');await command('Page.enable');await command('Page.navigate',{url:url+'/'});await wait("document.querySelectorAll('.curve-button').length>0&&"+idle);
 await click('#profile-open');await set('#profile','editor');await click('#open');await click('#example');
 await click('#profile-open');await set('#zone','UTC');await submit('#preferences-form');
 await click('#nav-parties');
 await check('party editors load versioned legal entities',"!document.querySelector('#party-form').hidden&&document.querySelector('#party-list').innerText.includes('Synthetic entity')");
 await set('#party-code','browser_entity');await set('#party-name','Synthetic browser entity');await set('#party-effective','2020-12-18T12:00');await submit('#party-form');
 await check('legal entity can be created through the shared business operation',"document.querySelector('#party-list').innerText.includes('Synthetic browser entity')&&document.querySelector('#party-saved').textContent.includes('revision 1')");
 await click('#party-list button[data-party-code="browser_entity"]');
 await check('identity code is immutable while name is editable',"document.querySelector('#party-code').disabled&&!document.querySelector('#party-fields').disabled");
 await set('#party-name','Synthetic browser entity revised');await set('#party-effective','2020-12-18T13:00');await submit('#party-form');
 await check('editing appends history and preserves original party name',"document.querySelector('#party-history').innerText.includes('Synthetic browser entity revised')&&[...document.querySelectorAll('#party-history tbody tr')].length===2&&document.querySelector('#party-saved').textContent.includes('revision 2')");
 await set('#party-kind','counterparty');await click('#party-new');await set('#party-code','browser_party');await set('#party-name','Synthetic browser counterparty');await set('#party-effective','2020-12-18T12:00');await submit('#party-form');
 await check('counterparties have the same versioned editor',"document.querySelector('#party-list').innerText.includes('Synthetic browser counterparty')");
 await click('#profile-open');await set('#profile','trader');await click('#open');await click('#example');await click('#nav-parties');
 await check('trader can inspect parties with read-only fields',"!document.querySelector('#party-read-only').hidden&&document.querySelector('#party-fields').disabled&&document.querySelector('#party-new').disabled");
 await click('#profile-open');await set('#profile','viewer');await click('#open');
 await check('identity change clears cached party records and hides unauthorized navigation',"document.querySelector('#nav-parties').hidden&&document.querySelector('#party-list').children.length===0&&document.querySelector('#party-name').value===''&&document.querySelector('#parties-page').hidden");
}
