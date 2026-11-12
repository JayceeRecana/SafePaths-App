// Test-only synthetic registrations and FCM validate_only. No phone is targeted.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {observedPost,withCleanup}=require('./hosted-push-transport.cjs');
const project='safepaths-test',endpoint='https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof';
let stage='preflight';
async function main(args){
 assert.ok(args.includes('--apply'));const file=args.find(v=>v.startsWith('--credentials='))?.slice(14);assert.ok(file);assert.ok(args.every(v=>v==='--apply'||v.startsWith('--credentials=')));
 const root=path.resolve(__dirname,'../..'),dir=path.join(root,'.usability-work-baseline/spark-proof-setup');
 const account=JSON.parse(fs.readFileSync(file,'utf8'));assert.equal(account.project_id,project);
 const fixtures=JSON.parse(fs.readFileSync(path.join(dir,'PRIVATE-test-accounts.json'),'utf8'));assert.equal(fixtures.project,project);
 const native=JSON.parse(fs.readFileSync(path.join(root,'android/app/src/fieldtest/google-services.json'),'utf8'));assert.equal(native.project_info.project_id,project);
 const env=Object.fromEntries(fs.readFileSync(path.join(dir,'PRIVATE-push.env'),'utf8').trim().split(/\r?\n/).map(v=>v.split('=')));
 assert.equal(env.PROOF_PUSH_ENABLED,'true');assert.match(env.PROOF_PUSH_WORKER_SECRET,/^[A-Za-z0-9_-]{43}$/);
 const run=crypto.randomUUID().replaceAll('-',''),installation=`hosted_synthetic_push_${run}`,deviceId=crypto.createHash('sha256').update(installation).digest('hex'),tokens={};
 const evidence={checkedAt:new Date().toISOString(),project,endpoint,deviceDeliveryTested:false,APKBuilt:false,passed:false,cleanupConfirmed:false,checks:[],observations:[]};
 const persist=()=>fs.writeFileSync(path.join(dir,'push-hosted-result.json'),JSON.stringify(evidence,null,2));persist();
 const record=name=>{evidence.checks.push(name);fs.writeFileSync(path.join(dir,'push-hosted-result.json'),JSON.stringify(evidence,null,2));};
 const request=async(route,bearer,data,caseName=stage)=>observedPost({route,bearer,data,caseName,observe:record=>{evidence.observations.push(record);persist();}});
 const app=initializeApp({projectId:project,credential:cert(account)},'push-hosted-acceptance');const db=getFirestore(app);
 await withCleanup(async()=>{
  for(const fixture of fixtures.accounts){assert.equal((await db.doc(`users/${fixture.uid}`).get()).data()?.proofFixtureVersion,1);const response=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${native.client[0].api_key[0].current_key}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'content-type':'application/json'},body:JSON.stringify({email:fixture.email,password:fixture.password,returnSecureToken:true})});assert.equal(response.status,200);tokens[fixture.uid]=(await response.json()).idToken;}
  const owner='spark-proof-resident',peer='spark-proof-other',admin='spark-proof-admin';
  stage='worker-secret-required';for(const [caseName,bearer] of [['admin_session',tokens[admin]],['wrong_worker_key','wrong-worker-key']]){const denied=await request('push-drain',bearer,{},caseName);assert.equal(denied.status,401);assert.equal(denied.data?.error?.code,'unauthenticated');assert.equal(denied.observation.noStore,true);}record(stage);
  stage='resident-cannot-validate-sender';assert.equal((await request('push-preflight',tokens[owner],{})).status,403);record(stage);
  stage='google-fcm-authenticated-validation-only';const preflight=await request('push-preflight',tokens[admin],{});assert.equal(preflight.status,200);assert.equal(preflight.data.result.senderValidated,true);assert.equal(preflight.data.result.deviceDeliveryTested,false);record(stage);
  const registration={installation,sequence:1,mode:'register',token:`synthetic-not-a-device-token-${run}`};
  stage='authenticated-synthetic-device-registration';let result=await request('push-device',tokens[owner],registration);assert.equal(result.status,200);assert.equal(result.data.result.registered,true);record(stage);
  stage='raw-token-owner-and-admin-reads-denied';
  for(const uid of [owner,admin]){const r=await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/push_devices/${deviceId}`,{headers:{authorization:`Bearer ${tokens[uid]}`},redirect:'error',signal:AbortSignal.timeout(20000)});assert.equal(r.status,403);}record(stage);
  stage='device-account-transfer-rejects-stale-save';assert.equal((await request('push-device',tokens[peer],{...registration,sequence:2})).status,200);assert.equal((await request('push-device',tokens[owner],registration)).status,409);assert.equal((await db.doc(`push_devices/${deviceId}`).get()).data().userId,peer);record(stage);
  stage='logout-device-deregistered';assert.equal((await request('push-device',tokens[peer],{installation,sequence:3,mode:'unregister'})).status,200);assert.equal((await db.doc(`push_devices/${deviceId}`).get()).data().active,false);record(stage);
  stage='saved-message-survives-no-device';
  // No active phone registrations are permitted in this automated no-device case.
  const active=await db.collection('push_devices').where('ownerKey','==',owner).get();assert.equal(active.size,0);
  const previous=JSON.parse(fs.readFileSync(path.join(dir,'admin-hosted-state.json'),'utf8'));assert.equal(previous.project,project);assert.equal((await db.doc(`reports/${previous.reportId}`).get()).data().userId,owner);
  const requestId=`push_proof_${run}`,body={action:'reply',reportId:previous.reportId,requestId,message:'Synthetic push acceptance update. No real incident or dispatch.'};
  result=await request('admin-action',tokens[admin],body);assert.equal(result.status,200);assert.equal(result.data.result.notification,'saved_in_app');
  const requestHash=crypto.createHash('sha256').update(`${admin}|${requestId}`).digest('hex'),eventId=crypto.createHash('sha256').update(`${requestHash}|reports/${previous.reportId}`).digest('hex');
  assert.equal((await request('push-drain',env.PROOF_PUSH_WORKER_SECRET,{})).status,200);
  let status;for(let n=0;n<12;n++){status=await request('push-status',tokens[owner],{eventId});if(status.data.result?.status==='no_device')break;await new Promise(resolve=>setTimeout(resolve,1000));}
  assert.equal(status.status,200);assert.equal(status.data.result.status,'no_device');assert.equal(status.data.result.acceptedCount,0);assert.equal(status.data.result.deviceReceiptConfirmed,false);assert.ok((await db.doc(`report_messages/${eventId}`).get()).exists);record(stage);
  stage='push-status-private-and-review-replay-safe';assert.equal((await request('push-status',tokens[peer],{eventId})).status,403);const replay=await request('admin-action',tokens[admin],body);assert.equal(replay.status,200);assert.equal(replay.data.result.replay,true);record(stage);
 },async()=>{
  // Retire only this run's synthetic installation, even after a lost response.
  try{const saved=await db.doc(`push_devices/${deviceId}`).get();if(saved.exists && saved.data().active && tokens[saved.data().userId]){const retired=await request('push-device',tokens[saved.data().userId],{installation,sequence:saved.data().sequence+1,mode:'unregister'},'cleanup_unregister');assert.equal(retired.status,200);}const final=await db.doc(`push_devices/${deviceId}`).get();assert.ok(!final.exists||final.data().active===false);evidence.cleanupConfirmed=true;persist();}finally{await deleteApp(app);}
 },lifecycle=>{evidence.lifecycle=lifecycle;persist();});
 evidence.passed=true;persist();console.log(JSON.stringify(evidence,null,2));
}
main(process.argv.slice(2)).catch(error=>{console.error(JSON.stringify({check:'push-hosted',stage,passed:false,category:typeof error.code==='string'&&/^[a-zA-Z_-]{1,40}$/.test(error.code)?error.code:'http-or-assertion',...(typeof error.actual==='number'&&typeof error.expected==='number'?{actual:error.actual,expected:error.expected}:{}),...(error.cause?.code&&/^[A-Z_]{1,40}$/.test(error.cause.code)?{networkCode:error.cause.code}:{})}));process.exitCode=1;});
