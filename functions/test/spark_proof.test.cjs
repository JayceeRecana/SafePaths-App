const {test,before} = require('node:test');
const assert=require('node:assert/strict');
const {storageFixture}=require('./support/proof_storage_fixture.cjs');
let common,firebase,reports,storage,handler;
before(async()=>{
  [common,firebase,reports,storage,handler]=await Promise.all(['proof_common','proof_firebase','proof_reports','proof_storage','proof_handler'].map(name=>import(`../../supabase/functions/_shared/${name}.mjs`)));
});
const projectId='demo-safepaths-spark-proof';
const data={requestId:'request_abcdefghijklmnop',roadId:'proof-road',title:' Flood ',description:' Synthetic ',severity:'High',isEmergency:false,location:{lat:14.676,lng:120.984,source:'gps',gpsAccuracyMeters:10}};

test('proof rejects main project, arbitrary emulator hosts and mismatched server credentials',()=>{
  assert.throws(()=>common.assertProofProject('safepaths-92c3d'));
  assert.throws(()=>common.assertProofProject('ordinary-production'));
  assert.throws(()=>common.assertLoopback('google.com:8080'));
  assert.throws(()=>common.assertLoopback('127.0.0.1:8080/redirect'));
  assert.throws(()=>firebase.createFirebaseVerifier({projectId:'safepaths-test',emulatorAuthHost:'127.0.0.1:9099'}));
  assert.throws(()=>new firebase.GoogleCredential({project_id:'safepaths-92c3d'},projectId));
  assert.doesNotThrow(()=>common.assertProofProject('safepaths-test'));
});

test('proof setup cannot target the main project or apply cloud changes implicitly',()=>{
  const {options}=require('../tools/prepare-spark-proof.cjs');
  assert.throws(()=>options(['--project=safepaths-92c3d','--credentials=private.json','--supabase-ref=aaaaaaaaaaaaaaaaaaaa']));
  const parsed=options(['--project=safepaths-test','--credentials=private.json','--supabase-ref=aaaaaaaaaaaaaaaaaaaa']);
  assert.equal(parsed.apply,false);
  assert.equal(options(['--project=safepaths-test','--credentials=private.json','--supabase-ref=aaaaaaaaaaaaaaaaaaaa','--apply']).apply,true);
});

test('portable validation and disconnected-road proximity match the existing backend',()=>{
  const original=require('../domain.cjs');
  assert.deepEqual(reports.validateReport({...data,userId:'forged',authorityScore:100}),original.validateReport(data));
  const geometries=[null,{coordinates:[[120.984,14.675],[120.984,14.677]]},{segments:[{points:[{lon:120.984,lat:14.675},{lon:120.984,lat:14.677}]}]},
    {type:'MultiLineString',coordinates:[[[120.98,14.67],[120.981,14.67]],[[120.99,14.67],[120.991,14.67]]]}];
  for(const geometry of geometries) assert.equal(reports.roadDistance(data.location,geometry),original.roadDistance(data.location,geometry));
  for(const malformed of [{severity:'fake'},{roadId:'a/b'},{requestId:'x'},{location:{lat:Infinity,lng:1}},{isEmergency:'yes'},{observedAt:'invalid'}]) {
    assert.throws(()=>reports.validateReport({...data,...malformed}));
    assert.throws(()=>original.validateReport({...data,...malformed}));
  }
});

test('Firestore REST values preserve timestamps, nulls, arrays and nested numbers',()=>{
  const value={observedAt:new Date('2026-10-24T10:00:00Z'),count:2,confidence:52.5,flag:true,missing:null,items:['a',1],location:{lat:14.676,lng:120.984}};
  assert.deepEqual(firebase.decodeValue(firebase.encodeValue(value)),value);
  assert.throws(()=>firebase.encodeValue({bad:NaN}));
});

test('server credential signs a scoped OAuth assertion and shares cached tokens without exposing a key',async()=>{
  const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
  const pem=`-----BEGIN PRIVATE KEY-----\n${Buffer.from(await crypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')}\n-----END PRIVATE KEY-----`;
  let now=Date.now(), calls=0;
  const email=`proof@${projectId}.iam.gserviceaccount.com`;
  const credential=new firebase.GoogleCredential({project_id:projectId,client_email:email,private_key:pem},projectId,async(url,options)=>{
    calls++;assert.equal(url,'https://oauth2.googleapis.com/token');
    const body=new URLSearchParams(options.body), assertion=body.get('assertion'), parts=assertion.split('.');
    assert.equal(body.get('grant_type'),'urn:ietf:params:oauth:grant-type:jwt-bearer');
    const payload=JSON.parse(Buffer.from(parts[1],'base64url'));
    assert.equal(payload.iss,email);assert.equal(payload.aud,url);assert.equal(payload.exp-payload.iat,3600);
    assert.ok(payload.scope.includes('https://www.googleapis.com/auth/datastore'));
    assert.equal(await crypto.subtle.verify('RSASSA-PKCS1-v1_5',pair.publicKey,common.fromBase64url(parts[2]),new TextEncoder().encode(`${parts[0]}.${parts[1]}`)),true);
    return new Response(JSON.stringify({access_token:'fixture-oauth-token',expires_in:3600}));
  },()=>now);
  assert.deepEqual(await Promise.all([credential.token(),credential.token()]),['fixture-oauth-token','fixture-oauth-token']);assert.equal(calls,1);
  now+=3600000;assert.equal(await credential.token(),'fixture-oauth-token');assert.equal(calls,2);
});

