// Real hosted smoke test, restricted to the synthetic Spark proof environment.
// Tokens/passwords/signed photo URLs remain in memory and are never logged.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const project='safepaths-test', ref='bbteuzgfgnrjjrqewidc';
const origin=`https://${ref}.supabase.co`, endpoint=`${origin}/functions/v1/safepaths-report-proof`;
let stage='preflight';
async function main(args){
  if(!args.includes('--apply'))throw new Error('An explicit --apply is required for synthetic test writes.');
  const file=args.find(value=>value.startsWith('--credentials='))?.slice('--credentials='.length);
  if(!file||args.some(value=>value!=='--apply'&&!value.startsWith('--credentials=')))throw new Error('Invalid proof arguments.');
  const root=path.resolve(__dirname,'../..'), dir=path.join(root,'.usability-work-baseline/spark-proof-setup');
  const account=JSON.parse(fs.readFileSync(file,'utf8'));
  assert.equal(account.project_id,project);
  assert.ok(account.client_email.endsWith(`@${project}.iam.gserviceaccount.com`));
  const fixtures=JSON.parse(fs.readFileSync(path.join(dir,'PRIVATE-test-accounts.json'),'utf8'));
  assert.equal(fixtures.project,project);
  assert.deepEqual(fixtures.accounts.map(user=>user.uid).sort(),['spark-proof-admin','spark-proof-other','spark-proof-resident']);
  const native=JSON.parse(fs.readFileSync(path.join(root,'android/app/src/fieldtest/google-services.json'),'utf8'));
  assert.equal(native.project_info.project_id,project);
  const apiKey=native.client[0].api_key[0].current_key;
  const env=Object.fromEntries(fs.readFileSync(path.join(root,'.env'),'utf8').split(/\r?\n/).filter(line=>line&&!line.startsWith('#')&&line.includes('=')).map(line=>{const i=line.indexOf('=');return[line.slice(0,i).trim(),line.slice(i+1).trim().replace(/^(['"])(.*)\1$/,'$2')];}));
  assert.equal(env.SUPABASE_URL.replace(/\/$/,''),origin);
  const bytes=fs.readFileSync(path.join(dir,'synthetic-proof.jpg'));
  assert.ok(bytes.length<2*1024*1024);
  const digest=crypto.createHash('sha256').update(bytes).digest('hex');
  const stateFile=path.join(dir,'hosted-smoke-state.json');
  const state=fs.existsSync(stateFile)?JSON.parse(fs.readFileSync(stateFile,'utf8')):{project,endpoint,digest,requestId:`hosted_smoke_${crypto.randomUUID().replaceAll('-','')}`,observedAt:new Date().toISOString()};
  assert.equal(state.project,project);assert.equal(state.endpoint,endpoint);assert.equal(state.digest,digest);
  const save=()=>fs.writeFileSync(stateFile,JSON.stringify(state,null,2),{mode:0o600});save();
  const evidence={checkedDate:'2026-10-25',project,endpoint,checks:[],physicalPhoneTest:false};
  const record=(name)=>{evidence.checks.push({name,passed:true});fs.writeFileSync(path.join(dir,'hosted-smoke-result.json'),JSON.stringify(evidence,null,2));};
  async function send(operation,token,body,type='application/json'){
    const response=await fetch(`${endpoint}/${operation}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(45000),headers:{...(token?{authorization:`Bearer ${token}`} : {}),'content-type':type},body:type==='application/json'?JSON.stringify(body):body});
    const data=await response.json().catch(()=>({}));
    if(response.status>=400)console.log(JSON.stringify({operation,httpStatus:response.status,errorCode:typeof data.error?.code==='string'&&/^[a-z-]{1,40}$/.test(data.error.code)?data.error.code:'provider-or-gateway'}));
    return {status:response.status,data};
  }
  const app=initializeApp({projectId:project,credential:cert(account)},'hosted-proof-smoke');
  try{
    const db=getFirestore(app);
    for(const user of fixtures.accounts){
      const profile=await db.doc(`users/${user.uid}`).get();assert.equal(profile.data()?.proofFixtureVersion,1);
    }
    stage='anonymous-endpoint';
    assert.equal((await send('photo-upload',null,bytes,'image/jpeg')).status,401);record(stage);
    const tokens={};
    stage='synthetic-login';
    for(const user of fixtures.accounts){
      const response=await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{'content-type':'application/json'},body:JSON.stringify({email:user.email,password:user.password,returnSecureToken:true})});
      assert.equal(response.status,200);const data=await response.json();assert.equal(data.localId,user.uid);tokens[user.uid]=data.idToken;
    }
    record(stage);
    const resident=tokens['spark-proof-resident'],admin=tokens['spark-proof-admin'],other=tokens['spark-proof-other'];
    stage='real-private-photo-upload';
    const uploaded=await send('photo-upload',resident,bytes,'image/jpeg');
    assert.equal(uploaded.status,200);
    const reference=`${endpoint}/photo/spark-proof-resident/${digest}`;
    assert.equal(uploaded.data.imageUrl,reference);state.reference=reference;save();record(stage);
    stage='immutable-photo-retry';
    const duplicate=await send('photo-upload',resident,bytes,'image/jpeg');assert.equal(duplicate.status,200);assert.equal(duplicate.data.imageUrl,reference);record(stage);
    stage='owner-admin-photo-peer-denial';
    assert.equal((await send('photo-url',other,{imageUrl:reference,role:'admin'})).status,403);
    for(const token of [resident,admin]){
      const signed=await send('photo-url',token,{imageUrl:reference});assert.equal(signed.status,200);assert.equal(signed.data.expiresIn,120);
      const url=new URL(signed.data.url);assert.equal(url.origin,origin);assert.ok(url.pathname.startsWith('/storage/v1/object/sign/report-photos-proof/'));
      const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(20000)});assert.equal(response.status,200);
      assert.equal(crypto.createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex'),digest);
    }
    record(stage);
    stage='report-save';
    const payload={requestId:state.requestId,roadId:'spark-proof-road',title:'Synthetic hosted Spark proof',description:'Automated test record. No real flood or emergency.',severity:'High',isEmergency:false,observedAt:state.observedAt,location:{lat:14.676,lng:120.984,source:'manual',imageUrl:reference}};
    const saved=await send('submit-report',resident,{data:payload});assert.equal(saved.status,200);assert.ok(saved.data.result.reportId);
    state.reportId=saved.data.result.reportId;save();record(stage);
    stage='durable-replay-and-content-guard';
    const replay=await send('submit-report',resident,{data:payload});assert.equal(replay.status,200);assert.equal(replay.data.result.reportId,state.reportId);assert.equal(replay.data.result.replay,true);
    const changed=await send('submit-report',resident,{data:{...payload,description:'Different content'}});assert.equal(changed.status,409);assert.equal(changed.data.error.code,'already-exists');record(stage);
    stage='concurrent-cooldown';
    const cooldownProfile=await db.doc('users/spark-proof-resident').get();
    if(Date.now()-cooldownProfile.data().lastReportAt.toMillis()>=300000){
      state.cooldownRequestId=`hosted_cooldown_${crypto.randomUUID().replaceAll('-','')}`;save();
      const primed=await send('submit-report',resident,{data:{...payload,requestId:state.cooldownRequestId,observedAt:new Date().toISOString()}});
      assert.equal(primed.status,200);assert.equal(primed.data.result.reportId,state.reportId);
    }
    const collisions=await Promise.all([1,2].map(value=>send('submit-report',resident,{data:{...payload,requestId:`${state.requestId}_${value}`}})));
    for(const result of collisions){assert.equal(result.status,429);assert.equal(result.data.error.code,'resource-exhausted');}record(stage);
    stage='saved-identity-photo-and-closure';
    const doc=await db.doc(`reports/${state.reportId}`).get(),road=await db.doc('roads/spark-proof-road').get();
    assert.equal(doc.data().userId,'spark-proof-resident');assert.equal(doc.data().authorityScore,80);assert.equal(doc.data().imageUrl,reference);assert.equal(road.data().status,'not_passable');
    assert.equal(new URL(doc.data().imageUrl).search,'');record(stage);
    stage='resident-history-and-admin-feed';
    const firestore=`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents:runQuery`;
    for(const [token,field,value] of [[resident,'userId','spark-proof-resident'],[admin,'roadId','spark-proof-road']]){
      const response=await fetch(firestore,{method:'POST',redirect:'error',signal:AbortSignal.timeout(20000),headers:{authorization:`Bearer ${token}`,'content-type':'application/json'},body:JSON.stringify({structuredQuery:{from:[{collectionId:'reports'}],where:{fieldFilter:{field:{fieldPath:field},op:'EQUAL',value:{stringValue:value}}},orderBy:[{field:{fieldPath:'createdAt'},direction:'DESCENDING'}],limit:20}})});
      assert.equal(response.status,200);const rows=await response.json();assert.ok(rows.some(row=>row.document?.name.endsWith(`/reports/${state.reportId}`)));
    }record(stage);
    stage='direct-resident-write-denied';
    const denied=await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/reports/${state.reportId}?updateMask.fieldPaths=description`,{method:'PATCH',redirect:'error',signal:AbortSignal.timeout(20000),headers:{authorization:`Bearer ${resident}`,'content-type':'application/json'},body:JSON.stringify({fields:{description:{stringValue:'Unauthorized direct write attempt'}}})});
    assert.equal(denied.status,403);record(stage);
    stage='anonymous-storage-read-list-write-denied';
    const storage=`${origin}/storage/v1`, object=`reports/spark-proof-resident/${digest}.jpg`;
    const headers={apikey:env.SUPABASE_ANON_KEY,authorization:`Bearer ${env.SUPABASE_ANON_KEY}`};
    const keyCheck=await fetch(`${origin}/auth/v1/settings`,{headers,redirect:'error',signal:AbortSignal.timeout(20000)});assert.equal(keyCheck.status,200);
    const read=await fetch(`${storage}/object/authenticated/report-photos-proof/${object}`,{headers,redirect:'error',signal:AbortSignal.timeout(20000)});assert.ok(!read.ok);
    const publicRead=await fetch(`${storage}/object/public/report-photos-proof/${object}`,{headers,redirect:'error',signal:AbortSignal.timeout(20000)});assert.ok(!publicRead.ok);
    const list=await fetch(`${storage}/object/list/report-photos-proof`,{method:'POST',headers:{...headers,'content-type':'application/json'},body:JSON.stringify({prefix:'reports/spark-proof-resident',limit:100}),redirect:'error',signal:AbortSignal.timeout(20000)});assert.ok(!list.ok||(await list.json()).length===0);
    const write=await fetch(`${storage}/object/report-photos-proof/reports/spark-proof-other/${digest}.jpg`,{method:'POST',headers:{...headers,'content-type':'image/jpeg','x-upsert':'false'},body:bytes,redirect:'error',signal:AbortSignal.timeout(20000)});assert.ok(!write.ok);
    const deletion=await fetch(`${storage}/object/report-photos-proof`,{method:'DELETE',headers:{...headers,'content-type':'application/json'},body:JSON.stringify({prefixes:[object]}),redirect:'error',signal:AbortSignal.timeout(20000)});assert.ok(!deletion.ok||(await deletion.json()).length===0);
    const stillOwned=await send('photo-url',resident,{imageUrl:reference});assert.equal(stillOwned.status,200);record(stage);
    evidence.passed=true;fs.writeFileSync(path.join(dir,'hosted-smoke-result.json'),JSON.stringify(evidence,null,2));console.log(JSON.stringify(evidence,null,2));
  }finally{await deleteApp(app);}
}
main(process.argv.slice(2)).catch(error=>{console.error(JSON.stringify({check:'hosted-spark-proof',stage,passed:false,category:typeof error.code==='string'&&/^[a-zA-Z_-]{1,40}$/.test(error.code)?error.code:'http-or-assertion'}));process.exitCode=1;});
