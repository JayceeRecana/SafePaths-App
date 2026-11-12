const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
const {storageFixture}=require('./support/proof_storage_fixture.cjs');
const {doc,getDoc,setDoc,deleteDoc}=require('firebase/firestore');
const {assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
// The Auth emulator's password sign-in endpoint uses the CLI's demo project.
// Run the files serially (package script) so their fixture resets cannot race.
const projectId='demo-safepaths-reliability';
if(!process.env.FIRESTORE_EMULATOR_HOST||!process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Run the demo Firestore/Auth emulators for the Spark proof.');
let app,admin,auth,env,handler,defaultHandler,followupHandler,photos,fixture,db,push,createPush,pushNow,sendResults,sendCalls,accountEnabled;
before(async()=>{
  const [{FirestoreRest,createFirebaseVerifier},{ProofStorage},{createProofHandler}]=await Promise.all([
    import('../../supabase/functions/_shared/proof_firebase.mjs'),import('../../supabase/functions/_shared/proof_storage.mjs'),import('../../supabase/functions/_shared/proof_handler.mjs')]);
  env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
  app=initializeApp({projectId},'spark-proof');admin=getFirestore(app);auth=getAuth(app);
  const credential={token:async()=>'owner'};
  db=new FirestoreRest({projectId,credential,emulatorHost:process.env.FIRESTORE_EMULATOR_HOST});
  fixture=storageFixture();photos=new ProofStorage({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher});
  createPush=(await import('../../supabase/functions/_shared/proof_push.mjs')).createProofPush;
  push=createPush({db,allowedUids:new Set(['resident','other','admin']),clock:()=>Math.max(pushNow,Date.now()),fcm:{account:async()=>({enabled:accountEnabled,validSince:0}),send:async value=>{sendCalls.push(value);return sendResults.shift()??{status:'accepted'};}}});
  handler=createProofHandler({db,photos,allowedUids:new Set(['resident','other','admin','unverified']),verify:createFirebaseVerifier({projectId,credential,emulatorAuthHost:process.env.FIREBASE_AUTH_EMULATOR_HOST}),push,workerSecret:'W'.repeat(43)});
  defaultHandler=handler;
  followupHandler=createProofHandler({db,photos,allowedUids:new Set(['resident','other','admin','unverified']),verify:createFirebaseVerifier({projectId,credential,emulatorAuthHost:process.env.FIREBASE_AUTH_EMULATOR_HOST}),push,followupsEnabled:true});
});
after(async()=>{await env.cleanup();await deleteApp(app);});
beforeEach(async()=>{
  handler=defaultHandler;
  await env.clearFirestore();fixture.files.clear();
  pushNow=Date.now();sendResults=[];sendCalls=[];accountEnabled=true;
  for(const uid of ['resident','other','admin','unverified']) {
    try{await auth.deleteUser(uid);}catch(_){}
    await auth.createUser({uid,email:`${uid}@example.com`,emailVerified:uid!=='unverified',password:'Proof-Test9!'});
    await admin.doc(`users/${uid}`).set({role:uid==='admin'?'admin':'user',trustScore:50,verifiedReports:0,dismissedReports:0});
  }
  await admin.doc('roads/spark-proof-road').set({name:'Synthetic proof road',status:'not_passable',geometry:{segments:[{points:[{lon:120.984,lat:14.675},{lon:120.984,lat:14.677}]}]}});
});
async function token(uid='resident') {
  const response=await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fixture`,
    {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:`${uid}@example.com`,password:'Proof-Test9!',returnSecureToken:true})});
  const data=await response.json();assert.ok(data.idToken,'Test sign-in must return a token');return data.idToken;
}
async function request(operation,body,uid='resident',bearer) {
  const authorization=bearer??await token(uid);
  const response=await handler(new Request(`${photos.endpoint}/${operation}`,{method:'POST',
    headers:{authorization:`Bearer ${authorization}`,'content-type':body instanceof Uint8Array?'image/jpeg':'application/json'},
    body:body instanceof Uint8Array?body:JSON.stringify(body)}));
  return {status:response.status,data:await response.json()};
}
const payload=(letter='a',imageUrl)=>({requestId:letter.repeat(24),roadId:'spark-proof-road',title:'Synthetic flood',description:'Test only',severity:'High',isEmergency:false,
  location:{lat:14.676,lng:120.984,source:'manual',...(imageUrl?{imageUrl}:{})}});

test('follow-up endpoints stay disabled until the coordinated test rollout',async()=>{
  const response=await request('followup-context',{data:{rootReportId:'a'.repeat(64)}});
  assert.equal(response.status,503);
});

test('REST follow-ups preserve evidence, enforce privacy and keep reopening separate from rewards',async()=>{
  handler=followupHandler;
  const imageUrl=(await request('photo-upload',new Uint8Array([255,216,255,1,255,217]))).data.imageUrl;
  const saved=await request('submit-report',{data:payload('a',imageUrl)});
  assert.equal(saved.status,200,JSON.stringify(saved.data));
  const rootReportId=saved.data.result.reportId;
  const original=(await admin.doc(`reports/${rootReportId}`).get()).data();
  assert.ok(original.originalSubmission.submittedAt.toMillis());
  await admin.doc('users/resident').update({lastReportAt:new Date(Date.now()-360000)});
  const context=await request('followup-context',{data:{rootReportId}});
  assert.equal(context.status,200,JSON.stringify(context.data));
  assert.equal((await request('followup-context',{data:{rootReportId}},'other')).status,403);
  assert.equal((await request('followup-context',{data:{rootReportId}},'admin')).data.result.viewerIsAdmin,true);
  const update={rootReportId,requestId:'f'.repeat(24),contextToken:context.data.result.token,
    conditionChange:'cleared',severity:'Low',description:'No floodwater visible at the time of this new observation.',
    observedAt:new Date(original.observedAt.toMillis()+1000).toISOString()};
  const child=await request('followup-submit',{data:update});
  assert.equal(child.status,200,JSON.stringify(child.data));
  assert.equal((await request('followup-submit',{data:update})).data.result.replay,true);
  assert.equal((await request('update-report',{data:{reportId:rootReportId,requestId:'z'.repeat(24),description:'Overwrite',severity:'Low',expectedUpdatedAt:original.createdAt.toMillis(),observedAt:update.observedAt}})).status,409);
  const after=(await admin.doc(`reports/${rootReportId}`).get()).data();
  assert.equal(after.imageUrl,original.imageUrl);assert.equal(after.description,original.description);
  assert.equal(after.createdAt.toMillis(),original.createdAt.toMillis());
  assert.equal((await admin.doc(`reports/${child.data.result.reportId}`).get()).data().imageUrl,undefined);
  async function review(reportId,letter,extra={}){
    const ctx=await request('admin-context',{data:{reportId}},'admin');
    return request('admin-action',{data:{reportId,requestId:letter.repeat(24),contextToken:ctx.data.result.token,
      action:'verify',roadStatus:'passable',note:'Independent current check found the road passable.',verifiedCurrentConditions:true,...extra}},'admin');
  }
  assert.equal((await review(child.data.result.reportId,'b',{meaningfulFollowup:true})).status,409);
  const originalReview=await review(rootReportId,'c');
  assert.equal(originalReview.status,200,JSON.stringify(originalReview.data));
  assert.equal(originalReview.data.result.pointsAwarded,10);
  const awaiting=(await admin.doc(`reports/${child.data.result.reportId}`).get()).data();
  assert.equal(awaiting.status,'pending');assert.equal(awaiting.incidentReviewStatus,'passable');
  const ctx=await request('admin-context',{data:{reportId:child.data.result.reportId}},'admin');
  const action={reportId:child.data.result.reportId,contextToken:ctx.data.result.token,action:'verify',
    roadStatus:'passable',note:'This new observation is verified separately.',verifiedCurrentConditions:true,meaningfulFollowup:true};
  const concurrent=await Promise.all(['d','e'].map(letter=>request('admin-action',{data:{...action,requestId:letter.repeat(24)}},'admin')));
  assert.equal(concurrent.filter(r=>r.status===200).length,1,JSON.stringify(concurrent));
  assert.equal((await admin.doc('users/resident').get()).data().trustScore,65);
  const own=env.authenticatedContext('resident',{email_verified:true}).firestore(),other=env.authenticatedContext('other',{email_verified:true}).firestore();
  const ledger=(await admin.collection('incident_rewards').get()).docs[0];
  await assertFails(setDoc(doc(own,'incident_rewards',ledger.id),{followupClaimed:false}));
  await assertFails(getDoc(doc(other,'incident_rewards',ledger.id)));
  const message=(await admin.collection('report_messages').where('reportId','==',child.data.result.reportId).get()).docs[0];
  await assertSucceeds(getDoc(doc(own,'report_messages',message.id)));
  await assertFails(getDoc(doc(other,'report_messages',message.id)));
});

test('REST proof uploads a photo, saves an atomic report, preserves profile/closure, and authorizes two identities',async()=>{
  const photo=new Uint8Array([255,216,255,1,255,217]);
  const uploaded=await request('photo-upload',photo);assert.equal(uploaded.status,200,JSON.stringify(uploaded.data));
  const imageUrl=uploaded.data.imageUrl;assert.ok(imageUrl.startsWith(`${photos.endpoint}/photo/resident/`));
  const saved=await request('submit-report',{data:{...payload('a',imageUrl),userId:'admin',authorityScore:100}});
  assert.equal(saved.status,200,JSON.stringify(saved.data));
  const report=(await admin.doc(`reports/${saved.data.result.reportId}`).get()).data();
  assert.equal(report.userId,'resident');assert.equal(report.authorityScore,80);assert.equal(report.imageUrl,imageUrl);assert.equal(report.status,'pending');
  assert.ok(report.createdAt.toMillis());assert.equal((await admin.doc('users/resident').get()).data().role,'user');
  assert.equal((await admin.doc('users/resident').get()).data().trustScore,50);
  assert.equal((await admin.doc('roads/spark-proof-road').get()).data().status,'not_passable');
  assert.equal((await request('photo-url',{imageUrl},'resident')).status,200);
  assert.equal((await request('photo-url',{imageUrl},'admin')).status,200);
  assert.equal((await request('photo-url',{imageUrl,role:'admin'},'other')).status,403);
  const other=await request('submit-report',{data:payload('b',imageUrl)},'other');assert.equal(other.status,403);
});

test('REST response-loss replay is durable and cannot reuse a receipt for changed photo or description',async()=>{
  const first=await request('submit-report',{data:payload()});assert.equal(first.status,200,JSON.stringify(first.data));
  const replay=await request('submit-report',{data:payload()});assert.equal(replay.status,200);assert.equal(replay.data.result.replay,true);
  assert.equal(replay.data.result.reportId,first.data.result.reportId);assert.equal((await admin.collection('reports').get()).size,1);
  assert.equal((await request('submit-report',{data:{...payload(),description:'changed'}})).status,409);
  assert.equal((await request('submit-report',{data:payload('a',photos.reference('resident','f'.repeat(64)))})).status,409);
});

test('REST concurrent different requests preserve atomic five-minute cooldown',async()=>{
  const bearer=await token();
  const results=await Promise.all([request('submit-report',{data:payload('a')},'resident',bearer),request('submit-report',{data:payload('b')},'resident',bearer)]);
  assert.equal(results.filter(r=>r.status===200).length,1,JSON.stringify(results));
  assert.equal(results.filter(r=>r.status===429&&r.data.error.code==='resource-exhausted').length,1,JSON.stringify(results));
  assert.equal((await admin.collection('reports').get()).size,1);
});

test('REST later edits preserve evidence and escalation limits',async()=>{
  const reference=(await request('photo-upload',new Uint8Array([255,216,255,1,255,217]))).data.imageUrl;
  const first=await request('submit-report',{data:{...payload('a',reference),severity:'Low'}});assert.equal(first.status,200,JSON.stringify(first.data));
  await admin.doc('users/resident').update({lastReportAt:new Date(Date.now()-61000)});
  const escalation=await request('submit-report',{data:{...payload('b'),severity:'High',description:'Worsening'}});
  assert.equal(escalation.status,200,JSON.stringify(escalation.data));assert.equal(escalation.data.result.reportId,first.data.result.reportId);
  const updated=(await admin.doc(`reports/${first.data.result.reportId}`).get()).data();assert.equal(updated.imageUrl,reference);assert.equal(updated.authorityScore,80);
  assert.equal((await request('submit-report',{data:payload('c')})).status,429);
});

test('REST proof refuses unverified, disabled and revoked sessions and out-of-range coordinates',async()=>{
  assert.equal((await request('submit-report',{data:payload()},'unverified')).status,401);
  const bearer=await token();await auth.updateUser('resident',{disabled:true});
  assert.equal((await request('submit-report',{data:payload()},'resident',bearer)).status,401);
  await auth.updateUser('resident',{disabled:false});
  const revived=await token();
  // Move validSince beyond the token's auth_time using the emulator admin REST surface.
  const claims=JSON.parse(Buffer.from(revived.split('.')[1],'base64url'));
  const changed=await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:update`,{method:'POST',headers:{authorization:'Bearer owner','content-type':'application/json'},body:JSON.stringify({localId:'resident',validSince:String(claims.auth_time+2)})});
  assert.ok(changed.ok);
  assert.equal((await request('submit-report',{data:payload()},'resident',revived)).status,401);
  const far=await request('submit-report',{data:{...payload(),location:{lat:0,lng:0}}},'other');assert.equal(far.data.error.message,'OUT_OF_RANGE');
});