test('bounded request reader cancels streamed oversized bodies without a content-length',async()=>{
  let canceled=false;
  const body=new ReadableStream({start(controller){controller.enqueue(new Uint8Array(12));},cancel(){canceled=true;}});
  await assert.rejects(()=>common.readBounded(new Request('https://example.com',{method:'POST',body,duplex:'half'}),10),{code:'too-large'});
  assert.equal(canceled,true);
});

test('Firebase verification checks signature, audience, issuer, expiry, email and revocation',async()=>{
  const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
  const jwk={...await crypto.subtle.exportKey('jwk',pair.publicKey),kid:'fixture-key'};
  const now=Date.now(), epoch=Math.floor(now/1000); let account={localId:'resident',emailVerified:true,validSince:String(epoch-30)}, lookups=0;
  const fetcher=async(url,options)=>{
    if(String(url).includes('/jwk/')) return new Response(JSON.stringify({keys:[jwk]}),{headers:{'cache-control':'max-age=300'}});
    assert.equal(new Headers(options.headers).get('authorization'),'Bearer server-token'); lookups++;
    return new Response(JSON.stringify({users:[account]}));
  };
  const verify=firebase.createFirebaseVerifier({projectId,credential:{token:async()=>'server-token'},fetcher,clock:()=>now});
  const claims={aud:projectId,iss:`https://securetoken.google.com/${projectId}`,sub:'resident',iat:epoch,exp:epoch+3600,auth_time:epoch-10,email_verified:true,firebase:{sign_in_provider:'password'}};
  async function token(overrides={},header={alg:'RS256',kid:'fixture-key'}) {
    const first=common.base64url(new TextEncoder().encode(JSON.stringify(header))), second=common.base64url(new TextEncoder().encode(JSON.stringify({...claims,...overrides})));
    const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',pair.privateKey,new TextEncoder().encode(`${first}.${second}`));
    return `${first}.${second}.${common.base64url(signature)}`;
  }
  assert.equal(await verify(`Bearer ${await token()}`),'resident');
  for(const seconds of [3,30]) assert.equal(await verify(`Bearer ${await token({iat:epoch+seconds,auth_time:epoch+seconds})}`),'resident');
  for(const invalid of [{aud:'safepaths-92c3d'},{iss:'fake'},{sub:'other/account'},{exp:epoch},{iat:epoch+31},{iat:epoch+31,auth_time:epoch+31},{auth_time:epoch+1},{email_verified:false},{firebase:{sign_in_provider:'anonymous'}}]) {
    await assert.rejects(()=>token(invalid).then(value=>verify(`Bearer ${value}`)),{code:'unauthenticated'});
  }
  await assert.rejects(()=>token({}, {alg:'none',kid:'fixture-key'}).then(value=>verify(`Bearer ${value}`)),{code:'unauthenticated'});
  const valid=await token(); const pieces=valid.split('.'); pieces[1]=common.base64url(new TextEncoder().encode(JSON.stringify({...claims,sub:'admin'})));
  await assert.rejects(()=>verify(`Bearer ${pieces.join('.')}`),{code:'unauthenticated'});
  account={...account,disabled:true}; await assert.rejects(()=>verify(`Bearer ${valid}`),{code:'unauthenticated'});
  account={...account,disabled:false,validSince:String(epoch)}; await assert.rejects(()=>verify(`Bearer ${valid}`),{code:'unauthenticated'});
  assert.equal(lookups,5);
});

test('proof Storage keeps immutable owner paths and recovers a lost upload response',async()=>{
  const fixture=storageFixture(), photos=new storage.ProofStorage({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher});
  const bytes=new Uint8Array([255,216,255,1,255,217]), digest=await common.sha256(bytes);
  fixture.loseUploadResponse=true;
  const reference=await photos.upload('resident',digest,bytes);
  assert.equal(await photos.upload('resident',digest,bytes),reference);
  assert.equal(fixture.writes,1);
  await assert.rejects(()=>photos.validate(reference,'other'),{code:'permission-denied'});
  assert.throws(()=>photos.parse(`${reference}?token=untrusted`));
  assert.throws(()=>photos.parse('https://other.example.com/photo'));
  const signed=await photos.signed(reference);
  assert.equal(signed.expiresIn,120);
  assert.deepEqual(new Uint8Array(await (await fixture.fetcher(signed.url)).arrayBuffer()),bytes);
  fixture.publicBucket=true;
  await assert.rejects(()=>photos.validate(reference,'resident'),{code:'unavailable'});
});

