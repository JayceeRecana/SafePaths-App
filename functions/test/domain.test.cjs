const {test} = require('node:test');
const assert = require('node:assert/strict');
const {calculateRisks, confidence, roadDistance, validateReport} = require('../domain.cjs');
const now = 1760000000000;
const road = {id:'r', status:'passable', vulnerability:'medium', updatedAt:now, neighbors:[], geometry:{type:'LineString',coordinates:[[120.984,14.675],[120.984,14.677]]}};
const report = {id:'a', roadId:'r', userId:'u', severity:'High', status:'pending', createdAt:now, authorityScore:50};
test('canonical risk retains original status, propagation and time thresholds', () => {
  assert.equal(calculateRisks([road], [], 'clear', now)[0].riskScore, 0);
  assert.equal(calculateRisks([{...road,status:'not_passable'}], [], 'clear', now)[0].riskScore, 100);
  const other = {...road,id:'other',riskScore:100};
  const result = calculateRisks([{...road,neighbors:['other'],vulnerability:'high'},other], [], 'typhoon',now)[0];
  assert.equal(result.riskScore,95);
  assert.equal(result.propagationSource,'other');
  assert.equal(calculateRisks([{...road,status:'not_passable',updatedAt:now-121*60000}], [], 'clear',now)[0].riskScore,80);
});
test('confidence ignores another report from the same account and decays', () => {
  assert.equal(confidence(report,[road],[report], 'clear',now),45);
  assert.equal(confidence(report,[road],[report,{...report,id:'b'}], 'clear',now),45);
  assert.equal(confidence(report,[road],[report], 'clear',now+12*3600000),25);
  assert.ok(confidence(report,[road],[report,{...report,id:'b',userId:'other'}], 'clear',now)>45);
});
test('location validation checks road segments, including disconnected geometry', () => {
  assert.ok(roadDistance({lat:14.676,lng:120.984},road.geometry)<0.1);
  assert.ok(roadDistance({lat:14.676,lng:121.5},road.geometry)>500);
  assert.equal(roadDistance({lat:0,lng:0},null),Infinity);
});
test('reports reject forged, incomplete and malformed fields', () => {
  const data = {requestId:'1234567890123456',roadId:'r',title:'Flood',description:'Water',severity:'High',isEmergency:false,location:{lat:14,lng:120}};
  assert.equal(validateReport(data).severity,'High');
  assert.throws(()=>validateReport({...data,location:{lat:NaN,lng:120}}));
  assert.throws(()=>validateReport({...data,roadId:'other/road'}));
  assert.throws(()=>validateReport({...data,severity:'safe'}));
});
