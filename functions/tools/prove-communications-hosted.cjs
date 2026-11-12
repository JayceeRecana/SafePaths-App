// Synthetic records only. No real phone is targeted: require an empty active
// test-device registry and use FCM validate_only for transport verification.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const project='safepaths-test',endpoint='https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof';
let stage='configuration';
async function main(args){
 const file=args.find(x=>x.startsWith('--credentials='))?.slice(14);assert.ok(file);
 const key=JSON.parse(fs.readFileSync(file,'utf8'));assert.equal(key.project_id,project);assert.ok(key.client_email.endsWith(`@${project}.iam.gserviceaccount.com`));
 const dir=path.resolve('.usability-work-baseline/spark-proof-setup'),fixtures=JSON.parse(fs.readFileSync(path.join(dir,'PRIVATE-test-accounts.json'),'utf8'));assert.equal(fixtures.project,project);
 assert.deepEqual(fixtures.accounts.map(x=>x.uid).sort(),['spark-proof-admin','spark-proof-other','spark-proof-resident']);
 const native=JSON.parse(fs.readFileSync('android/app/src/fieldtest/google-services.json','utf8'));assert.equal(native.project_info.project_id,project);
 const env=Object.fromEntries(fs.readFileSync(path.join(dir,'PRIVATE-push.env'),'utf8').trim().split(/\r?\n/).map(x=>x.split('=')));
 const app=initializeApp({projectId:project,credential:cert(key)},'communication-hosted');
 try{
  const db=getFirestore(app),tokens={},checks=[],stateFile=path.join(dir,'communications-hosted-state.json');
  const state=fs.existsSync(stateFile)?JSON.parse(fs.readFileSync(stateFile,'utf8')):{};
  const persist=()=>fs.writeFileSync(stateFile,JSON.stringify(state,null,2));
  function intent(name,data){if(!state[name]){state[name]={requestId:crypto.randomBytes(24).toString('base64url'),...data};persist();}return state[name];}
  const evidence={project,checkedAt:new Date().toISOString(),mainProjectModified:false,APKBuilt:false,deviceDeliveryTested:false,checks};
  const record=name=>{checks.push(name);fs.writeFileSync(path.join(dir,'communications-hosted-result.json'),JSON.stringify(evidence,null,2));};
  stage='fixture-sign-in';
  for(const user of fixtures.accounts){const profile=(await db.doc(`users/${user.uid}`).get()).data();assert.equal(profile?.proofFixtureVersion,1);assert.equal(profile.role,user.role);const response=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${native.client[0].api_key[0].current_key}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'content-type':'application/json'},body:JSON.stringify({email:user.email,password:user.password,returnSecureToken:true})});assert.equal(response.status,200);tokens[user.uid]=(await response.json()).idToken;}
  assert.equal((await db.collection('push_devices').where('active','==',true).limit(1).get()).empty,true,'No live devices may be targeted by this check');record('no active phone registration; hosted checks cannot target a phone');
  async function post(route,data,uid='spark-proof-admin',expected=200){stage=route;const response=await fetch(`${endpoint}/${route}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(45000),headers:{'content-type':'application/json',authorization:`Bearer ${uid?tokens[uid]:env.PROOF_PUSH_WORKER_SECRET}`},body:JSON.stringify({data})});assert.equal(response.status,expected,`Unexpected ${route} status`);return response.json();}
  async function access(resource,uid,method='GET',body){const response=await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${resource}`,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{authorization:`Bearer ${tokens[uid]}`,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});return response.status;}
  const input=intent('feedbackSubmit',{category:'General Feedback',rating:4,comments:'Synthetic hosted communication acceptance. No participant data.',allowFollowUp:true});
  const first=(await post('feedback-submit',input,'spark-proof-resident')).result;assert.equal(first.saved,true);const feedbackId=first.resourceId;
  assert.equal((await post('feedback-submit',input,'spark-proof-resident')).result.replay,true);assert.equal((await db.doc(`feedbacks/${feedbackId}`).get()).data().userId,'spark-proof-resident');record('server-owned feedback submission and durable response-loss replay');
  await post('feedback-submit',{...input,userId:'spark-proof-other'},'spark-proof-resident',400);record('forged feedback ownership rejected');
  assert.equal(await access(`feedbacks/${feedbackId}`,'spark-proof-resident'),200);assert.equal(await access(`feedbacks/${feedbackId}`,'spark-proof-admin'),200);assert.equal(await access(`feedbacks/${feedbackId}`,'spark-proof-other'),403);record('feedback history readable by owner/admin and denied to peer');
  assert.equal(await access(`feedbacks/${feedbackId}`,'spark-proof-admin','PATCH',{fields:{status:{stringValue:'resolved'}}}),403);record('direct admin feedback write denied after rollout control activation');
  await post('feedback-context',{feedbackId},'spark-proof-resident',403);record('resident cannot impersonate an administrative reviewer');
  if(!state.reply){const ctx=(await post('feedback-context',{feedbackId})).result;intent('reply',{feedbackId,contextToken:ctx.token,action:'reply',note:'Synthetic acknowledgement: received for review; no fix or dispatch claimed.',notify:true});}
  const reply=(await post('feedback-action',state.reply)).result;assert.equal(reply.queuedCount,1);assert.equal((await post('feedback-action',state.reply)).result.replay,true);record('private reply and notification queued once without duplicate retry');
  const message=await db.collection('feedback_messages').where('feedbackId','==',feedbackId).where('userId','==','spark-proof-resident').orderBy('createdAt','desc').get();assert.ok(message.size>=1);assert.equal(await access(message.docs[0].ref.path,'spark-proof-other'),403);assert.equal(await access(message.docs[0].ref.path,'spark-proof-resident'),200);record('actual indexed private feedback thread and peer denial verified');
  const stale=await post('feedback-action',{...state.reply,requestId:crypto.randomBytes(24).toString('base64url')},'spark-proof-admin',409);assert.equal(stale.error.code,'failed-precondition');record('stale review cannot overwrite a newer feedback state');
  if(!state.close){const ctx=(await post('feedback-context',{feedbackId})).result;intent('close',{feedbackId,contextToken:ctx.token,action:'resolve',note:'Synthetic suggestion recorded; no implemented fix is claimed.',notify:false,outcome:'recorded',confirmed:true});}
  await post('feedback-action',state.close);const closed=(await db.doc(`feedbacks/${feedbackId}`).get()).data();assert.equal(closed.status,'resolved');assert.equal(closed.resolutionOutcome,'recorded');assert.equal((await post('feedback-action',state.reply)).result.replay,true);record('explicit recorded closure and replay after closure preserve history');
  const other=(await post('feedback-submit',intent('noConsentSubmit',{category:'General Feedback',rating:3,comments:'Synthetic consent check only.',allowFollowUp:false}),'spark-proof-other')).result;
  if(!state.noConsentReply){const ctx=(await post('feedback-context',{feedbackId:other.resourceId})).result;intent('noConsentReply',{feedbackId:other.resourceId,contextToken:ctx.token,action:'reply',note:'Synthetic private note; optional contact was not authorized.',notify:true});}
  assert.equal((await post('feedback-action',state.noConsentReply)).result.queuedCount,0);record('no follow-up consent means no optional notification');
  const roadId='spark-normal-form-road',roadBefore=(await db.doc(`roads/${roadId}`).get()).data();assert.equal(roadBefore.studyArea,'nearby_test');
  const publication=intent('publication',{title:'Synthetic communication check',message:'Synthetic test-area advisory. This is not a real warning.',severity:'Advisory',roadId,sendPush:true,minutes:60,studyArea:'nearby_test'});
  const published=(await post('broadcast-publish',publication)).result;assert.equal(published.saved,true);assert.equal((await post('broadcast-publish',publication)).result.replay,true);assert.equal(published.queuedCount,2);record('scoped broadcast published and queued atomically with durable replay');
  const roadAfter=(await db.doc(`roads/${roadId}`).get()).data();assert.equal(roadAfter.status,roadBefore.status);assert.equal(roadAfter.notes,roadBefore.notes);assert.equal(roadAfter.updatedAt?.toMillis(),roadBefore.updatedAt?.toMillis());assert.equal(roadAfter.isVerified,roadBefore.isVerified);record('broadcast leaves official road status, notes and verification timestamp unchanged');
  await post('broadcast-publish',{...publication,requestId:crypto.randomBytes(24).toString('base64url')},'spark-proof-resident',403);record('broadcast publishing restricted to current administrators');
  for(const kind of ['feedback_update','broadcast_update']){const preflight=(await post('push-preflight',{kind})).result;assert.equal(preflight.senderValidated,true);assert.equal(preflight.deviceDeliveryTested,false);}record('real Google validation-only acceptance for both typed notification payloads');
  if(!state.withdraw){const ctx=(await post('broadcast-context',{alertId:published.resourceId})).result;intent('withdraw',{alertId:published.resourceId,contextToken:ctx.token,note:'Synthetic advisory withdrawn after the acceptance check.'});}
  await post('broadcast-action',state.withdraw);assert.equal((await post('broadcast-action',state.withdraw)).result.replay,true);assert.equal((await db.doc(`alerts/${published.resourceId}`).get()).data().status,'withdrawn');record('withdrawal preserves the alert record and replays without duplication');
  for(let i=0;i<3;i++)await post('push-drain',{},null);
  const queued=await db.collection('notification_outbox').where('requestHash','==',crypto.createHash('sha256').update(`spark-proof-admin|${state.reply.requestId}`).digest('hex')).get();assert.equal(queued.size,1);assert.equal(queued.docs[0].data().status,'no_device');assert.equal((await db.doc(`feedbacks/${feedbackId}`).get()).data().adminReply,closed.adminReply);record('sender finishes without a device while the saved private reply remains available');
  evidence.completed=true;record('communication acceptance complete; no APK or physical delivery claim');console.log(JSON.stringify(evidence,null,2));
 }finally{await deleteApp(app);}
}
main(process.argv.slice(2)).catch(()=>{console.error(JSON.stringify({passed:false,stage,reason:'Hosted communication check failed; private details were not logged.'}));process.exitCode=1;});
