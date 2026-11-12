const fixtures = require('../../test/risk-parity-fixtures.json');
const {calculateRisks} = require('../domain.cjs');
const {test} = require('node:test');
const assert = require('node:assert/strict');
for (const f of fixtures) test(`shared risk fixture: ${f.name}`,()=>assert.deepEqual(calculateRisks(f.roads,f.reports,f.weather,f.now),f.expected));
for (const f of fixtures) test(`Spark portable risk fixture: ${f.name}`,async()=>{
  const portable=await import('../../supabase/functions/_shared/risk_domain.mjs');
  assert.deepEqual(portable.calculateRisks(f.roads,f.reports,f.weather,f.now),f.expected);
});
