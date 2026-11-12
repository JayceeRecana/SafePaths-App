const {test,before}=require('node:test'),assert=require('node:assert/strict');
const {storageFixture}=require('./support/proof_storage_fixture.cjs');
let profiles,firebase,storage,weather,handler,common,communications;
before(async()=>{
 [profiles,firebase,storage,weather,handler,common,communications]=await Promise.all(
  ['backend_profile','proof_firebase','proof_storage','proof_weather','proof_handler','proof_common','proof_communications'].map(n=>import(`../../supabase/functions/_shared/${n}.mjs`)));
});
test('main is an explicit target; proof project guards and credential isolation stay intact',()=>{
 const {TEST_BACKEND,MARULAS_BACKEND,assertBackendProject}=profiles;
 assert.throws(()=>assertBackendProject('safepaths-92c3d'));
 assert.throws(()=>assertBackendProject('safepaths-test',MARULAS_BACKEND));
 assert.throws(()=>assertBackendProject('safepaths-92c3d',{...MARULAS_BACKEND}));
 assert.doesNotThrow(()=>assertBackendProject('safepaths-92c3d',MARULAS_BACKEND));
 for(const profile of [TEST_BACKEND,MARULAS_BACKEND]) {
  const main=profile===MARULAS_BACKEND, projectId=main?'safepaths-92c3d':'safepaths-test';
  assert.throws(()=>new firebase.GoogleCredential({project_id:main?'safepaths-test':'safepaths-92c3d'},projectId,fetch,Date.now,profile));
  assert.throws(()=>firebase.createFirebaseVerifier({projectId,profile,emulatorAuthHost:'127.0.0.1:9499'}));
  assert.throws(()=>new firebase.FirestoreRest({projectId,profile,emulatorHost:'127.0.0.1:8480'}));
 }
});
test('main JWT verification accepts only signed main sessions and checks current revocation',async()=>{
 const projectId='safepaths-92c3d',now=Date.now(),epoch=Math.floor(now/1000);
 const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
 const key={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'main-fixture'};
 let validSince=epoch-30,disabled=false;
 const verify=firebase.createFirebaseVerifier({projectId,profile:profiles.MARULAS_BACKEND,credential:{token:async()=>'fixture'},clock:()=>now,
  fetcher:async url=>new Response(JSON.stringify(String(url).includes('/jwk/')?{keys:[key]}:{users:[{localId:'resident',emailVerified:true,validSince:String(validSince),disabled}]}))});
 async function token(overrides={}) {
  const enc=v=>common.base64url(new TextEncoder().encode(JSON.stringify(v)));
  const body=enc({alg:'RS256',kid:key.kid})+'.'+enc({aud:projectId,iss:`https://securetoken.google.com/${projectId}`,sub:'resident',email_verified:true,iat:epoch,auth_time:epoch-10,exp:epoch+3600,firebase:{sign_in_provider:'password'},...overrides});
  return 'Bearer '+body+'.'+common.base64url(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(body)));
 }
 assert.equal(await verify(await token()),'resident');
 await assert.rejects(()=>token({aud:'safepaths-test'}).then(verify),{code:'unauthenticated'});
 await assert.rejects(()=>token({iss:'https://securetoken.google.com/safepaths-test'}).then(verify),{code:'unauthenticated'});
 validSince=epoch;await assert.rejects(()=>token().then(verify),{code:'unauthenticated'});
 validSince=epoch-30;disabled=true;await assert.rejects(()=>token().then(verify),{code:'unauthenticated'});
});
test('main photos use a different private bucket and reject proof references in either direction',async()=>{
 const profile=profiles.MARULAS_BACKEND,fixture=storageFixture({bucket:profile.bucket,origin:'https://bbteuzgfgnrjjrqewidc.supabase.co'});
 const main=new storage.ProofStorage({profile,url:fixture.origin,...fixture});
 const proofFixture=storageFixture(); const proof=new storage.ProofStorage({url:proofFixture.origin,...proofFixture});
 const bytes=new Uint8Array([255,216,255,1,255,217]),digest=await common.sha256(bytes);
 const ref=await main.upload('resident',digest,bytes);
 assert.match(ref,/\/safepaths-main\/photo\//);assert.equal(fixture.files.size,1);
 assert.ok([...fixture.files.keys()][0].startsWith('report-photos-marulas/'));
 assert.throws(()=>proof.parse(ref));assert.throws(()=>main.parse(proof.reference('resident',digest)));
 fixture.publicBucket=true;await assert.rejects(()=>main.upload('resident',digest,bytes),{code:'unavailable'});
});
test('main weather is scoped to Marulas and cannot validate a nearby simulation as local weather',()=>{
 const now=Date.now(),units={time:'unixtime',interval:'seconds',precipitation:'mm',wind_speed_10m:'m/s',temperature_2m:'\u00b0C',relative_humidity_2m:'%'};
 const parsed=weather.parseWeather({current_units:units,current:{time:Math.floor(now/1000),interval:900,precipitation:1,wind_speed_10m:3,temperature_2m:29,relative_humidity_2m:75,weather_code:61}},now,profiles.MARULAS_BACKEND);
 assert.equal(parsed.studyArea,'marulas');assert.equal(parsed.precipitationIntensity,4);
 assert.equal(weather.usableWeather(parsed,now,profiles.MARULAS_BACKEND),true);
 assert.equal(weather.usableWeather(parsed,now),false);
});
test('main admission uses current profiles and rejects nearby/unscoped road commands',async()=>{
 const doc=data=>({exists:true,data}),{eligibleMember,requireMainRoadScope}=profiles;
 assert.equal(eligibleMember(doc({role:'user'})),true);
 for(const data of [{role:'user',studyArea:'nearby_test'},{role:'user',disabled:true},{role:'user',isTestAccount:true},{role:'guest'},{}]) assert.equal(eligibleMember(doc(data)),false);
 const db={get:async path=>doc(path.startsWith('reports/')?{roadId:'road'}:{studyArea:'nearby_test'})};
 await assert.rejects(()=>requireMainRoadScope(db,{rootReportId:'report'}),{code:'failed-precondition'});
 db.get=async()=>doc({studyArea:'marulas'});await requireMainRoadScope(db,{roadId:'road'});
});
test('main handler requires release control, rejects proof routes, and blocks unapproved accounts before upload',async()=>{
 let enabled=false,role='user',uploads=0;
 const db={get:async path=>({exists:true,data:path==='system/backend_rollout'?{enabled,version:1,studyArea:'marulas'}:{role}})};
 const api=handler.createProofHandler({profile:profiles.MARULAS_BACKEND,db,verify:async()=>'resident',photos:{upload:async()=>{uploads++;return 'unused';}}});
 const request=path=>api(new Request(`https://example.com${path}`,{method:'POST',headers:{'content-type':'image/jpeg'},body:new Uint8Array([255,216,255,1,255,217])}));
 assert.equal((await request('/functions/v1/safepaths-main/photo-upload')).status,503);
 enabled=true;role='guest';assert.equal((await request('/safepaths-main/photo-upload')).status,403);
 assert.equal((await request('/safepaths-report-proof/photo-upload')).status,404);assert.equal(uploads,0);
 let reads=0;
 const closed=handler.createProofHandler({profile:profiles.MARULAS_BACKEND,db:{get:async()=>{reads++;throw Error('must not read');}},verify:async()=>{throw new common.ProofError('unauthenticated','Sign in',401);},photos:{}});
 assert.equal((await closed(new Request('https://example.com/safepaths-main/photo-upload',{method:'POST'}))).status,401);
 assert.equal(reads,0);
});
test('main broadcast audience is bounded before any write and publishing without push needs no audience scan',async()=>{
 let writes=0,queries=0;const doc=(path,data)=>({path,data,exists:!!data});
 const tx={get:async path=>doc(path,path==='users/admin'?{role:'admin'}:null),queryWhere:async()=>{queries++;return Array.from({length:201},(_,i)=>doc(`users/u${i}`,{role:'user'}));},set:()=>{writes++;}};
 const api=communications.createCommunications({profile:profiles.MARULAS_BACKEND,db:{transaction:work=>work(tx)}});
 const data={requestId:'a'.repeat(24),title:'Road advisory',message:'Check current barangay updates before travel.',severity:'Advisory',sendPush:true,minutes:60,studyArea:'marulas'};
 await assert.rejects(()=>api.publish('admin',data),{code:'resource-exhausted'});assert.equal(writes,0);
 const saved=await api.publish('admin',{...data,sendPush:false});assert.equal(saved.saved,true);assert.equal(saved.queuedCount,0);assert.equal(queries,1);
});
test('offline migration preserves road identity/conditions and rejects test datasets',()=>{
 const {plan}=require('../tools/prepare-main-integration.cjs');
 const snapshot={project:'safepaths-92c3d',documents:[{path:'roads/legacy_name',updateTime:'version',data:{name:'Road',status:'not_passable',isVerified:true,geometry:{coordinates:[[120.984,14.675],[120.984,14.677]]}}}]};
 const result=plan(snapshot);assert.equal(result.blockers.length,0);assert.deepEqual(result.roadMetadata[0].patch,{studyArea:'marulas'});
 assert.equal(result.controls['system/backend_rollout'].enabled,false);assert.equal(snapshot.documents[0].data.status,'not_passable');
 assert.throws(()=>plan({...snapshot,project:'safepaths-test'}));
 snapshot.documents[0].data.studyArea='nearby_test';assert.equal(plan(snapshot).blockers.length,1);
});
test('main metadata tool defaults to read-only and refuses control/path tampering',()=>{
 const {options,validatePlan}=require('../tools/apply-main-integration.cjs'),crypto=require('node:crypto');
 const args=['--project=safepaths-92c3d','--credentials=private.json','--plan=plan.json','--backup=backup.json'];
 assert.equal(options(args).apply,false);assert.equal(options([...args,'--apply']).apply,true);
 assert.throws(()=>options(args.map(a=>a.replace('safepaths-92c3d','safepaths-test'))));
 const bytes=Buffer.from('private-backup'),plan={project:'safepaths-92c3d',area:'marulas',blockers:[],roadCount:1,roadMetadata:[],backupSha256:crypto.createHash('sha256').update(bytes).digest('hex'),controls:{'system/core_setup':{version:1,studyArea:'marulas',roadCount:1},'system/communications':{enabled:true},'system/media':{enabled:true},'system/road_maintenance':{enabled:true},'system/backend_rollout':{enabled:false,version:1,studyArea:'marulas'}}};
 validatePlan(plan,bytes);assert.throws(()=>validatePlan(plan,Buffer.from('changed')));
 assert.throws(()=>validatePlan({...plan,controls:{...plan.controls,'system/backend_rollout':{enabled:true,version:1,studyArea:'marulas'}}},bytes));
});