async function reportForReview(letter='k',uid='resident') {
  const saved=await request('submit-report',{data:payload(letter)},uid);
  assert.equal(saved.status,200,JSON.stringify(saved.data));return saved.data.result.reportId;
}
async function reviewContext(reportId,roadIds,uid='admin') {
  const result=await request('admin-context',{data:{...(reportId?{reportId}:{}),...(roadIds?{roadIds}:{})}},uid);
  assert.equal(result.status,200,JSON.stringify(result.data));return result.data.result;
}
const reviewAction=(action,reportId,context,letter='m',extra={})=>({data:{action,reportId,contextToken:context.token,requestId:letter.repeat(24).slice(0,48),...extra}});
const verification={roadStatus:'not_passable',note:'Synthetic current field inspection confirmed flooding.',verifiedCurrentConditions:true};

test('admin context is read-only; explicit start saves one private acknowledgement and a durable receipt',async()=>{
  const id=await reportForReview();
  assert.equal((await request('admin-context',{data:{reportId:id}},'resident')).status,403);
  const context=await reviewContext(id);
  assert.equal((await admin.doc(`reports/${id}`).get()).data().status,'pending');
  const action=reviewAction('start',id,context);
  const result=await request('admin-action',action,'admin');assert.equal(result.status,200,JSON.stringify(result.data));
  const report=(await admin.doc(`reports/${id}`).get()).data();assert.equal(report.status,'under_review');assert.ok(report.reviewStartedAt.toMillis());assert.equal(report.reviewedAt,undefined);
  assert.equal(report.adminReply,undefined);assert.equal(report.adminReplies,undefined);assert.equal(report.hasAdminUpdates,true);
  assert.equal((await request('admin-action',action,'admin')).data.result.replay,true);
  assert.equal((await admin.collection('report_messages').get()).size,1);assert.equal((await admin.collection('admin_audits').get()).size,1);
  const message=(await admin.collection('report_messages').get()).docs[0];
  await assertSucceeds(getDoc(doc(env.authenticatedContext('resident',{email_verified:true}).firestore(),'report_messages',message.id)));
  await assertFails(getDoc(doc(env.authenticatedContext('other',{email_verified:true}).firestore(),'report_messages',message.id)));
  await assertFails(setDoc(doc(env.authenticatedContext('admin',{email_verified:true}).firestore(),'reports',id),{status:'verified'},{merge:true}));
});

test('admin verification commits report, current road, exact points, audit and private update together',async()=>{
  const invalidId=await reportForReview('j');
  const invalidContext=await reviewContext(invalidId);
  assert.equal((await request('admin-action',reviewAction('verify',invalidId,invalidContext,'badstatus',{...verification,roadStatus:'toString'}),'admin')).status,400);
  await admin.doc('users/resident').update({lastReportAt:new Date(Date.now()-301000)});
  const id=await reportForReview(),context=await reviewContext(id);
  const action=reviewAction('verify',id,context,'n',verification),saved=await request('admin-action',action,'admin');
  assert.equal(saved.status,200,JSON.stringify(saved.data));assert.equal(saved.data.result.pointsAwarded,10);
  const report=(await admin.doc(`reports/${id}`).get()).data(),road=(await admin.doc('roads/spark-proof-road').get()).data();
  assert.equal(report.status,'verified');assert.equal(report.incidentReviewStatus,'not_passable');assert.equal(report.pointsAwarded,10);assert.ok(report.reviewedAt.toMillis());
  assert.equal(road.status,'not_passable');assert.equal((await admin.doc('users/resident').get()).data().trustScore,60);
  assert.equal((await request('admin-action',action,'admin')).data.result.replay,true);assert.equal((await admin.doc('users/resident').get()).data().verifiedReports,1);
  assert.equal((await admin.collection('notification_outbox').get()).docs[0].data().status,'awaiting_sender');
});

test('two admins cannot apply different decisions from the same old review context',async()=>{
  const id=await reportForReview(),context=await reviewContext(id);await admin.doc('users/other').update({role:'admin'});
  const results=await Promise.all([
    request('admin-action',reviewAction('verify',id,context,'o',verification),'admin'),
    request('admin-action',reviewAction('verify',id,context,'p',{...verification,roadStatus:'partial'}),'other')]);
  assert.equal(results.filter(result=>result.status===200).length,1,JSON.stringify(results));assert.equal(results.filter(result=>result.status===409).length,1,JSON.stringify(results));
  assert.equal((await admin.doc('users/resident').get()).data().verifiedReports,1);assert.equal((await admin.collection('admin_audits').get()).size,1);
});

test('new observations invalidate an open admin decision and role removal invalidates replay',async()=>{
  const id=await reportForReview(),context=await reviewContext(id);
  await admin.doc('users/resident').update({lastReportAt:new Date(Date.now()-301000)});
  assert.equal((await request('submit-report',{data:{...payload('q'),description:'Newer conditions while admin was reading'}})).status,200);
  assert.equal((await request('admin-action',reviewAction('verify',id,context,'r',verification),'admin')).status,409);
  assert.equal((await admin.doc(`reports/${id}`).get()).data().status,'pending');
  const fresh=await reviewContext(id),action=reviewAction('start',id,fresh,'s');assert.equal((await request('admin-action',action,'admin')).status,200);
  await admin.doc('users/admin').update({role:'user'});assert.equal((await request('admin-action',action,'admin')).status,403);
});

test('road reopening resolves the incident while each resident report still awaits its own review',async()=>{
  const first=await reportForReview('t'),second=await reportForReview('u','other'),context=await reviewContext(null,['spark-proof-road']);
  const result=await request('admin-action',{data:{action:'road_review',roadIds:['spark-proof-road'],contextToken:context.token,requestId:'v'.repeat(24),...verification,roadStatus:'passable'}},'admin');
  assert.equal(result.status,200,JSON.stringify(result.data));assert.equal(result.data.result.pointsAwarded,0);
  for(const id of [first,second]) { const saved=(await admin.doc(`reports/${id}`).get()).data();assert.equal(saved.status,'pending');assert.equal(saved.reviewedAt,undefined); }
  for(const uid of ['resident','other'])assert.equal((await admin.doc(`users/${uid}`).get()).data().trustScore,50);
  assert.equal((await admin.doc('road_incidents/spark-proof-road').get()).data().state,'resolved');
});

test('private replies are saved once without changing report status or claiming push delivery',async()=>{
  const id=await reportForReview(),action={data:{action:'reply',reportId:id,requestId:'w'.repeat(24),message:'Synthetic acknowledgement only.',sender:'forged sender'}};
  assert.equal((await request('admin-action',action,'resident')).status,403);
  const results=await Promise.all([request('admin-action',action,'admin'),request('admin-action',action,'admin')]);
  for(const result of results){assert.equal(result.status,200,JSON.stringify(result.data));assert.equal(result.data.result.notification,'saved_in_app');}
  const report=(await admin.doc(`reports/${id}`).get()).data();assert.equal(report.status,'pending');assert.equal(report.adminReply,undefined);
  const messages=await admin.collection('report_messages').get();assert.equal(messages.size,1);assert.equal(messages.docs[0].data().sender,'SafePaths administrator');
  assert.equal((await request('admin-action',{data:{...action.data,message:'different'}},'admin')).status,409);
});

test('SOS spam dismissal needs explicit confirmations and clamps the actual penalty',async()=>{
  const id=await reportForReview();await admin.doc(`reports/${id}`).update({isEmergency:true});await admin.doc('users/resident').update({trustScore:5});
  const context=await reviewContext(id),action=reviewAction('dismiss',id,context,'x',{reason:'spam_false',note:'Confirmed false evidence after checking current records.'});
  assert.equal((await request('admin-action',action,'admin')).status,400);
  action.data.confirmEmergency=true;assert.equal((await request('admin-action',action,'admin')).status,400);
  action.data.confirmedFalseReport=true;const result=await request('admin-action',action,'admin');assert.equal(result.status,200,JSON.stringify(result.data));assert.equal(result.data.result.pointsAwarded,-5);
  assert.equal((await admin.doc('users/resident').get()).data().trustScore,0);assert.equal((await admin.doc('roads/spark-proof-road').get()).data().status,'not_passable');
});

test('verification reports the actual capped reward and preserves the per-road cooldown',async()=>{
  const id=await reportForReview();await admin.doc('users/resident').update({trustScore:97});
  let context=await reviewContext(id),result=await request('admin-action',reviewAction('verify',id,context,'y',verification),'admin');
  assert.equal(result.status,200,JSON.stringify(result.data));assert.equal(result.data.result.pointsAwarded,3);
  await admin.doc(`reports/${id}`).update({status:'under_review'});context=await reviewContext(id);
  result=await request('admin-action',reviewAction('verify',id,context,'z',verification),'admin');assert.equal(result.status,200,JSON.stringify(result.data));assert.equal(result.data.result.pointsAwarded,0);
});

test('resident edits keep identity/photo ownership, reject stale changes and remain replayable after admin review',async()=>{
  const id=await reportForReview(),report=(await admin.doc(`reports/${id}`).get()).data();
  await admin.doc('users/resident').update({lastReportAt:new Date(Date.now()-301000)});
  const action={data:{reportId:id,requestId:'edit_'.repeat(6),severity:'Medium',description:'Updated synthetic observation.',observedAt:new Date().toISOString(),expectedUpdatedAt:report.lastUpdatedByUser.toMillis(),userId:'other'}};
  assert.equal((await request('update-report',action,'other')).status,403);
  const saved=await request('update-report',action);assert.equal(saved.status,200,JSON.stringify(saved.data));assert.equal(saved.data.result.reportId,id);
  assert.equal((await admin.doc(`reports/${id}`).get()).data().userId,'resident');
  const context=await reviewContext(id);assert.equal((await request('admin-action',reviewAction('verify',id,context,'zz',verification),'admin')).status,200);
  assert.equal((await request('update-report',action)).data.result.replay,true);
  assert.equal((await request('update-report',{data:{...action.data,requestId:'new_edit_'.repeat(4)}})).status,409);
});

