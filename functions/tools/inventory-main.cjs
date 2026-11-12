// Read-only, bounded export. No rules, database, account or Storage writes.
const fs = require('node:fs'), path = require('node:path');
const project = 'safepaths-92c3d';
function options(args) {
  if (args.some(a => !a.startsWith('--credentials=') && a !== `--project=${project}`)) throw Error('Unknown option');
  const credential = args.find(a => a.startsWith('--credentials='))?.slice(14);
  if (!credential || !args.includes(`--project=${project}`)) throw Error('Explicit main project and local credential path required');
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw Error('Emulator settings are not allowed for a main inventory');
  return { credential };
}
function encode(value) {
  if (value == null || typeof value !== 'object') return value;
  if (typeof value.toMillis === 'function') return { $type: 'timestamp', seconds: value.seconds, nanoseconds: value.nanoseconds };
  if (Buffer.isBuffer(value)) return { $type: 'bytes', base64: value.toString('base64') };
  if (typeof value.latitude === 'number' && typeof value.longitude === 'number') return { $type: 'geopoint', latitude: value.latitude, longitude: value.longitude };
  if (value.firestore && typeof value.path === 'string') return { $type: 'reference', path: value.path };
  if (Array.isArray(value)) return value.map(encode);
  return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,encode(v)]));
}
function summarize(documents) {
  const collections = {}, blockers = [];
  let synthetic = 0, unscopedRoads = 0, legacyReports = 0;
  for (const d of documents) {
    const root = d.path.split('/')[0]; collections[root] = (collections[root] || 0) + 1;
    if (/test only|synthetic|spark proof|fixture/i.test(`${d.data.title || ''} ${d.data.name || ''} ${d.data.description || ''}`) || d.data.studyArea === 'nearby_test') synthetic++;
    if (root === 'roads' && d.data.studyArea == null) unscopedRoads++;
    if (root === 'reports' && !d.data.incidentId && ['pending','under_review'].includes(d.data.status)) legacyReports++;
  }
  if (synthetic) blockers.push('synthetic-or-nearby-records-require-review');
  if (unscopedRoads) blockers.push('road-area-and-geometry-review-required');
  if (legacyReports) blockers.push('legacy-active-reports-require-reconciliation');
  return { project, collections, documentCount: documents.length, syntheticCandidates: synthetic, unscopedRoads, legacyActiveReports: legacyReports, blockers };
}
async function main(args) {
  const opt = options(args), account = JSON.parse(fs.readFileSync(opt.credential,'utf8'));
  if (account.project_id !== project || !account.client_email?.endsWith(`@${project}.iam.gserviceaccount.com`)) throw Error('Credential mismatch');
  const {initializeApp,cert,deleteApp} = require('firebase-admin/app');
  const {getFirestore} = require('firebase-admin/firestore');
  const app = initializeApp({projectId:project,credential:cert(account)},'main-readonly-inventory');
  const dir = path.resolve('.usability-work-baseline/marulas-integration-20261101/private', String(Date.now()));
  const startedAt = new Date().toISOString(), documents = [];
  fs.mkdirSync(dir,{recursive:true});
  try {
    const db = getFirestore(app);
    async function walk(collection, depth = 0) {
      if (depth > 8) throw Error('Export depth limit');
      let cursor;
      for (;;) {
        let query = collection.orderBy('__name__').limit(200);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        for (const doc of page.docs) {
          if (documents.length >= 10000) throw Error('Export document limit');
          documents.push({path:doc.ref.path,updateTime:encode(doc.updateTime),data:encode(doc.data())});
          for (const child of await doc.ref.listCollections()) await walk(child,depth+1);
        }
        if (page.size < 200) break;
        cursor = page.docs.at(-1);
      }
    }
    for (const collection of await db.listCollections()) await walk(collection);
    const result = {...summarize(documents),startedAt,completedAt:new Date().toISOString(),readOnly:true,pointInTimeSnapshot:false,cloudWrites:0};
    fs.writeFileSync(path.join(dir,'firestore-export.json'),JSON.stringify({project,startedAt,documents},null,2),{flag:'wx'});
    fs.writeFileSync(path.join(dir,'inventory.json'),JSON.stringify(result,null,2),{flag:'wx'});
    // Counts only; document contents and credential paths never enter output.
    console.log(JSON.stringify({...result,backupDirectory:path.relative(process.cwd(),dir)}));
  } finally { await deleteApp(app); }
}
module.exports = {options,encode,summarize};
if (require.main === module) main(process.argv.slice(2)).catch(() => { console.error('Main inventory failed; no cloud data was changed. No credentials or record contents were logged.');process.exitCode=1; });
