// Final read-only deployment checks; print only counters/control state.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');const {getFirestore}=require('firebase-admin/firestore');
async function main(args){
 assert.equal(args.length,1);assert.ok(args[0].startsWith('--credentials='));assert.ok(!process.env.FIRESTORE_EMULATOR_HOST);
 const key=JSON.parse(fs.readFileSync(args[0].slice(14),'utf8'));assert.equal(key.project_id,'safepaths-test');const credential=cert(key),app=initializeApp({projectId:key.project_id,credential},'roads-final-state');
 try{
  const db=getFirestore(app),paths=['system/road_maintenance','system/road_inputs','system/core_cache','system/risk_job','system/core_budget','system/communications','system/media'];
  const docs=await db.getAll(...paths.map(p=>db.doc(p))),[control,marker,cache,job,budget,communications,media]=docs.map(d=>d.data());
  assert.equal(control.enabled,true);assert.equal(cache.topologyRevision,marker.topologyRevision);assert.equal(job.error,null);assert.equal(job.roadCount,cache.roads.length);assert.equal(communications.enabled,true);assert.equal(media.enabled,true);
  const setup=path.resolve('.usability-work-baseline/spark-proof-setup'),files=fs.readdirSync(setup).filter(n=>/^roads-hosted-state-.*\.json$/.test(n)).sort((a,b)=>fs.statSync(path.join(setup,b)).mtimeMs-fs.statSync(path.join(setup,a)).mtimeMs),state=JSON.parse(fs.readFileSync(path.join(setup,files[0]),'utf8'));assert.equal(state.project,key.project_id);
  const fixtures=await db.getAll(...state.ids.map(id=>db.doc(`roads/${id}`)));assert.ok(fixtures.every(d=>!d.exists));assert.ok(state.ids.every(id=>!cache.roads.some(r=>r.id===id)));
  const active=await db.collection('push_devices').where('active','==',true).limit(1).get();assert.equal(active.size,0);
  const indexes=await fetch('https://firestore.googleapis.com/v1/projects/safepaths-test/databases/(default)/collectionGroups/-/indexes',{redirect:'error',signal:AbortSignal.timeout(20000),headers:{authorization:`Bearer ${(await credential.getAccessToken()).access_token}`}});assert.equal(indexes.status,200);const rows=(await indexes.json()).indexes;assert.equal(rows.length,14);assert.ok(rows.every(x=>x.state==='READY'));
  const result={project:key.project_id,checkedAt:new Date().toISOString(),maintenanceControlEnabled:true,communicationsControlEnabled:true,mediaControlEnabled:true,topologyRevision:marker.topologyRevision,cachedTopologyRevision:cache.topologyRevision,currentRoadCount:job.roadCount,riskError:job.error,lastRiskSuccess:job.lastSuccess.toDate().toISOString(),syntheticRoadsAbsent:true,activePhoneRegistrations:0,indexesReady:14,coreWorkerBudgetOnly:{day:budget.day,reads:budget.reads,writes:budget.writes},mainProjectModified:false,APKBuilt:false};
  fs.writeFileSync('.usability-work-baseline/roads-cloud-state.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await deleteApp(app);}
}
main(process.argv.slice(2)).catch(()=>{console.error('Final test maintenance state check failed; private details were not logged.');process.exitCode=1;});
