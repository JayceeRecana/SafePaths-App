// Offline plan from the private read-only export. This script never connects
// to Firebase/Supabase and has no apply/deployment option.
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const {lines} = require('../domain.cjs');
const project = 'safepaths-92c3d';
function plan(snapshot) {
  if (snapshot?.project !== project || !Array.isArray(snapshot.documents)) throw Error('Main export required');
  const roads = snapshot.documents.filter(d => /^roads\/[^/]+$/.test(d.path));
  if (!roads.length || roads.length > 1000) throw Error('Road inventory exceeds the reviewed capstone envelope');
  const blockers = [], metadata = [];
  for (const doc of roads) {
    const road = doc.data, segments = lines(road.geometry), points = segments.flat();
    const usable = segments.length && points.every(p => Number.isFinite(p[1]) && Number.isFinite(p[0]));
    const overlaps = usable && points.some(([lng,lat]) => lat >= 14.666 && lat <= 14.6855 && lng >= 120.968 && lng <= 120.9995);
    if (!overlaps || road.studyArea && road.studyArea !== 'marulas' || /test only|synthetic|fixture/i.test(road.name || '')) {
      blockers.push({path:doc.path,reason:'road-area-or-geometry-review'});continue;
    }
    // Preserve status, official verification, notes, timestamps, IDs and links.
    if (road.studyArea !== 'marulas') metadata.push({path:doc.path,expectedUpdateTime:doc.updateTime,patch:{studyArea:'marulas'}});
  }
  for (const d of snapshot.documents.filter(d => /^reports\/[^/]+$/.test(d.path))) {
    if (['pending','under_review'].includes(d.data.status) && !d.data.incidentId) blockers.push({path:d.path,reason:'legacy-active-report'});
  }
  return {project,area:'marulas',roadCount:roads.length,roadMetadata:metadata,blockers,
    controls:{'system/core_setup':{version:1,studyArea:'marulas',roadCount:roads.length},
      'system/communications':{enabled:true},'system/media':{enabled:true},'system/road_maintenance':{enabled:true},
      'system/backend_rollout':{enabled:false,version:1,studyArea:'marulas'}},
    constraints:{deleteRecords:false,changeConditions:false,copyTestData:false,automaticRetention:false},
    releaseGates:['fresh-backup-and-update-time-checks','main-rules-and-indexes','main-private-storage-access-checks','main-service-secrets-and-disabled-schedules','legacy-photo-compatibility','beneficiary-destination-confirmation','controlled-main-candidate-acceptance']};
}
function main(args) {
  if (args.length !== 1 || !args[0].startsWith('--backup=')) throw Error('Provide one local backup path');
  const file = args[0].slice(9), snapshot = JSON.parse(fs.readFileSync(file,'utf8')), result = plan(snapshot);
  result.backupSha256 = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const dir = path.resolve('.usability-work-baseline/marulas-integration-20261101');fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,'main-migration-plan.json'),JSON.stringify(result,null,2));
  fs.writeFileSync(path.join(dir,'public-build-defines.json'),JSON.stringify({APP_ENV:'production',SAFEPATHS_BACKEND_ENABLED:true,
    SAFEPATHS_FIREBASE_PROJECT_ID:project,SAFEPATHS_BACKEND_URL:'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-main',SAFEPATHS_FOLLOWUPS_ENABLED:false},null,2));
  console.log(JSON.stringify({project,roads:result.roadCount,metadataPatches:result.roadMetadata.length,blockerCount:result.blockers.length,cloudWrites:0,mainActivated:false}));
}
module.exports = {plan};
if (require.main === module) {try {main(process.argv.slice(2));} catch (_) {console.error('Offline main plan failed; nothing was deployed or changed online.');process.exitCode=1;}}
