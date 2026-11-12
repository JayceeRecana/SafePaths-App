// Test-only bootstrap. Dry-run by default; never changes official road status.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {lines}=require('../domain.cjs');
function options(args){
 const values=Object.fromEntries(args.filter(x=>x.includes('=')).map(x=>x.slice(2).split(/=(.*)/s).slice(0,2)));
 if(values.project!=='safepaths-test' || !values.credentials)throw new Error('Explicit safepaths-test project and local credential path required.');
 return {...values,apply:args.includes('--apply')};
}
function inArea(road){
 if(road.studyArea)return road.studyArea==='nearby_test';
 return lines(road.geometry).some(line=>{
  const xs=line.map(p=>p[0]),ys=line.map(p=>p[1]);
  return Math.max(...xs)>=121.000131 && Math.min(...xs)<=121.018703 && Math.max(...ys)>=14.667156 && Math.min(...ys)<=14.685122;
 });
}
function backup(value){
 if(value?.toDate)return {$timestamp:value.toDate().toISOString()};
 if(Array.isArray(value))return value.map(backup);
 if(value && typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,backup(v)]));
 return value;
}
async function main(args){
 const opt=options(args),key=JSON.parse(fs.readFileSync(opt.credentials,'utf8'));
 assert.equal(key.project_id,opt.project);assert.ok(key.client_email.endsWith(`@${opt.project}.iam.gserviceaccount.com`));
 const app=initializeApp({projectId:opt.project,credential:cert(key)},'core-bootstrap');
 try{
  const db=getFirestore(app),[roads,reports,incidents]=await Promise.all([db.collection('roads').limit(1001).get(),db.collection('reports').limit(201).get(),db.collection('road_incidents').limit(201).get()]);
  if(roads.size>1000 || reports.size>200 || incidents.size>200)throw new Error('Bootstrap page limit reached; review before proceeding.');
  const selected=roads.docs.filter(d=>inArea(d.data())),result={project:opt.project,apply:opt.apply,roads:roads.size,scopedRoads:selected.length,reports:reports.size,incidents:incidents.size};
  if(!selected.length)throw new Error('No nearby test roads found.');
  if(opt.apply){
   const dir=path.resolve('.usability-work-baseline/core-bootstrap');fs.mkdirSync(dir,{recursive:true});
   const saved=path.join(dir,`before-${Date.now()}.json`);
   const system=await db.collection('system').get();
   fs.writeFileSync(saved,JSON.stringify({project:opt.project,createdAt:new Date().toISOString(),documents:[...roads.docs,...reports.docs,...incidents.docs,...system.docs].map(d=>({path:d.ref.path,data:backup(d.data())}))},null,2));
   const {createIncidentApi}=require('../incidents.cjs');
   // Revisit this small, backed-up test dataset once. Normal job runs never scan
   // historical reports repeatedly and retention/deletion remain unchanged.
   await db.doc('system/incident_migration').set({complete:false,cursor:null});
   const api=createIncidentApi({db,authenticated:async()=>{throw new Error('Not a callable bootstrap');},options:{}});
   await api.reconcile();await api.reconcile();await api.reconcile();
   for(const doc of reports.docs){
    const current=await doc.ref.get(),r=current.data();
    if(['pending','under_review'].includes(r.status) && !r.incidentId){
      const road=await db.doc(`roads/${r.roadId}`).get();
      if(road.data()?.isVerified && road.data()?.status==='passable' && road.data().updatedAt?.toMillis()> (r.observedAt??r.lastUpdatedByUser??r.createdAt)?.toMillis())await doc.ref.update({status:'resolved',incidentReviewStatus:'passable'});
      else throw new Error('Unresolved legacy test report requires review.');
    }
   }
   for(let i=0;i<selected.length;i+=150){const batch=db.batch();for(const doc of selected.slice(i,i+150))batch.update(doc.ref,{studyArea:'nearby_test',riskInputsUpdatedAt:FieldValue.serverTimestamp()});batch.set(db.doc('system/road_inputs'),{updatedAt:FieldValue.serverTimestamp()},{merge:true});await batch.commit();}
   await db.doc('system/core_setup').set({version:1,studyArea:'nearby_test',preparedAt:FieldValue.serverTimestamp(),roadCount:selected.length});
   result.backup=path.relative(process.cwd(),saved);
  }
  console.log(JSON.stringify(result));return result;
 }finally{await deleteApp(app);}
}
module.exports={options,inArea};
if(require.main===module)main(process.argv.slice(2)).catch(()=>{console.error('Core test bootstrap failed. Private details were not logged; inspect backed-up test data before retrying.');process.exitCode=1;});
