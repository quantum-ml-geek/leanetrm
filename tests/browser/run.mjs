import {withOwnedBrowser} from './owned-browser.mjs';
import {run as administration} from './administration.mjs';
import {run as marketContext} from './market-context.mjs';
import {run as power} from './power.mjs';
if(process.argv.length!==4)throw Error('Invoke through tools/run_preview.py --browser-check --browser /path/to/browser');
let total=0;
for(const [name,run] of [['market context',marketContext],['administration',administration],['power TOUs',power]]){
  const passed=await withOwnedBrowser(process.argv[2],process.argv[3],run);total+=passed;console.log(`${passed} ${name} browser checks passed.`);
}
console.log(`${total} owned browser checks passed.`);
