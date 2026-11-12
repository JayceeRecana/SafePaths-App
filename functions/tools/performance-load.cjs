// Local emulator workload only. Never accepts a production project or remote host.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {performance} = require('node:perf_hooks');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {randomBytes} = require('node:crypto');
const projectId = 'demo-safepaths-performance';

function localHost(name) {
  const value = process.env[name];
  if (!value || !/^(127\.0\.0\.1|localhost):\d+$/.test(value)) throw new Error(`Requires loopback ${name}.`);
  return value;
}
function percentile(samples, fraction) {
  if (!samples.length) return null;
  const sorted = [...samples].sort((a,b) => a-b);
  return Math.round(sorted[Math.max(0,Math.ceil(sorted.length*fraction)-1)] * 10) / 10;
}

async function main() {
  if (process.env.GCLOUD_PROJECT !== projectId) throw new Error(`Requires ${projectId}; refusing any other project.`);
  localHost('FIRESTORE_EMULATOR_HOST');
  const authHost = localHost('FIREBASE_AUTH_EMULATOR_HOST');
  localHost('FIREBASE_STORAGE_EMULATOR_HOST');
  const functionsHost = '127.0.0.1:5001';
  const levels = (process.argv.find(arg => arg.startsWith('--users='))?.slice(8) || '5,10,20').split(',').map(Number);
  if (!levels.length || levels.some(value => !Number.isInteger(value) || value < 1 || value > 30)) throw new Error('Choose 1–30 users per local stage.');
  const report = {projectId, emulatorOnly:true, createdAt:new Date().toISOString(),
    limitations:'Local callable HTTP concurrency and invariants, not production capacity, phone FPS, or internet latency.',
    host:{node:process.version,platform:os.platform(),cpus:os.availableParallelism()}, stages:[]};
  const app = initializeApp({projectId}), db = getFirestore(app), auth = getAuth(app);
  const run = Date.now().toString(36);
  const password = randomBytes(24).toString('base64url');
  let healthy = true;

  async function resident(label) {
    const email = `load-${run}-${label}@example.test`;
    const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local-emulator`, {
      method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({email,password,returnSecureToken:true}), signal:AbortSignal.timeout(15000)});
    const created = await response.json();
    if (!response.ok || !created.localId) throw new Error('Local account setup failed.');
    await auth.updateUser(created.localId,{emailVerified:true});
    await db.doc(`users/${created.localId}`).set({role:'user',trustScore:50});
    const signed = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local-emulator`, {
      method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({email,password,returnSecureToken:true}), signal:AbortSignal.timeout(15000)});
    const session = await signed.json();
    if (!signed.ok || !session.idToken) throw new Error('Local sign-in failed.');
    return {uid:created.localId,token:session.idToken};
  }
  async function call(name, user, data) {
    const start = performance.now();
    try {
      const response = await fetch(`http://${functionsHost}/${projectId}/us-central1/${name}`, {
        method:'POST', headers:{'Content-Type':'application/json',Authorization:`Bearer ${user.token}`},
        body:JSON.stringify({data}),signal:AbortSignal.timeout(35000)});
      const body = await response.json();
      return {ms:performance.now()-start,code:body.error?.status || (response.ok ? 'OK' : `HTTP_${response.status}`),result:body.result || body.data};
    } catch (error) { return {ms:performance.now()-start,code:error.name === 'TimeoutError' ? 'TIMEOUT' : 'TRANSPORT_ERROR'}; }
  }
  async function phase(name, jobs, expected='OK') {
    const start = performance.now();
    const results = await Promise.all(jobs.map(job => job()));
    const seconds = (performance.now()-start)/1000;
    const errors = {};
    for (const result of results) if (result.code !== expected) errors[result.code]=(errors[result.code] || 0)+1;
    return {results, metrics:{name,requests:results.length,expectedStatus:expected,
      matched:results.filter(result => result.code === expected).length, errors,
      p50Ms:percentile(results.map(result=>result.ms),0.5),p95Ms:percentile(results.map(result=>result.ms),0.95),
      maxMs:percentile(results.map(result=>result.ms),1),requestsPerSecond:Math.round(results.length/seconds*10)/10}};
  }
  try {
    for (const users of levels) {
      const roadId = `load_${run}_${users}`;
      await db.doc(`roads/${roadId}`).set({name:'Synthetic test road',status:'not_passable',updatedAt:new Date(),
        geometry:{segments:[{points:[{lon:120.984,lat:14.675},{lon:120.984,lat:14.677}]}]}});
      const reporters = [], observers = [];
      // Setup is excluded from request latency; never retain credentials in artifacts.
      for (let i=0;i<users;i++) {
        reporters.push(await resident(`${users}-r${i}`));
        observers.push(await resident(`${users}-o${i}`));
      }
      const payloads = reporters.map((_,i) => ({requestId:`load_${run}_${users}_${i}_report`,roadId,
        title:'Synthetic flood test',description:'Emulator performance fixture',severity:'High',isEmergency:false,
        observedAt:new Date().toISOString(),location:{lat:14.676,lng:120.984}}));
      const submissions = await phase('simultaneous_reports_same_road',reporters.map((user,i)=>()=>call('submitReport',user,payloads[i])));
      const saved = submissions.results.map((result,i)=>({result,i})).filter(({result})=>result.code==='OK');
      const replay = await phase('response_loss_replays',saved.flatMap(({i}) => [0,1].map(()=>()=>call('submitReport',reporters[i],payloads[i]))));
      const cooldown = await phase('cooldown_rejections',saved.map(({i})=>()=>call('submitReport',reporters[i],
        {...payloads[i],requestId:`load_${run}_${users}_${i}_blocked`})), 'RESOURCE_EXHAUSTED');
      const incident = (await db.doc(`road_incidents/${roadId}`).get()).data();
      const choices = ['still_flooded','appears_passable','cannot_confirm'];
      const observationData = observers.map((_,i)=>({requestId:`load_${run}_${users}_${i}_observe`,roadId,
        incidentId:incident?.incidentId,choice:choices[i%3],observedAt:new Date().toISOString()}));
      const observations = await phase('simultaneous_observations_same_incident',observers.map((user,i)=>()=>call('observeRoadIncident',user,observationData[i])));
      // Explicit recovery after a burst, using the SAME request IDs. This is
      // measured separately and never concealed in the original error counts.
      const recoveryResults = [];
      for (let i=0;i<users;i++) {
        if (submissions.results[i].code !== 'OK') recoveryResults.push(await call('submitReport',reporters[i],payloads[i]));
        if (observations.results[i].code !== 'OK') recoveryResults.push(await call('observeRoadIncident',observers[i],observationData[i]));
      }
      const stored = await db.collection('reports').where('roadId','==',roadId).get();
      const latest = (await db.doc(`road_incidents/${roadId}`).get()).data();
      const responseDocs = await db.collection(`road_incidents/${roadId}/responses`).get();
      const road = (await db.doc(`roads/${roadId}`).get()).data();
      const uniqueUsers = new Set(stored.docs.map(doc=>doc.data().userId));
      const invariants = {oneReportPerReporter:stored.size === users && uniqueUsers.size === users,
        oneResponsePerObserver:responseDocs.size === users,
        responseTotalsMatch:responseDocs.size === Object.values(latest?.counts || {}).reduce((a,b)=>a+b,0),
        roadNeverReopened:road.status === 'not_passable' && latest?.state !== 'resolved',
        replayIdsMatch:replay.results.every((result,index)=>result.code==='OK' && result.result?.reportId===saved[Math.floor(index/2)].result.result?.reportId)};
      const phases = [submissions,replay,cooldown,observations].map(result=>result.metrics);
      const burstPassed = phases.every(result=>result.matched===result.requests);
      const recovered = recoveryResults.every(result=>result.code==='OK') && Object.values(invariants).every(Boolean);
      healthy &&= burstPassed && recovered;
      report.stages.push({simultaneousUsers:users,phases,burstPassed,recoveryRequests:recoveryResults.length,recovered,invariants});
      console.log(JSON.stringify({users,burstPassed,recovered,phases,invariants}));
    }
    report.passed = healthy;
    const output = path.resolve('.performance-results','backend-load.json');
    fs.mkdirSync(path.dirname(output),{recursive:true});
    fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
    console.log(`Saved .performance-results/backend-load.json. Production capacity is not established.`);
    if (!healthy) process.exitCode=1;
  } finally { await deleteApp(app); }
}
if (require.main === module) main().catch(error=>{ console.error(error.message); process.exitCode=1; });
module.exports = {percentile,localHost};
