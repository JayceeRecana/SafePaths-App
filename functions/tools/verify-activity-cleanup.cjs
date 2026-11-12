// Read-only post-cleanup verification. Prints counts/check results, not records.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {encode}=require('./inventory-main.cjs');
const {buildPlan}=require('./clear-test-activity.cjs');
async function main(args){
 const opt={};for(const arg of args){const m=/^--(project|credentials|backup)=(.+)$/.exec(arg);if(!m||opt[m[1]])throw Error('Explicit matching options required');opt[m[1]]=m[2];}
 const snapshot=JSON.parse(fs.readFileSync(opt.backup,'utf8')),plan=buildPlan(snapshot,opt.project),key=JSON.parse(fs.readFileSync(opt.credentials,'utf8'));
 assert.equal(key.project_id,opt.project);if(process.env.FIRESTORE_EMULATOR_HOST)throw Error('Hosted verification only');
 const {initializeApp,cert,deleteApp}=require('firebase-admin/app'),{getFirestore}=require('firebase-admin/firestore');
 const app=initializeApp({projectId:opt.project,credential:cert(key)},'activity-cleanup-verify');
 try{
  const db=getFirestore(app),roots=['reports','report_messages','report_clarifications','road_incidents','alerts','feedbacks','feedback_messages','notification_outbox'];
  const [pages,users,roads,templates]=await Promise.all([Promise.all(roots.map(r=>db.collection(r).limit(1).get())),db.collection('users').get(),db.collection('roads').get(),db.collection('alert_templates').get()]);
  assert.ok(pages.every(p=>p.empty),'Activity appeared after cleanup');
  const old=new Map(snapshot.documents.map(d=>[d.path,d.data]));
  const beforeUsers=snapshot.documents.filter(d=>/^users\/[^/]+$/.test(d.path));assert.equal(users.size,beforeUsers.length);
  let residents=0;
  for(const doc of users.docs){const current=encode(doc.data()),before=old.get(doc.ref.path);assert.ok(before);
   for(const k of ['name','email','role','location','photoUrl','profileRevision','createdAt','fcmTokens'])assert.deepEqual(current[k],before[k],`Protected user field changed: ${k}`);
   if(current.role==='user'){residents++;assert.equal(current.trustScore,50);assert.equal(current.verifiedReports??0,0);assert.equal(current.dismissedReports??0,0);assert.equal(current.verifiedFollowups??0,0);}
  }
  assert.equal(roads.size,snapshot.documents.filter(d=>/^roads\/[^/]+$/.test(d.path)).length);
  for(const doc of roads.docs){const current=encode(doc.data()),before=old.get(doc.ref.path);assert.ok(before);for(const k of ['name','geometry','neighbors','status','notes','updatedAt','isVerified','source','vulnerability','studyArea'])assert.deepEqual(current[k],before[k],`Official road field changed: ${k}`);}
  const beforeTemplates=snapshot.documents.filter(d=>/^alert_templates\/[^/]+$/.test(d.path));assert.equal(templates.size,beforeTemplates.length);for(const doc of templates.docs)assert.deepEqual(encode(doc.data()),old.get(doc.ref.path));
  const deleted=plan.targets.length?await db.getAll(...plan.targets.map(d=>db.doc(d.path))):[];assert.ok(deleted.every(d=>!d.exists));
  const controls=snapshot.documents.filter(d=>/^system\/(core_setup|communications|media|road_maintenance|backend_rollout|incident_migration)$/.test(d.path));
  for(const before of controls)assert.deepEqual(encode((await db.doc(before.path).get()).data()),before.data);
  const result={project:opt.project,verified:true,activityEmpty:true,oldTargetRecordsAbsent:deleted.length,residentsAtBaseline:residents,accountsPreserved:users.size,roadsPreserved:roads.size,templatesPreserved:templates.size,officialRoadFieldsUnchanged:true,protectedProfileFieldsUnchanged:true,backendControlsUnchanged:true,storageObjectsDeleted:0,cloudWrites:0,verifiedAt:new Date().toISOString()};
  fs.writeFileSync(path.resolve('.usability-work-baseline/activity-cleanup-20261101',`${opt.project}-verified.json`),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await deleteApp(app);}
}
if(require.main===module)main(process.argv.slice(2)).catch(()=>{console.error('Read-only cleanup verification found a mismatch; no private details were logged and no writes were made.');process.exitCode=1;});
