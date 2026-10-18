export async function run({command,wait,click,set,submit,check,evaluate,idle,url}){
 await command('Runtime.enable');await command('Page.enable');
 await command('Page.navigate',{url:url+'/'});await wait("document.querySelectorAll('.curve-button').length>0&&"+idle);
 await click('#profile-open');await set('#profile','trader');await click('#open');await click('#example');await click('#nav-futures');
 await check('amount cells show quantity and price units even when saved columns hide unit labels',"/MMBtu \\(IT\\)/.test(document.querySelector('#futures-holdings').innerText)&&/USD\\/MMBtu/.test(document.querySelector('#futures-holdings').innerText)");
 await check('futures decimal prices follow their 0.025 tick precision',"/\\d+\\.\\d{3} USD\\/MMBtu/.test(document.querySelector('#futures-holdings').innerText)");
 await click('#profile-open');await check('Profile contains no amount precision controls',"!document.querySelector('#precision-money')&&!document.querySelector('#precision-quantity')");await click('#profile-close');
 await click('#futures-holdings .tabulator-row');await wait("document.querySelector('#trade-editor').open&&!document.querySelector('#trade-amount-format').hidden");
 const revision=await evaluate("document.querySelector('#trade-revision').value");
 await set('#trade-amount-format-trade-money','3');await set('#trade-amount-format-trade-quantity','2');await click('#trade-amount-format button[data-role="trade"]');
 await check('deal precision saves independently of a financial amendment',"document.querySelector('#trade-amount-format [role=status]').textContent.includes('saved')&&document.querySelector('#trade-revision').value==="+JSON.stringify(revision));
 await click('#trade-editor-close');await click('#futures-refresh');
 await check('saved deal precision changes its quantity presentation while futures retain tick precision',"/\\d+\\.\\d{2} MMBtu/.test(document.querySelector('#futures-holdings').innerText)&&/\\d+\\.\\d{3} USD\\/MMBtu/.test(document.querySelector('#futures-holdings').innerText)");
 await check('numeric grid retains raw exact strings separately from formatted cell text',"[...document.querySelectorAll('#futures-holdings .tabulator-cell span[title]')].some(s=>s.title!==s.textContent&&/^-?\\d+(\\.\\d+)?$/.test(s.title))");
 await click('#nav-reference');await set('#reference-table','units');
 await check('common unit catalog and quantity conversion controls are visible',"!document.querySelector('#unit-converter').hidden&&document.querySelector('#reference').textContent.includes('MMBtu (IT)')&&document.querySelector('#reference').textContent.includes('bbl (42 US gal)')");
 const supplemental=await evaluate("[...document.querySelector('#unit-from').options].some(o=>o.value==='test_power_catalog_only')");
 if(supplemental){await click('#nav-reference');await set('#reference-table','quantity_specifications');await check('supplemental quantity definitions resolve labels in their own exact unit catalog',"document.querySelector('#reference').innerText.includes('Catalog kWh')&&document.querySelector('#error').hidden");await click('#nav-reference');await set('#reference-table','units');}
 await set('#unit-from','test_power_gigajoule');await set('#unit-to','test_power_quantity');await set('#unit-value','1');await submit('#unit-conversion-form');
 await check('nonterminating conversion fails visibly with no successful default result',"!document.querySelector('#error').hidden&&document.querySelector('#unit-conversion-result').textContent===''");
 await set('#unit-rounding','round');await set('#unit-decimals','6');await submit('#unit-conversion-form');
 await check('explicit final precision displays the converted amount with its actual unit',"document.querySelector('#unit-conversion-result').textContent==='0.277778 MWh · rounded using the selected precision'&&document.querySelector('#error').hidden");
 await set('#unit-value','2');await check('editing conversion inputs immediately invalidates the prior result',"document.querySelector('#unit-conversion-result').textContent===''");
 await set('#unit-from','test_liquid_petroleum_barrel');await set('#unit-to','test_liquid_us_gallon');await set('#unit-rounding','exact');await submit('#unit-conversion-form');
 await check('exact barrel conversion displays gallons without an inferred heating value',"document.querySelector('#unit-conversion-result').textContent==='84 US gal · exact'");
}
