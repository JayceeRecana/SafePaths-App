const {test,before,after,beforeEach} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails} = require('@firebase/rules-unit-testing');
const {doc,setDoc,updateDoc,getDoc,getDocs,collection,query,where,orderBy,limit,startAfter,documentId,serverTimestamp} = require('firebase/firestore');
const {ref,uploadBytes} = require('firebase/storage');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error('Start the firestore,storage,auth emulators with demo-safepaths-reliability before running integration tests.');
const projectId = 'demo-safepaths-reliability';
process.env.GCLOUD_PROJECT = projectId;
process.env.FIREBASE_CONFIG = JSON.stringify({projectId});
let env,admin,api,auth;
before(async()=>{
  env = await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')},storage:{rules:fs.readFileSync(path.join(__dirname,'../../storage.rules'),'utf8')}});
  api = require('../index.cjs');
  admin = require('firebase-admin/firestore').getFirestore();
  auth = require('firebase-admin/auth').getAuth();
});
after(async()=>{await env.cleanup(); await require('firebase-admin/app').deleteApp(require('firebase-admin/app').getApp());});
beforeEach(async()=>{
  await env.clearFirestore();
  for (const uid of ['u','v','w','admin']) {
    try { await auth.deleteUser(uid); } catch (_) {}
    await auth.createUser({uid, email: `${uid}@example.com`, emailVerified: true});
  }
  await admin.doc('users/u').set({role:'user',trustScore:50,verifiedReports:0,dismissedReports:0});
  await admin.doc('users/admin').set({role:'admin'});
  await admin.doc('roads/r').set({name:'Test road',status:'passable',updatedAt:new Date(),geometry:{segments:[{points:[{lon:120.984,lat:14.675},{lon:120.984,lat:14.677}]}]}});
});
const context = uid => env.authenticatedContext(uid, {email_verified: true}).firestore();
const payload = id => ({requestId:id.repeat(20),roadId:'r',title:'Flood',description:'Water on road',severity:'High',isEmergency:false,location:{lat:14.676,lng:120.984}});
const submit = (data,uid='u') => api.submitReport.run({auth:{uid,token:{email_verified:true,auth_time:Math.floor(Date.now()/1000)}},data});
const incidentCall = (name, data, uid='v') => api[name].run({auth:{uid,token:{email_verified:true,auth_time:Math.floor(Date.now()/1000)}},data});
const currentIncident = async () => (await admin.doc('road_incidents/r').get()).data();
const observation = (incident, choice='still_flooded', id='o') => ({roadId:'r',incidentId:incident.incidentId,choice,observedAt:new Date().toISOString(),requestId:id.repeat(20)});
const review = (incident, status='passable', id='review') => ({roadId:'r',incidentId:incident.incidentId,
  revision:incident.revision,roadStatus:status,note:'Verified today by barangay field staff.',verifiedCurrentConditions:true,requestId:id.repeat(4)});

test('feedback diagnostics accept classifications and reject private contents and forged timestamps',async()=>{
  const db=context('u');
  const safe={type:'feedback_submission_error',errorCode:'unavailable',timestamp:serverTimestamp()};
  await assertSucceeds(setDoc(doc(db,'error_logs','safe'),safe));
  const stored=(await admin.doc('error_logs/safe').get()).data();
  assert.deepEqual(Object.keys(stored).sort(),['errorCode','timestamp','type']);
  await assertFails(setDoc(doc(db,'error_logs','identity'),{...safe,uid:'u'}));
  await assertFails(setDoc(doc(db,'error_logs','message'),{...safe,error:'person@example.com token=secret'}));
  await assertFails(setDoc(doc(db,'error_logs','arbitrary-code'),{...safe,errorCode:'person@example.com'}));
  await assertFails(setDoc(doc(db,'error_logs','old-time'),{...safe,timestamp:new Date(0)}));
});

