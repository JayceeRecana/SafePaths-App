// Main workflow in a demo database only. Production adapters still categorically
// reject emulator hosts; no main credentials or real user data are used here.
const {test,before,after,beforeEach}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {doc,setDoc}=require('firebase/firestore');
const {storageFixture}=require('./support/proof_storage_fixture.cjs');
const {jpeg}=require('./support/media_fixture.cjs');
if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Use the isolated demo Firebase emulator');
const projectId='demo-safepaths-reliability';
let env,app,admin,db,api,photos,fixture,profile,modules,push;
const point=(lng,lat)=>({lng,lat});
const geometry={type:'MultiLineString',segments:[{points:[point(120.984,14.675),point(120.984,14.677)]}]};
before(async()=>{
 modules=Object.fromEntries(await Promise.all(['backend_profile','proof_firebase','proof_storage','proof_handler','proof_push','proof_communications','proof_roads','proof_core','proof_media'].map(async name=>[name,await import(`../../supabase/functions/_shared/${name}.mjs`)])));
 profile=modules.backend_profile.MARULAS_BACKEND;
 env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}});
 app=initializeApp({projectId},'main-demo-workflows');admin=getFirestore(app);
 // Demo storage adapter for transaction verification; not a main emulator override.
 db=new modules.proof_firebase.FirestoreRest({projectId,credential:{token:async()=>'owner'},emulatorHost:process.env.FIRESTORE_EMULATOR_HOST});
 fixture=storageFixture({bucket:profile.bucket,origin:'https://bbteuzgfgnrjjrqewidc.supabase.co'});
 photos=new modules.proof_storage.ProofStorage({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher,profile});
 const stores=Object.fromEntries(['avatar','feedback'].map(purpose=>[purpose,new modules.proof_media.ProofMediaStorage({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher,profile},purpose)]));
 push=modules.proof_push.createProofPush({db,profile,communicationsEnabled:true,fcm:{account:async()=>({enabled:true,validSince:0}),send:async()=>({status:'accepted'})}});
 api=modules.proof_handler.createProofHandler({db,photos,profile,verify:async value=>value?.replace('Fixture ',''),push,
  communications:modules.proof_communications.createCommunications({db,profile,feedbackPhotos:stores.feedback}),
  media:modules.proof_media.createMediaWorkflow({db,stores}),
  roads:modules.proof_roads.createRoadMaintenance({db,profile}),
  core:modules.proof_core.createCoreMaintenance({db,profile})});
});
after(async()=>{await env.cleanup();await deleteApp(app);});
beforeEach(async()=>{
 await env.clearFirestore();fixture.files.clear();
 for(const uid of ['resident','other','admin'])await admin.doc(`users/${uid}`).set({role:uid==='admin'?'admin':'user',name:'Demo member',studyArea:'marulas',trustScore:50,verifiedReports:0,dismissedReports:0});
 await admin.doc('system/backend_rollout').set({enabled:true,version:1,studyArea:'marulas'});
 await admin.doc('system/road_maintenance').set({enabled:true});
 await admin.doc('roads/legacy_name').set({name:'Demo Marulas road',status:'passable',isVerified:true,source:'manual',studyArea:'marulas',geometry,updatedAt:new Date(),vulnerability:'high',neighbors:[]});
});
async function request(operation,data,uid='resident') {
 const binary=data instanceof Uint8Array;
 const response=await api(new Request(`${photos.endpoint}/${operation}`,{method:'POST',headers:{authorization:`Fixture ${uid}`,'content-type':binary?'image/jpeg':'application/json'},body:binary?data:JSON.stringify({data})}));
 return {status:response.status,body:response.headers.get('content-type')?.startsWith('image/')?new Uint8Array(await response.arrayBuffer()):await response.json()};
}
async function context(data) {
 const result=await request('admin-context',data,'admin');assert.equal(result.status,200,JSON.stringify(result.body));return result.body.result;
}
async function roadReview(status,sourceReportId) {
 const input={roadIds:['legacy_name'],...(sourceReportId?{sourceReportId}:{})},loaded=await context(input);
 return request('admin-action',{...input,action:'road_review',contextToken:loaded.token,requestId:crypto.randomUUID(),roadStatus:status,verifiedCurrentConditions:true,note:'Barangay staff checked current CCTV coverage and confirmed this condition.'},'admin');
}
test('main report to verified observation to linked road update preserves identity, evidence and one trust reward',async()=>{
 const upload=await request('photo-upload',jpeg());assert.equal(upload.status,200);
 const submitted=await request('submit-report',{requestId:'s'.repeat(24),roadId:'legacy_name',title:'Flood observation',description:'Water is covering this road.',severity:'High',isEmergency:false,location:{lat:14.676,lng:120.984,source:'manual',imageUrl:upload.body.imageUrl}});
 assert.equal(submitted.status,200,JSON.stringify(submitted.body));const reportId=submitted.body.result.reportId;
 const loaded=await context({reportId});
 const verified=await request('admin-action',{action:'verify',observationOnly:true,reportId,contextToken:loaded.token,requestId:'v'.repeat(24),note:'The submitted observation was checked against the available evidence.'},'admin');
 assert.equal(verified.status,200,JSON.stringify(verified.body));assert.equal((await admin.doc('roads/legacy_name').get()).data().status,'passable');
 assert.equal((await roadReview('not_passable',reportId)).status,200);
 const saved=(await admin.doc(`reports/${reportId}`).get()).data(),road=(await admin.doc('roads/legacy_name').get()).data();
 assert.equal(saved.status,'verified');assert.equal(saved.imageUrl,upload.body.imageUrl);assert.equal(road.status,'not_passable');
 assert.equal((await admin.doc('users/resident').get()).data().trustScore,60);
 assert.equal((await admin.collection('reports').get()).size,1);
 assert.equal((await request('followup-context',{rootReportId:reportId})).status,503);
});
test('direct barangay monitoring needs no resident report and never awards report points',async()=>{
 const result=await roadReview('partial');assert.equal(result.status,200,JSON.stringify(result.body));
 assert.equal((await admin.collection('reports').get()).size,0);assert.equal((await admin.doc('users/admin').get()).data().trustScore,50);
 assert.equal((await admin.doc('roads/legacy_name').get()).data().status,'partial');
});
test('main broadcasts find current Marulas residents without a synthetic account allowlist',async()=>{
 await admin.doc('users/wrong_area').set({role:'user',studyArea:'nearby_test'});
 await admin.doc('users/disabled_profile').set({role:'user',disabled:true});
 const result=await request('broadcast-publish',{requestId:'b'.repeat(24),title:'Barangay advisory',message:'Check current road updates before starting your trip.',severity:'Warning',sendPush:true,minutes:60,studyArea:'marulas'},'admin');
 assert.equal(result.status,200,JSON.stringify(result.body));assert.equal(result.body.result.queuedCount,2);
 const events=await admin.collection('notification_outbox').get();assert.equal(events.size,2);
 assert.deepEqual(events.docs.map(d=>d.data().userId).sort(),['other','resident']);
 await push.drain();
 const replay=await request('broadcast-publish',{requestId:'b'.repeat(24),title:'Barangay advisory',message:'Check current road updates before starting your trip.',severity:'Warning',sendPush:true,minutes:60,studyArea:'marulas'},'admin');
 assert.equal(replay.body.result.replay,true);assert.equal((await admin.collection('alerts').get()).size,1);
});
test('main importer rejects nearby geography and duplicate legacy segments before writing',async()=>{
 for(const geom of [geometry,{type:'MultiLineString',segments:[{points:[point(121.009,14.676),point(121.010,14.677)]}]}]) {
  const result=await request('road-import',{requestId:crypto.randomUUID(),roads:[{id:'osm_way_12345',name:'Demo road',geometry:geom}]},'admin');
  assert.ok([400,409].includes(result.status),JSON.stringify(result.body));assert.equal((await admin.collection('roads').get()).size,1);
 }
});
test('main release marker cannot be activated by client admins; missing marker blocks mutation',async()=>{
 const client=env.authenticatedContext('admin',{email_verified:true}).firestore();
 await assertFails(setDoc(doc(client,'system/backend_rollout'),{enabled:true,version:1,studyArea:'marulas'}));
 await admin.doc('system/backend_rollout').delete();
 const before=fixture.writes,result=await request('photo-upload',new Uint8Array([255,216,255,1,255,217]));
 assert.equal(result.status,503);assert.equal(fixture.writes,before);
});
test('main risk worker fetches Marulas weather and preserves official road conditions',async()=>{
 await admin.doc('system/core_setup').set({version:1,studyArea:'marulas',roadCount:1});
 let fetched=false;
 const core=modules.proof_core.createCoreMaintenance({db,profile,fetcher:async url=>{
  const parsed=new URL(url);assert.equal(parsed.searchParams.get('latitude'),'14.6761');assert.equal(parsed.searchParams.get('longitude'),'120.9842');fetched=true;
  return new Response(JSON.stringify({current_units:{time:'unixtime',interval:'seconds',precipitation:'mm',wind_speed_10m:'m/s',temperature_2m:'\u00b0C',relative_humidity_2m:'%'},current:{time:Math.floor(Date.now()/1000),interval:900,precipitation:0,wind_speed_10m:3,temperature_2m:29,relative_humidity_2m:75,weather_code:0}}));
 }});
 await core.run();assert.equal(fetched,true);
 const weather=(await admin.doc('system/weather').get()).data();assert.equal(weather.studyArea,'marulas');assert.equal(weather.source,'open-meteo');
 assert.equal((await admin.doc('roads/legacy_name').get()).data().status,'passable');
 assert.equal((await admin.doc('system/core_budget').get()).exists,true);
});
test('metadata preparation is atomic, preserves official data and leaves main closed',async()=>{
 const {applyTransaction}=require('../tools/apply-main-integration.cjs'),{FieldValue}=require('firebase-admin/firestore');
 await admin.doc('system/backend_rollout').set({enabled:false,version:1,studyArea:'marulas'});
 const ref=admin.doc('roads/legacy_name'),original=await ref.get();
 const plan={roadMetadata:[{path:ref.path,expectedUpdateTime:{seconds:original.updateTime.seconds,nanoseconds:original.updateTime.nanoseconds}}],controls:{'system/backend_rollout':{enabled:false,version:1,studyArea:'marulas'},'system/core_setup':{version:1,studyArea:'marulas',roadCount:1}}};
 const dry=await applyTransaction(admin,plan,()=>FieldValue.serverTimestamp());assert.equal(dry.readOnly,true);assert.equal(dry.metadataWrites,0);
 await ref.update({notes:'A newer command-center update'});
 await assert.rejects(()=>applyTransaction(admin,plan,()=>FieldValue.serverTimestamp(),{apply:true}));
 assert.equal((await admin.doc('system/core_setup').get()).exists,false);
 const fresh=await ref.get();plan.roadMetadata[0].expectedUpdateTime={seconds:fresh.updateTime.seconds,nanoseconds:fresh.updateTime.nanoseconds};
 const applied=await applyTransaction(admin,plan,()=>FieldValue.serverTimestamp(),{apply:true});assert.equal(applied.mainActivated,false);
 const saved=(await ref.get()).data();assert.equal(saved.status,original.data().status);assert.equal(saved.updatedAt.toMillis(),original.data().updatedAt.toMillis());assert.equal(saved.notes,'A newer command-center update');
 assert.equal((await admin.doc('system/backend_rollout').get()).data().enabled,false);
});
test('main profile photos retain private owner/admin access and do not change account privileges',async()=>{
 const uploaded=await request('media-upload/avatar',jpeg());assert.equal(uploaded.status,200,JSON.stringify(uploaded.body));
 const loaded=await request('profile-context',{});assert.equal(loaded.status,200);
 const saved=await request('profile-save',{requestId:'p'.repeat(24),contextToken:loaded.body.result.token,name:'Demo resident',location:'Marulas',photoMode:'set',photoUrl:uploaded.body.reference});
 assert.equal(saved.status,200,JSON.stringify(saved.body));
 const profile=(await admin.doc('users/resident').get()).data();assert.equal(profile.role,'user');assert.equal(profile.trustScore,50);
 for(const uid of ['resident','admin']) {const image=await request('media-read',{reference:uploaded.body.reference},uid);assert.equal(image.status,200);assert.deepEqual(image.body,jpeg());}
 assert.equal((await request('media-read',{reference:uploaded.body.reference},'other')).status,403);
});


