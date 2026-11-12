const {test} = require('node:test'), assert = require('node:assert/strict');
const {reviewDefines} = require('../tools/prepare-review-defines.cjs');
const source = {SPARK_PROOF_FIREBASE_PROJECT_ID: 'safepaths-test', SPARK_PROOF_BACKEND_URL: 'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof'};
const native = {project_info: {project_id: 'safepaths-test'}, client: [{client_info: {android_client_info: {package_name: 'com.safepaths.safepaths_app.test'}}}]};
test('candidate review configuration rejects main-project, foreign endpoint and unexpected credential fields', () => {
  assert.throws(() => reviewDefines({...source, SPARK_PROOF_FIREBASE_PROJECT_ID: 'safepaths-92c3d'}, native));
  assert.throws(() => reviewDefines({...source, SPARK_PROOF_BACKEND_URL: source.SPARK_PROOF_BACKEND_URL.replace('bbteuzgfgnrjjrqewidc', 'aaaaaaaaaaaaaaaaaaaa')}, native));
  assert.throws(() => reviewDefines({...source, SERVICE_ROLE_KEY: 'private'}, native));
  assert.throws(() => reviewDefines(source, {...native, project_info: {project_id: 'safepaths-92c3d'}}));
  assert.throws(() => reviewDefines(source, {...native, client: []}));
  const candidate = reviewDefines(source, native);
  assert.equal(candidate.APP_ENV, 'fieldtest'); assert.equal(Object.keys(candidate).filter(k => k.endsWith('_ENABLED') && candidate[k] === true).length, 5);
});