test('bounded history pages preserve equal-timestamp order and exclude no active hazards',async()=>{
  const batch=admin.batch();
  const date=new Date();
  for (let i=0;i<85;i++) batch.set(admin.doc(`reports/history${String(i).padStart(3,'0')}`),
    {userId:'u',status:'resolved',createdAt:date,roadId:'r'});
  for (let i=0;i<35;i++) batch.set(admin.doc(`reports/active${String(i).padStart(3,'0')}`),
    {userId:'other',status:i%2 ? 'pending':'under_review',createdAt:new Date(0),roadId:'r'});
  await batch.commit();
  const db=context('u');
  const active=await getDocs(query(collection(db,'reports'),where('status','in',['pending','under_review'])));
  assert.equal(active.size,35); // Never truncate active records by age or history-page size.
  const base=query(collection(db,'reports'),where('userId','==','u'),orderBy('createdAt','desc'),orderBy(documentId(),'desc'),limit(30));
  const first=await getDocs(base);
  const last=first.docs.at(-1);
  const second=await getDocs(query(base,startAfter(last.data().createdAt,last.id)));
  const third=await getDocs(query(base,startAfter(second.docs.at(-1).data().createdAt,second.docs.at(-1).id)));
  assert.equal(first.size,30); assert.equal(second.size,30); assert.equal(third.size,25);
  assert.equal(new Set([...first.docs,...second.docs,...third.docs].map(doc=>doc.id)).size,85);
});
test('resident cannot change road status, trust, cooldown or report verification',async()=>{
  const db=context('u');
  await assertFails(updateDoc(doc(db,'roads/r'),{status:'passable'}));
  await assertFails(updateDoc(doc(db,'users/u'),{trustScore:100}));
  await assertFails(updateDoc(doc(db,'users/u'),{lastReportAt:new Date(0)}));
  await assertFails(setDoc(doc(db,'reports/forged'),{userId:'admin',status:'verified'}));
  await admin.doc('reports/own').set({userId:'u',status:'pending'});
  await assertFails(updateDoc(doc(db,'reports/own'),{status:'verified'}));
  await assertSucceeds(updateDoc(doc(db,'users/u'),{name:'Updated',updatedAt:new Date()}));
  await assertSucceeds(updateDoc(doc(context('admin'),'roads/r'),{status:'not_passable'}));
  await assertFails(getDoc(doc(db,'users/admin')));
});
test('new accounts cannot choose elevated role or reputation',async()=>{
  const db=context('new');
  await assertFails(setDoc(doc(db,'users/new'),{role:'admin'}));
  await assertFails(setDoc(doc(db,'users/new'),{role:'user',trustScore:100}));
  await assertSucceeds(setDoc(doc(db,'users/new'),{role:'user',trustScore:50,verifiedReports:0,dismissedReports:0}));
});
test('storage rejects cross-account, oversized, wrong type and legacy writes',async()=>{
  const storage=env.authenticatedContext('u', {email_verified: true}).storage();
  await assertSucceeds(uploadBytes(ref(storage,'reports/u/test.jpg'),new Uint8Array([1,2,3]),{contentType:'image/jpeg'}));
  await assertFails(uploadBytes(ref(storage,'reports/other/test.jpg'),new Uint8Array([1]),{contentType:'image/jpeg'}));
  await assertFails(uploadBytes(ref(storage,'reports/u/code.txt'),new Uint8Array([1]),{contentType:'text/plain'}));
  await assertFails(uploadBytes(ref(storage,'reports/legacy.jpg'),new Uint8Array([1]),{contentType:'image/jpeg'}));
  await assertFails(uploadBytes(ref(storage,'reports/u/huge.jpg'),new Uint8Array(10*1024*1024+1),{contentType:'image/jpeg'}));
});
test('concurrent identical submissions and response-loss replays create one report',async()=>{
  const [a,b]=await Promise.all([submit(payload('a')),submit(payload('a'))]);
  assert.equal(a.reportId,b.reportId);
  assert.equal((await admin.collection('reports').get()).size,1);
  assert.equal((await submit(payload('a'))).replay,true);
});
test('concurrent different requests enforce server cooldown atomically',async()=>{
  const results=await Promise.allSettled([submit(payload('a')),submit(payload('b'))]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.match(results.find(r=>r.status==='rejected').reason.message,/SPAM_COOLDOWN/);
  assert.equal((await admin.collection('reports').get()).size,1);
});
test('later submissions update the active report using server state',async()=>{
  const first=await submit(payload('a'));
  await admin.doc('users/u').update({lastReportAt:new Date(Date.now()-6*60000)});
  const second=await submit({...payload('b'),description:'New depth'});
  assert.equal(second.reportId,first.reportId);
  assert.equal((await admin.doc(`reports/${first.reportId}`).get()).data().description,'New depth');
});
test('request reuse with different content and unauthenticated submission are rejected',async()=>{
  await submit(payload('a'));
  await assert.rejects(()=>submit({...payload('a'),description:'different'}),/different content/);
  await assert.rejects(()=>api.submitReport.run({data:payload('a')}),/sign in/);
  await assert.rejects(()=>submit({...payload('b'),location:{lat:0,lng:0}}),/SPAM_COOLDOWN/);
});
test('server validates location even for edits and photo ownership',async()=>{
  await assert.rejects(()=>submit({...payload('a'),location:{lat:0,lng:0}}),/OUT_OF_RANGE/);
  await assert.rejects(()=>submit({...payload('a'),location:{lat:14.676,lng:120.984,imageUrl:'https://example.com/other.jpg'}}),/Photo/);
});
test('ordinary accounts cannot invoke privileged notification dispatch',async()=>{
  await assert.rejects(()=>api.sendNotification.run({auth:{uid:'u',token:{email_verified:true,auth_time:Math.floor(Date.now()/1000)}},data:{title:'Fake',body:'Alert'}}),/Administrator/);
});
test('scheduled risk calculation works without an active app and expires old reports',async()=>{
  await admin.doc('system/weather').set({currentState:'heavyRain',isOverrideMode:false,lastFetched:new Date()});
  await admin.doc('reports/old').set({status:'pending',createdAt:new Date(Date.now()-25*3600000),roadId:'r'});
  await api.refreshRisk.run({});
  assert.equal((await admin.doc('reports/old').get()).data().status,'expired');
  assert.ok((await admin.doc('roads/r').get()).data().riskUpdatedAt);
  assert.ok((await admin.doc('system/risk_job').get()).data().lastSuccess);
});
test('stale weather cannot cause new safe scores or a successful job heartbeat',async()=>{
  await admin.doc('roads/r').update({riskScore:80});
  await admin.doc('system/weather').set({currentState:'clear',lastFetched:new Date(0)});
  await assert.rejects(()=>api.refreshRisk.run({}),/outdated/);
  assert.equal((await admin.doc('roads/r').get()).data().riskScore,80);
  assert.equal((await admin.doc('system/risk_job').get()).data().leaseUntil.toMillis(),0);
});

test('unverified, disabled and revoked accounts cannot submit reports',async()=>{
  await assert.rejects(()=>api.submitReport.run({auth:{uid:'u',token:{email_verified:false,auth_time:Math.floor(Date.now()/1000)}},data:payload('v')}),/Verify your email/);
  await auth.updateUser('u',{disabled:true});
  await assert.rejects(()=>submit(payload('v')),/no longer valid/);
  await auth.updateUser('u',{disabled:false});
  await auth.revokeRefreshTokens('u');
  await assert.rejects(()=>api.submitReport.run({auth:{uid:'u',token:{email_verified:true,auth_time:1}},data:payload('v')}),/no longer valid/);
});
test('unverified accounts cannot read reports, upload photos or write as administrators',async()=>{
  const unverified = env.authenticatedContext('u',{email_verified:false});
  await assertFails(getDoc(doc(unverified.firestore(),'reports/any')));
  await assertFails(uploadBytes(ref(unverified.storage(),'reports/u/unverified.jpg'),new Uint8Array([1]),{contentType:'image/jpeg'}));
  const unverifiedAdmin = env.authenticatedContext('admin',{email_verified:false});
  await assertFails(updateDoc(doc(unverifiedAdmin.firestore(),'roads/r'),{status:'passable'}));
  // Own profile setup stays possible before verification.
  await assertSucceeds(getDoc(doc(unverified.firestore(),'users/u')));
});

test('one incident is shared by reports from different residents; self-confirmation is rejected',async()=>{
  const first = await submit(payload('a'));
  const second = await submit(payload('b'),'v');
  const incident = await currentIncident();
  assert.equal((await admin.doc(`reports/${first.reportId}`).get()).data().incidentId,incident.incidentId);
  assert.equal((await admin.doc(`reports/${second.reportId}`).get()).data().incidentId,incident.incidentId);
  await assert.rejects(()=>incidentCall('observeRoadIncident',observation(incident),'u'),/own report/);
  await assert.rejects(()=>incidentCall('observeRoadIncident',observation(incident),'v'),/own report/);
});

test('concurrent response-loss retries count once and cannot reopen a road',async()=>{
  await submit(payload('a'));
  await admin.doc('roads/r').update({status:'not_passable'});
  const incident = await currentIncident(), data = observation(incident,'appears_passable');
  await Promise.all([incidentCall('observeRoadIncident',data),incidentCall('observeRoadIncident',data)]);
  assert.equal((await currentIncident()).counts.appears_passable,1);
  assert.equal((await currentIncident()).state,'under_verification');
  assert.equal((await admin.doc('roads/r').get()).data().status,'not_passable');
  assert.equal((await admin.collection('incident_audits').get()).size,1);
  await assert.rejects(()=>incidentCall('observeRoadIncident',{...data,choice:'still_flooded'}),/already used/);
});

test('a responder who later files a report no longer counts as an independent confirmation',async()=>{
  await submit(payload('a'));
  const incident = await currentIncident();
  await incidentCall('observeRoadIncident',observation(incident));
  assert.equal((await currentIncident()).counts.still_flooded,1);
  await submit(payload('b'),'v');
  assert.equal((await currentIncident()).counts.still_flooded,0);
  await assert.rejects(()=>incidentCall('observeRoadIncident',observation(incident,'still_flooded','x')),/own report/);
});

test('delayed observations cannot be relabelled as current on a retry',async()=>{
  await submit(payload('a'));
  const incident = await currentIncident();
  const stale = {...observation(incident),observedAt:new Date(Date.now()-6*60000).toISOString()};
  await assert.rejects(()=>incidentCall('observeRoadIncident',stale),/OBSERVATION_STALE/);
  const data = {...observation(incident),observedAt:new Date(Date.now()-4*60000).toISOString()};
  await incidentCall('observeRoadIncident',data);
  assert.equal((await currentIncident()).lastConfirmedAt.toMillis(),Date.parse(data.observedAt));
  const time = (await currentIncident()).lastConfirmedAt.toMillis();
  assert.equal((await incidentCall('observeRoadIncident',data)).replay,true);
  assert.equal((await currentIncident()).lastConfirmedAt.toMillis(),time);
});

test('changing a response replaces it; throttling and cannot-confirm do not refresh evidence',async()=>{
  await submit(payload('a'));
  const incident = await currentIncident();
  await incidentCall('observeRoadIncident',observation(incident));
  await assert.rejects(()=>incidentCall('observeRoadIncident',observation(incident,'cannot_confirm','c')),/one minute/);
  const oldTime = new Date(Date.now()-25*3600000);
  const responses = await admin.collection('road_incidents/r/responses').get();
  await responses.docs[0].ref.update({submittedAt:oldTime});
  await admin.doc('road_incidents/r').update({lastObservedAt:oldTime,lastConfirmedAt:oldTime});
  await incidentCall('observeRoadIncident',observation(incident,'cannot_confirm','c'));
  const updated = await currentIncident();
  assert.deepEqual(updated.counts,{still_flooded:0,appears_passable:0,cannot_confirm:1});
  assert.equal(updated.lastObservedAt.toMillis(),oldTime.getTime());
  assert.equal(updated.lastConfirmedAt.toMillis(),oldTime.getTime());
});

test('incident writes and private responses are server-controlled',async()=>{
  await submit(payload('a'));
  const incident = await currentIncident();
  await incidentCall('observeRoadIncident',observation(incident));
  const response = (await admin.collection('road_incidents/r/responses').get()).docs[0];
  await assertSucceeds(getDoc(doc(context('u'),'road_incidents/r')));
  await assertFails(updateDoc(doc(context('u'),'road_incidents/r'),{state:'resolved'}));
  await assertFails(updateDoc(doc(context('admin'),'road_incidents/r'),{state:'resolved'}));
  await assertSucceeds(getDoc(doc(context('v'),response.ref.path)));
  await assertFails(getDoc(doc(context('w'),response.ref.path)));
  await assertFails(updateDoc(doc(context('v'),response.ref.path),{choice:'appears_passable'}));
  await assertFails(getDoc(doc(env.authenticatedContext('u',{email_verified:false}).firestore(),'road_incidents/r')));
});

test('reopening requires an administrator, fresh revision, verification and audit note',async()=>{
  await submit(payload('a'));
  const initial = await currentIncident();
  await assert.rejects(()=>incidentCall('reviewRoadIncident',review(initial),'v'),/Administrator/);
  await assert.rejects(()=>incidentCall('reviewRoadIncident',{...review(initial),verifiedCurrentConditions:false},'admin'),/Verify current/);
  await assert.rejects(()=>incidentCall('reviewRoadIncident',{...review(initial),note:'ok'},'admin'),/review note/);
  await incidentCall('observeRoadIncident',observation(initial,'still_flooded'));
  await assert.rejects(()=>incidentCall('reviewRoadIncident',review(initial),'admin'),/New information/);
  const latest = await currentIncident(), data = review(latest);
  await incidentCall('reviewRoadIncident',data,'admin');
  assert.equal((await currentIncident()).state,'resolved');
  assert.equal((await admin.doc('roads/r').get()).data().communityCondition,'resolved');
  assert.equal((await admin.collection('reports').get()).docs[0].data().status,'resolved');
  assert.equal((await incidentCall('reviewRoadIncident',data,'admin')).replay,true);
  await assert.rejects(()=>incidentCall('observeRoadIncident',observation(initial,'appears_passable','p'),'w'),/changed or was resolved/);
  const next = await submit(payload('n'),'w');
  assert.notEqual((await currentIncident()).incidentId,latest.incidentId);
  assert.deepEqual((await currentIncident()).counts,{still_flooded:0,appears_passable:0,cannot_confirm:0});
  assert.equal((await admin.doc(`reports/${next.reportId}`).get()).data().status,'pending');
});

test('expired and under-review reports remain cautionary, including during weather outages',async()=>{
  const result = await submit(payload('a'));
  const old = new Date(Date.now()-25*3600000);
  await admin.doc(`reports/${result.reportId}`).update({observedAt:old,status:'under_review'});
  await admin.doc('road_incidents/r').update({lastObservedAt:old});
  await admin.doc('system/weather').set({currentState:'clear',lastFetched:new Date(0)});
  await assert.rejects(()=>api.refreshRisk.run({}),/outdated/);
  assert.equal((await currentIncident()).state,'outdated');
  assert.equal((await admin.doc(`reports/${result.reportId}`).get()).data().status,'expired');
  assert.equal((await admin.doc('roads/r').get()).data().communityCondition,'outdated');
  await admin.doc('system/weather').update({lastFetched:new Date()});
  await api.refreshRisk.run({});
  assert.equal((await admin.doc('roads/r').get()).data().riskScore,30);
  assert.equal((await admin.doc('roads/r').get()).data().riskCategory,'Watch');
});

test('legacy expired reports become unknown unless a later official reopening exists',async()=>{
  await admin.doc('reports/old').set({status:'expired',createdAt:new Date(Date.now()-25*3600000),roadId:'r',userId:'u'});
  await admin.doc('system/weather').set({currentState:'clear',lastFetched:new Date()});
  await api.refreshRisk.run({});
  assert.equal((await currentIncident()).state,'outdated');
  assert.equal((await admin.doc('roads/r').get()).data().riskCategory,'Watch');
  await admin.doc('roads/cleared').set({status:'passable',isVerified:true,updatedAt:new Date()});
  await admin.doc('reports/cleared-old').set({status:'expired',createdAt:new Date(Date.now()-25*3600000),roadId:'cleared',userId:'u'});
  await api.refreshRisk.run({});
  assert.equal((await admin.doc('road_incidents/cleared').get()).exists,false);
});

test('worsening an existing report has a bounded exception; normal spam still fails',async()=>{
  const first = await submit({...payload('a'),severity:'Low'});
  await admin.doc('users/u').update({lastReportAt:new Date(Date.now()-61*1000)});
  const escalated = await submit({...payload('b'),severity:'Medium'});
  assert.equal(escalated.reportId,first.reportId);
  assert.ok((await admin.doc('users/u').get()).data().lastEscalationAt);
  await admin.doc('users/u').update({lastReportAt:new Date(Date.now()-61*1000)});
  await assert.rejects(()=>submit({...payload('c'),severity:'High'}),/SPAM_COOLDOWN/);
});

test('legacy migration is paginated and later pages retain the newest observation',async()=>{
  const batch = admin.batch();
  for (let i=0;i<100;i++) batch.set(admin.doc(`reports/a${String(i).padStart(3,'0')}`),
    {status:'expired',createdAt:new Date(Date.now()-25*3600000),roadId:'r',userId:`legacy${i}`});
  batch.set(admin.doc('reports/znew'),{status:'pending',createdAt:new Date(),observedAt:new Date(),roadId:'r',userId:'u',severity:'High',authorityScore:50});
  await batch.commit();
  await admin.doc('system/weather').set({currentState:'clear',lastFetched:new Date()});
  await api.refreshRisk.run({});
  assert.equal((await admin.doc('system/incident_migration').get()).data().complete,false);
  assert.equal((await currentIncident()).state,'outdated');
  assert.equal((await admin.doc('reports/znew').get()).data().incidentId,undefined);
  await api.refreshRisk.run({});
  assert.equal((await admin.doc('system/incident_migration').get()).data().complete,true);
  assert.equal((await currentIncident()).state,'reported_flooding');
  assert.equal((await admin.doc('reports/znew').get()).data().incidentId,(await currentIncident()).incidentId);
});

test('observation timestamps cannot be forged into the future or refreshed by retry',async()=>{
  await assert.rejects(()=>submit({...payload('a'),observedAt:new Date(Date.now()+120000).toISOString()}),/Observation time/);
  await assert.rejects(()=>submit({...payload('b'),observedAt:new Date(Date.now()-25*3600000).toISOString()}),/Observation time/);
  const data = {...payload('c'), observedAt:new Date(Date.now()-23*3600000).toISOString(),
    location:{...payload('c').location,source:'manual'}};
  const first = await submit(data);
  const saved = (await admin.doc(`reports/${first.reportId}`).get()).data();
  assert.equal(saved.observedAt.toMillis(),Date.parse(data.observedAt));
  assert.equal(saved.locationCheck.source,'manual');
  assert.equal(saved.locationCheck.method,'provided_coordinates');
  assert.equal((await submit(data)).replay,true);
});
