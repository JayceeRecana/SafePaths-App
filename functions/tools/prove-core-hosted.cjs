// Synthetic identities and labelled test road only. Never prints credentials,
// sign-in tokens, report contents, coordinates or provider response bodies.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
async function main(args){
 const file=args.find(x=>x.startsWith('--credentials='))?.slice(14);assert.ok(file);
 const key=JSON.parse(fs.readFileSync(file,'utf8')),project='safepaths-test';assert.equal(key.project_id,project);assert.ok(key.client_email.endsWith(`@${project}.iam.gserviceaccount.com`));
 const dir=path.resolve('.usability-work-baseline/spark-proof-setup'),fixtures=JSON.parse(fs.readFileSync(path.join(dir,'PRIVATE-test-accounts.json'),'utf8'));assert.equal(fixtures.project,project);
 const config=JSON.parse(fs.readFileSync(path.join(dir,'public-build-defines.json'),'utf8'));assert.equal(config.SPARK_PROOF_FIREBASE_PROJECT_ID,project);
 const endpoint=config.SPARK_PROOF_BACKEND_URL;assert.equal(endpoint,'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof');
 const native=JSON.parse(fs.readFileSync('android/app/src/fieldtest/google-services.json','utf8'));assert.equal(native.project_info.project_id,project);
 const env=Object.fromEntries(fs.readFileSync(path.join(dir,'PRIVATE-push.env'),'utf8').trim().split(/\r?\n/).map(x=>x.split('=')));
 const app=initializeApp({projectId:project,credential:cert(key)},'core-hosted-proof');
 try{
  const db=getFirestore(app),tokens={};
  for(const user of fixtures.accounts){
   assert.ok(['spark-proof-admin','spark-proof-resident','spark-proof-other'].includes(user.uid));
   const response=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${native.client[0].api_key[0].current_key}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'content-type':'application/json'},body:JSON.stringify({email:user.email,password:user.password,returnSecureToken:true})});assert.equal(response.status,200);tokens[user.uid]=(await response.json()).idToken;
  }
  const checks=[];
  async function post(route,data,uid,expected=200){
   const response=await fetch(`${endpoint}/${route}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(115000),headers:{'content-type':'application/json',authorization:`Bearer ${uid?tokens[uid]:env.PROOF_PUSH_WORKER_SECRET}`},body:JSON.stringify({data})});assert.equal(response.status,expected,`Unexpected ${route} status`);return response.json();
  }
  const roadId='spark-normal-form-road',incident=(await db.doc(`road_incidents/${roadId}`).get()).data(),roadBefore=(await db.doc(`roads/${roadId}`).get()).data();assert.ok(incident && incident.state!=='resolved');assert.equal(roadBefore.studyArea,'nearby_test');
  const report=(await db.collection('reports').where('incidentId','==',incident.incidentId).limit(1).get()).docs[0].data(),owner=report.userId;assert.ok(['spark-proof-resident','spark-proof-other'].includes(owner));
  const peer=owner==='spark-proof-resident'?'spark-proof-other':'spark-proof-resident';
  const stateFile=path.join(dir,'core-hosted-state.json');let state=fs.existsSync(stateFile)?JSON.parse(fs.readFileSync(stateFile,'utf8')):null;
  if(state?.incidentId!==incident.incidentId){state={incidentId:incident.incidentId,roadId,choice:'appears_passable',requestId:require('node:crypto').randomBytes(24).toString('base64url'),observedAt:new Date().toISOString()};fs.writeFileSync(stateFile,JSON.stringify(state));}
  const denied=await post('observe-incident',state,owner,409);assert.equal(denied.error.code,'self-confirmation');checks.push('reporter cannot confirm own incident');
  assert.equal((await post('observe-incident',state,peer)).result.saved,true);assert.equal((await post('observe-incident',state,peer)).result.replay,true);checks.push('peer observation saves and replays without double counting');
  assert.equal((await db.doc(`roads/${roadId}`).get()).data().status,roadBefore.status);checks.push('appears-passable observation preserves official closure');
  const drill={requestId:require('node:crypto').randomBytes(24).toString('base64url'),enable:true,state:'heavyRain',minutes:5};
  await post('weather-override',drill,peer,403);await post('weather-override',drill,'spark-proof-admin');
  const expires=(await db.doc('system/weather').get()).data().overrideExpiresAt.toMillis();assert.ok(expires>Date.now() && expires<=Date.now()+5*60000+1000);assert.equal((await post('weather-override',drill,'spark-proof-admin')).result.replay,true);assert.equal((await db.doc('system/weather').get()).data().overrideExpiresAt.toMillis(),expires);checks.push('admin-only drill expires without extending on replay');
  await post('weather-override',{requestId:require('node:crypto').randomBytes(24).toString('base64url'),enable:false},'spark-proof-admin');
  const first=(await post('core-maintenance',{},null)).result;assert.equal(first.completed,true,`Core probe failed: ${first.error}`);checks.push('hosted worker refreshes weather and calculates scoped risk');
  const weather=(await db.doc('system/weather').get()).data(),job=(await db.doc('system/risk_job').get()).data();assert.equal(weather.source,'open-meteo');assert.equal(weather.available,true);assert.equal(weather.isOverrideMode,false);assert.ok(Date.now()-weather.observedAt.toMillis()<1800000);assert.equal(job.error,null);assert.ok(Date.now()-job.lastSuccess.toMillis()<120000);checks.push('actual provider timestamp and successful risk heartbeat verified');
  const second=(await post('core-maintenance',{},null)).result;assert.equal(second.completed,true,`Core repeat failed: ${second.error}`);checks.push('repeat worker succeeds with cached network');
  const result={date:new Date().toISOString(),project,mainProjectModified:false,checks,worker:first,repeatWorker:second,roadCount:job.roadCount,weatherSource:weather.source,weatherObservedAt:weather.observedAt.toDate().toISOString()};
  fs.writeFileSync(path.join(dir,'core-hosted-result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
 }finally{await deleteApp(app);}
}
main(process.argv.slice(2)).catch(()=>{console.error('Hosted core proof failed. Private details were not logged; keep the new scheduler inactive.');process.exitCode=1;});
