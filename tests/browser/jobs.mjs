export async function run({command,evaluate,wait,click,set,submit,persona,check,idle,url}){
  await command('Runtime.enable');await command('Page.enable');
  await command('Page.navigate',{url:url+'/'});await wait("document.querySelectorAll('.curve-button').length>0&&"+idle);
  await persona('viewer');await click('#nav-jobs');
  await check('ordinary members can open Jobs & Infrastructure',"!document.querySelector('#jobs-page').hidden&&document.querySelector('#page-title').textContent==='Jobs & Infrastructure'");
  await check('members see shared node status without infrastructure controls',"document.querySelector('#jobs-nodes').textContent.includes('Synthetic shared worker')&&![...document.querySelectorAll('#jobs-nodes button')].some(b=>b.textContent==='Pause scheduling')");
  await set('#job-name','Synthetic browser readiness');await set('#job-operation','worker_check');
  await evaluate("document.querySelector('#job-due').value=new Date(Date.now()+60000).toISOString().slice(0,19);document.querySelector('#job-expires').value=new Date(Date.now()+3600000).toISOString().slice(0,19)");
  await set('#job-frequency','once');await set('#job-timeout','30');await set('#job-attempts','2');
  await submit('#job-create');
  await check('member creates a durable owned job',"document.querySelector('#jobs-table').textContent.includes('Synthetic browser readiness')&&document.querySelector('#error').hidden");
  await evaluate("[...document.querySelectorAll('#jobs-table button')].find(b=>b.textContent==='Pause').click()");await wait(idle);
  await check('owner can pause the job',"document.querySelector('#jobs-table').textContent.includes('paused')");
  await persona('editor');await click('#nav-jobs');
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