test('failed commits change nothing; a lost commit response recovers the saved review without duplicate points',async()=>{
  const id=await reportForReview(),context=await reviewContext(id),action=reviewAction('verify',id,context,'lostcommit',verification);
  const original=db.request.bind(db);
  try{
    db.request=async(suffix,...args)=>{if(suffix===':commit')throw Object.assign(new Error('synthetic unavailable'),{code:'unavailable'});return original(suffix,...args);};
    assert.equal((await request('admin-action',action,'admin')).status,503);
    assert.equal((await admin.doc(`reports/${id}`).get()).data().status,'pending');assert.equal((await admin.doc('users/resident').get()).data().trustScore,50);
    assert.equal((await admin.collection('admin_audits').get()).size,0);assert.equal((await admin.collection('report_messages').get()).size,0);
    let lost=false;
    db.request=async(suffix,...args)=>{const result=await original(suffix,...args);if(suffix===':commit'&&!lost){lost=true;throw Object.assign(new Error('synthetic lost response'),{code:'unavailable'});}return result;};
    const saved=await request('admin-action',action,'admin');assert.equal(saved.status,200,JSON.stringify(saved.data));assert.equal(saved.data.result.replay,true);
    assert.equal((await admin.doc('users/resident').get()).data().verifiedReports,1);assert.equal((await admin.collection('admin_audits').get()).size,1);
  }finally{db.request=original;}
});

const installation='synthetic_installation_'.padEnd(43,'a'),fcmToken='synthetic_fcm_token_'.padEnd(60,'x');
async function register(uid='resident',sequence=1,extra={}){
 return request('push-device',{data:{installation,sequence,mode:'register',token:fcmToken,...extra}},uid);
}
async function queuedUpdate(){
 const id=await reportForReview();const context=await reviewContext(id);
 const r=await request('admin-action',reviewAction('start',id,context),'admin');assert.equal(r.status,200);
 const outbox=(await admin.collection('notification_outbox').get()).docs[0];return {id,eventId:outbox.id,path:`notification_outbox/${outbox.id}`};
}
test('push tokens are private, registrations are sequenced and account transfer rejects late old saves',async()=>{
 assert.equal((await register()).status,200);assert.equal((await register()).status,200);
 const device=(await admin.collection('push_devices').get()).docs[0];
 for(const uid of ['resident','admin'])await assertFails(getDoc(doc(env.authenticatedContext(uid,{email_verified:true}).firestore(),'push_devices',device.id)));
 assert.equal((await register('other',2)).status,200);
 assert.equal((await register('resident',1)).status,409);
 assert.equal((await register('resident',1,{installation:'different_installation_'.padEnd(43,'b')})).status,409);
 const current=(await device.ref.get()).data();assert.equal(current.userId,'other');assert.equal(current.sequence,2);
 assert.equal((await request('push-device',{data:{installation,sequence:3,mode:'unregister'}},'resident')).status,403);
});
test('sign-out deregistration prevents a queued send and keeps the in-app message',async()=>{
 const event=await queuedUpdate();await register();
 assert.equal((await request('push-device',{data:{installation,sequence:2,mode:'unregister'}})).status,200);
 assert.equal(await push.process(event.path),'no_device');assert.equal(sendCalls.length,0);
 assert.ok((await admin.doc(`report_messages/${event.eventId}`).get()).exists);
});
test('push worker is protected and provider acceptance never claims phone receipt',async()=>{
 const event=await queuedUpdate();await register();
 assert.equal((await request('push-drain',{})).status,401);
 const worker=await handler(new Request(`${photos.endpoint}/push-drain`,{method:'POST',headers:{authorization:`Bearer ${'W'.repeat(43)}`,'content-type':'application/json'},body:'{}'}));assert.equal(worker.status,200);
 assert.equal(sendCalls.length,1);assert.equal((await admin.doc(event.path).get()).data().status,'fcm_accepted');
 const owner=await request('push-status',{data:{eventId:event.eventId}});assert.equal(owner.status,200);assert.equal(owner.data.result.deviceReceiptConfirmed,false);assert.equal(owner.data.result.acceptedCount,1);
 assert.equal((await request('push-status',{data:{eventId:event.eventId}},'other')).status,403);
 assert.equal((await request('push-status',{data:{eventId:event.eventId}},'admin')).status,200);
 assert.ok((await admin.doc(`report_messages/${event.eventId}`).get()).exists);
});
test('two concurrent workers claim an event once and ordinary replay does not resend',async()=>{
 const event=await queuedUpdate();await register();
 await Promise.all([push.process(event.path),push.process(event.path)]);assert.equal(sendCalls.length,1);
 assert.equal(await push.process(event.path),'skipped');assert.equal(sendCalls.length,1);
});
test('temporary push failures back off and retry only the unaccepted device',async()=>{
 const event=await queuedUpdate();await register();await register('resident',1,{installation:'second_installation_'.padEnd(43,'b'),token:'second_fcm_token_'.padEnd(60,'y')});
 sendResults=[{status:'accepted'},{status:'retry',retryAfterMs:120000}];
 assert.equal(await push.process(event.path),'retry');assert.equal(sendCalls.length,2);
 assert.equal(await push.process(event.path),'skipped');assert.equal(sendCalls.length,2);
 pushNow+=121000;assert.equal(await push.process(event.path),'fcm_accepted');assert.equal(sendCalls.length,3);
 assert.equal(new Set(sendCalls.map(v=>v.eventId)).size,1);
});
test('unregistered token is retired, while payload/configuration rejection preserves it',async()=>{
 const event=await queuedUpdate();await register();sendResults=[{status:'invalid_token'}];
 assert.equal(await push.process(event.path),'no_device');let device=(await admin.collection('push_devices').get()).docs[0];assert.equal(device.data().active,false);
 await register('resident',2);
 await admin.doc(event.path).update({status:'awaiting_sender',dispatchable:true,dueAt:new Date(pushNow),targets:{},discarded:{}});
 // A new independent message can target the renewed registration.
 const context=await reviewContext(event.id);await request('admin-action',reviewAction('reply',event.id,context,'reject',{message:'Synthetic private update'}),'admin');
 const next=(await admin.collection('notification_outbox').get()).docs.find(d=>d.id!==event.eventId);sendResults=[{status:'failed',code:'provider_rejected'}];
 assert.equal(await push.process(next.ref.path),'failed');device=await device.ref.get();assert.equal(device.data().active,true);
});
test('a retry does not follow a transferred device into another account',async()=>{
 const event=await queuedUpdate();await register();sendResults=[{status:'retry'}];assert.equal(await push.process(event.path),'retry');
 await register('other',2);pushNow+=61000;assert.equal(await push.process(event.path),'no_device');assert.equal(sendCalls.length,1);
});
test('expired updates and disabled accounts never reach the push provider',async()=>{
 const event=await queuedUpdate();await register();accountEnabled=false;
 assert.equal(await push.process(event.path),'account_unavailable');assert.equal(sendCalls.length,0);
 accountEnabled=true;await admin.doc(event.path).update({status:'awaiting_sender',dispatchable:true,dueAt:new Date(pushNow),expiresAt:new Date(pushNow-1)});
 assert.equal(await push.process(event.path),'skipped');assert.equal((await admin.doc(event.path).get()).data().status,'expired');assert.equal(sendCalls.length,0);
});
test('device count is bounded and unverified accounts cannot register or trigger sending',async()=>{
 for(let n=0;n<3;n++)assert.equal((await register('resident',1,{installation:`installation_${n}_`.padEnd(43,'a'),token:`token_${n}_`.padEnd(60,'x')})).status,200);
 assert.equal((await register('resident',1,{installation:'installation_4_'.padEnd(43,'a'),token:'token_4_'.padEnd(60,'x')})).status,429);
 assert.equal((await register('unverified')).status,401);
});
test('a failed immediate push hook cannot turn an already saved admin message into failure',async()=>{
 const id=await reportForReview();const {createProofHandler}=await import('../../supabase/functions/_shared/proof_handler.mjs');
 const isolated=createProofHandler({db,photos,allowedUids:new Set(['admin']),verify:async()=>'admin',push:{drain:async()=>({})},background:()=>{throw new Error('synthetic scheduler unavailable');}});
 const data={action:'reply',requestId:'saved_without_push_hook_12345',reportId:id,message:'Synthetic private update stays saved.'};
 const response=await isolated(new Request(`${photos.endpoint}/admin-action`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({data})}));
 assert.equal(response.status,200);assert.equal((await response.json()).result.notification,'saved_in_app');
 assert.equal((await admin.collection('report_messages').get()).size,1);assert.equal((await admin.collection('notification_outbox').get()).size,1);
});
test('scheduled worker HMAC tickets are one-use even when requests arrive together',async()=>{
 const now=String(Math.floor(Date.now()/1000)),nonce='c'.repeat(32),key='W'.repeat(43);
 const signature=require('node:crypto').createHmac('sha256',key).update(`${now}.${nonce}`).digest('hex');
 const make=()=>new Request(`${photos.endpoint}/push-drain`,{method:'POST',headers:{'x-proof-worker-time':now,'x-proof-worker-nonce':nonce,'x-proof-worker-signature':signature},body:'{}'});
 const responses=await Promise.all([handler(make()),handler(make())]);assert.deepEqual(responses.map(r=>r.status).sort(),[200,409]);
 const records=await admin.collection('push_worker_requests').get();assert.equal(records.size,1);
 await assertFails(getDoc(doc(env.authenticatedContext('admin',{email_verified:true}).firestore(),'push_worker_requests',records.docs[0].id)));
});
test('a removed uploaded photo requests reupload, while an already saved report still replays its receipt',async()=>{
 const bytes=new Uint8Array([255,216,255,7,255,217]);
 const uploaded=await request('photo-upload',bytes);assert.equal(uploaded.status,200);const imageUrl=uploaded.data.imageUrl;
 fixture.files.clear();
 const data=payload('p',imageUrl);let result=await request('submit-report',{data});assert.equal(result.status,400);assert.equal(result.data.error.code,'photo-unavailable');
 assert.equal((await admin.collection('reports').get()).size,0);
 assert.equal((await request('photo-upload',bytes)).data.imageUrl,imageUrl);
 result=await request('submit-report',{data});assert.equal(result.status,200);
 fixture.files.clear();result=await request('submit-report',{data});assert.equal(result.status,200);assert.equal(result.data.result.replay,true);
});

