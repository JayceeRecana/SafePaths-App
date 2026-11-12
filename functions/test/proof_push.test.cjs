const {test,before}=require('node:test');
const assert=require('node:assert/strict');
let ProofFcm,verifyWorker,verifyWorkerTicket;
before(async()=>({ProofFcm,verifyWorker,verifyWorkerTicket}=await import('../../supabase/functions/_shared/proof_push.mjs')));
const projectId='safepaths-test',now=Date.now();
const message={token:'synthetic_token_abcdefghijklmnop',eventId:'e'.repeat(64),reportId:'synthetic-report',uid:'synthetic-resident',expiresAt:now+3600000};
function sender(fetcher){return new ProofFcm({projectId,credential:{token:async()=>'fixture-oauth'},fetcher,clock:()=>now});}
test('push transport rejects the main project',()=>{assert.throws(()=>new ProofFcm({projectId:'safepaths-92c3d'}));});

test('each explicit backend targets its own Android package',async()=>{
 const {TEST_BACKEND,MARULAS_BACKEND}=await import('../../supabase/functions/_shared/backend_profile.mjs');
 for(const [profile,id,packageName] of [[TEST_BACKEND,'safepaths-test','com.safepaths.safepaths_app.test'],[MARULAS_BACKEND,'safepaths-92c3d','com.safepaths.safepaths_app']]) {
  let calls=0;
  const client=new ProofFcm({projectId:id,profile,credential:{token:async()=>'fixture-oauth'},clock:()=>now,fetcher:async(url,options)=>{
   calls++; assert.equal(url,`https://fcm.googleapis.com/v1/projects/${id}/messages:send`);
   const body=JSON.parse(options.body);
   assert.equal(body.message.android.restricted_package_name,packageName);
   assert.equal(body.message.data.recipientUid,message.uid);
   return new Response(JSON.stringify({name:`projects/${id}/messages/fixture`}));
  }});
  assert.equal((await client.send(message)).status,'accepted'); assert.equal(calls,1);
 }
});
test('preflight uses validate-only with a fixed synthetic topic and sends to no device',async()=>{
 const client=sender(async(url,options)=>{const body=JSON.parse(options.body);assert.equal(body.validate_only,true);assert.equal(body.message.topic,'safepaths_proof_validation_only');assert.equal(body.message.token,undefined);return new Response(JSON.stringify({name:`projects/${projectId}/messages/validation`}));});
 assert.equal((await client.send(message,{validateOnly:true})).status,'accepted');
});
test('FCM payload contains generic copy and stable identifiers, never the private reply',async()=>{
 let calls=0;
 const client=sender(async(url,options)=>{calls++;assert.equal(url,`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`);assert.equal(options.redirect,'error');assert.equal(options.headers.authorization,'Bearer fixture-oauth');
  const body=JSON.parse(options.body);assert.equal(body.validate_only,false);assert.deepEqual(Object.keys(body.message.data).sort(),['eventId','recipientUid','reportId','type']);assert.equal(body.message.data.type,'report_update');
  assert.equal(body.message.android.notification.tag,message.eventId);assert.equal(body.message.android.restricted_package_name,'com.safepaths.safepaths_app.test');assert.equal(body.message.android.ttl,'3600s');
  assert.ok(!JSON.stringify(body).includes('Private resident details'));return new Response(JSON.stringify({name:`projects/${projectId}/messages/fixture`}));
 });
 assert.deepEqual(await client.send({...message,body:'Private resident details'}),{status:'accepted'});assert.equal(calls,1);
});
test('only explicit UNREGISTERED deletes a device; payload and authorization errors do not',async()=>{
 for(const [http,code,expected]of [[404,'UNREGISTERED','invalid_token'],[400,'INVALID_ARGUMENT','failed'],[403,'SENDER_ID_MISMATCH','failed'],[401,null,'failed']]){
  const client=sender(async()=>new Response(JSON.stringify({error:{details:[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:code}]}}),{status:http}));
  assert.equal((await client.send(message)).status,expected);
 }
});
test('provider throttling and unavailability retain Retry-After without leaking responses',async()=>{
 for(const [status,header,delay] of [[429,'120',120000],[503,new Date(now+180000).toUTCString(),180000-(now%1000)],[500,'bad',0]]){
  const result=await sender(async()=>new Response(JSON.stringify({error:{message:'PRIVATE PROVIDER BODY'}}),{status,headers:{'retry-after':header}})).send(message);
  assert.equal(result.status,'retry');assert.equal(result.retryAfterMs,delay);assert.ok(!JSON.stringify(result).includes('PRIVATE'));
 }
});
test('current account lookup enforces enabled verified account and revocation boundary',async()=>{
 for(const [user,enabled]of [[{localId:message.uid,emailVerified:true,validSince:'100'},true],[{localId:message.uid,emailVerified:false},false],[{localId:message.uid,emailVerified:true,disabled:true},false]]){
  const result=await sender(async()=>new Response(JSON.stringify({users:[user]}))).account(message.uid);assert.equal(result.enabled,enabled);
  if(enabled)assert.equal(result.validSince,100000);
 }
});
test('worker endpoint requires a separate strong secret, never a resident token',async()=>{
 const secret='W'.repeat(43);assert.equal(await verifyWorker(`Bearer ${secret}`,secret),true);
 for(const value of [null,'Bearer resident-jwt','Bearer wrong',secret])assert.equal(await verifyWorker(value,secret),false);
 assert.equal(await verifyWorker('Bearer weak','weak'),false);
});
test('scheduled worker tickets require a correct signature, nonce and bounded time',async()=>{
 const secret='W'.repeat(43),time=String(Math.floor(now/1000)),nonce='a'.repeat(32);
 const signature=require('node:crypto').createHmac('sha256',secret).update(`${time}.${nonce}`).digest('hex');
 const headers=new Headers({'x-proof-worker-time':time,'x-proof-worker-nonce':nonce,'x-proof-worker-signature':signature});
 assert.equal(await verifyWorkerTicket(headers,secret,()=>now),nonce);
 assert.equal(await verifyWorkerTicket(headers,secret,()=>now+121000),null);
 assert.equal(await verifyWorkerTicket(headers,secret,()=>now-121000),null);
 headers.set('x-proof-worker-nonce','b'.repeat(32));assert.equal(await verifyWorkerTicket(headers,secret,()=>now),null);
 headers.set('x-proof-worker-signature','malformed');assert.equal(await verifyWorkerTicket(headers,secret,()=>now),null);
});
