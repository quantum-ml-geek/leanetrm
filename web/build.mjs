import { copyFileSync, mkdirSync } from 'node:fs';
mkdirSync('dist', { recursive: true });
for (const file of ['index.html', 'app.css']) copyFileSync(`src/${file}`, `dist/${file}`);

mkdirSync('dist/vendor', {recursive:true});
for(const [source,target] of [
 ['node_modules/tabulator-tables/dist/js/tabulator_esm.min.js','tabulator.js'],
 ['node_modules/tabulator-tables/dist/css/tabulator.min.css','tabulator.css'],
 ['node_modules/tabulator-tables/LICENSE','TABULATOR-LICENSE'],
 ['node_modules/echarts/dist/echarts.esm.min.js','echarts.js'],
 ['node_modules/echarts/LICENSE','ECHARTS-LICENSE'],
 ['node_modules/echarts/NOTICE','ECHARTS-NOTICE'],
 ['node_modules/zrender/LICENSE','ZRENDER-LICENSE'],
 ['node_modules/tslib/CopyrightNotice.txt','TSLIB-COPYRIGHT'],
 ['node_modules/tslib/LICENSE.txt','TSLIB-LICENSE'],
]) copyFileSync(source,'dist/vendor/'+target);
