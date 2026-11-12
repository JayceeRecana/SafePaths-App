const {test} = require('node:test');
const assert = require('node:assert/strict');
const {observedPost, withCleanup} = require('../tools/hosted-push-transport.cjs');
test('hosted diagnostics distinguish handler denial from gateway failure without copying private response text', async () => {
  const records = [], token = 'SECRET_SESSION_TOKEN', privateBody = 'PRIVATE_REPORT_TEXT';
  const denied = await observedPost({route: 'push-drain', bearer: token, data: {message: privateBody}, caseName: 'admin_session', observe: r => records.push(r), fetcher: async (_, options) => {
    assert.equal(options.headers.authorization, `Bearer ${token}`);
    return new Response(JSON.stringify({error: {code: 'unauthenticated', message: token + privateBody}}), {status: 401, headers: {'cache-control': 'no-store', 'sb-request-id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'}});
  }});
  assert.equal(denied.status, 401); assert.equal(records[0].errorCode, 'unauthenticated'); assert.equal(records[0].noStore, true);
  const gateway = await observedPost({route: 'push-drain', bearer: token, data: {}, caseName: 'gateway_failure', observe: r => records.push(r), fetcher: async () => new Response(`<html>${token}</html>`, {status: 503})});
  assert.equal(gateway.status, 503); assert.equal(records[1].json, false); assert.equal(records[1].outcome, 'http-response');
  assert.ok(!JSON.stringify(records).includes(token) && !JSON.stringify(records).includes(privateBody));
});
test('hosted diagnostics retain network causes and original status when observation storage fails', async () => {
  const network = await observedPost({route: 'push-drain', data: {}, caseName: 'network_failure', fetcher: async () => {throw new TypeError('Sensitive provider detail', {cause: {code: 'ECONNRESET'}});}});
  assert.equal(network.status, null); assert.equal(network.observation.networkCode, 'ECONNRESET'); assert.equal(network.observation.outcome, 'network-error');
  const actual = await observedPost({route: 'push-drain', data: {}, caseName: 'observer_failure', observe: () => {throw new Error('disk failed');}, fetcher: async () => new Response('{"error":{"code":"unauthenticated"}}', {status: 401})});
  assert.equal(actual.status, 401); assert.equal(actual.data.error.code, 'unauthenticated');
});
test('hosted diagnostic response capture is bounded and never logs an oversized provider body', async () => {
  const result = await observedPost({route: 'push-drain', data: {}, caseName: 'oversized_response', fetcher: async () => new Response('SENSITIVE'.repeat(4000), {status: 502})});
  assert.equal(result.status, 502); assert.equal(result.observation.outcome, 'response-read-error'); assert.ok(!JSON.stringify(result.observation).includes('SENSITIVE'));
});
test('ordinary admin sessions and bad worker credentials are denied before account/database or sender access', async () => {
  const {createProofHandler} = await import('../../supabase/functions/_shared/proof_handler.mjs');
  let verifyCalls = 0, sends = 0;
  const handler = createProofHandler({db: {}, photos: {}, allowedUids: new Set(['admin']), workerSecret: 'W'.repeat(43), verify: async () => {verifyCalls++; return 'admin';}, push: {drain: async () => {sends++; return {};}}});
  for (const authorization of ['Bearer synthetic-admin-session', 'Bearer wrong-worker-key', null]) {
    const response = await handler(new Request('https://example.test/safepaths-report-proof/push-drain', {method: 'POST', headers: authorization ? {authorization} : {}, body: '{}'}));
    assert.equal(response.status, 401); assert.equal((await response.json()).error.code, 'unauthenticated');
  }
  assert.equal(verifyCalls, 0); assert.equal(sends, 0);
});
test('cleanup preserves the first failed check and records cleanup-only failures separately', async () => {
  const original = new Error('original check failure'), cleanup = new Error('cleanup failed'), recorded = [];
  await assert.rejects(withCleanup(async () => {throw original;}, async () => {throw cleanup;}, value => recorded.push(value)), error => error === original);
  assert.deepEqual(recorded[0], {workFailed: true, cleanupFailed: true, retainedFailure: 'work'});
  await assert.rejects(withCleanup(async () => {}, async () => {throw cleanup;}, value => recorded.push(value)), error => error === cleanup);
  assert.deepEqual(recorded[1], {workFailed: false, cleanupFailed: true, retainedFailure: 'cleanup'});
  assert.equal(await withCleanup(async () => 7, async () => {}), 7);
});
