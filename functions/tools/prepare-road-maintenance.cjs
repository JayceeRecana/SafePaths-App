// Isolated test control/bootstrap only. Never alter road records or schedules.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const serialize=v=>v?.toDate?{$timestamp:v.toDate().toISOString()}:Array.isArray(v)?v.map(serialize):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).map(([k,x])=>[k,serialize(x)])):v;
async function main(args){
 assert.ok(args.every(x=>x==='--apply'||x==='--activate'||x.startsWith('--credentials=')));const file=args.find(x=>x.startsWith('--credentials='))?.slice(14);assert.ok(file);const apply=args.includes('--apply'),activate=args.includes('--activate');assert.ok(!activate||apply);assert.ok(!process.env.FIRESTORE_EMULATOR_HOST);
 const key=JSON.parse(fs.readFileSync(file,'utf8'));assert.equal(key.project_id,'safepaths-test');assert.ok(key.client_email.endsWith('@safepaths-test.iam.gserviceaccount.com'));
 const app=initializeApp({projectId:key.project_id,credential:cert(key)},'roads-preparation');
 try{
  const db=getFirestore(app),paths=['system/road_maintenance','system/road_inputs','system/core_cache','system/core_setup','system/risk_job',...['admin','resident','other'].map(x=>`users/spark-proof-${x}`)],docs=await Promise.all(paths.map(p=>db.doc(p).get()));
  assert.equal(docs[3].data()?.version,1);assert.equal(docs[3].data()?.studyArea,'nearby_test');assert.ok(docs.slice(5).every(d=>d.data()?.proofFixtureVersion===1));
  const result={project:key.project_id,apply,activate,checkedAt:new Date().toISOString(),enabledBefore:docs[0].data()?.enabled===true,roadsModified:false,schedulesModified:false,mainProjectModified:false};
  if(apply&&!activate){
   assert.notEqual(docs[0].data()?.enabled,true,'Never replace an active control.');const dir=path.resolve('.usability-work-baseline/roads-private');fs.mkdirSync(dir,{recursive:true});const target=path.join(dir,`bootstrap-before-${Date.now()}.json`);
   const roads=await db.collection('roads').limit(1001).get();assert.ok(roads.size<=1000);fs.writeFileSync(target,JSON.stringify({project:key.project_id,documents:[...docs,...roads.docs].filter(d=>d.exists).map(d=>({path:d.ref.path,data:serialize(d.data())}))},null,2));
   await db.doc('system/road_maintenance').set({enabled:false,version:1,preparedAt:FieldValue.serverTimestamp()});result.backup=path.relative(process.cwd(),target);
  }
  if(activate){
   const preparation=JSON.parse(fs.readFileSync('.usability-work-baseline/roads-preparation.json','utf8'));assert.equal(preparation.project,key.project_id);assert.equal(preparation.apply,true);assert.ok(fs.existsSync(preparation.backup));
   await db.runTransaction(async tx=>{const control=await tx.get(db.doc('system/road_maintenance')),marker=await tx.get(db.doc('system/road_inputs'));assert.equal(control.data()?.version,1);if(control.data()?.enabled===true)return;tx.set(control.ref,{enabled:true,activatedAt:FieldValue.serverTimestamp()},{merge:true});tx.set(marker.ref,{topologyRevision:(marker.data()?.topologyRevision??0)+1,updatedAt:FieldValue.serverTimestamp()},{merge:true});});result.enabled=true;
  }
  fs.writeFileSync(`.usability-work-baseline/roads-${activate?'activation':'preparation'}.json`,JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await deleteApp(app);}
}
main(process.argv.slice(2)).catch(()=>{console.error('Road maintenance test preparation failed; no private details logged.');process.exitCode=1;});
