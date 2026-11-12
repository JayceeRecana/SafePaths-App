// Creates and deletes only this run's new, isolated synthetic road IDs.
// Existing roads/reports/photos are never deleted or restored over newer edits.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {withCleanup}=require('./hosted-push-transport.cjs');
const endpoint='https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof',project='safepaths-test';let stage='configuration';
async function main(args){
 assert.equal(args.length,1);assert.ok(args[0].startsWith('--credentials='));assert.ok(!process.env.FIRESTORE_EMULATOR_HOST);
 const key=JSON.parse(fs.readFileSync(args[0].slice(14),'utf8'));assert.equal(key.project_id,project);assert.ok(key.client_email.endsWith(`@${project}.iam.gserviceaccount.com`));
 const dir=path.resolve('.usability-work-baseline/spark-proof-setup'),fixtures=JSON.parse(fs.readFileSync(path.join(dir,'PRIVATE-test-accounts.json'),'utf8')),native=JSON.parse(fs.readFileSync('android/app/src/fieldtest/google-services.json','utf8'));
 assert.equal(fixtures.project,project);assert.equal(native.project_info.project_id,project);assert.deepEqual(fixtures.accounts.map(x=>x.uid).sort(),['spark-proof-admin','spark-proof-other','spark-proof-resident']);
 const env=Object.fromEntries(fs.readFileSync(path.join(dir,'PRIVATE-push.env'),'utf8').trim().split(/\r?\n/).map(x=>x.split('=')));
 const app=initializeApp({projectId:project,credential:cert(key)},'roads-hosted'),db=getFirestore(app),tokens={},owner='spark-proof-admin';
 const run=String(crypto.randomBytes(5).readUIntBE(0,5)),ids=[`osm_way_99${run}1`,`osm_way_99${run}2`],checks=[],requests={};
 const evidence={project,startedAt:new Date().toISOString(),mainProjectModified:false,APKBuilt:false,physicalDeviceTested:false,phoneTargeted:false,existingRoadDeleted:false,passed:false,cleanupConfirmed:false,checks};
 const stateFile=path.join(dir,`roads-hosted-state-${run}.json`),resultFile=path.join(dir,'roads-hosted-result.json');
 const persist=()=>{fs.writeFileSync(stateFile,JSON.stringify({project,run,ids,requests},null,2));fs.writeFileSync(resultFile,JSON.stringify(evidence,null,2));};persist();
 const record=name=>{checks.push(name);persist();};
 const intent=(name,data)=>{assert.ok(!requests[name]);requests[name]={requestId:crypto.randomBytes(24).toString('base64url'),...data};persist();return requests[name];};
 async function post(route,data,uid=owner,expected=200){stage=route;const response=await fetch(`${endpoint}/${route}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(115000),headers:{'content-type':'application/json',authorization:`Bearer ${uid?tokens[uid]:env.PROOF_PUSH_WORKER_SECRET}`},body:JSON.stringify({data})});const body=await response.json();assert.equal(response.status,expected,`Unexpected ${route} status`);return body.result??body;}
 async function worker(){for(let i=0;i<4;i++){const result=await post('core-maintenance',{},null);if(result.completed)return result;assert.equal(result.reason,'busy-or-budget');await new Promise(resolve=>setTimeout(resolve,1000));}throw new Error('Worker did not complete during the bounded check.');}
 async function review(id,status,name){const ctx=await post('admin-context',{roadIds:[id]});return post('admin-action',intent(name,{action:'road_review',roadIds:[id],contextToken:ctx.token,roadStatus:status,note:'Synthetic maintenance acceptance only. No real road observation or warning.',verifiedCurrentConditions:true}));}
 const projected=data=>JSON.stringify(Object.fromEntries(['name','status','notes','geometry','studyArea','vulnerability','isVerified','source','updatedAt','maintenanceGeneration'].filter(k=>data[k]!==undefined).map(k=>[k,data[k]])));
 let before=[];
 async function assertOwned(id){assert.ok(ids.includes(id));const doc=await db.doc(`roads/${id}`).get();if(!doc.exists)return false;assert.equal(doc.data().name,`Synthetic maintenance ${run} ${ids.indexOf(id)+1}`);assert.equal(doc.data().maintenanceGeneration,crypto.createHash('sha256').update(`${owner}|${requests.import.requestId}`).digest('hex'));return true;}
 await withCleanup(async()=>{
  assert.equal((await db.doc('system/road_maintenance').get()).data()?.enabled,true);
  for(const user of fixtures.accounts){assert.equal((await db.doc(`users/${user.uid}`).get()).data()?.proofFixtureVersion,1);const signed=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${native.client[0].api_key[0].current_key}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'content-type':'application/json'},body:JSON.stringify({email:user.email,password:user.password,returnSecureToken:true})});assert.equal(signed.status,200);tokens[user.uid]=(await signed.json()).idToken;}
  assert.equal((await db.collection('push_devices').where('active','==',true).limit(1).get()).empty,true);
  const existing=await db.collection('roads').limit(1001).get();assert.ok(existing.size<=1000);before=existing.docs.map(d=>({id:d.id,official:projected(d.data()),data:d.data()}));
  const {roadDistance}=await import('../../supabase/functions/_shared/proof_reports.mjs');let spot;
  for(const lat of [14.668,14.6835,14.674,14.679])for(const lng of [121.001,121.0175,121.004,121.014]){if(spot)continue;const points=[{lat,lng},{lat:lat+0.0002,lng},{lat,lng:lng+0.0001},{lat:lat+0.0002,lng:lng+0.0001}];if(before.every(r=>points.every(p=>roadDistance(p,r.data.geometry)>150)))spot={lat,lng};}
  assert.ok(spot,'Require an isolated synthetic location to avoid changing existing road links.');
  for(const id of ids)assert.equal((await db.doc(`roads/${id}`).get()).exists,false);
  record('exact test project/cohort and an isolated location verified; no active phone');
  const roads=ids.map((id,i)=>({id,name:`Synthetic maintenance ${run} ${i+1}`,geometry:{type:'MultiLineString',segments:[{points:[{lat:spot.lat,lng:spot.lng+i*0.0001},{lat:spot.lat+0.0002,lng:spot.lng+i*0.0001}]}]}}));
  const input=intent('import',{roads});await post('road-import',input,'spark-proof-resident',403);
  const created=await post('road-import',input);assert.equal(created.createdCount,2);assert.equal(created.skippedCount,0);assert.equal((await post('road-import',input)).replay,true);for(const id of ids)assert.ok(await assertOwned(id));
  record('admin-only create-only import and durable response-loss replay confirmed');
  for(const id of ids)assert.deepEqual((await db.doc(`roads/${id}`).get()).data().neighbors,[ids.find(x=>x!==id)]);
  record('new roads connected symmetrically inside the import transaction');
  await worker();let cache=(await db.doc('system/core_cache').get()).data();assert.ok(ids.every(id=>cache.roads.some(r=>r.id===id)));
  record('actual hosted worker accepts imported topology and caches both new roads');
  const old=await post('road-delete-context',{roadId:ids[0]});assert.equal(old.canDelete,true);
  await review(ids[0],'not_passable','closedReview');const official=(await db.doc(`roads/${ids[0]}`).get()).data();
  const skipped=await post('road-import',intent('retryImport',{roads}));assert.equal(skipped.createdCount,0);assert.equal(skipped.skippedCount,2);assert.equal((await db.doc(`roads/${ids[0]}`).get()).data().notes,official.notes);assert.equal((await db.doc(`roads/${ids[0]}`).get()).data().status,'not_passable');
  record('stale import selection preserves the newer official closure and review note');
  assert.equal((await post('road-delete-context',{roadId:ids[0]})).canDelete,false);await post('road-delete',intent('staleDelete',{roadId:ids[0],contextToken:old.token,confirmed:true}),owner,409);
  record('road closure and stale confirmation block deletion');
  await review(ids[0],'passable','openReview');await post('road-delete',intent('stillStaleDelete',{roadId:ids[0],contextToken:old.token,confirmed:true}),owner,409);
  const direct=await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/roads/${ids[0]}`,{method:'DELETE',redirect:'error',signal:AbortSignal.timeout(20000),headers:{authorization:`Bearer ${tokens[owner]}`}});assert.equal(direct.status,403);
  record('legacy direct admin deletion denied and a refreshed review remains required');
  const fresh=await post('road-delete-context',{roadId:ids[0]});const remove=intent('removeFirst',{roadId:ids[0],contextToken:fresh.token,confirmed:true});assert.equal((await post('road-delete',remove)).saved,true);assert.equal((await post('road-delete',remove)).replay,true);assert.equal((await db.doc(`roads/${ids[0]}`).get()).exists,false);assert.deepEqual((await db.doc(`roads/${ids[1]}`).get()).data().neighbors,[]);
  record('confirmed deletion removes only its synthetic road and prunes the incoming neighbor link');
  await worker();cache=(await db.doc('system/core_cache').get()).data();assert.ok(!cache.roads.some(r=>r.id===ids[0]));assert.equal(cache.topologyRevision,(await db.doc('system/road_inputs').get()).data().topologyRevision);
  record('next hosted worker drops the deleted cached road without waiting for hourly refresh');
  const rebuilt=await post('road-graph-rebuild',intent('rebuild',{}));assert.equal(rebuilt.saved,true);assert.equal((await post('road-graph-rebuild',requests.rebuild)).replay,true);
  record('protected graph repair executes and replays without touching official road decisions');
  const submitted=await post('submit-report',intent('linkedReport',{roadId:ids[1],title:'Synthetic maintenance retention check',description:'Synthetic test only. No participant or real road incident.',severity:'Low',isEmergency:false,observedAt:new Date().toISOString(),location:{lat:spot.lat,lng:spot.lng+0.0001,source:'manual'}}),'spark-proof-other');
  const blocked=await post('road-delete-context',{roadId:ids[1]});assert.equal(blocked.canDelete,false);await post('road-delete',intent('activeBlockedDelete',{roadId:ids[1],contextToken:blocked.token,confirmed:true}),owner,409);
  record('actual pending report and unresolved incident block hosted deletion');
  await review(ids[1],'passable','resolveLinkedReport');assert.equal((await db.doc(`reports/${submitted.reportId}`).get()).data().status,'resolved');
  const last=await post('road-delete-context',{roadId:ids[1]});await post('road-delete',intent('removeLast',{roadId:ids[1],contextToken:last.token,confirmed:true}));await worker();cache=(await db.doc('system/core_cache').get()).data();assert.ok(ids.every(id=>!cache.roads.some(r=>r.id===id)));
  assert.equal((await db.doc(`reports/${submitted.reportId}`).get()).data().status,'resolved');assert.equal((await db.doc(`road_incidents/${ids[1]}`).get()).data().state,'resolved');
  record('resolved report and incident history retained after the synthetic road is removed');
  for(const original of before){const current=await db.doc(`roads/${original.id}`).get();assert.ok(current.exists);assert.equal(projected(current.data()),original.official);}
  record('synthetic roads removed and original official road data preserved');
 },async()=>{
  try{
   if(tokens[owner]&&requests.import)for(const id of ids)if(await assertOwned(id)){
    let ctx=await post('road-delete-context',{roadId:id});
    if(!ctx.canDelete){const pending=await db.collection('reports').where('roadId','==',id).get(),incident=(await db.doc(`road_incidents/${id}`).get()).data();assert.ok(pending.docs.every(d=>!['pending','under_review'].includes(d.data().status)));assert.ok(!incident||incident.state==='resolved');await review(id,'passable',`cleanupReview${ids.indexOf(id)}`);ctx=await post('road-delete-context',{roadId:id});}
    assert.equal(ctx.canDelete,true);await post('road-delete',intent(`cleanupDelete${ids.indexOf(id)}`,{roadId:id,contextToken:ctx.token,confirmed:true}));
   }
   for(const id of ids)assert.equal((await db.doc(`roads/${id}`).get()).exists,false);evidence.cleanupConfirmed=true;persist();
  }finally{await deleteApp(app);}
 },lifecycle=>{evidence.lifecycle=lifecycle;persist();});
 evidence.passed=true;evidence.completedAt=new Date().toISOString();persist();console.log(JSON.stringify(evidence,null,2));
}
main(process.argv.slice(2)).catch(error=>{console.error(JSON.stringify({passed:false,stage,...(typeof error.actual==='number'&&typeof error.expected==='number'?{actual:error.actual,expected:error.expected}:{}),reason:'Hosted maintenance check failed; private fixture state retained for review.'}));process.exitCode=1;});
