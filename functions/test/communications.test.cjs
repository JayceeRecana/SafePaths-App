const {test,before}=require('node:test'),assert=require('node:assert/strict');
let ProofFcm,createCommunications;
before(async()=>{({ProofFcm}=await import('../../supabase/functions/_shared/proof_push.mjs'));({createCommunications}=await import('../../supabase/functions/_shared/proof_communications.mjs'));});
test('typed feedback and broadcast payloads contain no private reply, alert body or media URL',async()=>{
 const now=Date.now();
 for(const kind of ['feedback_update','broadcast_update']){
  let body;const sender=new ProofFcm({projectId:'safepaths-test',credential:{token:async()=>'fixture'},clock:()=>now,fetcher:async(url,options)=>{body=JSON.parse(options.body);return new Response(JSON.stringify({name:'projects/safepaths-test/messages/accepted'}));}});
  await sender.send({kind,token:'fixture_token_abcdefghijklmnop',uid:'resident',eventId:'e'.repeat(64),feedbackId:'feedback',alertId:'alert',studyArea:'nearby_test',expiresAt:now+3600000,body:'PRIVATE REPLY',imageUrl:'PRIVATE MEDIA'});
  assert.equal(body.message.data.type,kind);assert.equal(body.message.data.recipientUid,'resident');assert.ok(!JSON.stringify(body).includes('PRIVATE REPLY'));assert.ok(!JSON.stringify(body).includes('PRIVATE MEDIA'));
  assert.equal(body.message.android.notification.channel_id,kind==='feedback_update'?'safepaths_reports':'safepaths_alerts');assert.equal(body.message.android.notification.tag,'e'.repeat(64));assert.equal(body.message.android.collapse_key,kind==='feedback_update'?'safepaths_feedback_updates':'safepaths_area_alerts');
  assert.equal(body.message.data.reportId,undefined);
 }
});
test('transport refuses unsupported types and a broadcast outside the isolated test area',async()=>{
 const sender=new ProofFcm({projectId:'safepaths-test',credential:{token:async()=>'fixture'},fetcher:async()=>{throw new Error('must not send');}});
 await assert.rejects(()=>sender.send({kind:'arbitrary-user-message'}));await assert.rejects(()=>sender.send({kind:'broadcast_update',alertId:'a',studyArea:'marulas'}));
});
test('communication validation rejects forged identity, invalid consent and unbounded message input before database access',async()=>{
 const api=createCommunications({db:{get:()=>{throw new Error('must not read');}},allowedUids:new Set(['resident'])});
 const valid={requestId:'f'.repeat(24),category:'Map Accuracy',rating:4,comments:'test',allowFollowUp:false};
 for(const extra of [{userId:'other'},{allowFollowUp:'true'},{comments:'x'.repeat(2001)},{rating:0},{adminReply:'forged'}])await assert.rejects(()=>api.submit('resident',{...valid,...extra}),{code:'invalid-argument'});
});
