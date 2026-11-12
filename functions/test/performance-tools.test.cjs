const {test} = require('node:test');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const path = require('node:path');
const {percentile,localHost} = require('../tools/performance-load.cjs');
test('load workload refuses a production project before any network setup',()=>{
  const result = spawnSync(process.execPath,[path.join(__dirname,'../tools/performance-load.cjs')],
    {env:{...process.env,GCLOUD_PROJECT:'safepaths-92c3d'},encoding:'utf8'});
  assert.equal(result.status,1);
  assert.match(result.stderr,/refusing any other project/);
});
test('performance statistics and loopback guards handle small capstone samples',()=>{
  assert.equal(percentile([],0.95),null);
  assert.equal(percentile([1,5,3,2,4],0.95),5);
  assert.equal(percentile([1,5,3,2,4],0.5),3);
  const variable = 'SAFEPATHS_PERFORMANCE_TEST_HOST';
  process.env[variable]='https://example.com';
  assert.throws(()=>localHost(variable),/loopback/);
  process.env[variable]='127.0.0.1:8080';
  assert.equal(localHost(variable),'127.0.0.1:8080');
  delete process.env[variable];
});
