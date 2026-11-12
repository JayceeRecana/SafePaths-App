const {test,before}=require('node:test'),assert=require('node:assert/strict');
let queueAdminReportNotice,createProofPush,TEST_BACKEND,MARULAS_BACKEND,serverTime,ProofFcm,FirestoreRest;
before(async()=>{
 ({queueAdminReportNotice}=await import('../../supabase/functions/_shared/admin_report_notifications.mjs'));
 ({createProofPush,ProofFcm}=await import('../../supabase/functions/_shared/proof_push.mjs'));
 ({TEST_BACKEND,MARULAS_BACKEND}=await import('../../supabase/functions/_shared/backend_profile.mjs'));
 ({serverTime}=await import('../../supabase/functions/_shared/proof_common.mjs'));
 ({FirestoreRest}=await import('../../supabase/functions/_shared/proof_firebase.mjs'));
});
function fixture(main=false){
 let now=Date.now(), tail=Promise.resolve(),failQuery=false;
 const docs=new Map(),sent=[],profile=main?MARULAS_BACKEND:TEST_BACKEND,allowedUids=new Set(['resident','admin','other']);
 const copy=v=>v===serverTime?new Date(now):v instanceof Date?new Date(v):Array.isArray(v)?v.map(copy):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).map(([k,x])=>[k,copy(x)])):v;
 const get=async(path,state=docs)=>({path,exists:state.has(path),data:copy(state.get(path)??{})});
 const query=async(c,filters,options={},state=docs)=>{
  if(failQuery){failQuery=false;throw Error('Synthetic query outage');}
  return [...state].filter(([p,v])=>p.startsWith(c+'/')&&p.split('/').length===2&&(!options.afterDocument||p>options.afterDocument)&&filters.every(([f,op,t])=>op==='EQUAL'?v[f]===t:op==='LESS_THAN_OR_EQUAL'?v[f]<=t:false))
   .sort(([a],[b])=>a.localeCompare(b)).slice(0,options.limit??100).map(([p])=>({path:p,exists:true,data:copy(state.get(p))}));
 };
 const db={get,query,transaction(work){const task=tail.then(async()=>{
  const state=new Map([...docs].map(([p,v])=>[p,copy(v)]));let writing=false;
  const tx={get:p=>{assert.equal(writing,false);return get(p,state);},query:(c,f,v,limit)=>{assert.equal(writing,false);return query(c,[[f,'EQUAL',v]],{limit},state);},
   set:(p,v,{merge=false,create=false}={})=>{writing=true;if(create)assert.equal(state.has(p),false);state.set(p,{...(merge?state.get(p)??{}:{}),...copy(v)});}};
  const result=await work(tx);docs.clear();for(const [p,v]of state)docs.set(p,v);return result;
 });tail=task.catch(()=>{});return task;}};
 docs.set('users/admin',{role:'admin',studyArea:profile.area});docs.set('users/resident',{role:'user',studyArea:profile.area});
 const push=createProofPush({db,profile,allowedUids,clock:()=>now,fcm:{account:async()=>({enabled:true,validSince:0}),send:async v=>{sent.push(v);return {status:'accepted'};}}});
 async function queue(kind='report_new_admin'){
  return db.transaction(async tx=>{
   const eventId=await queueAdminReportNotice(tx,{reportId:'report',userId:'resident',requestHash:'a'.repeat(64),kind,now});
   tx.set('reports/report',{userId:'resident',status:'pending',adminNoticeEventId:eventId},{merge:true});return 'notification_outbox/'+eventId;
  });
 }
 const register=async(uid='admin',installation='a'.repeat(64),sequence=1)=>push.device(uid,{mode:'register',installation,sequence,token:'synthetic_token_abcdefghijklmnop'});
 return {docs,db,push,sent,queue,register,allowedUids,advance:ms=>now+=ms,failQuery:()=>failQuery=true};
}
test('admin work expands once and sends only an eligible admin a report-scoped notice',async()=>{
 const f=fixture();await f.register();const root=await f.queue();
 await Promise.all([f.push.process(root),f.push.process(root)]);
 const children=[...f.docs].filter(([p,v])=>v.kind==='report_new_admin');assert.equal(children.length,1);
 await f.push.process(children[0][0]);await f.push.process(children[0][0]);
 assert.equal(f.sent.length,1);assert.equal(f.sent[0].uid,'admin');assert.equal(f.sent[0].reportId,'report');
 assert.equal(f.sent[0].kind,'report_new_admin');assert.equal(f.docs.get(root).status,'expanded');
});
test('clarification replies use a separate durable notice and never target resident or foreign admins',async()=>{
 const f=fixture();f.docs.set('users/other',{role:'admin',studyArea:'other-area'});f.docs.set('users/outsider',{role:'admin'});
 const root=await f.queue('report_reply_admin');await f.push.process(root);
 assert.deepEqual([...f.docs.values()].filter(v=>v.kind==='report_reply_admin').map(v=>v.userId),['admin']);
});
test('main audience is paged beyond twenty admins without losing or duplicating recipients',async()=>{
 const f=fixture(true);f.docs.delete('users/admin');
 for(let i=0;i<45;i++)f.docs.set(`users/admin${String(i).padStart(2,'0')}`,{role:'admin',studyArea:'marulas'});
 const root=await f.queue();
 await f.push.process(root);assert.equal([...f.docs.values()].filter(v=>v.kind==='report_new_admin').length,20);
 f.advance(1001);await f.push.process(root);f.advance(1001);await f.push.process(root);
 assert.equal([...f.docs.values()].filter(v=>v.kind==='report_new_admin').length,45);
 assert.equal(f.docs.get(root).dispatchable,false);
});
test('completed report, changed question, revoked role and changed area suppress stale admin delivery',async()=>{
 for(const change of ['status','event','role','area']){
  const f=fixture();await f.register();const root=await f.queue();await f.push.process(root);
  const child=[...f.docs].find(([p,v])=>v.kind==='report_new_admin')[0];
  if(change==='status')f.docs.get('reports/report').status='verified';
  if(change==='event')f.docs.get('reports/report').adminNoticeEventId='b'.repeat(64);
  if(change==='role')f.docs.get('users/admin').role='user';
  if(change==='area')f.docs.get('users/admin').studyArea='elsewhere';
  assert.equal(await f.push.process(child),'suppressed');assert.equal(f.sent.length,0);
 }
});
test('audience query failure retains work and a later retry expands; expiry sends nothing',async()=>{
 const f=fixture();const root=await f.queue();f.failQuery();assert.equal(await f.push.process(root),'retry');
 assert.equal(f.docs.get(root).dispatchable,true);f.advance(60001);await f.push.process(root);assert.equal(f.docs.get(root).status,'expanded');
 const g=fixture();const stale=await g.queue();g.advance(3600001);assert.equal(await g.push.process(stale),'expired');assert.equal(g.sent.length,0);
});
test('admin push payload has no report description, road location, private reply or attachment',async()=>{
 for(const kind of ['report_new_admin','report_reply_admin']){
  let payload;
  const fcm=new ProofFcm({projectId:'safepaths-test',credential:{token:async()=>'fake'},fetcher:async(url,options)=>{payload=JSON.parse(options.body);return new Response(JSON.stringify({name:'projects/safepaths-test/messages/fake'}));}});
  await fcm.send({kind,eventId:'e'.repeat(64),reportId:'report',uid:'admin',token:'synthetic_token_abcdefghijklmnop',expiresAt:Date.now()+3600000,body:'secret_report_marker',imageUrl:'secret_report_marker',roadName:'secret_report_marker'});
  assert.deepEqual(Object.keys(payload.message.data).sort(),['eventId','recipientUid','reportId','type']);
  assert.equal(payload.message.data.type,kind);assert.equal(JSON.stringify(payload).includes('secret_report_marker'),false);
 }
});
test('REST document-name paging encodes a reference cursor and rejects cursor injection',async()=>{
 let payload;
 const db=new FirestoreRest({projectId:'safepaths-test',credential:{token:async()=>'fake'},fetcher:async(url,options)=>{payload=JSON.parse(options.body);return new Response('[]');}});
 const options={limit:20,orderBy:[{field:{fieldPath:'__name__'},direction:'ASCENDING'}],afterDocument:'users/admin20'};
 await db.query('users',[['role','EQUAL','admin']],options);
 assert.deepEqual(payload.structuredQuery.startAt,{values:[{referenceValue:'projects/safepaths-test/databases/(default)/documents/users/admin20'}],before:false});
 await assert.rejects(()=>db.query('users',[],{...options,afterDocument:'users/../reports/report'}));
 await assert.rejects(()=>db.query('users',[],{...options,orderBy:[]}));
});

test('transferred or signed-out installations cannot receive pending admin work',async()=>{
 for(const action of ['transfer','logout']) {
  const f=fixture();await f.register();const root=await f.queue();await f.push.process(root);
  const child=[...f.docs].find(([p,v])=>v.kind==='report_new_admin')[0];
  const device=[...f.docs].find(([p])=>p.startsWith('push_devices/'))[1];
  if(action==='transfer')device.userId='resident';else device.active=false;
  assert.equal(await f.push.process(child),'no_device');assert.equal(f.sent.length,0);
 }
});
