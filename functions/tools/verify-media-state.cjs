// Read-only verification of the isolated deployment. Output contains no secrets.
const fs = require('node:fs'), assert = require('node:assert/strict');
const {initializeApp, cert, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
async function main(args) {
  assert.equal(args.length, 1); assert.ok(args[0].startsWith('--credentials='));
  assert.ok(!process.env.FIRESTORE_EMULATOR_HOST && !process.env.FIREBASE_AUTH_EMULATOR_HOST);
  const key = JSON.parse(fs.readFileSync(args[0].slice(14), 'utf8')); assert.equal(key.project_id, 'safepaths-test');
  const credential = cert(key), app = initializeApp({projectId: key.project_id, credential}, 'media-final-read');
  try {
    const db = getFirestore(app), paths = ['system/media', 'system/communications', ...['resident', 'other', 'admin'].map(x => `users/spark-proof-${x}`)];
    const profiles = await Promise.all(paths.map(p => db.doc(p).get()));
    assert.ok(profiles.slice(2).every(d => d.data()?.proofFixtureVersion === 1));
    assert.equal(profiles[0].data()?.enabled, true); assert.equal(profiles[1].data()?.enabled, true);
    assert.equal(profiles[2].data()?.photoUrl ?? null, null);
    const active = await db.collection('push_devices').where('active', '==', true).limit(1).get(); assert.equal(active.size, 0);
    const response = await fetch('https://firestore.googleapis.com/v1/projects/safepaths-test/databases/(default)/collectionGroups/-/indexes', {redirect: 'error', signal: AbortSignal.timeout(20000), headers: {authorization: `Bearer ${(await credential.getAccessToken()).access_token}`}});
    assert.equal(response.status, 200); const indexes = (await response.json()).indexes;
    assert.equal(indexes.length, 14); assert.ok(indexes.every(i => i.state === 'READY'));
    const collections = ['media_uploads', 'media_limits', 'profile_requests'];
    const counts = await Promise.all(collections.map(name => db.collection(name).count().get()));
    const result = {project: key.project_id, checkedAt: new Date().toISOString(), mediaControlEnabled: true, communicationsControlEnabled: true, allowlistedSyntheticProfiles: 3, syntheticAvatarRemoved: true, activePhoneRegistrations: 0, indexesReady: indexes.length, serverManagedRecordCounts: Object.fromEntries(collections.map((c, i) => [c, counts[i].data().count])), mainProjectModified: false, APKBuilt: false};
    fs.writeFileSync('.usability-work-baseline/media-cloud-state.json', JSON.stringify(result, null, 2)); console.log(JSON.stringify(result));
  } finally {await deleteApp(app);}
}
main(process.argv.slice(2)).catch(() => {console.error('Isolated media state verification failed; private details were not logged.'); process.exitCode = 1;});
