// Local candidate configuration only. This never builds, installs or deploys.
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const backend = 'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof';
function reviewDefines(source, native) {
  assert.ok(source && typeof source === 'object' && !Array.isArray(source));
  assert.deepEqual(Object.keys(source).sort(), ['SPARK_PROOF_BACKEND_URL', 'SPARK_PROOF_FIREBASE_PROJECT_ID']);
  assert.equal(source.SPARK_PROOF_FIREBASE_PROJECT_ID, 'safepaths-test');
  assert.equal(source.SPARK_PROOF_BACKEND_URL, backend);
  assert.equal(native.project_info.project_id, 'safepaths-test');
  assert.ok(native.client.some(c => c.client_info.android_client_info.package_name === 'com.safepaths.safepaths_app.test'));
  return {APP_ENV: 'fieldtest', ...source, SPARK_PROOF_REPORTS_ENABLED: true, SPARK_PROOF_CORE_ENABLED: true, SPARK_PROOF_COMMUNICATIONS_ENABLED: true, SPARK_PROOF_MEDIA_ENABLED: true, SPARK_PROOF_PUSH_ENABLED: true};
}
function main(args) {
  assert.deepEqual(args, []);
  const source = JSON.parse(fs.readFileSync('.usability-work-baseline/spark-proof-setup/public-build-defines.json', 'utf8'));
  const native = JSON.parse(fs.readFileSync('android/app/src/fieldtest/google-services.json', 'utf8'));
  const result = reviewDefines(source, native), dir = path.resolve('.usability-work-baseline/review-candidate');
  fs.mkdirSync(dir, {recursive: true}); fs.writeFileSync(path.join(dir, 'public-build-defines.json'), JSON.stringify(result, null, 2));
  const evidence = {project: 'safepaths-test', preparedAt: new Date().toISOString(), candidateFile: '.usability-work-baseline/review-candidate/public-build-defines.json', featureFlagsEnabled: 5, APKBuildApproved: false, APKBuilt: false, deployed: false, mainProjectModified: false};
  fs.writeFileSync('.usability-work-baseline/integration-review-config.json', JSON.stringify(evidence, null, 2)); console.log(JSON.stringify(evidence));
}
module.exports = {reviewDefines};
if (require.main === module) {try {main(process.argv.slice(2));} catch (_) {console.error('Candidate configuration rejected; no build or deployment was attempted.'); process.exitCode = 1;}}
