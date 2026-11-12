const { test, before } = require('node:test');
const assert = require('node:assert/strict');
let createReportFollowups, createAdminWorkflow, serverTime;
before(async () => {
  ({ createReportFollowups } = await import('../../supabase/functions/_shared/report_followups.mjs'));
  ({ createAdminWorkflow } = await import('../../supabase/functions/_shared/admin_workflow.mjs'));
  ({ serverTime } = await import('../../supabase/functions/_shared/proof_common.mjs'));
});
const rootId = 'a'.repeat(64), incidentId = 'b'.repeat(64);
function fixture(score = 50) {
  let now = Date.parse('2026-10-26T12:00:00Z');
  const docs = new Map();
  const copy = (value) => value === serverTime ? new Date(now) : value instanceof Date ? new Date(value) :
    Array.isArray(value) ? value.map(copy) : value && typeof value === 'object' ?
      Object.fromEntries(Object.entries(value).map(([k, v]) => [k, copy(v)])) : value;
  const get = async (path, state = docs) => ({ path, exists: state.has(path), data: copy(state.get(path) ?? {}) });
  const query = async (collection, filters, options = {}, state = docs) => [...state.entries()]
    .filter(([path, value]) => path.split('/').length === 2 && path.startsWith(collection + '/') &&
      filters.every(([field, op, target]) => { assert.equal(op, 'EQUAL'); return value[field] === target; }))
    .slice(0, options.limit ?? 100).map(([path, data]) => ({ path, exists: true, data: copy(data) }));
  let tail = Promise.resolve();
  const db = {
    get, query,
    transaction(work) {
      const task = tail.then(async () => {
        const state = new Map([...docs].map(([path, data]) => [path, copy(data)]));
        let writing = false;
        const tx = {
          get: (path) => { assert.equal(writing, false, 'Firestore reads must precede writes'); return get(path, state); },
          query: (c, f, v, limit) => { assert.equal(writing, false); return query(c, [[f, 'EQUAL', v]], { limit }, state); },
          set(path, data, { merge = false, create = false } = {}) {
            writing = true;
            if (create) assert.equal(state.has(path), false);
            state.set(path, { ...(merge ? state.get(path) ?? {} : {}), ...copy(data) });
          },
        };
        const result = await work(tx);
        docs.clear(); for (const [path, data] of state) docs.set(path, data);
        return result;
      });
      tail = task.catch(() => {});
      return task;
    },
  };
  docs.set('users/resident', { role: 'user', trustScore: score, lastReportAt: new Date(now - 3600000) });
  docs.set('users/admin', { role: 'admin' });
  docs.set('users/other', { role: 'user', trustScore: 50 });
  docs.set('roads/road', { name: 'Synthetic road', status: 'not_passable', notes: 'Closed after current check', updatedAt: new Date(now - 3600000) });
  docs.set('road_incidents/road', { incidentId, revision: 1, state: 'admin_confirmed', lastObservedAt: new Date(now - 3600000) });
  docs.set(`reports/${rootId}`, { userId: 'resident', roadId: 'road', incidentId, title: 'Original flood report', description: 'Original flooding', severity: 'High', status: 'pending', isEmergency: false, createdAt: new Date(now - 3600000), observedAt: new Date(now - 3600000), imageUrl: 'resident-photo-original' });
  const photos = { validate: async (reference, uid) => assert.ok(reference.startsWith(uid + '-photo-')) };
  const api = createReportFollowups({ db, photos, clock: () => now });
  const admin = createAdminWorkflow({ db, clock: () => now, followupsEnabled: true });
  let serial = 0;
  const requestId = () => `request_followup_${++serial}`.padEnd(24, 'x');
  async function submit(extra = {}, uid = 'resident') {
    const context = await api.context(uid, { rootReportId: rootId });
    const payload = { rootReportId: rootId, requestId: requestId(), contextToken: context.token,
      conditionChange: 'improved', severity: 'Low', description: `Water lower ${serial}`, observedAt: new Date(now).toISOString(), ...extra };
    return { result: await api.submit(uid, payload), payload };
  }
  async function review(reportId, extra = {}) {
    const context = await admin.context('admin', { reportId });
    const payload = { reportId, action: 'verify', requestId: requestId(), contextToken: context.token,
      roadStatus: 'not_passable', note: 'Field team checked current conditions.', verifiedCurrentConditions: true, ...extra };
    return { result: await admin.action('admin', payload), payload };
  }
  return { docs, db, api, admin, submit, review, requestId, advance: (ms = 360000) => now += ms };
}

