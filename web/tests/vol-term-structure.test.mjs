import {test} from 'node:test';
import assert from 'node:assert/strict';
import {termPoints} from '../dist/vol-term-structure.js';

const expiry=(expiryAt,status,parameters,extra={})=>({expiryAt,underlyingCode:'ng',futures:'3',status,parameters,points:status==='fitted'?7:0,rmsResidual:status==='fitted'?'0.0012':null,
 maxAbsResidual:null,grid:[],atTheMoneyStrike:'3',daysToExpiry:'30',...extra});
const surface={modelId:'m',strikeAxis:[],series:[],sensitivities:null,expiries:[
 expiry('2027-01-26T19:30:00+00:00','fitted',{a:'0.451234567890123456789012345678',b:'-0.1025',c:'0.8'}),
 expiry('2027-02-23T19:30:00+00:00','vol_fit_insufficient_strikes',null),
 expiry('2027-03-26T19:30:00+00:00','fitted',{a:'0.398',b:'0.02',c:'0.5'},{points:9,rmsResidual:'0.0004'})]};

test('the term structure has one point per expiry in the surface\'s order, with the fitted level and slope as stored',()=>{
 assert.deepEqual(termPoints(surface),[
  {expiryAt:'2027-01-26T19:30:00+00:00',status:'fitted',level:'0.451234567890123456789012345678',slope:'-0.1025',points:7,rmsResidual:'0.0012'},
  {expiryAt:'2027-02-23T19:30:00+00:00',status:'vol_fit_insufficient_strikes',level:null,slope:null,points:0,rmsResidual:null},
  {expiryAt:'2027-03-26T19:30:00+00:00',status:'fitted',level:'0.398',slope:'0.02',points:9,rmsResidual:'0.0004'}]);
});

test('an expiry that is not fitted has no level: nothing is interpolated across it',()=>{
 const gap=termPoints(surface)[1];
 assert.equal(gap.level,null);assert.equal(gap.slope,null);
});

test('a fitted expiry without its parameters is refused, not drawn at some other level',()=>{
 assert.throws(()=>termPoints({...surface,expiries:[expiry('2027-01-26T19:30:00+00:00','fitted',null)]}),/parameters/);
});
