// Read-only cloud inventory and private backup for a reviewed manual cleanup.
// No deletion/reset option is provided by this preparation tool.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {encode}=require('./inventory-main.cjs');
const projects=new Set(['safepaths-test','safepaths-92c3d']);
const activity=new Set(['reports','report_messages','report_clarifications','road_incidents','feedbacks','feedback_messages','alerts']);
const ledger=new Set(['report_requests','followup_requests','followup_audits','incident_rewards','report_slots','admin_requests','admin_audits','notification_outbox','clarification_requests','incident_requests','incident_audits','communication_requests','communication_audits','consensus_audits']);
function classify(doc) {
 const root=doc.path.split('/')[0];
 // Keep the history/idempotency of independent official road checks.
 if(root==='admin_audits' && doc.data.action==='road_review' && !doc.data.reportId && !doc.data.sourceReportId)return 'preserve';
 if(root==='admin_requests' && doc.data.result?.action==='road_review' && !doc.data.result.reportId && !doc.data.result.sourceReportId)return 'preserve';
 if(activity.has(root))return 'activity';
 if(ledger.has(root))return 'activity-ledger';
 if(root==='roads' && (/test only|synthetic|fixture/i.test(doc.data.name||'') || doc.data.proofFixtureVersion))return 'fixture-road-review';
 return 'preserve';
}
function summarize(documents,project) {
 const counts={},groups={};let pendingPush=0;
 for(const d of documents) {
  const root=d.path.split('/')[0];counts[root]=(counts[root]||0)+1;
  const group=classify(d);groups[group]=(groups[group]||0)+1;
  if(root==='notification_outbox' && d.data.dispatchable===true)pendingPush++;
 }
 const profiles=documents.filter(d=>/^users\/[^/]+$/.test(d.path));
 const roads=documents.filter(d=>/^roads\/[^/]+$/.test(d.path));
 return {project,documentCount:documents.length,collections:counts,groups,pendingPush,
  profilesWithReportRewards:profiles.filter(d=>d.data.trustScore!==50 || d.data.verifiedReports>0 || d.data.dismissedReports>0).length,
  roadsWithCommunityState:roads.filter(d=>d.data.communityCondition!=null).length,
  roadsLinkedToReports:roads.filter(d=>d.data.sourceReportId!=null || d.data.lastVerifiedReportId!=null).length,
  fixtureRoads:roads.filter(d=>classify(d)==='fixture-road-review').map(d=>({id:d.path.split('/')[1],name:d.data.name})),
  officialConditions:Object.fromEntries([...new Set(roads.map(d=>d.data.status))].map(status=>[status,roads.filter(d=>d.data.status===status).length]))};
}
async function main(args) {
 const options={};for(const arg of args){const m=/^--(project|credentials)=(.+)$/.exec(arg);if(!m||options[m[1]])throw Error('Explicit project and credential required');options[m[1]]=m[2];}
 if(!projects.has(options.project)||!options.credentials || process.env.FIRESTORE_EMULATOR_HOST)throw Error('Select one exact hosted app project');
 const key=JSON.parse(fs.readFileSync(options.credentials,'utf8'));
 if(key.project_id!==options.project || !key.client_email?.endsWith(`@${options.project}.iam.gserviceaccount.com`))throw Error('Credential mismatch');
 const {initializeApp,cert,deleteApp}=require('firebase-admin/app'),{getFirestore}=require('firebase-admin/firestore');
 const app=initializeApp({projectId:options.project,credential:cert(key)},'activity-backup');
 const dir=path.resolve('.usability-work-baseline/activity-cleanup-20261101/private',options.project,String(Date.now()));fs.mkdirSync(dir,{recursive:true});
 const documents=[],startedAt=new Date().toISOString();
 try {
  const db=getFirestore(app);
  async function walk(collection,depth=0) {
   if(depth>8)throw Error('Depth limit');let cursor;
   for(;;){let query=collection.orderBy('__name__').limit(200);if(cursor)query=query.startAfter(cursor);const page=await query.get();
    for(let start=0;start<page.docs.length;start+=8)await Promise.all(page.docs.slice(start,start+8).map(async doc=>{
     if(documents.length>=15000)throw Error('Document limit');documents.push({path:doc.ref.path,updateTime:encode(doc.updateTime),data:encode(doc.data())});
     for(const child of await doc.ref.listCollections())await walk(child,depth+1);
    }));
    if(page.size<200)break;cursor=page.docs.at(-1);
   }
  }
  for(const collection of await db.listCollections()){
   await walk(collection);
   console.log(JSON.stringify({phase:'backup-progress',project:options.project,collection:collection.id,documents:documents.length}));
  }
  const backup={project:options.project,startedAt,completedAt:new Date().toISOString(),documents},bytes=JSON.stringify(backup,null,2);
  fs.writeFileSync(path.join(dir,'firestore-backup.json'),bytes,{flag:'wx'});
  const summary=summarize(documents,options.project),plan={...summary,readOnly:true,cloudWrites:0,backupSha256:crypto.createHash('sha256').update(bytes).digest('hex'),backupDirectory:path.relative(process.cwd(),dir),proposedRecords:documents.filter(d=>classify(d)!=='preserve').map(d=>({path:d.path,group:classify(d),expectedUpdateTime:d.updateTime})),needsReview:['which activity collections to clear','whether to reset report rewards','whether to remove clearly labelled fixture roads','official road conditions and configuration are preserved by default','Storage objects are not deleted by this plan']};
  fs.writeFileSync(path.join(dir,'cleanup-plan.json'),JSON.stringify(plan,null,2),{flag:'wx'});
  const out={...summary,readOnly:true,cloudWrites:0,backupDirectory:plan.backupDirectory};delete out.fixtureRoads;
  console.log(JSON.stringify(out));
 } finally {await deleteApp(app);}
}
module.exports={classify,summarize,activity,ledger};
if(require.main===module)main(process.argv.slice(2)).catch(()=>{console.error('Cleanup inventory failed. No cloud records were deleted or changed; private details were not logged.');process.exitCode=1;});
