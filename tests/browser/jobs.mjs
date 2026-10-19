export async function run({command,evaluate,wait,click,set,submit,persona,check,idle,url}){
  await command('Runtime.enable');await command('Page.enable');
  await command('Page.navigate',{url:url+'/'});await wait("document.querySelectorAll('.curve-button').length>0&&"+idle);
  await persona('viewer');await click('#nav-jobs');
  await check('ordinary members can open Jobs & Infrastructure',"!document.querySelector('#jobs-page').hidden&&document.querySelector('#page-title').textContent==='Jobs & Infrastructure'");
  await check('members see shared node status without infrastructure controls',"document.querySelector('#jobs-nodes').textContent.includes('Synthetic shared worker')&&![...document.querySelectorAll('#jobs-nodes button')].some(b=>b.textContent==='Pause scheduling')");
  await click('#profile-open');await set('#zone','Asia/Tokyo');await submit('#preferences-form');
  await set('#job-name','Synthetic browser readiness');await set('#job-operation','worker_check');
  await evaluate(`(async()=>{const {localTimeValue}=await import(new URL('user-time.js',document.querySelector('script[type=module]').src));const due=new Date(Math.floor(Date.now()/1000)*1000+120000).toISOString(),expires=new Date(Math.floor(Date.now()/1000)*1000+3600000).toISOString();window.expectedJobDue=due;document.querySelector('#job-due').value=localTimeValue(due,'Asia/Tokyo',true);document.querySelector('#job-expires').value=localTimeValue(expires,'Asia/Tokyo',true);const prior=window.fetch;window.fetch=async(...args)=>{if(String(args[0]).endsWith('/jobs/create'))window.jobSubmission=JSON.parse(args[1].body);return prior(...args);};})()`);
  await set('#job-frequency','once');await set('#job-timeout','30');await set('#job-attempts','2');
  await submit('#job-create');
  await check('job entry resolves the selected user clock into a UTC request',"new Date(window.jobSubmission?.dueAt).getTime()===new Date(window.expectedJobDue).getTime()&&window.jobSubmission?.timeZone==='UTC'");
  await check('member creates a durable owned job',"document.querySelector('#jobs-table').textContent.includes('Synthetic browser readiness')&&document.querySelector('#error').hidden");
  await evaluate("[...document.querySelectorAll('#jobs-table button')].find(b=>b.textContent==='Pause').click()");await wait(idle);
  await check('owner can pause the job',"document.querySelector('#jobs-table').textContent.includes('paused')");
  await persona('editor');await click('#nav-jobs');
  await check('job entry zone label follows the newly selected account',"document.querySelector('#job-zone').textContent===document.querySelector('[data-user-time-zone]').textContent");
  await check('another member cannot discover the private job row',"!document.querySelector('#jobs-table').textContent.includes('Synthetic browser readiness')");
  await persona('admin');await click('#nav-jobs');
  await check('administrator can manage another member job',"document.querySelector('#jobs-table').textContent.includes('Synthetic browser readiness')&&[...document.querySelectorAll('#jobs-table button')].some(b=>b.textContent==='Resume')");
  await evaluate("[...document.querySelectorAll('#jobs-table button')].find(b=>b.textContent==='Cancel').click()");await wait(idle);
  await check('administrator cancellation is persisted',"document.querySelector('#jobs-table').textContent.includes('cancelled')&&document.querySelector('#error').hidden");
  await evaluate("[...document.querySelectorAll('#jobs-nodes button')].find(b=>b.textContent==='Pause scheduling').click()");await wait(idle);
  await check('explicit infrastructure operator queues a durable node command',"document.querySelector('#jobs-node-commands').textContent.includes('queued')&&document.querySelector('#error').hidden");
  await persona('viewer');await click('#nav-jobs');
  await check('owner sees the administrator outcome without stale controls',"document.querySelector('#jobs-table').textContent.includes('cancelled')&&![...document.querySelectorAll('#jobs-table button')].some(b=>['Pause','Resume','Cancel'].includes(b.textContent))");
}
