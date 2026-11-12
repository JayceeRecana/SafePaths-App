// Fixed, bounded diagnostic run: 12 sequential rejected requests, no retries.
// No valid worker secret/ticket is sent and no phone is targeted.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict'), crypto = require('node:crypto');
const {initializeApp, cert, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {observedPost} = require('./hosted-push-transport.cjs');
async function main(args) {
  assert.equal(args.length, 1); assert.ok(args[0].startsWith('--credentials='));
  assert.ok(!process.env.FIRESTORE_EMULATOR_HOST && !process.env.FIREBASE_AUTH_EMULATOR_HOST);
  const key = JSON.parse(fs.readFileSync(args[0].slice(14), 'utf8')); assert.equal(key.project_id, 'safepaths-test');
  assert.ok(key.client_email.endsWith('@safepaths-test.iam.gserviceaccount.com'));
  const dir = path.resolve('.usability-work-baseline/spark-proof-setup'), fixtures = JSON.parse(fs.readFileSync(path.join(dir, 'PRIVATE-test-accounts.json'), 'utf8'));
  assert.equal(fixtures.project, key.project_id); assert.deepEqual(fixtures.accounts.map(x => x.uid).sort(), ['spark-proof-admin', 'spark-proof-other', 'spark-proof-resident']);
  const native = JSON.parse(fs.readFileSync('android/app/src/fieldtest/google-services.json', 'utf8')); assert.equal(native.project_info.project_id, key.project_id);
  const app = initializeApp({projectId: key.project_id, credential: cert(key)}, 'push-auth-probe');
  const evidence = {project: key.project_id, startedAt: new Date().toISOString(), plannedRequests: 12, automaticRetries: 0, validWorkerCredentialSent: false, phoneTargeted: false, historicalRootCauseConfirmed: false, observations: [], passed: false};
  const file = path.join(dir, `push-auth-probe-${crypto.randomUUID()}.json`), persist = () => fs.writeFileSync(file, JSON.stringify(evidence, null, 2)); persist();
  try {
    const db = getFirestore(app);
    const fixture = fixtures.accounts.find(x => x.uid === 'spark-proof-admin');
    const profile = (await db.doc(`users/${fixture.uid}`).get()).data(); assert.equal(profile?.proofFixtureVersion, 1); assert.equal(profile.role, 'admin');
    assert.equal((await db.collection('push_devices').where('active', '==', true).limit(1).get()).size, 0);
    const signin = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${native.client[0].api_key[0].current_key}`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20000), headers: {'content-type': 'application/json'}, body: JSON.stringify({email: fixture.email, password: fixture.password, returnSecureToken: true})});
    assert.equal(signin.status, 200); const token = (await signin.json()).idToken; assert.ok(token);
    let matched = 0;
    for (let round = 1; round <= 3; round++) {
      for (const [kind, bearer, headers] of [
        ['admin_session', token, {}], ['wrong_worker_key', 'wrong-worker-key', {}],
        ['missing_credential', null, {}],
        ['invalid_ticket', null, {'x-proof-worker-time': String(Math.floor(Date.now()/1000)), 'x-proof-worker-nonce': crypto.randomBytes(16).toString('hex'), 'x-proof-worker-signature': '0'.repeat(64)}],
      ]) {
        const response = await observedPost({route: 'push-drain', bearer, data: {}, headers, caseName: `${kind}_${round}`, timeoutMs: 15000, observe: record => {evidence.observations.push(record); persist();}});
        if (response.status === 401 && response.data?.error?.code === 'unauthenticated' && response.observation.noStore) matched++;
      }
    }
    evidence.matchedRejections = matched; evidence.completedAt = new Date().toISOString(); evidence.passed = matched === evidence.plannedRequests; persist();
    fs.writeFileSync('.usability-work-baseline/integration-push-auth-probe.json', JSON.stringify({...evidence, retainedResult: path.relative(process.cwd(), file)}, null, 2));
    console.log(JSON.stringify({project: key.project_id, passed: evidence.passed, rejectedAsExpected: matched, requests: evidence.observations.length, retries: 0, rootCauseOfHistoricalFailureConfirmed: false}));
    assert.equal(matched, 12, 'Retain every observed failure for diagnosis; never retry until green.');
  } finally {await deleteApp(app);}
}
main(process.argv.slice(2)).catch(() => {console.error('Bounded push authorization probe failed; sanitized observations were retained without private details.'); process.exitCode = 1;});
