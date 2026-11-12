// Explicit, backed-up activity-only cleanup. Never clears a whole database.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {classify,activity,ledger}=require('./prepare-activity-cleanup.cjs');
const {encode}=require('./inventory-main.cjs');
const projects=new Set(['safepaths-test','safepaths-92c3d']);
function options(args) {
 const out={apply:false};
 for(const arg of args){if(arg==='--apply'){out.apply=true;continue;}const m=/^--(project|credentials|backup)=(.+)$/.exec(arg);if(!m||out[m[1]])throw Error('Unknown/duplicate cleanup option');out[m[1]]=m[2];}
 if(!projects.has(out.project)||!out.credentials||!out.backup||process.env.FIRESTORE_EMULATOR_HOST)throw Error('Explicit hosted app project, credential and backup required');return out;
}
function buildPlan(snapshot,project) {
 if(snapshot.project!==project || !projects.has(project)||!Array.isArray(snapshot.documents))throw Error('Matching complete backup required');
 const targets=snapshot.documents.filter(d=>['activity','activity-ledger'].includes(classify(d)));
 if(targets.some(d=>!d.updateTime || d.path.split('/').some(p=>!p || p==='.' || p==='..')))throw Error('Fenced document paths required');
 return {project,targets,backupDocuments:snapshot.documents};
}
function sameVersion(a,b){return a?.seconds===b?.seconds&&a?.nanoseconds===b?.nanoseconds;}
function stale(){const e=Error('Activity changed after the backup; preserve it and take a fresh backup.');e.code='cleanup-stale';throw e;}
async function execute(db,plan,field,{apply=false}={}) {
 const expected=new Map(plan.targets.map(d=>[d.path,d])),roots=[...new Set([...activity,...ledger])];
 const result=await db.runTransaction(async tx=>{
  const [rootPages,users,roads,analytics,cache,marker,job]=await Promise.all([
   Promise.all(roots.map(r=>tx.get(db.collection(r).limit(501)))),tx.get(db.collection('users').limit(101)),
   tx.get(db.collection('roads').limit(1001)),tx.get(db.collection('analytics').limit(51)),
   tx.get(db.doc('system/core_cache')),tx.get(db.doc('system/road_inputs')),tx.get(db.doc('system/risk_job')),
  ]);
  if(rootPages.some(p=>p.size>500)||users.size>100||roads.size>1000||analytics.size>50)throw Error('Cleanup bounds require a separate review');
  if(job.exists && job.data().leaseUntil?.toMillis?.()>Date.now()){const e=Error('Risk worker is running; retry after it finishes.');e.code='cleanup-worker-busy';throw e;}
  const liveRoots=rootPages.flatMap(p=>p.docs).filter(d=>['activity','activity-ledger'].includes(classify({path:d.ref.path,data:d.data()})));
  const expectedRoots=plan.targets.filter(d=>d.path.split('/').length===2);
  if(liveRoots.length!==expectedRoots.length || liveRoots.some(d=>!expected.has(d.ref.path)))stale();
  const targets=await Promise.all(plan.targets.map(d=>tx.get(db.doc(d.path))));
  for(const doc of targets)if(!doc.exists||!sameVersion(doc.updateTime,expected.get(doc.ref.path).updateTime))stale();
  const reportIds=new Set(plan.targets.filter(d=>d.path.startsWith('reports/')&&d.path.split('/').length===2).map(d=>d.path.split('/')[1]));
  const incidentRoads=new Set(plan.targets.filter(d=>d.path.startsWith('road_incidents/')).map(d=>d.path.split('/')[1]));
  const roadPatches=[];
  for(const doc of roads.docs){const data=doc.data(),patch={};
   if(incidentRoads.has(doc.id))for(const key of ['activeIncidentId','communityCondition','communityReviewedAt'])if(key in data)patch[key]=field.delete();
   for(const key of ['sourceReportId','lastVerifiedReportId'])if(reportIds.has(data[key]))patch[key]=field.delete();
   if(Object.keys(patch).length)roadPatches.push({ref:doc.ref,patch:{...patch,riskInputsUpdatedAt:field.serverTimestamp()}});
  }
  const profilePatches=[];
  for(const doc of users.docs){const data=doc.data(),patch={};
   if(data.role==='user'){
    if(data.trustScore!==50)patch.trustScore=50;
    for(const k of ['verifiedReports','dismissedReports','verifiedFollowups'])if(k in data && data[k]!==0)patch[k]=0;
    for(const k of ['lastReportAt','lastEscalationAt','roadReputationGains'])if(k in data)patch[k]=field.delete();
   }
   for(const k of ['lastFeedbackAt','lastBroadcastAt'])if(k in data)patch[k]=field.delete();
   if(Object.keys(patch).length)profilePatches.push({ref:doc.ref,patch});
  }
  const metricPatches=analytics.docs.map(doc=>({ref:doc.ref,patch:Object.fromEntries(['routesProtectedCount','totalRiskReduction'].filter(k=>k in doc.data()&&doc.data()[k]!==0).map(k=>[k,0]))})).filter(d=>Object.keys(d.patch).length);
  const invalidates=roadPatches.length>0||cache.exists;
  const writes=targets.length+roadPatches.length+profilePatches.length+metricPatches.length+(cache.exists?1:0)+(invalidates?1:0);
  if(writes>450)throw Error('Atomic cleanup exceeds the reviewed write bound');
  const counts={};for(const d of targets){const root=d.ref.path.split('/')[0];counts[root]=(counts[root]||0)+1;}
  if(apply){
   // All version checks complete before any delete/update is staged.
   for(const d of targets)tx.delete(d.ref);
   for(const d of [...roadPatches,...profilePatches,...metricPatches])tx.update(d.ref,d.patch);
   if(cache.exists)tx.delete(cache.ref);
   if(invalidates)tx.set(marker.ref,{updatedAt:field.serverTimestamp()},{merge:true});
  }
  return {project:plan.project,apply,plannedDeletes:targets.length,deleted:apply?targets.length:0,collections:counts,
   residentProfilesReset:profilePatches.filter(p=>p.patch.trustScore===50||p.patch.verifiedReports===0||p.patch.dismissedReports===0).length,
   profilesWithActivityMetadataReset:profilePatches.length,communityRoadPatches:roadPatches.length,metricPatches:metricPatches.length,
   roadsPreserved:roads.size,accountsPreserved:users.size,officialConditionsChanged:false,storageObjectsDeleted:0,atomic:true};
 });return result;
}
async function main(args) {
 const opt=options(args),bytes=fs.readFileSync(opt.backup),snapshot=JSON.parse(bytes.toString('utf8')),plan=buildPlan(snapshot,opt.project);
 const key=JSON.parse(fs.readFileSync(opt.credentials,'utf8'));if(key.project_id!==opt.project||!key.client_email?.endsWith(`@${opt.project}.iam.gserviceaccount.com`))throw Error('Credential mismatch');
 const {initializeApp,cert,deleteApp}=require('firebase-admin/app'),{getFirestore,FieldValue}=require('firebase-admin/firestore');
 const app=initializeApp({projectId:opt.project,credential:cert(key)},'reviewed-activity-cleanup');
 const dir=path.resolve('.usability-work-baseline/activity-cleanup-20261101');fs.mkdirSync(dir,{recursive:true});
 try{
  const result=await execute(getFirestore(app),plan,FieldValue,opt);
  result.backupSha256=crypto.createHash('sha256').update(bytes).digest('hex');result.completedAt=new Date().toISOString();
  fs.writeFileSync(path.join(dir,`${opt.project}-${opt.apply?'applied':'preflight'}.json`),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await deleteApp(app);}
}
module.exports={options,buildPlan,execute};
if(require.main===module)main(process.argv.slice(2)).catch(error=>{console.error(JSON.stringify({cleanupCompleted:false,code:['cleanup-stale','cleanup-worker-busy'].includes(error.code)?error.code:'cleanup-stopped',note:'The atomic cleanup did not commit. No private records or credentials were logged.'}));process.exitCode=1;});
