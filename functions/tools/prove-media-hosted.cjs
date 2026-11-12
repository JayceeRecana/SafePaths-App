// Only the three existing synthetic test accounts and a generated JPEG are used.
// Never log credentials, tokens, request payloads or returned image references.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict'), crypto = require('node:crypto');
const {initializeApp, cert, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const project = 'safepaths-test', endpoint = 'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof';
let stage = 'configuration';
async function main(args) {
  assert.ok(args.every(x => x.startsWith('--credentials=')));
  const file = args.find(x => x.startsWith('--credentials='))?.slice(14); assert.ok(file);
  const key = JSON.parse(fs.readFileSync(file, 'utf8')); assert.equal(key.project_id, project);
  assert.ok(key.client_email.endsWith(`@${project}.iam.gserviceaccount.com`));
  const dir = path.resolve('.usability-work-baseline/spark-proof-setup');
  const fixtures = JSON.parse(fs.readFileSync(path.join(dir, 'PRIVATE-test-accounts.json'), 'utf8')); assert.equal(fixtures.project, project);
  assert.deepEqual(fixtures.accounts.map(x => x.uid).sort(), ['spark-proof-admin', 'spark-proof-other', 'spark-proof-resident']);
  const native = JSON.parse(fs.readFileSync('android/app/src/fieldtest/google-services.json', 'utf8')); assert.equal(native.project_info.project_id, project);
  const app = initializeApp({projectId: project, credential: cert(key)}, 'media-hosted');
  const tokens = {}, checks = [], owner = 'spark-proof-resident', peer = 'spark-proof-other', admin = 'spark-proof-admin';
  const run = crypto.randomBytes(12).toString('hex'), state = {project, run, intents: {}};
  const resultFile = path.join(dir, 'media-hosted-result.json'), stateFile = path.join(dir, `media-hosted-state-${run}.json`);
  const evidence = {project, checkedAt: new Date().toISOString(), APKBuilt: false, mainProjectModified: false, physicalDeviceTested: false, checks};
  const persist = () => fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
  const record = name => {checks.push(name); fs.writeFileSync(resultFile, JSON.stringify(evidence, null, 2));};
  const intent = (name, data) => {assert.ok(!state.intents[name]); state.intents[name] = {requestId: crypto.randomBytes(24).toString('base64url'), ...data}; persist(); return state.intents[name];};
  const db = getFirestore(app); let original, profileTouched = false;
  async function post(route, data, uid = owner, expected = 200) {
    stage = route;
    const response = await fetch(`${endpoint}/${route}`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(45000), headers: {'content-type': 'application/json', authorization: `Bearer ${tokens[uid]}`}, body: JSON.stringify({data})});
    const body = await response.json();
    assert.equal(response.status, expected, `Unexpected ${route} status (${body.error?.code ?? 'no error code'})`); return body.result ?? body;
  }
  async function upload(purpose, bytes, expected = 200, route = `media-upload/${purpose}`) {
    stage = route;
    const response = await fetch(`${endpoint}/${route}`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(45000), headers: {'content-type': 'image/jpeg', authorization: `Bearer ${tokens[owner]}`}, body: bytes});
    const body = await response.json(); assert.equal(response.status, expected, `Unexpected ${route} status (${body.error?.code ?? 'no error code'})`); return body;
  }
  async function read(reference, uid, feedbackId, expected = 200) {
    stage = 'media-read';
    const response = await fetch(`${endpoint}/media-read`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(45000), headers: {'content-type': 'application/json', authorization: `Bearer ${tokens[uid]}`}, body: JSON.stringify({data: {reference, ...(feedbackId ? {feedbackId} : {})}})});
    assert.equal(response.status, expected, 'Unexpected private image access status');
    if (expected === 200) {assert.equal(response.headers.get('cache-control'), 'no-store'); assert.equal(response.headers.get('content-type'), 'image/jpeg'); assert.equal(response.headers.get('x-content-type-options'), 'nosniff'); return new Uint8Array(await response.arrayBuffer());}
    await response.arrayBuffer();
  }
  async function direct(resource, uid, method = 'GET', body) {
    const response = await fetch(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${resource}`, {method, redirect: 'error', signal: AbortSignal.timeout(20000), headers: {authorization: `Bearer ${tokens[uid]}`, 'content-type': 'application/json'}, ...(body ? {body: JSON.stringify(body)} : {})}); return response.status;
  }
  try {
    assert.equal((await db.doc('system/media').get()).data()?.enabled, true);
    for (const user of fixtures.accounts) {
      assert.equal((await db.doc(`users/${user.uid}`).get()).data()?.proofFixtureVersion, 1);
      stage = 'fixture-sign-in';
      const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${native.client[0].api_key[0].current_key}`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20000), headers: {'content-type': 'application/json'}, body: JSON.stringify({email: user.email, password: user.password, returnSecureToken: true})});
      assert.equal(response.status, 200); tokens[user.uid] = (await response.json()).idToken;
    }
    assert.equal((await db.collection('push_devices').where('active', '==', true).limit(1).get()).empty, true);
    record('test project and synthetic accounts verified; no phone targeted');
    original = (await db.doc(`users/${owner}`).get()).data(); assert.equal(original.photoUrl ?? null, null, 'Do not replace an existing avatar'); state.original = {name: original.name, location: original.location ?? '', photoUrl: null}; persist();
    const bytes = require('../test/support/media_fixture.cjs').jpeg(), digest = crypto.createHash('sha256').update(bytes).digest('hex');
    const context = await post('profile-context', {}); assert.equal(context.ownerUid, owner);
    await post('profile-context', {uid: peer}, owner, 400);
    const avatar = (await upload('avatar', bytes)).reference;
    assert.equal(avatar, `${endpoint}/media/avatar/${owner}/${digest}`);
    const allowance = (await db.doc(`media_limits/${owner}`).get()).data();
    assert.equal((await upload('avatar', bytes)).reference, avatar);
    assert.equal((await db.doc(`media_limits/${owner}`).get()).data().count, allowance.count);
    const reservation = await db.doc(`media_uploads/${crypto.createHash('sha256').update(`avatar|${owner}|${digest}`).digest('hex')}`).get(); assert.equal(reservation.data().status, 'ready');
    record('private immutable avatar upload and retry reuse one reservation');
    await read(avatar, owner, null, 403); record('unbound uploaded avatar cannot be read');
    const save = intent('profileSave', {contextToken: context.token, name: 'Synthetic media acceptance', location: 'Synthetic test location', photoMode: 'set', photoUrl: avatar});
    for (const forged of [{email: 'synthetic@example.invalid'}, {userId: peer}, {role: 'admin'}]) await post('profile-save', {...save, ...forged}, owner, 400);
    await post('profile-save', {...save, contextToken: (await post('profile-context', {}, peer)).token}, peer, 403);
    profileTouched = true; assert.equal((await post('profile-save', save)).saved, true); assert.equal((await post('profile-save', save)).replay, true);
    const saved = (await db.doc(`users/${owner}`).get()).data(); assert.equal(saved.photoUrl, avatar);
    for (const field of Object.keys(original).filter(k => /^(role|email|trust|totalReports|successfulReports)/.test(k))) assert.deepEqual(saved[field], original[field]);
    record('server-owned profile save replays once and preserves role, trust and account email');
    for (const uid of [owner, admin]) assert.deepEqual(await read(avatar, uid), bytes); await read(avatar, peer, null, 403);
    record('avatar bytes available to owner/current admin and denied to peer');
    for (const uid of [owner, admin]) {
      assert.equal(await direct(`users/${owner}?updateMask.fieldPaths=photoUrl`, uid, 'PATCH', {fields: {photoUrl: {stringValue: 'https://example.invalid/forged.jpg'}}}), 403);
      assert.equal(await direct(`users/${owner}?updateMask.fieldPaths=name`, uid, 'PATCH', {fields: {name: {stringValue: 'Forged name'}}}), 403);
      assert.equal(await direct('media_limits/' + owner, uid), 403);
    }
    record('direct owner/admin profile writes and media registry reads denied');
    await post('profile-save', {...save, requestId: crypto.randomBytes(24).toString('base64url'), name: 'Stale edit'}, owner, 409); record('stale profile edits cannot overwrite the saved version');
    const feedbackRef = (await upload('feedback', bytes)).reference;
    assert.equal(feedbackRef, `${endpoint}/media/feedback/${owner}/${digest}`);
    const feedbackInput = intent('feedbackSubmit', {category: 'General Feedback', rating: 4, comments: 'Synthetic attachment acceptance only. No participant data.', allowFollowUp: false, imageUrl: feedbackRef});
    await read(feedbackRef, owner, 'unbound_synthetic_record', 403);
    const feedback = await post('feedback-submit', feedbackInput); state.feedbackId = feedback.resourceId; persist();
    assert.equal((await post('feedback-submit', feedbackInput)).replay, true);
    const recordData = (await db.doc(`feedbacks/${feedback.resourceId}`).get()).data(); assert.equal(recordData.hasAttachment, true); assert.equal(recordData.imageUrl, feedbackRef); assert.equal(recordData.userId, owner);
    for (const uid of [owner, admin]) assert.deepEqual(await read(feedbackRef, uid, feedback.resourceId), bytes);
    await read(feedbackRef, peer, feedback.resourceId, 403); await read(feedbackRef, owner, 'unbound_synthetic_record', 403);
    record('feedback attachment persists with its record; retry, owner/admin reads and peer/wrong-record denials verified');
    await post('feedback-submit', {...feedbackInput, requestId: crypto.randomBytes(24).toString('base64url')}, peer, 403);
    await post('feedback-submit', {...feedbackInput, requestId: crypto.randomBytes(24).toString('base64url'), imageUrl: avatar}, owner, 400);
    await post('feedback-submit', {...feedbackInput, requestId: crypto.randomBytes(24).toString('base64url'), imageUrl: `${endpoint}/media/feedback/${owner}/${'a'.repeat(64)}`}, owner, 409);
    record('wrong owner, wrong media purpose and missing attachment rejected before feedback save');
    stage = 'public-access-denied';
    for (const url of [avatar, feedbackRef, `https://bbteuzgfgnrjjrqewidc.supabase.co/storage/v1/object/public/report-photos-proof/avatars/${owner}/${digest}.jpg`, `https://bbteuzgfgnrjjrqewidc.supabase.co/storage/v1/object/public/report-photos-proof/feedback/${owner}/${digest}.jpg`]) {
      const response = await fetch(url, {redirect: 'error', signal: AbortSignal.timeout(20000)}); assert.notEqual(response.status, 200); await response.arrayBuffer();
    }
    record('opaque references and public storage URLs cannot serve the private media anonymously');
    for (const purpose of ['avatar', 'feedback']) await upload(purpose, new Uint8Array([255, 216, 255, 217]), 400);
    await upload('feedback', new Uint8Array([255, 216, 255, 217]), 400, 'photo-upload');
    record('malformed JPEG rejected for avatars, screenshots and existing report uploads');
    const remove = intent('profileRestore', {contextToken: (await post('profile-context', {})).token, name: original.name, location: original.location ?? '', photoMode: 'remove'});
    assert.equal((await post('profile-save', remove)).saved, true); assert.equal((await post('profile-save', remove)).replay, true);
    await read(avatar, owner, null, 403); await read(avatar, admin, null, 403);
    assert.equal((await post('profile-save', save)).replay, true); assert.equal((await db.doc(`users/${owner}`).get()).data().photoUrl, null);
    record('default-avatar removal revokes new reads; an old save replay cannot resurrect it');
    const restored = (await db.doc(`users/${owner}`).get()).data(); assert.equal(restored.name, original.name); assert.equal(restored.location, original.location ?? '');
    profileTouched = false; record('synthetic original profile restored through the protected API; no object deletion');
    evidence.completed = true; record('hosted media acceptance complete; physical phone and main rollout remain open');
    console.log(JSON.stringify(evidence, null, 2));
  } finally {
    if (profileTouched && original && tokens[owner]) {
      try {
        const ctx = await post('profile-context', {});
        await post('profile-save', intent('failureRestore', {contextToken: ctx.token, name: original.name, location: original.location ?? '', photoMode: 'remove'}));
        evidence.profileRestoredAfterFailure = true; fs.writeFileSync(resultFile, JSON.stringify(evidence, null, 2));
      } catch (_) { console.error('Synthetic profile restoration requires review of the private saved test state.'); }
    }
    await deleteApp(app);
  }
}
main(process.argv.slice(2)).catch(() => {console.error(JSON.stringify({passed: false, stage, reason: 'Hosted media check failed; private details were not logged.'})); process.exitCode = 1;});
