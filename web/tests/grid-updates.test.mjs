import test from 'node:test';
import assert from 'node:assert/strict';
test('grid patches name only changed exact cells and preserve zero, negatives and rational strings',async()=>{
 const {changedCells}=await import('../dist/grid-updates.js');
 assert.deepEqual(changedCells(['a','b'],[['1','0'],['3/7','-2']],['a','b'],[['1','-0.01'],['3/7','-2']]),[{row:0,column:1}]);
 assert.deepEqual(changedCells(['a'],[['1']],['a'],[['1']]),[]);
 assert.equal(changedCells(['a'],[['1']],['b','a'],[['2'],['1']]),null);
});
