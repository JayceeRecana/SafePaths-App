const { test, before } = require('node:test');
const assert = require('node:assert/strict');
let createReportFollowups, createAdminWorkflow, createReportClarifications, serverTime;
before(async () => {
  ({ createReportFollowups } = await import('../../supabase/functions/_shared/report_followups.mjs'));
  ({ createAdminWorkflow } = await import('../../supabase/functions/_shared/admin_workflow.mjs'));
  ({ createReportClarifications } = await import('../../supabase/functions/_shared/report_clarifications.mjs'));
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
  const admin = createAdminWorkflow({ db, clock: () => now, followupsEnabled: false });
  const clarification = createReportClarifications({ db, photos, clock: () => now });
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
  return { docs, db, api, admin, clarification, submit, review, requestId, advance: (ms = 360000) => now += ms };
}
async function act(f, action, extra={}) {
 const ctx = await f.admin.context('admin', {reportId: rootId});
 const payload = {reportId:rootId, action, requestId:f.requestId(), contextToken:ctx.token, note:'Evidence checked with resident and local staff.', ...extra};
 return {result:await f.admin.action('admin',payload), payload};
}
test('clarification round trip preserves original evidence, returns same report to queue, and awards nothing', async()=>{
 const f=fixture(); const original=structuredClone(f.docs.get(`reports/${rootId}`));
 const {payload:request}=await act(f,'request_clarification',{note:'Please clarify the time this photo was taken.'});
 assert.equal(f.docs.get(`reports/${rootId}`).status,'waiting_resident');
 assert.equal((await f.admin.action('admin',request)).replay,true);
 const ctx=await f.clarification.context('resident',{reportId:rootId});
 const payload={reportId:rootId,clarificationRequestId:ctx.requestId,requestId:f.requestId(),message:'The photo was taken during the original observation.',imageUrl:'resident-photo-clearer',photoObservedAt:original.observedAt.toISOString(),photoMatchesObservation:true};
 await f.clarification.reply('resident',payload);
 assert.equal((await f.clarification.reply('resident',payload)).replay,true);
 const report=f.docs.get(`reports/${rootId}`);
 assert.equal(report.status,'pending');
 for(const key of ['createdAt','observedAt','imageUrl','description']) assert.deepEqual(report[key],original[key]);
 assert.equal(f.docs.get('users/resident').trustScore,50);
 assert.equal(f.docs.get('roads/road').status,'not_passable');
 assert.equal([...f.docs.keys()].filter(p=>p.startsWith('reports/')).length,1);
 assert.equal((await f.clarification.context('resident',{reportId:rootId})).canReply,false);
 await assert.rejects(()=>f.clarification.reply('resident',{...payload,message:'Changed content after uncertain save'}),{code:'already-exists'});
});
test('clarification is owner scoped; stale decisions and wrong photo owners cannot mutate',async()=>{
 const f=fixture(); await act(f,'request_clarification');
 const ctx=await f.clarification.context('resident',{reportId:rootId});
 await assert.rejects(()=>f.clarification.context('other',{reportId:rootId}),{code:'permission-denied'});
 const reviewContext=await f.admin.context('admin',{reportId:rootId});
 const payload={reportId:rootId,clarificationRequestId:ctx.requestId,requestId:f.requestId(),message:'The picture shows the original morning conditions.'};
 await assert.rejects(()=>f.clarification.reply('other',payload),{code:'permission-denied'});
 await assert.rejects(()=>f.clarification.reply('resident',{...payload,imageUrl:'other-photo-x',photoObservedAt:new Date('2026-10-26').toISOString(),photoMatchesObservation:true}));
 await f.clarification.reply('resident',payload);
 await assert.rejects(()=>f.admin.action('admin',{reportId:rootId,action:'verify',requestId:f.requestId(),contextToken:reviewContext.token,observationOnly:true,note:'Evidence checked before resident replied.'}),{code:'failed-precondition'});
});
test('historical observation verifies without changing road or another report and rewards once',async()=>{
 const f=fixture(); f.docs.get(`reports/${rootId}`).incidentId='older-incident';
 const road=structuredClone(f.docs.get('roads/road'));
 const {result,payload}=await act(f,'verify',{observationOnly:true});
 assert.equal(result.pointsAwarded,10);assert.equal(result.observationOnly,true);
 assert.deepEqual(f.docs.get('roads/road'),road);
 assert.equal(f.docs.get(`reports/${rootId}`).status,'verified');
 assert.equal((await f.admin.action('admin',payload)).replay,true);
 assert.equal(f.docs.get('users/resident').trustScore,60);
 await assert.rejects(()=>act(f,'verify',{observationOnly:true}),{code:'failed-precondition'});
});
test('reopening a road leaves each other report and clarification awaiting its own decision',async()=>{
 const f=fixture(); f.docs.set('reports/second',{...f.docs.get(`reports/${rootId}`),userId:'other',status:'waiting_resident'});
 await act(f,'verify',{roadStatus:'passable',verifiedCurrentConditions:true});
 assert.equal(f.docs.get('roads/road').status,'passable');
 assert.equal(f.docs.get('reports/second').status,'waiting_resident');
});
test('unable to verify requires a reason, preserves restrictions, and never deducts trust',async()=>{
 const f=fixture();
 await assert.rejects(()=>act(f,'dismiss',{reason:'unable_to_verify',note:''}),{code:'invalid-argument'});
 await act(f,'dismiss',{reason:'unable_to_verify'});
 assert.equal(f.docs.get(`reports/${rootId}`).dismissReason,'unable_to_verify');
 assert.equal(f.docs.get('users/resident').trustScore,50);
 assert.equal(f.docs.get('roads/road').status,'not_passable');
});
test('concurrent admins can complete only one decision; self-review forbidden even without followups',async()=>{
 const f=fixture();const ctx=await f.admin.context('admin',{reportId:rootId});
 const action={action:'verify',reportId:rootId,contextToken:ctx.token,observationOnly:true,note:'Evidence checked with local staff.'};
 const results=await Promise.allSettled([f.admin.action('admin',{...action,requestId:f.requestId()}),f.admin.action('admin',{...action,requestId:f.requestId()})]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(f.docs.get('users/resident').trustScore,60);
 const g=fixture();g.docs.get(`reports/${rootId}`).userId='admin';
 await assert.rejects(()=>act(g,'verify',{observationOnly:true}),{code:'self-review'});
});


async function roadAction(f, sourceReportId, extra = {}) {
 const details={roadIds:['road'],...(sourceReportId ? {sourceReportId} : {})};
 const context=await f.admin.context('admin',details);
 const payload={...details,action:'road_review',requestId:f.requestId(),contextToken:context.token,
  roadStatus:'passable',verifiedCurrentConditions:true,note:'CCTV checked by command-center staff at the recorded time.',...extra};
 return {context,payload,result:await f.admin.action('admin',payload)};
}
test('a later road update retains the verified source report and privately closes the loop without another reward',async()=>{
 const f=fixture();await act(f,'verify',{observationOnly:true});
 const before=structuredClone(f.docs.get(`reports/${rootId}`));
 const messageCount=[...f.docs.keys()].filter(p=>p.startsWith('report_messages/')).length;
 const {context,payload,result}=await roadAction(f,rootId);
 assert.equal(context.reportRoadLinkSupported,true);assert.equal(context.report,null);
 assert.deepEqual(context.sourceReport,{id:rootId,roadId:'road',status:'verified'});
 assert.equal(result.sourceReportId,rootId);assert.equal(result.pointsAwarded,0);
 assert.equal(f.docs.get('roads/road').status,'passable');
 assert.equal(f.docs.get('users/resident').trustScore,60);
 const saved=f.docs.get(`reports/${rootId}`);
 for(const key of ['status','reviewedAt','pointsAwarded','description','imageUrl','observedAt','createdAt']) assert.deepEqual(saved[key],before[key]);
 const audits=[...f.docs.values()].filter(v=>v.action==='road_review' && v.performedByUid);
 assert.equal(audits.length,1);assert.equal(audits[0].reportId,null);assert.equal(audits[0].sourceReportId,rootId);
 assert.deepEqual(audits[0].roadIds,['road']);assert.equal(audits[0].performedByUid,'admin');
 assert.equal((await f.admin.action('admin',payload)).replay,true);
 assert.equal([...f.docs.keys()].filter(p=>p.startsWith('report_messages/')).length,messageCount+1);
 const linked=[...f.docs.entries()].filter(([p,v])=>p.startsWith('report_messages/') && v.message.startsWith('Road update linked'));
 assert.equal(linked.length,1);assert.equal(linked[0][1].reportId,rootId);assert.equal(linked[0][1].userId,'resident');
 assert.match(linked[0][1].message,/existing review outcome was not changed/);
 assert.equal(Object.hasOwn(f.docs.get('roads/road'),'sourceReportId'),false);
});
test('direct monitoring can update a road without a source report or a fabricated report record',async()=>{
 const f=fixture();const {result}=await roadAction(f,null,{roadStatus:'not_passable'});
 assert.equal(result.sourceReportId,undefined);assert.equal(result.pointsAwarded,0);
 const audit=[...f.docs.values()].find(v=>v.action==='road_review' && v.performedByUid);
 assert.equal(audit.sourceReportId,null);assert.equal(audit.reportId,null);
 assert.equal([...f.docs.keys()].filter(p=>p.startsWith('reports/')).length,1);
 assert.equal(f.docs.get(`reports/${rootId}`).status,'pending');assert.equal(f.docs.get('users/resident').trustScore,50);
});
test('a contextual link to pending evidence never verifies it and does not duplicate its reopen message',async()=>{
 const f=fixture();const original=structuredClone(f.docs.get(`reports/${rootId}`));await roadAction(f,rootId);
 const saved=f.docs.get(`reports/${rootId}`);
 assert.equal(saved.status,'pending');assert.equal(saved.reviewedAt,undefined);assert.equal(saved.pointsAwarded,undefined);
 for(const key of ['description','imageUrl','observedAt','createdAt'])assert.deepEqual(saved[key],original[key]);
 assert.equal([...f.docs.keys()].filter(p=>p.startsWith('report_messages/')).length,1);
 assert.equal([...f.docs.keys()].filter(p=>p.startsWith('notification_outbox/')).length,1);
 assert.match([...f.docs.values()].find(v=>v.message?.startsWith('Road update linked')).message,/still awaits its own review/);
});
test('source report links reject missing reports, mismatched roads and ambiguous bulk or verification payloads',async()=>{
 const f=fixture();
 await assert.rejects(()=>f.admin.context('admin',{roadIds:['road'],sourceReportId:'missing'}),{code:'not-found'});
 await assert.rejects(()=>f.admin.context('admin',{roadIds:['road'],sourceReportId:'../escape'}),{code:'invalid-argument'});
 await assert.rejects(()=>f.admin.context('admin',{roadIds:['road','second'],sourceReportId:rootId}),{code:'invalid-argument'});
 await assert.rejects(()=>f.admin.context('admin',{reportId:rootId,sourceReportId:rootId}),{code:'invalid-argument'});
 f.docs.get(`reports/${rootId}`).roadId='another-road';
 await assert.rejects(()=>f.admin.context('admin',{roadIds:['road'],sourceReportId:rootId}),{code:'failed-precondition'});
 assert.equal(f.docs.get('roads/road').status,'not_passable');
});
test('a linked context binds report identity and rejects changed or deleted source data before any save',async()=>{
 const f=fixture();const input={roadIds:['road'],sourceReportId:rootId};const ctx=await f.admin.context('admin',input);
 const payload={...input,action:'road_review',requestId:f.requestId(),contextToken:ctx.token,roadStatus:'passable',verifiedCurrentConditions:true,note:'Field staff checked the current road condition.'};
 const second='c'.repeat(64);f.docs.set(`reports/${second}`,structuredClone(f.docs.get(`reports/${rootId}`)));
 await assert.rejects(()=>f.admin.action('admin',{...payload,sourceReportId:second}),{code:'failed-precondition'});
 f.docs.get(`reports/${rootId}`).description='A newer clarification arrived.';
 await assert.rejects(()=>f.admin.action('admin',payload),{code:'failed-precondition'});
 f.docs.delete(`reports/${rootId}`);
 await assert.rejects(()=>f.admin.action('admin',payload),{code:'not-found'});
 assert.equal(f.docs.get('roads/road').status,'not_passable');
 assert.equal([...f.docs.keys()].filter(p=>p.startsWith('admin_audits/')).length,0);
});
test('a source reference never bypasses administrator permission or becomes a report-verification action',async()=>{
 const f=fixture();const input={roadIds:['road'],sourceReportId:rootId};const ctx=await f.admin.context('admin',input);
 await assert.rejects(()=>f.admin.context('resident',input),{code:'permission-denied'});
 const payload={...input,action:'road_review',requestId:f.requestId(),contextToken:ctx.token,roadStatus:'passable',verifiedCurrentConditions:true,note:'Current conditions checked from the command center.'};
 await assert.rejects(()=>f.admin.action('resident',payload),{code:'permission-denied'});
 await assert.rejects(()=>f.admin.action('admin',{...payload,action:'verify',reportId:rootId}),{code:'invalid-argument'});
 assert.equal(f.docs.get('roads/road').status,'not_passable');assert.equal(f.docs.get('users/resident').trustScore,50);
});


test('new resident incident activity does not discard an independent current-road check',async()=>{
 const f=fixture();const input={roadIds:['road']};const ctx=await f.admin.context('admin',input);
 f.docs.get('road_incidents/road').revision=7;
 f.docs.get('road_incidents/road').state='reported_flooding';
 const another='d'.repeat(64);f.docs.set(`reports/${another}`,{...structuredClone(f.docs.get(`reports/${rootId}`)),userId:'other'});
 const result=await f.admin.action('admin',{...input,action:'road_review',requestId:f.requestId(),contextToken:ctx.token,roadStatus:'not_passable',verifiedCurrentConditions:true,note:'Field staff checked current flooding just now.'});
 assert.equal(result.pointsAwarded,0);assert.equal(f.docs.get('roads/road').status,'not_passable');
 assert.equal(f.docs.get('road_incidents/road').revision,8);
 assert.equal(f.docs.get(`reports/${rootId}`).status,'pending');assert.equal(f.docs.get(`reports/${another}`).status,'pending');
 assert.equal(f.docs.get('users/resident').trustScore,50);
});

test('a rapid second admin road change rejects a previously loaded current-road check',async()=>{
 const f=fixture();const input={roadIds:['road']};const ctx=await f.admin.context('admin',input);
 await roadAction(f,null,{roadStatus:'partial'});
 await assert.rejects(()=>f.admin.action('admin',{...input,action:'road_review',requestId:f.requestId(),contextToken:ctx.token,roadStatus:'passable',verifiedCurrentConditions:true,note:'Older field check must not override the new status.'}),{code:'failed-precondition'});
 assert.equal(f.docs.get('roads/road').status,'partial');
});

test('resident incident changes still invalidate a report-evidence review',async()=>{
 const f=fixture();const ctx=await f.admin.context('admin',{reportId:rootId});
 f.docs.get('road_incidents/road').revision++;
 await assert.rejects(()=>f.admin.action('admin',{reportId:rootId,action:'verify',requestId:f.requestId(),contextToken:ctx.token,observationOnly:true,note:'Evidence was checked before the new observation.'}),{code:'failed-precondition'});
 assert.equal(f.docs.get(`reports/${rootId}`).status,'pending');assert.equal(f.docs.get('users/resident').trustScore,50);
});
