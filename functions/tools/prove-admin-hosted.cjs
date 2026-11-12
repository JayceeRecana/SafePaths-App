// Synthetic test-only acceptance. Private keys, passwords and tokens stay in memory.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {initializeApp, cert, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const project = 'safepaths-test';
const endpoint = 'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof';
let stage = 'preflight';
async function main(args) {
  assert.ok(args.includes('--apply'));
  const filename = args.find(a => a.startsWith('--credentials='))?.slice(14);
  assert.ok(filename);
  assert.ok(args.every(a => a === '--apply' || a.startsWith('--credentials=')));
  const root = path.resolve(__dirname, '../..');
  const dir = path.join(root, '.usability-work-baseline/spark-proof-setup');
  const key = JSON.parse(fs.readFileSync(filename, 'utf8'));
  assert.equal(key.project_id, project);
  const native = JSON.parse(fs.readFileSync(path.join(root, 'android/app/src/fieldtest/google-services.json'), 'utf8'));
  assert.equal(native.project_info.project_id, project);
  const fixtures = JSON.parse(fs.readFileSync(path.join(dir, 'PRIVATE-test-accounts.json'), 'utf8'));
  assert.equal(fixtures.project, project);
  assert.deepEqual(fixtures.accounts.map(a => a.uid).sort(), ['spark-proof-admin', 'spark-proof-other', 'spark-proof-resident']);
  const statefile = path.join(dir, 'admin-hosted-state.json');
  const state = fs.existsSync(statefile) ? JSON.parse(fs.readFileSync(statefile, 'utf8')) : {project, endpoint, run: crypto.randomUUID().replaceAll('-', ''), observedAt: new Date().toISOString(), done: []};
  assert.equal(state.project, project); assert.equal(state.endpoint, endpoint);
  const save = () => fs.writeFileSync(statefile, JSON.stringify(state, null, 2));
  const evidence = {checkedAt: new Date().toISOString(), project, endpoint, physicalPhoneAcceptance: 'pending', checks: state.done};
  const resultfile = path.join(dir, 'admin-hosted-result.json');
  const record = () => {save(); fs.writeFileSync(resultfile, JSON.stringify(evidence, null, 2));};
  async function check(name, run) {stage = name; if (state.done.includes(name)) return; await run(); state.done.push(name); record();}
  async function request(operation, uid, data) {
    const response = await fetch(`${endpoint}/${operation}`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(60000), headers: {authorization: `Bearer ${tokens[uid]}`, 'content-type': 'application/json'}, body: JSON.stringify({data})});
    return {status: response.status, data: await response.json().catch(() => ({}))};
  }
  const tokens = {};
  const app = initializeApp({projectId: project, credential: cert(key)}, 'admin-hosted-acceptance');
  try {
    const db = getFirestore(app);
    for (const account of fixtures.accounts) {
      assert.equal((await db.doc(`users/${account.uid}`).get()).data()?.proofFixtureVersion, 1);
      const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${native.client[0].api_key[0].current_key}`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(25000), headers: {'content-type': 'application/json'}, body: JSON.stringify({email: account.email, password: account.password, returnSecureToken: true})});
      assert.equal(response.status, 200); const auth = await response.json(); assert.equal(auth.localId, account.uid); tokens[account.uid] = auth.idToken;
    }
    const resident = 'spark-proof-resident', admin = 'spark-proof-admin', other = 'spark-proof-other';
    assert.equal((await db.doc('roads/spark-proof-road').get()).data()?.proofFixtureVersion, 1);
    const report = () => db.doc(`reports/${state.reportId}`);
    const ctx = async () => {const r = await request('admin-context', admin, {reportId: state.reportId}); assert.equal(r.status, 200); return r.data.result;};
    async function action(name, details) {
      if (!state[name]) {state[name] = {requestId: `${name}_${state.run}`, reportId: state.reportId, ...details}; save();}
      return request('admin-action', admin, state[name]);
    }
    await check('authenticated-test-report-save', async () => {
      const r = await request('submit-report', resident, {requestId: `admin_proof_${state.run}`, roadId: 'spark-proof-road', title: 'Synthetic admin workflow acceptance', description: 'Automated synthetic observation. No real flood or emergency.', severity: 'High', isEmergency: false, observedAt: state.observedAt, location: {lat: 14.676, lng: 120.984, source: 'manual'}});
      assert.equal(r.status, 200); state.reportId = r.data.result.reportId;
      assert.equal((await report().get()).data().userId, resident);
    });
    await check('opening-context-does-not-review', async () => {
      const before = await report().get(); state.originalContext = await ctx();
      const after = await report().get(); assert.equal(after.data().status, 'pending'); assert.equal(before.updateTime.toMillis(), after.updateTime.toMillis());
    });
    await check('resident-cannot-moderate-or-spoof-role', async () => {
      assert.equal((await request('admin-context', resident, {reportId: state.reportId, role: 'admin'})).status, 403);
      assert.equal((await request('admin-action', other, {requestId: `denied_${state.run}`, action: 'reply', reportId: state.reportId, message: 'Spoofed administrator'})).status, 403);
    });
    await check('explicit-start-and-durable-acknowledgement', async () => {
      const r = await action('start', {action: 'start', contextToken: state.originalContext.token}); assert.equal(r.status, 200); assert.equal(r.data.result.notification, 'saved_in_app');
      assert.equal((await report().get()).data().status, 'under_review');
      assert.equal((await request('admin-action', admin, state.start)).data.result.replay, true);
    });
    await check('private-reply-concurrent-retry-saves-once', async () => {
      if (state.replyCountBefore == null) state.replyCountBefore = (await db.collection('report_messages').where('reportId', '==', state.reportId).get()).size;
      if (!state.staleContext) state.staleContext = await ctx(); save();
      const details = {action: 'reply', message: 'We received this synthetic report. This is not a rescue dispatch confirmation.'};
      const first = await action('reply', details); assert.equal(first.status, 200);
      const retries = await Promise.all([request('admin-action', admin, state.reply), request('admin-action', admin, state.reply)]);
      for (const r of retries) {assert.equal(r.status, 200); assert.equal(r.data.result.replay, true);}
      const after = await db.collection('report_messages').where('reportId', '==', state.reportId).get(); assert.equal(after.size, state.replyCountBefore + 1);
      state.messageId = after.docs.find(d => d.data().message === details.message).id;
      const publicData = (await report().get()).data(); assert.notEqual(publicData.adminReply, details.message); assert.ok(!JSON.stringify(publicData.adminReplies ?? []).includes(details.message));
    });
    const documents = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
    async function queryMessages(uid, own) {
      const filters = [{fieldFilter: {field: {fieldPath: 'reportId'}, op: 'EQUAL', value: {stringValue: state.reportId}}}];
      if (own) filters.push({fieldFilter: {field: {fieldPath: 'userId'}, op: 'EQUAL', value: {stringValue: uid}}});
      return fetch(`${documents}:runQuery`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(25000), headers: {authorization: `Bearer ${tokens[uid]}`, 'content-type': 'application/json'}, body: JSON.stringify({structuredQuery: {from: [{collectionId: 'report_messages'}], where: filters.length === 1 ? filters[0] : {compositeFilter: {op: 'AND', filters}}, orderBy: [{field: {fieldPath: 'createdAt'}, direction: 'DESCENDING'}, {field: {fieldPath: '__name__'}, direction: 'DESCENDING'}], limit: 20}})});
    }
    await check('owner-and-admin-private-message-indexes', async () => {
      for (const [uid, own] of [[resident, true], [admin, false]]) {const r = await queryMessages(uid, own); assert.equal(r.status, 200); assert.ok((await r.json()).some(row => row.document?.name.endsWith(`/report_messages/${state.messageId}`)));}
    });
    await check('peer-private-message-read-denied', async () => {
      const r = await fetch(`${documents}/report_messages/${state.messageId}`, {headers: {authorization: `Bearer ${tokens[other]}`}, redirect: 'error', signal: AbortSignal.timeout(25000)}); assert.equal(r.status, 403);
      assert.equal((await queryMessages(other, false)).status, 403);
    });
    await check('direct-admin-report-write-denied', async () => {
      const r = await fetch(`${documents}/reports/${state.reportId}?updateMask.fieldPaths=status`, {method: 'PATCH', redirect: 'error', signal: AbortSignal.timeout(25000), headers: {authorization: `Bearer ${tokens[admin]}`, 'content-type': 'application/json'}, body: JSON.stringify({fields: {status: {stringValue: 'verified'}}})}); assert.equal(r.status, 403);
    });
    const verification = {action: 'verify', roadStatus: 'not_passable', note: 'Synthetic field inspection confirms the test road remains flooded.', verifiedCurrentConditions: true};
    await check('stale-review-rejected', async () => {
      const r = await request('admin-action', admin, {requestId: `stale_${state.run}`, reportId: state.reportId, contextToken: state.staleContext.token, ...verification}); assert.equal(r.status, 409); assert.equal((await report().get()).data().status, 'under_review');
    });
    await check('atomic-verification-with-actual-trust', async () => {
      const before = (await db.doc(`users/${resident}`).get()).data();
      if (state.trustBefore == null) {state.trustBefore = before.trustScore; state.verifiedBefore = before.verifiedReports ?? 0; save();}
      const context = await ctx(); const r = await action('verify', {...verification, contextToken: context.token}); assert.equal(r.status, 200);
      state.points = r.data.result.pointsAwarded; assert.ok(Number.isInteger(state.points) && state.points >= 0 && state.points <= 10);
      const after = (await db.doc(`users/${resident}`).get()).data(), reviewed = (await report().get()).data();
      assert.equal(after.trustScore - state.trustBefore, state.points); assert.equal(after.verifiedReports, state.verifiedBefore + 1); assert.equal(reviewed.pointsAwarded, state.points); assert.equal(reviewed.status, 'verified'); assert.equal(reviewed.incidentReviewStatus, 'not_passable');
      const hash = crypto.createHash('sha256').update(`${admin}|${state.verify.requestId}`).digest('hex');
      assert.ok((await db.doc(`admin_requests/${hash}`).get()).exists); assert.ok((await db.doc(`admin_audits/${hash}`).get()).exists);
      const messageHash = crypto.createHash('sha256').update(`${hash}|reports/${state.reportId}`).digest('hex');
      const outbox = (await db.doc(`notification_outbox/${messageHash}`).get()).data();
      // The test push worker can advance this independently after the saved review.
      assert.ok(['awaiting_sender','sending','retry','no_device','fcm_accepted','failed','expired','account_unavailable'].includes(outbox.status));
    });
    await check('verification-retry-does-not-double-award', async () => {
      const before = (await db.doc(`users/${resident}`).get()).data(); const r = await request('admin-action', admin, state.verify); assert.equal(r.status, 200); assert.equal(r.data.result.replay, true);
      const after = (await db.doc(`users/${resident}`).get()).data(); assert.equal(after.trustScore, before.trustScore); assert.equal(after.verifiedReports, before.verifiedReports);
    });
    await check('verified-observation-keeps-road-closed', async () => {assert.equal((await db.doc('roads/spark-proof-road').get()).data().status, 'not_passable');});
    await check('resident-edit-after-review-rejected', async () => {
      const data = (await report().get()).data(); const r = await request('update-report', resident, {reportId: state.reportId, requestId: `edit_${state.run}`, severity: 'High', description: 'Attempt to edit reviewed synthetic report.', observedAt: new Date().toISOString(), expectedUpdatedAt: (data.lastUpdatedByUser ?? data.createdAt).toMillis()}); assert.equal(r.status, 409);
    });
    evidence.passed = true; record(); console.log(JSON.stringify(evidence, null, 2));
  } finally {await deleteApp(app);}
}
main(process.argv.slice(2)).catch(error => {console.error(JSON.stringify({check: 'admin-hosted', stage, passed: false, category: typeof error.code === 'string' && /^[a-zA-Z_-]{1,40}$/.test(error.code) ? error.code : 'http-or-assertion'})); process.exitCode = 1;});