test('follow-up is append-only, preserves original photo and does not reopen the road', async () => {
  const f = fixture(); const before = structuredClone(f.docs.get(`reports/${rootId}`));
  const { result } = await f.submit({ imageUrl: 'resident-photo-current', photoMatchesObservation: true, conditionChange: 'cleared' });
  const parent = f.docs.get(`reports/${rootId}`), child = f.docs.get(`reports/${result.reportId}`);
  for (const field of ['description', 'imageUrl', 'status', 'createdAt', 'observedAt']) assert.deepEqual(parent[field], before[field]);
  assert.equal(parent.originalSubmission.imageUrl, before.imageUrl);
  assert.equal(parent.originalSubmission.photoSubmittedAt, null);
  assert.equal(child.reportType, 'followup'); assert.equal(child.rootReportId, rootId);
  assert.equal(child.imageUrl, 'resident-photo-current'); assert.equal(child.location, undefined);
  assert.equal(f.docs.get('roads/road').status, 'not_passable');
  assert.equal(f.docs.get('road_incidents/road').state, 'under_verification');
});

test('owner-only history, own photo, stale context and duplicate evidence fail without writes', async () => {
  const f = fixture();
  await assert.rejects(() => f.api.context('other', { rootReportId: rootId }), { code: 'permission-denied' });
  await assert.rejects(() => f.submit({ imageUrl: 'other-photo-current', photoMatchesObservation: true }), /assertion|false|match/i);
  await assert.rejects(() => f.submit({ imageUrl: 'resident-photo-original', photoMatchesObservation: true }), { code: 'duplicate-evidence' });
  await assert.rejects(() => f.submit({ contextToken: 'f'.repeat(64) }), { code: 'failed-precondition' });
  assert.equal([...f.docs.keys()].filter((p) => p.startsWith('reports/')).length, 1);
});

test('response-loss retry saves only one update and changed payload cannot reuse receipt', async () => {
  const f = fixture(); const { result, payload } = await f.submit();
  const repeated = await f.api.submit('resident', payload);
  assert.equal(repeated.replay, true); assert.equal(repeated.reportId, result.reportId);
  await assert.rejects(() => f.api.submit('resident', { ...payload, description: 'Changed after uncertain save' }), { code: 'already-exists' });
  assert.equal(f.docs.get(`reports/${rootId}`).followupCount, 1);
});

test('closed incidents, old observations and cooldowns cannot be bypassed', async () => {
  const f = fixture();
  await assert.rejects(() => f.submit({ observedAt: '2026-10-25T10:00:00Z' }), { code: 'observation-stale' });
  await f.submit(); f.advance(30000);
  await assert.rejects(() => f.submit(), { code: 'resource-exhausted' });
  f.docs.get('road_incidents/road').state = 'resolved';
  assert.equal((await f.api.context('resident', { rootReportId: rootId })).canSubmit, false);
  await assert.rejects(() => f.submit(), { code: 'failed-precondition' });
});

test('one verified original plus one meaningful verified follow-up earn at most 15 per incident', async () => {
  const f = fixture(); assert.equal((await f.review(rootId)).result.pointsAwarded, 10);
  const first = await f.submit(); const review = await f.review(first.result.reportId, { meaningfulFollowup: true });
  assert.equal(review.result.pointsAwarded, 5);
  assert.equal((await f.admin.action('admin', review.payload)).replay, true);
  f.advance(); const second = await f.submit();
  assert.equal((await f.review(second.result.reportId, { meaningfulFollowup: true })).result.pointsAwarded, 0);
  assert.equal(f.docs.get('users/resident').trustScore, 65);
  assert.equal(f.docs.get(`reports/${rootId}`).pointsAwarded, 10);
});

test('a trustworthy but unchanged update and an unconfirmed meaningful claim earn no bonus', async () => {
  const f = fixture(); await f.review(rootId);
  const first = await f.submit({ conditionChange: 'unchanged' });
  assert.equal((await f.review(first.result.reportId, { meaningfulFollowup: true })).result.pointsAwarded, 0);
  f.advance(); const second = await f.submit();
  assert.equal((await f.review(second.result.reportId)).result.pointsAwarded, 0);
  assert.equal(f.docs.get('users/resident').trustScore, 60);
});

test('points are capped at 100 and a confirmed false follow-up does not undo original reward', async () => {
  const capped = fixture(98); assert.equal((await capped.review(rootId)).result.pointsAwarded, 2);
  const child = await capped.submit(); assert.equal((await capped.review(child.result.reportId, { meaningfulFollowup: true })).result.pointsAwarded, 0);
  assert.equal(capped.docs.get('users/resident').trustScore, 100);
  const f = fixture(); await f.review(rootId); const update = await f.submit();
  await assert.rejects(() => f.review(update.result.reportId, { action: 'dismiss', reason: 'spam_false' }), { code: 'failed-precondition' });
  assert.equal((await f.review(update.result.reportId, { action: 'dismiss', reason: 'spam_false', confirmedFalseReport: true })).result.pointsAwarded, -5);
  assert.equal(f.docs.get('users/resident').trustScore, 55);
  assert.equal(f.docs.get(`reports/${rootId}`).pointsAwarded, 10);
});