// Core migration uses the same real REST transaction adapter as the hosted Edge function.
async function coreFixture(fetcher) {
  const {createCoreMaintenance}=await import('../../supabase/functions/_shared/proof_core.mjs');
  await admin.doc('system/core_setup').set({version:1,studyArea:'nearby_test'});
  await admin.doc('system/road_inputs').set({updatedAt:new Date()});
  await admin.doc('roads/spark-proof-road').update({studyArea:'nearby_test',neighbors:[],vulnerability:'medium',updatedAt:new Date()});
  return createCoreMaintenance({db,fetcher:fetcher??(async()=>new Response(JSON.stringify({
    current_units:{time:'unixtime',interval:'seconds',precipitation:'mm',wind_speed_10m:'m/s',temperature_2m:'\u00b0C',relative_humidity_2m:'%'},
    current:{time:Math.floor(Date.now()/1000),interval:900,precipitation:0,wind_speed_10m:2,temperature_2m:29,relative_humidity_2m:70,weather_code:0}
  })))});
}
async function observe(choice='appears_passable',uid='other',id='o'.repeat(24)) {
  const {createResidentObservations}=await import('../../supabase/functions/_shared/proof_incidents.mjs');
  const incident=(await admin.doc('road_incidents/spark-proof-road').get()).data();
  return createResidentObservations({db})(uid,{roadId:'spark-proof-road',incidentId:incident.incidentId,choice,requestId:id,observedAt:new Date().toISOString()});
}
test('Spark observation rejects self confirmation and never reopens the official road',async()=>{
 await request('submit-report',{data:payload()});
 await assert.rejects(()=>observe('still_flooded','resident'),{code:'self-confirmation'});
 assert.equal((await observe()).saved,true);
 assert.equal((await admin.doc('roads/spark-proof-road').get()).data().status,'not_passable');
 const incident=(await admin.doc('road_incidents/spark-proof-road').get()).data();assert.equal(incident.state,'under_verification');assert.equal(incident.counts.appears_passable,1);
 await assert.rejects(()=>observe('still_flooded','other','z'.repeat(24)),{code:'resource-exhausted'});
});
test('Spark observation lost-response retry remains durable after incident resolution',async()=>{
 await request('submit-report',{data:payload()});
 const {createResidentObservations}=await import('../../supabase/functions/_shared/proof_incidents.mjs'),api=createResidentObservations({db});
 const incident=(await admin.doc('road_incidents/spark-proof-road').get()).data(),data={roadId:'spark-proof-road',incidentId:incident.incidentId,choice:'appears_passable',requestId:'o'.repeat(24),observedAt:new Date().toISOString()};
 await api('other',data);await admin.doc('road_incidents/spark-proof-road').update({state:'resolved'});
 assert.equal((await api('other',data)).replay,true);
 await assert.rejects(()=>api('other',{...data,choice:'still_flooded'}),{code:'already-exists'});
 await assert.rejects(()=>api('other',{...data,requestId:'n'.repeat(24)}),{code:'failed-precondition'});
});
test('Spark current observation rejects old/future evidence without incrementing counts',async()=>{
 await request('submit-report',{data:payload()});
 const {createResidentObservations}=await import('../../supabase/functions/_shared/proof_incidents.mjs'),api=createResidentObservations({db});
 const incident=(await admin.doc('road_incidents/spark-proof-road').get()).data();
 for(const offset of [-301000,61000])await assert.rejects(()=>api('other',{roadId:'spark-proof-road',incidentId:incident.incidentId,choice:'still_flooded',requestId:'o'.repeat(24),observedAt:new Date(Date.now()+offset).toISOString()}),{code:'observation-stale'});
 assert.equal((await admin.doc('road_incidents/spark-proof-road').get()).data().revision,1);
});
test('Spark core calculates with real REST paging and skips unchanged road writes on the next cycle',async()=>{
 const core=await coreFixture();const first=await core.run();assert.equal(first.completed,true,JSON.stringify(first));assert.equal(first.changedRoads,1);
 const road=await admin.doc('roads/spark-proof-road').get(),stamp=road.data().riskUpdatedAt.toMillis();assert.equal(road.data().riskScore,100);
 const second=await core.run();assert.equal(second.completed,true,JSON.stringify(second));assert.equal(second.changedRoads,0);
 assert.equal((await admin.doc('roads/spark-proof-road').get()).data().riskUpdatedAt.toMillis(),stamp);
 assert.ok((await admin.doc('system/risk_job').get()).data().lastSuccess.toMillis());
});
test('Spark core retains outstanding reviews while the incident becomes outdated during weather failure',async()=>{
 await request('submit-report',{data:payload()});
 const id=(await admin.collection('reports').get()).docs[0].id,old=new Date(Date.now()-25*3600000);
 await admin.doc(`reports/${id}`).update({observedAt:old});await admin.doc('road_incidents/spark-proof-road').update({lastObservedAt:old});
 const core=await coreFixture(async()=>new Response('{}',{status:503})),result=await core.run();
 assert.equal(result.completed,false);assert.equal(result.error,'weather-unavailable');
 assert.equal((await admin.doc(`reports/${id}`).get()).data().status,'pending');
 assert.equal((await admin.doc('road_incidents/spark-proof-road').get()).data().state,'outdated');
 assert.equal((await admin.doc('roads/spark-proof-road').get()).data().status,'not_passable');
 const job=(await admin.doc('system/risk_job').get()).data();assert.equal(job.lastSuccess,undefined);assert.equal(job.leaseUntil.toMillis(),0);
});
test('Spark core drill is admin-only, bounded, replayable and disabling never invents clear weather',async()=>{
 const core=await coreFixture(),data={requestId:'w'.repeat(24),enable:true,state:'heavyRain',minutes:30};
 await assert.rejects(()=>core.override('resident',data),{code:'permission-denied'});
 await assert.rejects(()=>core.override('admin',{...data,minutes:31}),{code:'invalid-argument'});
 await core.override('admin',data);const expiry=(await admin.doc('system/weather').get()).data().overrideExpiresAt.toMillis();
 assert.equal((await core.override('admin',data)).replay,true);assert.equal((await admin.doc('system/weather').get()).data().overrideExpiresAt.toMillis(),expiry);
 await core.override('admin',{requestId:'v'.repeat(24),enable:false});const off=(await admin.doc('system/weather').get()).data();assert.equal(off.available,false);assert.equal(off.currentState,'heavyRain');
});
test('Spark core failure after a partial road write cannot advance lastSuccess or its cache',async()=>{
 const {createCoreMaintenance}=await import('../../supabase/functions/_shared/proof_core.mjs');await coreFixture();
 const road=(await admin.doc('roads/spark-proof-road').get()).data();
 const batch=admin.batch();for(let i=0;i<76;i++)batch.set(admin.doc(`roads/core-${i}`),road);await batch.commit();
 let writes=0;
 const broken=Object.create(db);broken.transaction=work=>db.transaction(tx=>work({...tx,set:(path,data,options)=>{if(path.startsWith('roads/') && ++writes===76)throw new Error('fixture-write-failure');return tx.set(path,data,options);}}));
 const core=createCoreMaintenance({db:broken,fetcher:async()=>new Response(JSON.stringify({current_units:{time:'unixtime',interval:'seconds',precipitation:'mm',wind_speed_10m:'m/s',temperature_2m:'\u00b0C',relative_humidity_2m:'%'},current:{time:Math.floor(Date.now()/1000),interval:900,precipitation:0,wind_speed_10m:2,temperature_2m:29,relative_humidity_2m:70,weather_code:0}}))});
 const result=await core.run();assert.equal(result.completed,false);assert.equal(result.changedRoads,75);assert.equal((await admin.doc('system/risk_job').get()).data().lastSuccess,undefined);assert.equal((await admin.doc('system/core_cache').get()).exists,false);
 const recovered=await (await coreFixture()).run();assert.equal(recovered.completed,true,JSON.stringify(recovered));
});
test('Spark core private state and managed weather cannot be overwritten by a client administrator',async()=>{
 await admin.doc('system/weather').set({sparkManaged:true});
 const client=env.authenticatedContext('admin',{email_verified:true}).firestore();
 for(const path of ['system/core_cache','system/core_budget','system/core_setup','system/risk_job','core_worker_requests/fixture','weather_requests/fixture','system/weather'])await assertFails(setDoc(doc(client,path),{tamper:true}));
 await assertFails(getDoc(doc(client,'system/core_cache')));
 await assertSucceeds(getDoc(doc(client,'system/weather')));
});

test('Spark cache sees stamped graph edits without refreshing official verification time',async()=>{
 const core=await coreFixture();assert.equal((await core.run()).completed,true);
 const road=await admin.doc('roads/spark-proof-road').get(),verifiedAt=road.data().updatedAt.toMillis();
 const batch=admin.batch();batch.update(road.ref,{status:'partial',riskInputsUpdatedAt:new Date()});batch.set(admin.doc('system/road_inputs'),{updatedAt:new Date()},{merge:true});await batch.commit();
 const result=await core.run();assert.equal(result.completed,true,JSON.stringify(result));
 const changed=(await road.ref.get()).data();assert.equal(changed.riskScore,50);assert.equal(changed.updatedAt.toMillis(),verifiedAt);
});
test('Spark quota reservation stops work visibly when its daily allocation is spent',async()=>{
 const core=await coreFixture();assert.equal((await core.run()).completed,true);
 const budget=(await admin.doc('system/core_budget').get()).data();await admin.doc('system/core_budget').update({reads:30000});
 const prior=(await admin.doc('system/risk_job').get()).data().lastSuccess.toMillis();
 assert.equal((await core.run()).completed,false);const job=(await admin.doc('system/risk_job').get()).data();assert.equal(job.error,'core-daily-budget');assert.equal(job.lastSuccess.toMillis(),prior);
 assert.ok(budget.reads>0);
});
test('Spark source edit during risk calculation fences writes and prevents a false success heartbeat',async()=>{
 const {createCoreMaintenance}=await import('../../supabase/functions/_shared/proof_core.mjs');await coreFixture();
 let changed=false;const racing=Object.create(db);racing.queryPage=async(...args)=>{const page=await db.queryPage(...args);if(!changed && args[0]==='roads'){changed=true;await admin.doc('system/road_inputs').update({updatedAt:new Date()});}return page;};
 const provider=async()=>new Response(JSON.stringify({current_units:{time:'unixtime',interval:'seconds',precipitation:'mm',wind_speed_10m:'m/s',temperature_2m:'\u00b0C',relative_humidity_2m:'%'},current:{time:Math.floor(Date.now()/1000),interval:900,precipitation:0,wind_speed_10m:2,temperature_2m:29,relative_humidity_2m:70,weather_code:0}}));
 const result=await createCoreMaintenance({db:racing,fetcher:provider}).run();assert.equal(result.completed,false);assert.equal(result.error,'core-input-conflict');assert.equal((await admin.doc('system/risk_job').get()).data().lastSuccess,undefined);
});

// Broadcast/feedback migration acceptance, using actual portable REST transactions.
async function communicationApi(){return (await import('../../supabase/functions/_shared/proof_communications.mjs')).createCommunications({db,allowedUids:new Set(['resident','other','admin'])});}
const feedbackPayload=(letter='f',follow=true)=>({requestId:letter.repeat(24),category:'Map Accuracy',rating:4,comments:'Synthetic private feedback',allowFollowUp:follow});
async function feedbackFixture(follow=true){const api=await communicationApi(),saved=await api.submit('resident',feedbackPayload('f',follow));return {api,id:saved.resourceId};}
async function feedbackAction(api,id,action='reply',letter='g',extra={}){const ctx=await api.feedbackContext('admin',{feedbackId:id});return api.feedback('admin',{requestId:letter.repeat(24),feedbackId:id,contextToken:ctx.token,action,note:'Synthetic factual acknowledgement',notify:true,...extra});}
async function broadcastFixture(pushRequested=true){const api=await communicationApi();await admin.doc('roads/spark-proof-road').update({studyArea:'nearby_test',notes:'Verified road note',updatedAt:new Date(),isVerified:true});const data={requestId:'b'.repeat(24),title:'Synthetic area alert',message:'Synthetic advisory for test users only.',severity:'Warning',roadId:'spark-proof-road',sendPush:pushRequested,minutes:15,studyArea:'nearby_test'};const saved=await api.publish('admin',data);return {api,id:saved.resourceId,data};}
function communicationPush(){return createPush({db,allowedUids:new Set(['resident','other','admin']),communicationsEnabled:true,clock:()=>Math.max(pushNow,Date.now()),fcm:{account:async()=>({enabled:accountEnabled,validSince:0}),send:async value=>{sendCalls.push(value);return sendResults.shift()??{status:'accepted'};}}});}
async function communicationDevice(uid='resident',area='nearby_test'){const sender=communicationPush();await sender.device(uid,{installation:(uid==='resident'?'R':'O').repeat(43),sequence:1,mode:'register',token:`synthetic_${uid}_token_abcdefghijklmnop`,studyArea:area});return sender;}

