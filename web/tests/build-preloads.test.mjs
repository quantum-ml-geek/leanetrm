import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

test('initial HTML discovers shared presentation modules before their import waterfall',()=>{
  const html=readFileSync(new URL('../dist/index.html',import.meta.url),'utf8');
  const preloads=[...html.matchAll(/<link rel="modulepreload" href="([^"]+)">/g)].map(match=>match[1]);
  for(const file of ['/vendor/echarts.js','/vendor/tabulator.js','/market-view.js','/data-grid.js'])
    assert.ok(preloads.includes(file),'missing initial module discovery: '+file);
  assert.equal(new Set(preloads).size,preloads.length);
  assert.ok(preloads.every(file=>file.startsWith('/')&&!file.startsWith('//')));
  assert.equal((html.match(/<script type="module" src="\/app.js"><\/script>/g)??[]).length,1);
});