test('honest correction has no penalty; reversing an awarded bonus is explicit and idempotent', async () => {
  const f = fixture(); await f.review(rootId); const child = await f.submit();
  assert.equal((await f.review(child.result.reportId, { action: 'dismiss', reason: 'needs_correction' })).result.pointsAwarded, 0);
  f.advance(); const second = await f.submit(); await f.review(second.result.reportId, { meaningfulFollowup: true });
  const correction = await f.review(second.result.reportId, { action: 'correct_followup', reason: 'mistaken_approval', note: 'Wrong attachment was approved in error.' });
  assert.equal(correction.result.pointsReversed, 5); assert.equal(correction.result.falsePenalty, 0);
  assert.equal(f.docs.get('users/resident').trustScore, 60);
  await f.admin.action('admin', correction.payload);
  assert.equal(f.docs.get('users/resident').trustScore, 60);
  await assert.rejects(() => f.review(second.result.reportId, { action: 'correct_followup', reason: 'mistaken_approval' }), { code: 'failed-precondition' });
});

test('concurrent admin reviews cannot award a bonus twice', async () => {
  const f = fixture(); await f.review(rootId); const child = await f.submit();
  const context = await f.admin.context('admin', { reportId: child.result.reportId });
  const payload = { reportId: child.result.reportId, action: 'verify', contextToken: context.token,
    roadStatus: 'not_passable', note: 'Independent check confirms this update.', verifiedCurrentConditions: true, meaningfulFollowup: true };
  const results = await Promise.allSettled([f.admin.action('admin', { ...payload, requestId: f.requestId() }), f.admin.action('admin', { ...payload, requestId: f.requestId() })]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(f.docs.get('users/resident').trustScore, 65);
});

test('original review comes first and reopening a road preserves independent follow-up review', async () => {
  const f = fixture(); const child = await f.submit({ conditionChange: 'cleared' });
  await assert.rejects(() => f.review(child.result.reportId, { roadStatus: 'passable', meaningfulFollowup: true }), { code: 'failed-precondition' });
  assert.equal((await f.review(rootId, { roadStatus: 'passable' })).result.pointsAwarded, 10);
  const waiting = f.docs.get(`reports/${child.result.reportId}`);
  assert.equal(waiting.status, 'pending'); assert.equal(waiting.incidentReviewStatus, 'passable');
  assert.equal(waiting.pointsAwarded, undefined);
  assert.equal(f.docs.get('road_incidents/road').state, 'resolved');
  assert.equal((await f.review(child.result.reportId, { roadStatus: 'passable', meaningfulFollowup: true })).result.pointsAwarded, 5);
  assert.equal(f.docs.get('users/resident').trustScore, 65);
});

test('administrators cannot review their own evidence or award themselves points', async () => {
  const f = fixture(); f.docs.get('users/resident').role = 'admin';
  const context = await f.admin.context('resident', { reportId: rootId });
  assert.equal(context.selfReview, true);
  await assert.rejects(() => f.admin.action('resident', { reportId: rootId, action: 'verify',
    requestId: f.requestId(), contextToken: context.token, roadStatus: 'not_passable',
    note: 'I submitted this observation myself.', verifiedCurrentConditions: true }), { code: 'self-review' });
  assert.equal(f.docs.get('users/resident').trustScore, 50);
  assert.equal(f.docs.get(`reports/${rootId}`).status, 'pending');
});

test('historical verified originals bootstrap the incident reward cap', async () => {
  const f = fixture(); f.docs.set('reports/legacy', { ...f.docs.get(`reports/${rootId}`), status: 'verified', pointsAwarded: 10 });
  assert.equal((await f.review(rootId)).result.pointsAwarded, 0);
  const child = await f.submit();
  assert.equal((await f.review(child.result.reportId, { meaningfulFollowup: true })).result.pointsAwarded, 5);
  assert.equal(f.docs.get('users/resident').trustScore, 55);
});

test('disproved rewarded evidence has separate bonus reversal and confirmed-false penalty', async () => {
  const f = fixture(); await f.review(rootId); const child = await f.submit();
  await f.review(child.result.reportId, { meaningfulFollowup: true });
  await assert.rejects(() => f.review(child.result.reportId, { action: 'correct_followup', reason: 'confirmed_false', confirmedFalseReport: false }), { code: 'invalid-argument' });
  const correction = await f.review(child.result.reportId, { action: 'correct_followup', reason: 'confirmed_false', confirmedFalseReport: true, note: 'Independent evidence established this was a false submission.' });
  assert.equal(correction.result.pointsReversed, 5); assert.equal(correction.result.falsePenalty, 5);
  assert.equal(f.docs.get('users/resident').trustScore, 55);
  assert.equal(f.docs.get(`reports/${rootId}`).pointsAwarded, 10);
  assert.equal(f.docs.get('road_incidents/road').state, 'under_verification');
  await f.admin.action('admin', correction.payload);
  assert.equal(f.docs.get('users/resident').trustScore, 55);
});