test('feedback server assigns ownership, rejects forged fields and replays one submission',async()=>{
 const api=await communicationApi();await assert.rejects(()=>api.submit('resident',{...feedbackPayload(),userId:'other',adminReply:'forged'}),{code:'invalid-argument'});
 const first=await api.submit('resident',feedbackPayload());assert.equal((await api.submit('resident',feedbackPayload())).replay,true);assert.equal((await admin.collection('feedbacks').get()).size,1);
 const doc=(await admin.doc(`feedbacks/${first.resourceId}`).get()).data();assert.equal(doc.userId,'resident');assert.equal(doc.status,'new');assert.equal(doc.adminReply,null);
 await assert.rejects(()=>api.submit('resident',feedbackPayload('x')),{code:'resource-exhausted'});
});
test('feedback history is private to owner/admin and all writes are server-only after activation',async()=>{
 const {id}=await feedbackFixture();await admin.doc('system/communications').set({enabled:true});
 for(const uid of ['resident','admin'])await assertSucceeds(getDoc(doc(env.authenticatedContext(uid,{email_verified:true}).firestore(),`feedbacks/${id}`)));
 await assertFails(getDoc(doc(env.authenticatedContext('other',{email_verified:true}).firestore(),`feedbacks/${id}`)));
 for(const uid of ['resident','admin']){const client=env.authenticatedContext(uid,{email_verified:true}).firestore();await assertFails(setDoc(doc(client,`feedbacks/${id}`),{rating:5,userId:uid}));await assertFails(setDoc(doc(client,'feedbacks/forged'),{rating:5,userId:uid,status:'new'}));await assertFails(setDoc(doc(client,'alerts/forged'),{title:'forged'}));await assertFails(setDoc(doc(client,'system/communications'),{enabled:false}));}
});
test('feedback reply saves private history once, does not resolve, and recovers a lost response after closure',async()=>{
 const {api,id}=await feedbackFixture(),ctx=await api.feedbackContext('admin',{feedbackId:id}),data={requestId:'g'.repeat(24),feedbackId:id,contextToken:ctx.token,action:'reply',note:'Private synthetic reply',notify:true};
 const first=await api.feedback('admin',data);assert.equal(first.queuedCount,1);assert.equal((await admin.doc(`feedbacks/${id}`).get()).data().status,'reviewed');
 await feedbackAction(api,id,'resolve','h',{outcome:'recorded',confirmed:true});assert.equal((await api.feedback('admin',data)).replay,true);
 assert.equal((await admin.collection('feedback_messages').get()).size,2);assert.equal((await admin.collection('notification_outbox').get()).size,2);
 const peer=env.authenticatedContext('other',{email_verified:true}).firestore(),message=(await admin.collection('feedback_messages').get()).docs[0];await assertFails(getDoc(doc(peer,message.ref.path)));
});
test('feedback notification respects absent/false consent and unowned legacy records',async()=>{
 const {api,id}=await feedbackFixture(false);assert.equal((await feedbackAction(api,id)).queuedCount,0);
 await admin.doc('feedbacks/legacy-unowned').set({status:'new',category:'General Feedback',rating:3,comments:'legacy',userId:null,adminReply:'Old administrative note'});
 assert.equal((await feedbackAction(api,'legacy-unowned','reply','j')).queuedCount,0);
 assert.equal((await admin.collection('notification_outbox').get()).size,0);
});
test('feedback closure requires an explicit outcome and note, with reopening kept separate',async()=>{
 const {api,id}=await feedbackFixture();await assert.rejects(()=>feedbackAction(api,id,'resolve'),{code:'invalid-argument'});
 await feedbackAction(api,id,'resolve','h',{outcome:'recorded',confirmed:true});assert.equal((await admin.doc(`feedbacks/${id}`).get()).data().resolutionOutcome,'recorded');
 await assert.rejects(()=>feedbackAction(api,id,'reply','i'),{code:'failed-precondition'});await assert.rejects(()=>feedbackAction(api,id,'review','i'),{code:'failed-precondition'});
 await feedbackAction(api,id,'reopen','j',{note:'',notify:false});assert.equal((await admin.doc(`feedbacks/${id}`).get()).data().status,'reviewed');
});
test('feedback rechecks role on replay and rejects a stale second administrator',async()=>{
 const {api,id}=await feedbackFixture(),ctx=await api.feedbackContext('admin',{feedbackId:id}),data={requestId:'g'.repeat(24),feedbackId:id,contextToken:ctx.token,action:'reply',note:'First reviewed reply',notify:false};
 await admin.doc('users/other').update({role:'admin'});const other=await api.feedbackContext('other',{feedbackId:id});
 await api.feedback('admin',data);await assert.rejects(()=>api.feedback('other',{...data,requestId:'i'.repeat(24),contextToken:other.token}),{code:'failed-precondition'});
 await admin.doc('users/admin').update({role:'user'});await assert.rejects(()=>api.feedback('admin',data),{code:'permission-denied'});assert.equal((await admin.collection('feedback_messages').get()).size,1);
});
test('feedback queue failure rolls back reply, receipt, history and status together',async()=>{
 const {api,id}=await feedbackFixture(),ctx=await api.feedbackContext('admin',{feedbackId:id});const broken=Object.create(db);broken.transaction=work=>db.transaction(tx=>work({...tx,set:(path,...args)=>{if(path.startsWith('notification_outbox/'))throw new Error('fixture-commit-failure');return tx.set(path,...args);}}));
 const failing=(await import('../../supabase/functions/_shared/proof_communications.mjs')).createCommunications({db:broken,allowedUids:new Set(['resident','admin','other'])});
 await assert.rejects(()=>failing.feedback('admin',{requestId:'g'.repeat(24),feedbackId:id,contextToken:ctx.token,action:'reply',note:'Synthetic rollback proof',notify:true}));
 assert.equal((await admin.doc(`feedbacks/${id}`).get()).data().status,'new');assert.equal((await admin.collection('feedback_messages').get()).size,0);assert.equal((await admin.collection('communication_requests').get()).size,1);
});
test('feedback typed delivery rechecks consent and preserves in-app replies when suppressed',async()=>{
 const {api,id}=await feedbackFixture();await feedbackAction(api,id);const sender=await communicationDevice();
 await admin.doc(`feedbacks/${id}`).update({allowFollowUp:false});const result=await sender.drain();assert.equal(result.fcmAccepted,0);assert.equal(sendCalls.length,0);assert.equal((await admin.collection('notification_outbox').get()).docs[0].data().status,'suppressed');assert.equal((await admin.collection('feedback_messages').get()).size,1);
});
test('feedback typed delivery targets only its owner and contains no private body',async()=>{
 const {api,id}=await feedbackFixture();await feedbackAction(api,id);const sender=await communicationDevice();assert.equal((await sender.drain()).fcmAccepted,1);assert.equal(sendCalls[0].kind,'feedback_update');assert.equal(sendCalls[0].uid,'resident');assert.equal(sendCalls[0].feedbackId,id);assert.equal(sendCalls[0].body,undefined);
});
test('broadcast publication/replay is atomic, scope checked and never changes official road fields',async()=>{
 const {api,id,data}=await broadcastFixture();const road=(await admin.doc('roads/spark-proof-road').get()).data();assert.equal(road.status,'not_passable');assert.equal(road.notes,'Verified road note');const stamp=road.updatedAt.toMillis();
 assert.equal((await api.publish('admin',data)).replay,true);assert.equal((await admin.collection('alerts').get()).size,1);assert.equal((await admin.collection('notification_outbox').get()).size,2);
 assert.equal((await admin.doc('roads/spark-proof-road').get()).data().updatedAt.toMillis(),stamp);assert.equal((await admin.doc(`alerts/${id}`).get()).data().studyArea,'nearby_test');
 await assert.rejects(()=>api.publish('resident',{...data,requestId:'n'.repeat(24)}),{code:'permission-denied'});
});
test('broadcast rejects wrong area/road and an invalid expiry before creating anything',async()=>{
 const api=await communicationApi(),data={requestId:'b'.repeat(24),title:'Test area alert',message:'Synthetic alert body',severity:'Warning',sendPush:true,minutes:15,studyArea:'nearby_test'};
 await assert.rejects(()=>api.publish('admin',{...data,studyArea:'marulas'}),{code:'invalid-argument'});await assert.rejects(()=>api.publish('admin',{...data,minutes:0}),{code:'invalid-argument'});await assert.rejects(()=>api.publish('admin',{...data,roadId:'spark-proof-road'}),{code:'failed-precondition'});assert.equal((await admin.collection('alerts').get()).size,0);
});
test('broadcast deliveries require matching registered device area and never use legacy unknown-area registrations',async()=>{
 await broadcastFixture();const sender=communicationPush();await sender.device('resident',{installation:'R'.repeat(43),sequence:1,mode:'register',token:'synthetic_resident_token_abcdefghijklmnop'});
 assert.equal((await sender.drain()).fcmAccepted,0);assert.equal(sendCalls.length,0);
});
test('broadcast withdrawal is durable, preserves audit/history and suppresses pending notifications',async()=>{
 const {api,id}=await broadcastFixture(),ctx=await api.broadcastContext('admin',{alertId:id}),data={requestId:'w'.repeat(24),alertId:id,contextToken:ctx.token,note:'Synthetic advisory withdrawn after review.'};
 await api.withdraw('admin',data);assert.equal((await api.withdraw('admin',data)).replay,true);assert.equal((await admin.doc(`alerts/${id}`).get()).data().status,'withdrawn');
 const sender=await communicationDevice();await sender.drain();assert.equal(sendCalls.length,0);assert.equal((await admin.collection('communication_audits').get()).size,2);
});
test('expired broadcast cannot send, while an active scoped publication uses its dedicated type',async()=>{
 const {id}=await broadcastFixture(),sender=await communicationDevice();await admin.doc(`alerts/${id}`).update({expiresAt:new Date(0)});await sender.drain();assert.equal(sendCalls.length,0);
});
test('fair queue gives report updates a slot even behind a bulk broadcast backlog',async()=>{
 const {api}=await broadcastFixture(),sender=await communicationDevice();const oldest=(await admin.collection('notification_outbox').get()).docs[0].data(),batch=admin.batch();
 for(let i=0;i<12;i++)batch.set(admin.doc(`notification_outbox/bulk-${i}`),{...oldest,userId:'resident',dueAt:new Date(Date.now()-60000)});
 batch.set(admin.doc('reports/fair-report'),{userId:'resident'});batch.set(admin.doc(`report_messages/${'a'.repeat(64)}`),{userId:'resident',reportId:'fair-report'});batch.set(admin.doc(`notification_outbox/${'a'.repeat(64)}`),{kind:'report_update',queueClass:'report',userId:'resident',reportId:'fair-report',dispatchable:true,status:'queued',dueAt:new Date(),expiresAt:new Date(Date.now()+3600000)});await batch.commit();
 const result=await sender.drain();assert.ok(result.examined<=3);assert.ok(sendCalls.some(call=>call.kind==='report_update'));assert.ok(sendCalls.some(call=>call.kind==='broadcast_update'));
});

