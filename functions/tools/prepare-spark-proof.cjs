// No cloud write unless --apply is explicit. Never targets the main Firebase project.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {initializeApp,cert,deleteApp}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
const {getFirestore}=require('firebase-admin/firestore');

function options(args) {
  const result={apply:false};
  for(const value of args) {
    if(value==='--apply') result.apply=true;
    else {
      const match=/^--(project|credentials|supabase-ref)=(.+)$/.exec(value);
      if(!match) throw new Error('Use --project=TEST_ID --credentials=PRIVATE_LOCAL_FILE --supabase-ref=PROJECT_REF [--apply].');
      if(result[match[1]]) throw new Error('Duplicate proof option.');
      result[match[1]]=match[2];
    }
  }
  const project=result.project;
  if(!/^[a-z][a-z0-9-]{5,62}$/.test(project??'')||project==='safepaths-92c3d'||!/(?:^demo-|[-](?:test|staging)(?:-|$))/.test(project)) throw new Error('An explicitly named test/staging Firebase project is required; the main project is forbidden.');
  if(!/^[a-z0-9]{20}$/.test(result['supabase-ref']??'')) throw new Error('An exact Supabase project reference is required.');
  if(!result.credentials) throw new Error('A private local credential file for the test Firebase project is required.');
  return result;
}
const identities=[['spark-proof-resident','resident','user'],['spark-proof-admin','admin','admin'],['spark-proof-other','other','user']];

async function main(args) {
  const config=options(args);
  const account=JSON.parse(fs.readFileSync(path.resolve(config.credentials),'utf8'));
  if(account.project_id!==config.project||!account.client_email?.endsWith(`@${config.project}.iam.gserviceaccount.com`)||!account.private_key) throw new Error('The credential must belong only to the selected test project.');
  const json=JSON.stringify(account);
  if(json.includes("'")) throw new Error('Credential cannot be encoded in the local secret file. Use the private dashboard input instead.');
  const output=path.resolve(__dirname,'../../.usability-work-baseline/spark-proof-setup');
  if(!config.apply) {
    console.log(JSON.stringify({mode:'dry-run',firebaseProject:config.project,supabaseProject:config['supabase-ref'],
      intendedWrites:['three synthetic test accounts/profiles','one synthetic road','private local setup files'],
      note:'No cloud writes, deploy, bucket changes or billing changes. Add --apply only for the agreed test environment.'},null,2));
    return;
  }
  fs.mkdirSync(output,{recursive:true});
  const accountsFile=path.join(output,'PRIVATE-test-accounts.json');
  let saved=[];
  if(fs.existsSync(accountsFile)) {
    const existing=JSON.parse(fs.readFileSync(accountsFile,'utf8'));
    if(existing.project!==config.project) throw new Error('The existing private setup belongs to a different test project. Preserve it before choosing another project.');
    saved=existing.accounts;
  }
  const app=initializeApp({projectId:config.project,credential:cert(account)},'spark-proof-setup');
  const auth=getAuth(app), db=getFirestore(app);
  try {
    // Refuse to overwrite an unrelated account/profile/road. Check every identity
    // first, before creating anything. Generated passwords are retained locally.
    const planned=[];
    for(const [uid,label,role] of identities) {
      const email=`${label}.spark-proof@example.invalid`;
      let user=null;
      try {user=await auth.getUser(uid);} catch(error) {if(error.code!=='auth/user-not-found') throw error;}
      const profile=await db.doc(`users/${uid}`).get();
      const credential=saved.find(value=>value.uid===uid);
      if(user&&(!credential||user.email!==email||user.disabled||!user.emailVerified)) throw new Error('A proof UID already exists without matching active/verified local test credentials. Nothing will be overwritten.');
      if(profile.exists&&(profile.data().proofFixtureVersion!==1||profile.data().role!==role)) throw new Error('A proof profile already exists with unexpected fields. Nothing will be overwritten.');
      planned.push({uid,email,role,label,profileExists:profile.exists,userExists:!!user,
        password:credential?.password??`Proof9!${crypto.randomBytes(18).toString('base64url')}`});
    }
    const roadRef=db.doc('roads/spark-proof-road'), road=await roadRef.get();
    if(road.exists&&road.data().proofFixtureVersion!==1) throw new Error('The synthetic proof road ID is already in use. Nothing will be overwritten.');
    fs.writeFileSync(accountsFile,JSON.stringify({project:config.project,notice:'PRIVATE. Synthetic test passwords. Do not share in chat or commit.',accounts:planned.map(({uid,email,password,role})=>({uid,email,password,role}))},null,2),{mode:0o600});
    for(const value of planned) if(!value.userExists) await auth.createUser({uid:value.uid,email:value.email,password:value.password,emailVerified:true,displayName:`Spark proof ${value.label}`});
    const batch=db.batch();
    for(const value of planned) if(!value.profileExists) batch.create(db.doc(`users/${value.uid}`),{name:`Spark proof ${value.label}`,email:value.email,role:value.role,trustScore:50,verifiedReports:0,dismissedReports:0,proofFixtureVersion:1});
    if(!road.exists) batch.create(roadRef,{name:'Synthetic Spark proof road',status:'not_passable',proofFixtureVersion:1,
      geometry:{segments:[{points:[{lon:120.984,lat:14.675},{lon:120.984,lat:14.677}]}]},updatedAt:new Date()});
    await batch.commit();
    fs.writeFileSync(path.join(output,'PRIVATE-secrets.env'),`PROOF_FIREBASE_PROJECT_ID=${config.project}\nPROOF_ALLOWED_UIDS=${identities.map(value=>value[0]).join(',')}\nPROOF_GOOGLE_SERVICE_ACCOUNT_JSON='${json}'\n`,{mode:0o600});
    fs.writeFileSync(path.join(output,'public-build-defines.json'),JSON.stringify({SPARK_PROOF_FIREBASE_PROJECT_ID:config.project,
      SPARK_PROOF_BACKEND_URL:`https://${config['supabase-ref']}.supabase.co/functions/v1/safepaths-report-proof`},null,2));
    console.log(JSON.stringify({mode:'applied-to-test-project',firebaseProject:config.project,localOutput:output,
      note:'Passwords and keys were written only to ignored local files. No Supabase deployment, rules, APK or billing change was performed.'},null,2));
  } finally {await deleteApp(app);}
}
module.exports={options};
if(require.main===module) main(process.argv.slice(2)).catch(()=>{console.error('Proof setup did not complete. Check test-project access, credential ownership and existing synthetic fixture conflicts. Private details were not logged.');process.exitCode=1;});
