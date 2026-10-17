import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {readdir,readFile,stat} from 'node:fs/promises';
import {dirname,join,resolve} from 'node:path';
import {withOwnedBrowser} from './owned-browser.mjs';

export async function checkProfileLifetime(targetFile,browserPath){
  const root=dirname(resolve(targetFile)),before=new Set(await readdir(root));
  let profile,descendant;
  try{
    await withOwnedBrowser(targetFile,browserPath,async()=>{
      const created=(await readdir(root)).filter(name=>name.startsWith('browser-')&&!before.has(name));
      assert.equal(created.length,1);
      profile=join(root,created[0]);
      descendant=spawn(process.execPath,['--input-type=module','-e',
        "import {writeFile} from 'node:fs/promises';process.stdin.once('data',async()=>{try{await writeFile(process.argv[1],'done');process.exit(0);}catch{process.exit(1);}});process.stdout.write('ready');",
        join(profile,'descendant-write')],{stdio:['pipe','pipe','inherit']});
      const [ready]=await once(descendant.stdout,'data',{signal:AbortSignal.timeout(5000)});
      assert.equal(ready.toString(),'ready');
    });
    assert.ok((await stat(profile)).isDirectory(),'Profile removed while an owned descendant still uses it');
    assert.equal(descendant.exitCode,null);
    const finished=once(descendant,'exit',{signal:AbortSignal.timeout(5000)});
    descendant.stdin.end('finish');
    const [status]=await finished;
    assert.equal(status,0);
    assert.equal(await readFile(join(profile,'descendant-write'),'utf8'),'done');
    console.log('PASS browser profile survives until owned descendants finish');
    return 1;
  }finally{
    if(descendant&&descendant.exitCode===null&&descendant.signalCode===null){
      const stopped=once(descendant,'exit',{signal:AbortSignal.timeout(5000)});
      descendant.kill('SIGKILL');await stopped;
    }
    descendant?.stdin.destroy();descendant?.stdout.destroy();
  }
}