async function mediaFixture(){const {ProofMediaStorage,createMediaWorkflow}=await import('../../supabase/functions/_shared/proof_media.mjs');const stores=Object.fromEntries(['avatar','feedback'].map(p=>[p,new ProofMediaStorage({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher},p)]));return {stores,api:createMediaWorkflow({db,stores}),bytes:require('./support/media_fixture.cjs').jpeg()};}
async function profileSave(api,reference,id='p'.repeat(24),extra={}){const context=await api.context('resident');return api.save('resident',{requestId:id,contextToken:context.token,name:'Synthetic profile',location:'Test location',photoMode:reference?'set':'keep',...(reference?{photoUrl:reference}:{}),...extra});}
test('profile media is private, versioned and server-owned without modifying trust, role or account email',async()=>{
 const {api,bytes}=await mediaFixture(),photo=await api.upload('resident','avatar',bytes);assert.equal((await api.upload('resident','avatar',bytes)).reference,photo.reference);assert.equal((await admin.doc('media_limits/resident').get()).data().count,1);
 await assert.rejects(()=>api.read('resident',{reference:photo.reference}),{code:'permission-denied'});
 const before=(await admin.doc('users/resident').get()).data();await profileSave(api,photo.reference);const after=(await admin.doc('users/resident').get()).data();assert.equal(after.role,before.role);assert.equal(after.trustScore,before.trustScore);assert.equal(after.email,before.email);assert.equal(after.photoUrl,photo.reference);
 assert.deepEqual(await api.read('resident',{reference:photo.reference}),bytes);assert.deepEqual(await api.read('admin',{reference:photo.reference}),bytes);await assert.rejects(()=>api.read('other',{reference:photo.reference}),{code:'permission-denied'});
});
test('profile save rejects forged fields, wrong owners and stale profile edits but unrelated activity does not invalidate context',async()=>{
 const {api,bytes}=await mediaFixture(),photo=await api.upload('resident','avatar',bytes),ctx=await api.context('resident'),data={requestId:'p'.repeat(24),contextToken:ctx.token,name:'New name',location:'Test',photoMode:'set',photoUrl:photo.reference};
 await assert.rejects(()=>api.save('resident',{...data,email:'forged@example.com'}),{code:'invalid-argument'});await assert.rejects(()=>api.save('resident',{...data,userId:'other'}),{code:'invalid-argument'});
 const peer=await api.context('other');await assert.rejects(()=>api.save('other',{...data,contextToken:peer.token}),{code:'permission-denied'});
 await admin.doc('users/resident').update({lastReportAt:new Date()});await api.save('resident',data);await assert.rejects(()=>api.save('resident',{...data,requestId:'q'.repeat(24),name:'Stale edit'}),{code:'failed-precondition'});
});
test('profile response-loss replay works after object disappearance and default-avatar removal revokes new reads',async()=>{
 const {api,stores,bytes}=await mediaFixture(),photo=await api.upload('resident','avatar',bytes),ctx=await api.context('resident'),data={requestId:'p'.repeat(24),contextToken:ctx.token,name:'Synthetic profile',location:'Test',photoMode:'set',photoUrl:photo.reference};
 await api.save('resident',data);const parsed=stores.avatar.parse(photo.reference);fixture.files.delete(`report-photos-proof/${stores.avatar.path(parsed.uid,parsed.digest)}`);assert.equal((await api.save('resident',data)).replay,true);
 await api.upload('resident','avatar',bytes);await profileSave(api,null,'r'.repeat(24),{photoMode:'remove'});assert.equal((await admin.doc('users/resident').get()).data().photoUrl,null);await assert.rejects(()=>api.read('resident',{reference:photo.reference}),{code:'permission-denied'});
});
test('feedback attachment is bound to its record and only owner/current admin can fetch bytes',async()=>{
 const {api,stores,bytes}=await mediaFixture(),photo=await api.upload('resident','feedback',bytes);const comm=(await import('../../supabase/functions/_shared/proof_communications.mjs')).createCommunications({db,allowedUids:new Set(['resident','other','admin']),feedbackPhotos:stores.feedback});
 const payload={...feedbackPayload(),imageUrl:photo.reference},saved=await comm.submit('resident',payload),record=(await admin.doc(`feedbacks/${saved.resourceId}`).get()).data();assert.equal(record.hasAttachment,true);assert.equal(record.imageUrl,photo.reference);
 for(const uid of ['resident','admin'])assert.deepEqual(await api.read(uid,{reference:photo.reference,feedbackId:saved.resourceId}),bytes);
 await assert.rejects(()=>api.read('other',{reference:photo.reference,feedbackId:saved.resourceId}),{code:'permission-denied'});await assert.rejects(()=>api.read('resident',{reference:photo.reference,feedbackId:'unbound'}),{code:'permission-denied'});
 await assert.rejects(()=>comm.submit('other',{...feedbackPayload('o'),imageUrl:photo.reference}),{code:'permission-denied'});
 const parsed=stores.feedback.parse(photo.reference);fixture.files.delete(`report-photos-proof/${stores.feedback.path(parsed.uid,parsed.digest)}`);assert.equal((await comm.submit('resident',payload)).replay,true);
});
test('missing or mismatched feedback image fails before saving any record and cannot be silently omitted',async()=>{
 const {stores}=await mediaFixture(),comm=(await import('../../supabase/functions/_shared/proof_communications.mjs')).createCommunications({db,allowedUids:new Set(['resident']),feedbackPhotos:stores.feedback});
 await assert.rejects(()=>comm.submit('resident',{...feedbackPayload(),imageUrl:stores.feedback.reference('resident','a'.repeat(64))}),{code:'media-unavailable'});assert.equal((await admin.collection('feedbacks').get()).size,0);
 await assert.rejects(()=>comm.submit('resident',{...feedbackPayload(),imageUrl:'https://example.com/public.jpg'}),{code:'invalid-argument'});
});
test('media upload retries do not spend another reservation, while quota exhaustion and malformed bytes never report success',async()=>{
 const {api,bytes}=await mediaFixture();await api.upload('resident','avatar',bytes);await api.upload('resident','avatar',bytes);assert.equal((await admin.doc('media_limits/resident').get()).data().count,1);
 await admin.doc('media_limits/other').set({count:100,bytes:0});await assert.rejects(()=>api.upload('other','feedback',bytes),{code:'resource-exhausted'});await assert.rejects(()=>api.upload('resident','avatar',new Uint8Array([255,216,255,217])),{code:'invalid-argument'});
});
test('media activation blocks direct profile-image and editable-profile tampering while token/session updates still work',async()=>{
 await admin.doc('system/media').set({enabled:true});
 const owner=env.authenticatedContext('resident',{email_verified:true}).firestore(),administrator=env.authenticatedContext('admin',{email_verified:true}).firestore();
 for(const client of [owner,administrator]){await assertFails(setDoc(doc(client,'users/resident'),{photoUrl:'data:image/jpeg;base64,forged'},{merge:true}));await assertFails(setDoc(doc(client,'users/resident'),{name:'Forged profile name'},{merge:true}));await assertFails(setDoc(doc(client,'system/media'),{enabled:false}));await assertFails(getDoc(doc(client,'media_limits/resident')));}
 await assertFails(setDoc(doc(administrator,'users/forged'),{role:'user',photoUrl:'https://example.com/public.jpg'}));await assertSucceeds(setDoc(doc(owner,'users/resident'),{dismissedAlertIds:['test']},{merge:true}));
});
test('profile binding changes during delivery prevent a late response from returning removed bytes',async()=>{
 const {api,stores,bytes}=await mediaFixture(),photo=await api.upload('resident','avatar',bytes);await profileSave(api,photo.reference);
 const original=stores.avatar.read.bind(stores.avatar);stores.avatar.read=async reference=>{const result=await original(reference);await admin.doc('users/resident').update({photoUrl:null});return result;};await assert.rejects(()=>api.read('resident',{reference:photo.reference}),{code:'permission-denied'});
});

