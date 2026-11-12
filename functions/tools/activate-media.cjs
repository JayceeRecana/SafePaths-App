// Coordinated isolated-test rollout only. The main Firebase project is rejected.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {initializeApp, cert, deleteApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
async function main(args) {
  assert.ok(args.includes('--apply'));
  assert.ok(args.every(x => x === '--apply' || x.startsWith('--credentials=')));
  const file = args.find(x => x.startsWith('--credentials='))?.slice(14);
  assert.ok(file);
  const key = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.equal(key.project_id, 'safepaths-test');
  assert.ok(key.client_email.endsWith('@safepaths-test.iam.gserviceaccount.com'));
  const preparation = JSON.parse(fs.readFileSync('.usability-work-baseline/media-preparation.json', 'utf8'));
  assert.equal(preparation.project, key.project_id);
  assert.equal(preparation.apply, true);
  assert.ok(fs.existsSync(preparation.backup));
  const app = initializeApp({projectId: key.project_id, credential: cert(key)}, 'media-activation');
  try {
    const db = getFirestore(app);
    await db.runTransaction(async tx => {
      const paths = ['system/communications', 'system/media', ...['resident', 'other', 'admin'].map(x => `users/spark-proof-${x}`)];
      const docs = await Promise.all(paths.map(p => tx.get(db.doc(p))));
      assert.equal(docs[0].data()?.enabled, true);
      assert.equal(docs[1].data()?.version, 1);
      assert.ok(docs.slice(2).every(d => d.data()?.proofFixtureVersion === 1));
      tx.set(docs[1].ref, {enabled: true, activatedAt: FieldValue.serverTimestamp()}, {merge: true});
    });
    const result = {project: key.project_id, enabled: true, activatedAt: new Date().toISOString(), mainProjectModified: false};
    fs.writeFileSync('.usability-work-baseline/media-activation.json', JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result));
  } finally { await deleteApp(app); }
}
main(process.argv.slice(2)).catch(() => { console.error('Isolated media activation failed; private details were not logged.'); process.exitCode = 1; });
