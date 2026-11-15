import {idle} from './owned-browser.mjs';
// Explicit synthetic selections through the same controls a person uses.
export async function chooseCalendars({evaluate,set,wait},root,code){
 await wait(idle);
 const reference=JSON.stringify(['10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',code]);
 const ids=await evaluate(`[...document.querySelectorAll(${JSON.stringify(root+' [data-side-calendar]')})].filter(n=>!n.disabled&&n.getClientRects().length).map(n=>n.id)`);
 if(!ids.length)throw Error('No applicable calendar controls in '+root);
 for(const id of ids){
  const choice=`[...document.getElementById(${JSON.stringify(id)}).options].find(o=>o.value===${JSON.stringify(reference)})`;
  await wait(`!!(${choice})`);
  await set('#'+id,await evaluate(`(${choice}).value`));
  await wait(idle);
 }
}