const maintenanceRoad=(id='osm_way_90000000001',offset=0)=>({id,name:`Synthetic maintenance ${id}`,geometry:{type:'MultiLineString',segments:[{points:[{lat:14.676,lng:121.006+offset},{lat:14.677,lng:121.006+offset}]}]}});
async function maintenanceFixture(){await admin.doc('system/road_maintenance').set({enabled:true,version:1});return (await import('../../supabase/functions/_shared/proof_roads.mjs')).createRoadMaintenance({db});}
const maintenanceRequest=letter=>letter.repeat(24);
async function maintenanceImport(api,roads=[maintenanceRoad()],id='i'){return api.importRoads('admin',{requestId:maintenanceRequest(id),roads});}
async function maintenanceDelete(api,id,request='d'){const ctx=await api.context('admin',{roadId:id});return api.remove('admin',{requestId:maintenanceRequest(request),roadId:id,contextToken:ctx.token,confirmed:true});}
test('road import is admin-only/create-only, preserves concurrent official review and replays without overwriting',async()=>{
 const api=await maintenanceFixture(),data={requestId:maintenanceRequest('i'),roads:[maintenanceRoad()]};
 await assert.rejects(()=>api.importRoads('resident',data),{code:'permission-denied'});
 assert.equal((await api.importRoads('admin',data)).createdCount,1);
 const ref=admin.doc(`roads/${data.roads[0].id}`),first=(await ref.get()).data();
 await Promise.all([api.importRoads('admin',{...data,requestId:maintenanceRequest('j')}),ref.update({status:'not_passable',notes:'New official decision',isVerified:true,updatedAt:new Date()})]);
 const reviewed=(await ref.get()).data();assert.equal(reviewed.status,'not_passable');assert.equal(reviewed.notes,'New official decision');
 assert.equal((await api.importRoads('admin',data)).replay,true);assert.equal((await ref.get()).data().notes,'New official decision');assert.equal(first.riskCategory,'Unknown');
 await assert.rejects(()=>api.importRoads('admin',{...data,roads:[{...data.roads[0],name:'Different intent'}]}),{code:'already-exists'});
});
test('concurrent imports create each OSM road once and keep a symmetric graph without a client rebuild',async()=>{
 const api=await maintenanceFixture(),roads=[maintenanceRoad(),maintenanceRoad('osm_way_90000000002',0.0001)];
 const result=await Promise.all([maintenanceImport(api,roads,'i'),maintenanceImport(api,roads,'j')]);assert.equal(result.reduce((n,r)=>n+r.createdCount,0),2);
 for(const road of roads){const value=(await admin.doc(`roads/${road.id}`).get()).data();assert.deepEqual(value.neighbors,[roads.find(r=>r.id!==road.id).id]);}
 assert.equal((await admin.doc('system/road_inputs').get()).data().topologyRevision,1);
});
test('road delete removes incoming neighbor links atomically, keeps history and cannot be revived by old retry receipts',async()=>{
 const api=await maintenanceFixture(),roads=[maintenanceRoad(),maintenanceRoad('osm_way_90000000002',0.0001)];await maintenanceImport(api,roads);
 await admin.doc(`roads/${roads[1].id}`).update({status:'not_passable',notes:'Retained official neighbor decision',updatedAt:new Date()});const neighborBefore=(await admin.doc(`roads/${roads[1].id}`).get()).data();
 await admin.doc('reports/historical-road-record').set({roadId:roads[0].id,status:'verified',userId:'resident',imageUrl:'retained-reference'});
 const ctx=await api.context('admin',{roadId:roads[0].id}),data={requestId:maintenanceRequest('d'),roadId:roads[0].id,contextToken:ctx.token,confirmed:true};
 await api.remove('admin',data);assert.equal((await admin.doc(`roads/${roads[0].id}`).get()).exists,false);assert.deepEqual((await admin.doc(`roads/${roads[1].id}`).get()).data().neighbors,[]);assert.equal((await admin.doc('reports/historical-road-record').get()).data().imageUrl,'retained-reference');
 const neighborAfter=(await admin.doc(`roads/${roads[1].id}`).get()).data();assert.equal(neighborAfter.notes,neighborBefore.notes);assert.equal(neighborAfter.status,neighborBefore.status);assert.equal(neighborAfter.updatedAt.toMillis(),neighborBefore.updatedAt.toMillis());
 await maintenanceImport(api,[roads[0]],'k');const generation=(await admin.doc(`roads/${roads[0].id}`).get()).data().maintenanceGeneration;
 assert.equal((await api.remove('admin',data)).replay,true);assert.equal((await admin.doc(`roads/${roads[0].id}`).get()).data().maintenanceGeneration,generation);
});
test('deletion rejects active reports/incidents/closures, wrong roles and a newer admin review after confirmation',async()=>{
 const api=await maintenanceFixture(),road=maintenanceRoad();await maintenanceImport(api);const ctx=await api.context('admin',{roadId:road.id}),data={requestId:maintenanceRequest('d'),roadId:road.id,contextToken:ctx.token,confirmed:true};
 await assert.rejects(()=>api.remove('resident',data),{code:'permission-denied'});
 await admin.doc('reports/active-maintenance-report').set({roadId:road.id,status:'pending',userId:'resident'});assert.equal((await api.context('admin',{roadId:road.id})).canDelete,false);await assert.rejects(()=>api.remove('admin',data),{code:'failed-precondition'});
 await admin.doc('reports/active-maintenance-report').update({status:'verified'});await admin.doc(`road_incidents/${road.id}`).set({state:'outdated',revision:1});assert.equal((await api.context('admin',{roadId:road.id})).canDelete,false);
 await admin.doc(`road_incidents/${road.id}`).update({state:'resolved'});const fresh=await api.context('admin',{roadId:road.id});await admin.doc(`roads/${road.id}`).update({notes:'New review',status:'partial',updatedAt:new Date()});await assert.rejects(()=>api.remove('admin',{...data,contextToken:fresh.token}),{code:'failed-precondition'});assert.equal((await admin.doc(`roads/${road.id}`).get()).data().notes,'New review');
});
test('deletion confirmation belongs to the current admin while derived risk updates alone do not invalidate it',async()=>{
 const api=await maintenanceFixture();await maintenanceImport(api);const roadId=maintenanceRoad().id,ctx=await api.context('admin',{roadId}),data={requestId:maintenanceRequest('d'),roadId,contextToken:ctx.token,confirmed:true};
 await admin.doc('users/other').update({role:'admin'});await assert.rejects(()=>api.remove('other',data),{code:'failed-precondition'});
 await admin.doc(`roads/${roadId}`).update({riskScore:75,riskCategory:'High',riskUpdatedAt:new Date()});assert.equal((await api.remove('admin',data)).saved,true);
});
test('maintenance write failure rolls back road creation, neighbor writes, receipts and topology invalidation together',async()=>{
 const api=await maintenanceFixture();await maintenanceImport(api);const marker=(await admin.doc('system/road_inputs').get()).data().topologyRevision;
 const broken=Object.create(db);broken.transaction=work=>db.transaction(tx=>work({...tx,set:(path,...args)=>{if(path.startsWith('road_maintenance_requests/'))throw new Error('synthetic commit failure');return tx.set(path,...args);}}));
 const bad=(await import('../../supabase/functions/_shared/proof_roads.mjs')).createRoadMaintenance({db:broken});await assert.rejects(()=>maintenanceImport(bad,[maintenanceRoad('osm_way_90000000002',0.0001)],'j'));
 assert.equal((await admin.doc('roads/osm_way_90000000002').get()).exists,false);assert.deepEqual((await admin.doc('roads/osm_way_90000000001').get()).data().neighbors,[]);assert.equal((await admin.doc('system/road_inputs').get()).data().topologyRevision,marker);
});
test('topology revision forces the next risk run to remove a deleted cached road and accept an empty network',async()=>{
 const api=await maintenanceFixture(),core=await coreFixture();await maintenanceImport(api);assert.equal((await core.run()).completed,true);
 let cache=(await admin.doc('system/core_cache').get()).data();assert.ok(cache.roads.some(r=>r.id==='osm_way_90000000001'));
 await maintenanceDelete(api,'osm_way_90000000001');assert.equal((await core.run()).completed,true);cache=(await admin.doc('system/core_cache').get()).data();assert.ok(!cache.roads.some(r=>r.id==='osm_way_90000000001'));assert.equal(cache.topologyRevision,(await admin.doc('system/road_inputs').get()).data().topologyRevision);
 await admin.doc('roads/spark-proof-road').update({status:'passable'});await maintenanceDelete(api,'spark-proof-road','e');const empty=await core.run();assert.equal(empty.completed,true,JSON.stringify(empty));assert.equal((await admin.doc('system/core_cache').get()).data().roads.length,0);assert.equal((await admin.doc('system/risk_job').get()).data().roadCount,0);
});
test('newer topology change during risk calculation cannot advance the cache or success heartbeat',async()=>{
 const api=await maintenanceFixture();await coreFixture();await maintenanceImport(api);const core=await coreFixture();await core.run();const before=(await admin.doc('system/risk_job').get()).data().lastSuccess.toMillis();
 let changed=false;const racing=Object.create(db);racing.queryPage=async(...args)=>{const page=await db.queryPage(...args);if(!changed&&args[0]==='roads'){changed=true;await maintenanceDelete(api,'osm_way_90000000001');}return page;};
 const provider=async()=>new Response(JSON.stringify({current_units:{time:'unixtime',interval:'seconds',precipitation:'mm',wind_speed_10m:'m/s',temperature_2m:'\u00b0C',relative_humidity_2m:'%'},current:{time:Math.floor(Date.now()/1000),interval:900,precipitation:0,wind_speed_10m:2,temperature_2m:29,relative_humidity_2m:70,weather_code:0}}));
 const result=await (await import('../../supabase/functions/_shared/proof_core.mjs')).createCoreMaintenance({db:racing,fetcher:provider}).run();assert.equal(result.completed,false);assert.equal((await admin.doc('system/risk_job').get()).data().lastSuccess.toMillis(),before);assert.equal((await core.run()).completed,true);
});
test('protected maintenance rules block legacy admin writes but preserve reads and the trusted maintenance endpoints',async()=>{
 const api=await maintenanceFixture();await maintenanceImport(api);const client=env.authenticatedContext('admin',{email_verified:true}).firestore();
 for(const path of ['roads/osm_way_90000000001','roads/new-road','system/road_inputs','system/road_maintenance','road_maintenance_requests/forged'])await assertFails(setDoc(doc(client,path),{neighbors:[],enabled:false},{merge:true}));
 await assertFails(deleteDoc(doc(client,'roads/osm_way_90000000001')));await assertSucceeds(getDoc(doc(client,'roads/osm_way_90000000001')));await assertSucceeds(getDoc(doc(client,'system/road_inputs')));
});
test('graph repair updates only neighbors/input stamps and import validation cannot assign official or foreign-area fields',async()=>{
 const api=await maintenanceFixture();await maintenanceImport(api);const ref=admin.doc('roads/osm_way_90000000001');await ref.update({neighbors:['deleted'],status:'not_passable',notes:'Official closure',isVerified:true});const before=(await ref.get()).data();
 const fixed=await api.rebuild('admin',{requestId:maintenanceRequest('g')});assert.equal(fixed.changedRoads,1);const after=(await ref.get()).data();assert.deepEqual(after.neighbors,[]);assert.equal(after.status,before.status);assert.equal(after.notes,before.notes);assert.equal(after.updatedAt.toMillis(),before.updatedAt.toMillis());
 await assert.rejects(()=>maintenanceImport(api,[{...maintenanceRoad(),status:'passable'}],'k'),{code:'invalid-argument'});const foreign=maintenanceRoad('osm_way_90000000003');foreign.geometry.segments[0].points=[{lat:0,lng:0},{lat:0,lng:1}];await assert.rejects(()=>maintenanceImport(api,[foreign],'l'),{code:'invalid-argument'});
});


