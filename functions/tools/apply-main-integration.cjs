// Default is a read-only preflight. --apply performs one bounded, atomic main
// metadata/control migration and deliberately leaves the new service inactive.
const fs=require('node:fs'),crypto=require('node:crypto');
const project='safepaths-92c3d';
function options(args) {
 const out={apply:false};
 for(const arg of args) {
  if(arg==='--apply') {out.apply=true;continue;}
  const match=/^--(project|credentials|plan|backup)=(.+)$/.exec(arg);
  if(!match || out[match[1]])throw Error('Invalid or duplicate option');out[match[1]]=match[2];
 }
 if(out.project!==project || !out.credentials || !out.plan || !out.backup)throw Error('Explicit main project, matching credential, plan and backup are required');
 if(process.env.FIRESTORE_EMULATOR_HOST)throw Error('Main CLI cannot use emulators');
 return out;
}
function validatePlan(plan,backupBytes) {
 if(plan.project!==project || plan.area!=='marulas' || plan.blockers?.length!==0 || !Array.isArray(plan.roadMetadata) || plan.roadMetadata.length>380)throw Error('Unreviewed migration plan');
 if(crypto.createHash('sha256').update(backupBytes).digest('hex')!==plan.backupSha256)throw Error('Backup no longer matches the plan');
 if(!Number.isInteger(plan.roadCount) || plan.roadCount<1 || plan.roadCount>1000)throw Error('Invalid road count');
 const expected={'system/core_setup':{version:1,studyArea:'marulas',roadCount:plan.roadCount},
  'system/communications':{enabled:true},'system/media':{enabled:true},'system/road_maintenance':{enabled:true},
  'system/backend_rollout':{enabled:false,version:1,studyArea:'marulas'}};
 require('node:assert/strict').deepEqual(plan.controls,expected);
 for(const r of plan.roadMetadata)if(!/^roads\/[A-Za-z0-9_-]{1,128}$/.test(r.path) || JSON.stringify(r.patch)!==JSON.stringify({studyArea:'marulas'}) || r.expectedUpdateTime?.$type!=='timestamp')throw Error('Only fenced road-area metadata is allowed');
 return plan;
}
async function applyTransaction(db,plan,serverTimestamp,{apply=false}={}) {
 return db.runTransaction(async tx=>{
  const ids=['system/backend_rollout','system/core_setup','system/communications','system/media','system/road_maintenance','system/road_inputs'];
  const controls=await Promise.all(ids.map(p=>tx.get(db.doc(p))));
  if(controls[0].data()?.enabled===true)throw Error('Main is already active; inspect the rollout first');
  if(controls[1].exists && controls[1].data().studyArea!=='marulas')throw Error('Existing core setup has a different area');
  const active=await tx.get(db.collection('reports').where('status','in',['pending','under_review']).limit(201));
  if(active.size>200 || active.docs.some(d=>!d.data().incidentId))throw Error('Active legacy reports need reconciliation');
  const roads=await Promise.all(plan.roadMetadata.map(r=>tx.get(db.doc(r.path))));
  for(let i=0;i<roads.length;i++) {
   const doc=roads[i],expected=plan.roadMetadata[i].expectedUpdateTime;
   if(!doc.exists || doc.updateTime.seconds!==expected.seconds || doc.updateTime.nanoseconds!==expected.nanoseconds)throw Error('A road changed after the backup; take a fresh inventory');
  }
  if(apply) {
   for(const road of roads)tx.update(road.ref,{studyArea:'marulas',riskInputsUpdatedAt:serverTimestamp()});
   for(const [p,value] of Object.entries(plan.controls))tx.set(db.doc(p),{...value,preparedAt:serverTimestamp()},{merge:true});
   tx.set(db.doc('system/road_inputs'),{updatedAt:serverTimestamp()},{merge:true});
  }
  return {project,roadsChecked:roads.length,metadataWrites:apply?roads.length:0,mainActivated:false,readOnly:!apply,conditionsChanged:false};
 });
}
async function main(args) {
 const opt=options(args),plan=validatePlan(JSON.parse(fs.readFileSync(opt.plan,'utf8')),fs.readFileSync(opt.backup));
 const account=JSON.parse(fs.readFileSync(opt.credentials,'utf8'));
 if(account.project_id!==project || !account.client_email?.endsWith(`@${project}.iam.gserviceaccount.com`))throw Error('Main credential mismatch');
 const {initializeApp,cert,deleteApp}=require('firebase-admin/app'),{getFirestore,FieldValue}=require('firebase-admin/firestore');
 const app=initializeApp({projectId:project,credential:cert(account)},'main-metadata-preflight');
 try {console.log(JSON.stringify(await applyTransaction(getFirestore(app),plan,()=>FieldValue.serverTimestamp(),opt)));}
 finally {await deleteApp(app);}
}
module.exports={options,validatePlan,applyTransaction};
if(require.main===module)main(process.argv.slice(2)).catch(()=>{console.error('Main migration stopped. No secrets or record contents were logged. Inspect the backup/preflight before retrying.');process.exitCode=1;});
