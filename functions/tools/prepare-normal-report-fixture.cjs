// Adds exactly one labelled synthetic road in the existing Test app study area.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
async function main(args){
 const apply=args.includes('--apply'),file=args.find(value=>value.startsWith('--credentials='))?.slice(14);assert.ok(file);assert.ok(args.every(v=>v==='--apply'||v.startsWith('--credentials=')));
 const root=path.resolve(__dirname,'../..'),project='safepaths-test';
 const fixture=JSON.parse(fs.readFileSync(path.join(root,'test/normal-report-fixture.json'),'utf8'));assert.equal(fixture.id,'spark-normal-form-road');assert.equal(fixture.proofScope,'normal_report_form');assert.equal(fixture.studyArea,'nearby_test');assert.equal(fixture.status,'not_passable');
 // Retired fixtures must fail before credentials, authentication or cloud access.
 if(apply&&fixture.retired===true){console.error('This reporting fixture is retired and cannot be recreated. Agree on a public test segment before a new drill.');process.exitCode=1;return;}
 const credential=JSON.parse(fs.readFileSync(file,'utf8'));assert.equal(credential.project_id,project);
 assert.ok(credential.client_email?.endsWith(`@${project}.iam.gserviceaccount.com`));
 const native=JSON.parse(fs.readFileSync(path.join(root,'android/app/src/fieldtest/google-services.json'),'utf8'));assert.equal(native.project_info.project_id,project);
 const app=initializeApp({projectId:project,credential:cert(credential)},'normal-report-fixture');
 try{
  const db=getFirestore(app),auth=getAuth(app);
  for(const uid of ['spark-proof-resident','spark-proof-admin','spark-proof-other']){const profile=await db.doc(`users/${uid}`).get(),user=await auth.getUser(uid);assert.equal(profile.data()?.proofFixtureVersion,1);assert.equal(profile.data().role,uid==='spark-proof-admin'?'admin':'user');assert.equal(user.disabled,false);assert.equal(user.emailVerified,true);}
  const road=db.doc(`roads/${fixture.id}`),before=await road.get();
  if(before.exists){assert.equal(before.data().proofScope,fixture.proofScope);assert.equal(before.data().proofFixtureVersion,1);assert.deepEqual(before.data().geometry,fixture.geometry);}
  if(apply&&!before.exists){const {id,studyArea,latitude,longitude,...data}=fixture;await road.create({...data,studyArea,updatedAt:FieldValue.serverTimestamp()});}
  const result={checkedDate:'2026-10-25',project,apply,roadId:fixture.id,created:apply&&!before.exists,existingBefore:before.exists,studyArea:fixture.studyArea,status:before.exists?before.data().status:fixture.status,mainProjectModified:false};
  fs.writeFileSync(path.join(root,'.usability-work-baseline/spark-proof-setup/normal-form-fixture-result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
 }finally{await deleteApp(app);}
}
main(process.argv.slice(2)).catch(()=>{console.error('Normal-form fixture setup failed; private details were not logged.');process.exitCode=1;});