test('complete assistive journey: resident evidence, clarification, observation verification and a later linked road update',async()=>{
 await admin.doc('roads/spark-proof-road').update({status:'passable',isVerified:true,updatedAt:new Date(Date.now()-3600000)});
 const uploaded=await request('photo-upload',new Uint8Array([255,216,255,1,255,217]));assert.equal(uploaded.status,200,JSON.stringify(uploaded.data));
 const evidence={...payload('a',uploaded.data.imageUrl),observedAt:new Date(Date.now()-1200000).toISOString(),description:'Water around the crossing during the resident observation.'};
 const submitted=await request('submit-report',{data:evidence});assert.equal(submitted.status,200,JSON.stringify(submitted.data));const id=submitted.data.result.reportId;
 assert.equal((await request('submit-report',{data:evidence})).data.result.replay,true);
 const original=(await admin.doc(`reports/${id}`).get()).data();assert.equal(original.status,'pending');assert.equal(original.imageUrl,uploaded.data.imageUrl);
 assert.equal((await admin.doc('roads/spark-proof-road').get()).data().status,'passable');
 assert.equal((await admin.collection('reports').get()).size,1);
 let ctx=await reviewContext(id);
 assert.equal((await request('admin-action',reviewAction('start',id,ctx,'j'),'admin')).status,200);
 ctx=await reviewContext(id);
 const asked=await request('admin-action',reviewAction('request_clarification',id,ctx,'k',{note:'Please clarify which crossing is shown in the original photo.'}),'admin');assert.equal(asked.status,200,JSON.stringify(asked.data));
 assert.equal((await admin.doc(`reports/${id}`).get()).data().status,'waiting_resident');
 const clarification=await request('clarification-context',{data:{reportId:id}});assert.equal(clarification.status,200,JSON.stringify(clarification.data));
 const supporting=await request('photo-upload',new Uint8Array([255,216,255,2,255,217]));assert.equal(supporting.status,200);
 const reply={reportId:id,clarificationRequestId:clarification.data.result.requestId,requestId:'full_journey_reply_0001',message:'The photo shows the crossing beside the school entrance.',imageUrl:supporting.data.imageUrl,photoObservedAt:evidence.observedAt,photoMatchesObservation:true};
 const answered=await request('clarification-reply',{data:reply});assert.equal(answered.status,200,JSON.stringify(answered.data));
 assert.equal((await request('clarification-reply',{data:reply})).data.result.replay,true);
 const replied=(await admin.doc(`reports/${id}`).get()).data();assert.equal(replied.status,'pending');
 const savedClarification=(await admin.doc(`report_clarifications/${reply.clarificationRequestId}`).get()).data();
 assert.equal(savedClarification.answered,true);assert.equal(savedClarification.response.imageUrl,supporting.data.imageUrl);
 assert.equal(savedClarification.response.photoObservedAt.toMillis(),Date.parse(evidence.observedAt));
 assert.ok(savedClarification.response.repliedAt.toMillis()>0);assert.equal(savedClarification.response.repliedAt.toMillis(),replied.clarificationRepliedAt.toMillis());
 assert.equal(replied.imageUrl,original.imageUrl);assert.equal((await admin.doc('users/resident').get()).data().trustScore,50);
 ctx=await reviewContext(id);
 const verify=reviewAction('verify',id,ctx,'l',{observationOnly:true,note:'The earlier observation was checked with the resident and available evidence.'});
 const verified=await request('admin-action',verify,'admin');assert.equal(verified.status,200,JSON.stringify(verified.data));assert.equal(verified.data.result.pointsAwarded,10);
 assert.equal((await request('admin-action',verify,'admin')).data.result.replay,true);
 const reviewed=(await admin.doc(`reports/${id}`).get()).data();assert.equal(reviewed.status,'verified');assert.equal(reviewed.pointsAwarded,10);
 assert.equal((await admin.doc('roads/spark-proof-road').get()).data().status,'passable');
 const input={roadIds:['spark-proof-road'],sourceReportId:id};
 const loaded=await request('admin-context',{data:input},'admin');assert.equal(loaded.status,200,JSON.stringify(loaded.data));
 assert.equal(loaded.data.result.reportRoadLinkSupported,true);assert.equal(loaded.data.result.sourceReport.id,id);assert.equal(loaded.data.result.report,null);
 const action={...input,action:'road_review',contextToken:loaded.data.result.token,requestId:'m'.repeat(24),roadStatus:'not_passable',verifiedCurrentConditions:true,note:'Command-center staff checked current CCTV coverage at 4 PM. Floodwater covers the crossing.'};
 const messageCount=(await admin.collection('report_messages').get()).size;
 const updated=await request('admin-action',{data:action},'admin');assert.equal(updated.status,200,JSON.stringify(updated.data));assert.equal(updated.data.result.sourceReportId,id);assert.equal(updated.data.result.pointsAwarded,0);
 assert.equal((await request('admin-action',{data:action},'admin')).data.result.replay,true);
 const road=(await admin.doc('roads/spark-proof-road').get()).data();assert.equal(road.status,'not_passable');assert.equal(road.isVerified,true);assert.equal(road.updatedByUid,'admin');assert.equal(road.sourceReportId,undefined);
 const saved=(await admin.doc(`reports/${id}`).get()).data();assert.equal(saved.status,'verified');assert.equal(saved.reviewedAt.toMillis(),reviewed.reviewedAt.toMillis());assert.equal(saved.pointsAwarded,10);
 assert.equal(saved.imageUrl,original.imageUrl);assert.equal(saved.observedAt.toMillis(),original.observedAt.toMillis());assert.equal(saved.createdAt.toMillis(),original.createdAt.toMillis());assert.equal(saved.description,original.description);
 assert.equal((await admin.doc('users/resident').get()).data().trustScore,60);assert.equal((await admin.collection('reports').get()).size,1);
 const audit=(await admin.collection('admin_audits').where('sourceReportId','==',id).get());assert.equal(audit.size,1);assert.equal(audit.docs[0].data().reportId,null);
 const messages=await admin.collection('report_messages').get();assert.equal(messages.size,messageCount+1);const linked=messages.docs.find(d=>d.data().message.startsWith('Road update linked'));assert.ok(linked);assert.equal(linked.data().reportId,id);assert.equal(linked.data().userId,'resident');
 const outbox=(await admin.doc(`notification_outbox/${linked.id}`).get()).data();assert.equal(outbox.status,'awaiting_sender');assert.equal(outbox.userId,'resident');assert.equal(outbox.reportId,id);
 const owner=env.authenticatedContext('resident',{email_verified:true}).firestore(),other=env.authenticatedContext('other',{email_verified:true}).firestore(),staff=env.authenticatedContext('admin',{email_verified:true}).firestore();
 await assertSucceeds(getDoc(doc(owner,`report_messages/${linked.id}`)));await assertFails(getDoc(doc(other,`report_messages/${linked.id}`)));
 await assertSucceeds(getDoc(doc(staff,audit.docs[0].ref.path)));await assertFails(getDoc(doc(owner,audit.docs[0].ref.path)));
});

test('direct CCTV or field monitoring can update the road with no resident report at all',async()=>{
 const ctx=await reviewContext(null,['spark-proof-road']);
 const action={action:'road_review',roadIds:['spark-proof-road'],contextToken:ctx.token,requestId:'n'.repeat(24),roadStatus:'partial',verifiedCurrentConditions:true,note:'Current field check by barangay staff: only suitable vehicles can pass.'};
 const saved=await request('admin-action',{data:action},'admin');assert.equal(saved.status,200,JSON.stringify(saved.data));
 assert.equal(saved.data.result.sourceReportId,undefined);assert.equal(saved.data.result.pointsAwarded,0);
 const road=(await admin.doc('roads/spark-proof-road').get()).data();assert.equal(road.status,'partial');assert.equal(road.updatedByUid,'admin');
 assert.equal((await admin.collection('reports').get()).size,0);assert.equal((await admin.collection('report_messages').get()).size,0);
 const audit=(await admin.collection('admin_audits').get()).docs[0].data();assert.equal(audit.sourceReportId,null);assert.equal(audit.reportId,null);
 assert.equal((await admin.doc('users/resident').get()).data().trustScore,50);
});


test('independent current-road review accepts arriving resident activity but rejects a newer road update',async()=>{
 const ctx=await reviewContext(null,['spark-proof-road']);
 const submitted=await request('submit-report',{data:payload('r')});assert.equal(submitted.status,200,JSON.stringify(submitted.data));
 const id=submitted.data.result.reportId;
 const action={action:'road_review',roadIds:['spark-proof-road'],contextToken:ctx.token,requestId:'rapid'.padEnd(24,'r'),roadStatus:'not_passable',verifiedCurrentConditions:true,note:'Barangay staff checked current CCTV coverage and confirmed floodwater.'};
 const saved=await request('admin-action',{data:action},'admin');assert.equal(saved.status,200,JSON.stringify(saved.data));assert.equal(saved.data.result.pointsAwarded,0);
 assert.equal((await admin.doc(`reports/${id}`).get()).data().status,'pending');
 const first=await reviewContext(null,['spark-proof-road']);const second=await reviewContext(null,['spark-proof-road']);
 const updated=await request('admin-action',{data:{...action,contextToken:second.token,requestId:'newer'.padEnd(24,'n'),roadStatus:'partial'}},'admin');assert.equal(updated.status,200,JSON.stringify(updated.data));
 const stale=await request('admin-action',{data:{...action,contextToken:first.token,requestId:'stale'.padEnd(24,'s'),roadStatus:'passable'}},'admin');assert.equal(stale.status,409,JSON.stringify(stale.data));
 assert.equal((await admin.doc('roads/spark-proof-road').get()).data().status,'partial');
 assert.equal((await admin.doc(`reports/${id}`).get()).data().status,'pending');
 assert.equal((await admin.doc('users/resident').get()).data().trustScore,50);
});


test('admin report notices cover saved submission and resident reply with idempotent private routing',async()=>{
 const {createProofHandler}=await import('../../supabase/functions/_shared/proof_handler.mjs');
 const tasks=[];
 const api=createProofHandler({db,photos,allowedUids:new Set(['resident','other','admin']),adminNotices:true,push,
  verify:async header=>header==='Bearer fixture-admin'?'admin':'resident',background:task=>tasks.push(task)});
 async function call(route,data,asAdmin=false){
  const response=await api(new Request(`${photos.endpoint}/${route}`,{method:'POST',headers:{authorization:asAdmin?'Bearer fixture-admin':'Bearer fixture-resident','content-type':'application/json'},body:JSON.stringify({data})}));
  const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));return body.result;
 }
 await push.device('admin',{installation:'notice_installation_admin_1234567890',sequence:1,mode:'register',token:fcmToken});
 const report=await call('submit-report',payload('n'));
 await Promise.all(tasks.splice(0));
 assert.equal(sendCalls.length,1);assert.equal(sendCalls[0].kind,'report_new_admin');assert.equal(sendCalls[0].uid,'admin');assert.equal(sendCalls[0].reportId,report.reportId);
 const count=(await admin.collection('notification_outbox').get()).size;
 assert.equal((await call('submit-report',payload('n'))).replay,true);await Promise.all(tasks.splice(0));
 assert.equal((await admin.collection('notification_outbox').get()).size,count);assert.equal(sendCalls.length,1);
 const ctx=await call('admin-context',{reportId:report.reportId},true);
 await call('admin-action',{reportId:report.reportId,action:'request_clarification',requestId:'clarify_notice_1234567890',contextToken:ctx.token,note:'Which part of the road does the photo show?'},true);
 await Promise.all(tasks.splice(0));
 const question=await call('clarification-context',{reportId:report.reportId});
 const answer={reportId:report.reportId,clarificationRequestId:question.requestId,requestId:'answer_notice_1234567890',message:'The photo shows the crossing beside the covered court.'};
 await call('clarification-reply',answer);await Promise.all(tasks.splice(0));
 assert.equal(sendCalls.filter(c=>c.kind==='report_reply_admin').length,1);
 assert.equal(sendCalls.at(-1).uid,'admin');assert.equal(sendCalls.at(-1).reportId,report.reportId);
 const answeredCount=(await admin.collection('notification_outbox').get()).size;
 assert.equal((await call('clarification-reply',answer)).replay,true);await Promise.all(tasks.splice(0));
 assert.equal((await admin.collection('notification_outbox').get()).size,answeredCount);
 assert.equal(sendCalls.filter(c=>c.kind==='report_reply_admin').length,1);
 assert.equal((await admin.doc(`reports/${report.reportId}`).get()).data().status,'pending');
 assert.equal((await admin.doc('users/resident').get()).data().trustScore,50);
});

test('REST admin audience paginates by document reference beyond twenty admins',async()=>{
 const {queueAdminReportNotice}=await import('../../supabase/functions/_shared/admin_report_notifications.mjs');
 const {MARULAS_BACKEND}=await import('../../supabase/functions/_shared/backend_profile.mjs');
 const {expandAdminReportNotice}=await import('../../supabase/functions/_shared/admin_report_notifications.mjs');
 for(let i=0;i<24;i++)await admin.doc(`users/admin_page_${String(i).padStart(2,'0')}`).set({role:'admin',studyArea:'marulas'});
 // Existing synthetic admin is in the nearby test area and must not enter main audience.
 await admin.doc('users/admin').update({studyArea:'nearby_test'});
 let eventId;
 await db.transaction(async tx=>{
  eventId=await queueAdminReportNotice(tx,{reportId:'pagination-report',userId:'resident',requestHash:'c'.repeat(64),kind:'report_new_admin',now:Date.now()});
  tx.set('reports/pagination-report',{userId:'resident',status:'pending',adminNoticeEventId:eventId});
 });
 const args={db,path:`notification_outbox/${eventId}`,profile:MARULAS_BACKEND,allowedUids:new Set(),clock:()=>Date.now()+2000};
 assert.equal(await expandAdminReportNotice(args),'retry');
 args.clock=()=>Date.now()+5000;
 assert.equal(await expandAdminReportNotice(args),'expanded');
 const events=(await admin.collection('notification_outbox').where('kind','==','report_new_admin').get()).docs;
 assert.equal(events.length,24);assert.equal(new Set(events.map(d=>d.data().userId)).size,24);
});
