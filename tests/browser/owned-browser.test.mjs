import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {mkdtemp,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {waitForBrowserPort} from './owned-browser.mjs';

async function fixture(t,args=['-e','setInterval(()=>{},1000)']){
  const directory=await mkdtemp(join(tmpdir(),'openetrm-browser-port-'));
  const child=spawn(process.execPath,args,{stdio:'ignore'});
  t.after(async()=>{
    if(child.exitCode===null&&child.signalCode===null){const closed=once(child,'exit');child.kill('SIGTERM');await closed;}
    await rm(directory,{recursive:true,force:true});
  });
  return {directory,child,file:join(directory,'DevToolsActivePort')};
}

test('browser startup waits through missing, empty, partial and invalid port files',async t=>{
  const {directory,child,file}=await fixture(t);
  const outcome=waitForBrowserPort(directory,child).then(port=>({port}),error=>({error}));
  for(const content of [null,'','314','nonsense\n','0\n','65536\n','3.14\n','1e3\n']){
    if(content!==null)await writeFile(file,content);
    assert.equal(await Promise.race([outcome,delay(120).then(()=>null)]),null,
      'readiness must remain pending until a complete valid port line: '+JSON.stringify(content));
  }
  await writeFile(file,'31415\n/devtools/browser/synthetic');
  assert.deepEqual(await outcome,{port:31415});
});

test('browser startup accepts both valid port boundaries after a complete line',async t=>{
  for(const port of [1,65535]){
    const {directory,child,file}=await fixture(t);await writeFile(file,port+'\n');
    assert.equal(await waitForBrowserPort(directory,child),port);
  }
});

test('browser startup reports an owned process exit before readiness',async t=>{
  const {directory,child}=await fixture(t,['-e','process.exit(9)']);
  await assert.rejects(waitForBrowserPort(directory,child),/exited before readiness/);
});

test('browser startup reports an owned process signal before readiness',async t=>{
  const {directory,child}=await fixture(t);
  const outcome=waitForBrowserPort(directory,child);
  child.kill('SIGTERM');
  await assert.rejects(outcome,/exited before readiness/);
});

test('browser startup preserves a spawn error',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'openetrm-browser-port-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  const child=spawn(join(directory,'missing-browser'),[],{stdio:'ignore'});
  await assert.rejects(waitForBrowserPort(directory,child),{code:'ENOENT'});
});

test('browser startup retains its bounded readiness deadline for an invalid file',async t=>{
  const {directory,child,file}=await fixture(t);await writeFile(file,'invalid\n');
  const start=performance.now();
  await assert.rejects(waitForBrowserPort(directory,child,1000),/did not become ready/);
  assert.ok(performance.now()-start>=1000,'invalid content must not skip the readiness wait');
});
