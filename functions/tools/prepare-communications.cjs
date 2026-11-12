const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const project='safepaths-test';
function options(args){
 const credentials=args.find(x=>x.startsWith('--credentials='))?.slice(14);
 if(!credentials || !args.every(x=>x==='--apply'||x.startsWith('--credentials=')))throw new Error('Local test credential path required; dry-run by default.');
 return {credentials,apply:args.includes('--apply')};
}
function backup(value){if(value?.toDate)return {$timestamp:value.toDate().toISOString()};if(Array.isArray(value))return value.map(backup);if(value && typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,backup(v)]));return value;}
async function main(args){
 const opt=options(args),key=JSON.parse(fs.readFileSync(opt.credentials,'utf8'));assert.equal(key.project_id,project);assert.ok(key.client_email.endsWith(`@${project}.iam.gserviceaccount.com`));
 const app=initializeApp({projectId:project,credential:cert(key)},'communication-prepare');
 try{
  const db=getFirestore(app),names=['alerts','feedbacks','feedback_messages','notification_outbox','communication_requests','communication_audits'];
  const pages=await Promise.all(names.map(name=>db.collection(name).limit(501).get()));assert.ok(pages.every(p=>p.size<=500));
  const control=await db.doc('system/communications').get(),setup=await db.doc('system/core_setup').get();assert.equal(setup.data()?.studyArea,'nearby_test');
  const result={project,apply:opt.apply,counts:Object.fromEntries(pages.map((p,i)=>[names[i],p.size])),alreadyEnabled:control.data()?.enabled===true};
  if(opt.apply){
   assert.notEqual(control.data()?.enabled,true,'Do not overwrite an active rollout control.');
   const profiles=await Promise.all(['spark-proof-resident','spark-proof-admin','spark-proof-other'].map(uid=>db.doc(`users/${uid}`).get()));assert.ok(profiles.every(d=>d.data()?.proofFixtureVersion===1));
   const dir=path.resolve('.usability-work-baseline/communications-cloud-before');fs.mkdirSync(dir,{recursive:true});const target=path.join(dir,`before-${Date.now()}.json`);
   fs.writeFileSync(target,JSON.stringify({project,createdAt:new Date().toISOString(),documents:[...pages.flatMap(p=>p.docs),...profiles,...(control.exists?[control]:[])].map(d=>({path:d.ref.path,data:backup(d.data())}))},null,2));
   let tagged=0;
   for(const row of pages[names.indexOf('notification_outbox')].docs){
    if(row.data().queueClass || !row.data().reportId || row.data().kind && row.data().kind!=='report_update')continue;
    await db.runTransaction(async tx=>{const doc=await tx.get(row.ref);if(doc.exists && !doc.data().queueClass && doc.data().reportId && (!doc.data().kind || doc.data().kind==='report_update')){tx.update(doc.ref,{kind:'report_update',queueClass:'report'});tagged++;}});
   }
   await control.ref.set({enabled:false,version:1,studyArea:'nearby_test',preparedAt:FieldValue.serverTimestamp()});
   result.backup=path.relative(process.cwd(),target);result.legacyReportQueueTagged=tagged;
  }
  fs.writeFileSync('.usability-work-baseline/communications-preparation.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await deleteApp(app);}
}
module.exports={options};
if(require.main===module)main(process.argv.slice(2)).catch(()=>{console.error('Test communication preparation failed; private details were not logged.');process.exitCode=1;});
