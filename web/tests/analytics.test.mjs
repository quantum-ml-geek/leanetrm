import test from 'node:test';
import assert from 'node:assert/strict';
import {compareDecimalStrings,pivotMatrix} from '../dist/analytics-model.js';
import {chartOptions} from '../dist/chart-view.js';

test('numeric grid ordering preserves decimal strings beyond browser precision',()=>{
 const values=['2','10','-0.01','0','9007199254740993','9007199254740992','0.000000000000000002','0.000000000000000001'];
 assert.deepEqual(values.toSorted(compareDecimalStrings),['-0.01','0','0.000000000000000001','0.000000000000000002','2','10','9007199254740992','9007199254740993']);
 assert.equal(compareDecimalStrings('1.000','01'),0);
});
test('cross-tab places exact server values without adding or merging equal display-unit labels',()=>{
 const common={bookId:'a',book:'A',unit:'EA',currency:'TST',currencyReference:{code:'c'},quantitySpecification:{code:'q'}};
 const groups=[{...common,contractId:'jan',deliveryFrom:'2021-01-01',deliveryTo:'2021-02-01',quantity:'80',executionPnl:'0.000000000000000001'},
 {...common,contractId:'feb',deliveryFrom:'2021-02-01',deliveryTo:'2021-03-01',quantity:'-40',executionPnl:'-4'},
 {...common,quantitySpecification:{code:'other'},contractId:'jan',deliveryFrom:'2021-01-01',deliveryTo:'2021-02-01',quantity:'3',executionPnl:'2'}];
 const result=pivotMatrix(groups,['book','contract'],['contract'],['quantity','executionPnl']);
 assert.equal(result.rows.length,2);assert.equal(result.columns.length,7);
 assert.equal(result.rows[0][result.columns[3].key],'80');assert.equal(result.rows[0][result.columns[4].key],'0.000000000000000001');
 assert.equal(result.rows[1][result.columns[5].key],null);
 assert.throws(()=>pivotMatrix([...groups,groups[0]],['book','contract'],['contract'],['quantity']));
});
test('chart standard labels date meaning and units, preserves gaps and exact tooltip values',()=>{
 const option=chartOptions({title:'Curve',axis:'delivery',unit:'TST/EA',series:[{name:'Selected',points:[{x:'Jan',y:'0.123456789123456789'},{x:'Feb',y:null},{x:'Mar',y:'2'}]}]});
 assert.equal(option.xAxis.name,'Delivery period');assert.equal(option.yAxis.name,'TST/EA');
 assert.equal(option.series[0].connectNulls,false);assert.equal(option.series[0].data[1],null);
 assert.ok(option.tooltip.formatter([{seriesIndex:0,dataIndex:0}]).includes('0.123456789123456789'));
 assert.equal(chartOptions({title:'History',axis:'observation',unit:'TST/EA',series:[]}).xAxis.name,'Observation date');
});
test('book scenario chart labels categories without claiming a date axis',()=>{
 const option=chartOptions({title:'Shock changes',axis:'category',unit:'TST',kind:'bar',series:[{name:'Up',points:[{x:'book-a',label:'Book A',y:'4'}]}]});
 assert.equal(option.xAxis.name,'Book');assert.equal(option.xAxis.axisLabel.formatter('book-a'),'Book A');assert.equal(option.yAxis.scale,false);
});

test('distinct exact chart categories survive identical display labels and hostile tooltips are text',()=>{
 const option=chartOptions({title:'Curve',axis:'delivery',unit:'EA',series:[{name:'<img src=x>',points:[{x:'first',label:'Jan',y:'1'},{x:'second',label:'Jan',y:'2'}]}]});
 assert.deepEqual(option.xAxis.data,['first','second']);assert.deepEqual(option.series[0].data,[1,2]);assert.equal(option.xAxis.axisLabel.formatter('second'),'Jan');assert.equal(option.dataZoom[1].labelFormatter(1,'second'),'Jan');assert.equal(option.xAxis.axisPointer.label.formatter({value:'second'}),'Jan');
 assert.ok(!option.tooltip.formatter([{seriesIndex:0,dataIndex:0}]).includes('<img'));
 assert.throws(()=>chartOptions({title:'Bad',axis:'delivery',unit:'EA',series:[{name:'A',points:[{x:'same',y:'1'},{x:'same',y:'2'}]}]}));
});
test('position bars use a zero baseline while price lines can scale to their range',()=>{
 const spec={title:'Positions',axis:'delivery',unit:'EA',series:[{name:'A',points:[{x:'Jan',y:'440'}]}]};
 assert.equal(chartOptions({...spec,kind:'bar'}).yAxis.scale,false);
 assert.equal(chartOptions({...spec,kind:'line'}).yAxis.scale,true);
});
test('custom curve chart accepts the served category axis name',()=>{const option=chartOptions({title:'Rolling curve',axis:'category',axisName:'Contract position',unit:'USD/MMBtu',series:[]});assert.equal(option.xAxis.name,'Contract position');});
