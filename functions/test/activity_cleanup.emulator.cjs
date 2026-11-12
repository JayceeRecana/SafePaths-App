const {test,before,after,beforeEach}=require('node:test'),assert=require('node:assert/strict');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue,Timestamp}=require('firebase-admin/firestore');
const {execute,buildPlan}=require('../tools/clear-test-activity.cjs');
const {encode}=require('../tools/inventory-main.cjs');
if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Demo emulator required');
const projectId='demo-safepaths-reliability';let app,db,env,snapshot;
before(async()=>{env=await initializeTestEnvironment({projectId});app=initializeApp({projectId},'activity-cleanup-demo');db=getFirestore(app);});
after(async()=>{await env.cleanup();await deleteApp(app);});
beforeEach(async()=>{
 await env.clearFirestore();
 const seed={
  'reports/r':{roadId:'road',status:'verified'},'report_messages/m':{reportId:'r'},
  'road_incidents/road':{state:'admin_confirmed'},'road_incidents/road/responses/resident':{choice:'still_flooded'},
  'users/resident':{role:'user',trustScore:70,verifiedReports:2,dismissedReports:1,verifiedFollowups:1,photoUrl:'keep-avatar',fcmTokens:['keep-token'],roadReputationGains:{road:Timestamp.now()}},
  'users/admin':{role:'admin',trustScore:100,photoUrl:'keep-admin'},
  'roads/road':{status:'not_passable',notes:'Keep official check',updatedAt:Timestamp.fromMillis(1000),isVerified:true,communityCondition:'admin_confirmed',activeIncidentId:'incident'},
  'alert_templates/template':{title:'Keep template'},'system/weather':{currentState:'clear'},'system/core_cache':{roads:[]},
  'system/risk_job':{leaseUntil:Timestamp.fromMillis(0)},'analytics/global':{routesProtectedCount:5,totalRiskReduction:10},
  'push_devices/device':{userId:'resident'},'media_uploads/avatar':{owner:'resident'},
  'admin_audits/road_check':{action:'road_review',reportId:null},'core_worker_requests/security':{usedAt:Timestamp.now()},
 };
 for(const [p,d]of Object.entries(seed))await db.doc(p).set(d);
 const docs=await Promise.all(Object.keys(seed).map(p=>db.doc(p).get()));
 snapshot={project:'safepaths-test',documents:docs.map(d=>({path:d.ref.path,data:encode(d.data()),updateTime:encode(d.updateTime)}))};
});
test('dry-run does not delete activity or reset rewards',async()=>{
 const result=await execute(db,buildPlan(snapshot,'safepaths-test'),FieldValue);
 assert.equal(result.apply,false);assert.equal(result.deleted,0);assert.equal((await db.doc('reports/r').get()).exists,true);assert.equal((await db.doc('users/resident').get()).data().trustScore,70);
});
test('changed or newly inserted reports abort the entire cleanup before any reset',async()=>{
 await db.doc('reports/r').update({description:'new evidence'});
 await assert.rejects(()=>execute(db,buildPlan(snapshot,'safepaths-test'),FieldValue,{apply:true}),{code:'cleanup-stale'});
 assert.equal((await db.doc('report_messages/m').get()).exists,true);assert.equal((await db.doc('users/resident').get()).data().trustScore,70);
});
test('atomic cleanup deletes selected nested activity while preserving accounts, media and official roads',async()=>{
 const result=await execute(db,buildPlan(snapshot,'safepaths-test'),FieldValue,{apply:true});assert.equal(result.deleted,4);
 for(const p of ['reports/r','report_messages/m','road_incidents/road','road_incidents/road/responses/resident','system/core_cache'])assert.equal((await db.doc(p).get()).exists,false,p);
 const resident=(await db.doc('users/resident').get()).data();assert.equal(resident.trustScore,50);assert.equal(resident.verifiedReports,0);assert.equal(resident.dismissedReports,0);assert.equal(resident.photoUrl,'keep-avatar');assert.deepEqual(resident.fcmTokens,['keep-token']);assert.equal(resident.roadReputationGains,undefined);
 const road=(await db.doc('roads/road').get()).data();assert.equal(road.status,'not_passable');assert.equal(road.notes,'Keep official check');assert.equal(road.updatedAt.toMillis(),1000);assert.equal(road.communityCondition,undefined);
 for(const p of ['users/admin','alert_templates/template','system/weather','push_devices/device','media_uploads/avatar','admin_audits/road_check','core_worker_requests/security'])assert.equal((await db.doc(p).get()).exists,true,p);
 assert.equal((await db.doc('users/admin').get()).data().trustScore,100);assert.equal((await db.doc('analytics/global').get()).data().routesProtectedCount,0);
});
