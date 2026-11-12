// Requires the existing Windows Firebase CLI installation and `firebase login`.
// Uses its session in memory; never prints or exports credentials.
const fs = require('node:fs');
const path = require('node:path');
async function main() {
  const root = path.resolve(__dirname, '..');
  const test = JSON.parse(fs.readFileSync(path.join(root, 'android/app/src/fieldtest/google-services.json'), 'utf8'));
  const prod = JSON.parse(fs.readFileSync(path.join(root, 'android/app/google-services.json'), 'utf8'));
  const project = test.project_info.project_id;
  if (!project || project === prod.project_info.project_id ||
      !test.client.some(c => c.client_info.android_client_info.package_name === 'com.safepaths.safepaths_app.test')) {
    throw new Error('Separate test project and Android application are required.');
  }
  const auth = require(path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth.js'));
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error('Run firebase login first.');
  const tokens = account.tokens.expires_at > Date.now() + 60000 ? account.tokens
    : await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
  const headers = {Authorization: `Bearer ${tokens.access_token}`, 'Content-Type': 'application/json'};
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(project)}/databases/(default)/documents/system/weather`;
  const existing = await fetch(url, {headers});
  if (existing.ok) { console.log(`Weather already configured in ${project}; preserved.`); return; }
  if (existing.status !== 404) throw new Error(`Weather read failed: HTTP ${existing.status}`);
  const fields = {currentState: {stringValue: 'clear'}, isOverrideMode: {booleanValue: true},
    precipitationIntensity: {doubleValue: 0}, windSpeed: {doubleValue: 0}};
  const response = await fetch(`${url}?currentDocument.exists=false`, {
    method: 'PATCH', headers, body: JSON.stringify({fields}),
  });
  if (!response.ok) throw new Error(`Weather initialization failed: HTTP ${response.status}`);
  console.log(`Clear test weather initialized in ${project}.`);
}
main().catch(e => { console.error(e.message); process.exitCode = 1; });
