const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const project='safepaths-test';
function backup(v){if(v?.toDate)return {$timestamp:v.toDate().toISOString()};if(Array.isArray(v))return v.map(backup);if(v && typeof v==='object')return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,backup(x)]));return v;}
async function main(args){
 const file=args.find(x=>x.startsWith('--credentials='))?.slice(14),apply=args.includes('--apply');assert.ok(file);assert.ok(args.every(x=>x==='--apply'||x.startsWith('--credentials=')));
 const key=JSON.parse(fs.readFileSync(file,'utf8'));assert.equal(key.project_id,project);assert.ok(key.client_email.endsWith(`@${project}.iam.gserviceaccount.com`));
 const app=initializeApp({projectId:project,credential:cert(key)},'media-preparation');
 try{
  const db=getFirestore(app),control=await db.doc('system/media').get(),communication=await db.doc('system/communications').get();assert.equal(communication.data()?.enabled,true);
  const profiles=await Promise.all(['spark-proof-resident','spark-proof-admin','spark-proof-other'].map(uid=>db.doc(`users/${uid}`).get()));assert.ok(profiles.every(d=>d.data()?.proofFixtureVersion===1));
  const names=['media_uploads','media_limits','profile_requests','feedbacks'];const pages=await Promise.all(names.map(name=>db.collection(name).limit(501).get()));assert.ok(pages.every(p=>p.size<=500));
  const result={project,apply,enabledBefore:control.data()?.enabled===true,counts:Object.fromEntries(pages.map((p,i)=>[names[i],p.size]))};
  if(apply){
   assert.notEqual(control.data()?.enabled,true,'Never overwrite an active rollout.');
   const dir=path.resolve('.usability-work-baseline/media-cloud-before');fs.mkdirSync(dir,{recursive:true});const target=path.join(dir,`before-${Date.now()}.json`);
   fs.writeFileSync(target,JSON.stringify({project,createdAt:new Date().toISOString(),documents:[...profiles,...pages.flatMap(p=>p.docs),...(control.exists?[control]:[])].map(d=>({path:d.ref.path,data:backup(d.data())}))},null,2));
   await control.ref.set({enabled:false,version:1,preparedAt:FieldValue.serverTimestamp()});result.backup=path.relative(process.cwd(),target);
  }
  fs.writeFileSync('.usability-work-baseline/media-preparation.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await deleteApp(app);}
}
if(require.main===module)main(process.argv.slice(2)).catch(()=>{console.error('Test media preparation failed; private details were not logged.');process.exitCode=1;});