test('Storage recognizes hosted wrapped missing-object responses without bypassing permission errors',async()=>{
  const fixture=storageFixture();fixture.missingInfoAs400=true;
  const photos=new storage.ProofStorage({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher});
  const bytes=new Uint8Array([255,216,255,1,255,217]),digest=await common.sha256(bytes);
  assert.ok(await photos.upload('resident',digest,bytes));assert.equal(fixture.writes,1);
  const denied=new storage.ProofStorage({url:fixture.origin,secret:fixture.secret,fetcher:async(url,options)=>String(url).includes('/object/info/')?new Response(JSON.stringify({statusCode:'403',error:'AccessDenied'}),{status:400}):fixture.fetcher(url,options)});
  await assert.rejects(()=>denied.upload('resident','b'.repeat(64),bytes),{code:'unavailable'});
  assert.equal(fixture.writes,1);
});

test('proof handler rejects unsigned uploads before reading bodies and hides provider errors',async()=>{
  let reads=0;
  const handle=handler.createProofHandler({db:{},photos:{},allowedUids:new Set(['resident']),verify:async()=>{throw new common.ProofError('unauthenticated','Please sign in.',401);}});
  const request={url:'https://example.com/safepaths-report-proof/photo-upload',method:'POST',headers:new Headers(),
    get body(){reads++;throw new Error('An unauthenticated body must not be read.');}};
  const response=await handle(request);
  assert.equal(response.status,401);
  assert.equal(reads,0);
  const broken=handler.createProofHandler({db:{},photos:{},allowedUids:new Set(['resident']),verify:async()=>{throw new Error('PRIVATE token=secret person@example.com');}});
  const failure=await broken(new Request('https://example.com/safepaths-report-proof/submit-report',{method:'POST',body:'{}'}));
  assert.equal(failure.status,503);
  assert.doesNotMatch(await failure.text(),/PRIVATE|secret|person@example/);
});

test('photo URL authorization uses the live server profile, not client-supplied roles',async()=>{
  const fixture=storageFixture(), photos=new storage.ProofStorage({url:fixture.origin,secret:fixture.secret,fetcher:fixture.fetcher});
  const reference=await photos.upload('owner','a'.repeat(64),new Uint8Array([1]));
  let role='user';
  const handle=handler.createProofHandler({photos,db:{get:async()=>({data:{role}})},allowedUids:new Set(['other']),verify:async()=> 'other'});
  const request=()=>new Request(`${photos.endpoint}/photo-url`,{method:'POST',body:JSON.stringify({imageUrl:reference,role:'admin'})});
  assert.equal((await handle(request())).status,403);
  role='admin'; assert.equal((await handle(request())).status,200);
  role='user'; assert.equal((await handle(request())).status,403);
});

test('the hosted proof is closed to arbitrary verified accounts and missing allowlists',async()=>{
  assert.throws(()=>handler.createProofHandler({db:{},photos:{},verify:async()=> 'outsider'}));
  const closed=handler.createProofHandler({db:{},photos:{},allowedUids:new Set(['resident']),verify:async()=> 'outsider'});
  const result=await closed(new Request('https://example.com/safepaths-report-proof/submit-report',{method:'POST',body:'{}'}));
  assert.equal(result.status,403);
});


test('Firestore REST commits nested server timestamps without encoding sentinels as values',async()=>{
 const db=new firebase.FirestoreRest({projectId,credential:{token:async()=>'fixture'},emulatorHost:'127.0.0.1:8480'});
 let committed;
 db.request=async(endpoint,body)=>{
  if(endpoint===':beginTransaction')return {transaction:'fixture-transaction'};
  if(endpoint===':commit'){committed=body;return {};}
  throw new Error('Unexpected request '+endpoint);
 };
 await db.transaction(async tx=>tx.set('report_clarifications/fixture',{
  answered:true,response:{message:'The original crossing.',photoObservedAt:new Date('2026-10-30T08:00:00Z'),repliedAt:common.serverTime,
   'unusual.key':{createdAt:common.serverTime}},updatedAt:common.serverTime,
 },{merge:true}));
 const write=committed.writes[0];
 assert.deepEqual(write.updateTransforms,[
  {fieldPath:'response.repliedAt',setToServerValue:'REQUEST_TIME'},
  {fieldPath:'response.`unusual.key`.createdAt',setToServerValue:'REQUEST_TIME'},
  {fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'},
 ]);
 assert.deepEqual(write.updateMask.fieldPaths,['answered','response']);
 assert.deepEqual(firebase.decodeValue(write.update.fields.response),{
  message:'The original crossing.',photoObservedAt:new Date('2026-10-30T08:00:00Z'),'unusual.key':{},
 });
 await assert.rejects(()=>db.transaction(async tx=>tx.set('reports/fixture',{items:[common.serverTime]})),/Unsupported Firestore proof value/);
});
