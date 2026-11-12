const {test}=require('node:test'),assert=require('node:assert/strict');
const {classify}=require('../tools/prepare-activity-cleanup.cjs');
const {options,buildPlan}=require('../tools/clear-test-activity.cjs');
test('cleanup defaults to read-only and accepts only exact projects with explicit backups',()=>{
 const args=['--project=safepaths-test','--credentials=private.json','--backup=backup.json'];
 assert.equal(options(args).apply,false);assert.equal(options([...args,'--apply']).apply,true);
 for(const bad of [args.filter(a=>!a.startsWith('--backup=')),args.map(a=>a.replace('safepaths-test','unrelated-project')),[...args,'--delete-all']])assert.throws(()=>options(bad));
});
test('cleanup excludes accounts, roads, profile media, templates, configuration and worker replay guards',()=>{
 for(const path of ['users/u','roads/r','media_uploads/m','profile_requests/p','alert_templates/t','system/weather','core_worker_requests/c','push_worker_requests/p','road_maintenance_audits/a','system_audits/a'])assert.equal(classify({path,data:{}}),'preserve');
 assert.equal(classify({path:'roads/fixture',data:{name:'[TEST ONLY] reporting fixture'}}),'fixture-road-review');
 assert.equal(classify({path:'admin_audits/a',data:{action:'road_review',reportId:null}}),'preserve');
 assert.equal(classify({path:'admin_requests/a',data:{result:{action:'road_review',reportId:null}}}),'preserve');
 assert.equal(classify({path:'report_messages/m',data:{}}),'activity');
});
test('cleanup requires versioned backup records and never selects preserved roots',()=>{
 const snapshot={project:'safepaths-test',documents:[{path:'reports/r',data:{},updateTime:{seconds:1,nanoseconds:0}},{path:'users/u',data:{}},{path:'roads/r',data:{}}]};
 assert.deepEqual(buildPlan(snapshot,'safepaths-test').targets.map(d=>d.path),['reports/r']);
 assert.throws(()=>buildPlan(snapshot,'safepaths-92c3d'));
 snapshot.documents[0].path='reports/../users/u';assert.throws(()=>buildPlan(snapshot,'safepaths-test'));
});