test('enabled Marulas follow-up returns to review, notifies admins, and preserves the original reward',async()=>{
 const originalApi=api;
 api=modules.proof_handler.createProofHandler({db,photos,profile,verify:async value=>value?.replace('Fixture ',''),push,adminNotices:true,followupsEnabled:true});
 try {
  const upload=await request('photo-upload',jpeg());assert.equal(upload.status,200);
  const submitted=await request('submit-report',{requestId:'main_root_followup_123456',roadId:'legacy_name',title:'Flood observation',description:'Water is covering this road.',severity:'High',isEmergency:false,observedAt:new Date(Date.now()-600000).toISOString(),location:{lat:14.676,lng:120.984,source:'manual',imageUrl:upload.body.imageUrl}});
  assert.equal(submitted.status,200,JSON.stringify(submitted.body));const rootReportId=submitted.body.result.reportId;
  const loaded=await context({reportId:rootReportId});
  const reviewed=await request('admin-action',{action:'verify',observationOnly:true,reportId:rootReportId,contextToken:loaded.token,requestId:'main_root_verify_12345678',note:'Observation checked against available evidence.'},'admin');assert.equal(reviewed.status,200,JSON.stringify(reviewed.body));
  assert.equal((await roadReview('not_passable',rootReportId)).status,200);
  await admin.doc('users/resident').update({lastReportAt:new Date(Date.now()-360000)});
  const current=await request('followup-context',{rootReportId});assert.equal(current.status,200,JSON.stringify(current.body));assert.equal(current.body.result.canSubmit,true);
  const payload={rootReportId,requestId:'main_followup_submit_123456',contextToken:current.body.result.token,conditionChange:'improved',severity:'Low',description:'The water is lower at the crossing during this new observation.',observedAt:new Date().toISOString()};
  const followed=await request('followup-submit',payload);assert.equal(followed.status,200,JSON.stringify(followed.body));const childId=followed.body.result.reportId;
  assert.notEqual(childId,rootReportId);assert.equal((await request('followup-submit',payload)).body.result.replay,true);
  const root=(await admin.doc(`reports/${rootReportId}`).get()).data(),child=(await admin.doc(`reports/${childId}`).get()).data();
  assert.equal(root.imageUrl,upload.body.imageUrl);assert.equal(root.status,'verified');assert.equal(root.pointsAwarded,10);assert.equal(child.rootReportId,rootReportId);assert.equal(child.status,'pending');
  assert.equal((await admin.doc('users/resident').get()).data().trustScore,60);
  const parent=await admin.doc(`notification_outbox/${child.adminNoticeEventId}`).get();assert.equal(parent.data().reportId,childId);
  assert.equal(await push.process(parent.ref.path),'expanded');
  const notices=await admin.collection('notification_outbox').where('parentEventId','==',parent.id).get();assert.equal(notices.size,1);assert.equal(notices.docs[0].data().userId,'admin');assert.equal(notices.docs[0].data().reportId,childId);
  const childContext=await context({reportId:childId});
  const childReview=await request('admin-action',{action:'verify',observationOnly:true,reportId:childId,contextToken:childContext.token,requestId:'main_followup_verify_12345',meaningfulFollowup:true,note:'The updated observation has been checked.'},'admin');
  assert.equal(childReview.status,200,JSON.stringify(childReview.body));assert.equal(childReview.body.result.pointsAwarded,5);
  assert.equal((await admin.doc('users/resident').get()).data().trustScore,65);assert.equal((await admin.doc(`reports/${rootReportId}`).get()).data().pointsAwarded,10);
  assert.equal((await admin.doc('roads/legacy_name').get()).data().status,'not_passable');
 } finally {api=originalApi;}
});
