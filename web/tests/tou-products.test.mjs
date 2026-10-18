import test from 'node:test';
import assert from 'node:assert/strict';
import {peakLabel,clockLabel} from '../dist/tou-products.js';
test('peak windows are described from stored hour-beginning bounds and the Saturday flag',()=>{
  assert.equal(peakLabel({peakStartHour:7,peakEndHour:23,peakSaturday:false}),'Mon–Fri HE08–HE23');
  assert.equal(peakLabel({peakStartHour:6,peakEndHour:22,peakSaturday:true}),'Mon–Sat HE07–HE22');
});
test('clock labels come from the served clock rule, never a guessed zone',()=>{
  assert.equal(clockLabel({reference:{code:'synthetic_eastern'},kind:'iana',ianaZone:'America/New_York',tzdbVersion:'2026c',fixedOffsetSeconds:null}),'America/New_York · tzdb 2026c');
  assert.equal(clockLabel({reference:{code:'synthetic_fixed_est'},kind:'fixed_offset',ianaZone:null,tzdbVersion:null,fixedOffsetSeconds:-18000}),'Fixed UTC−05:00');
  assert.equal(clockLabel({reference:{code:'x'},kind:'fixed_offset',ianaZone:null,tzdbVersion:null,fixedOffsetSeconds:19800}),'Fixed UTC+05:30');
});
