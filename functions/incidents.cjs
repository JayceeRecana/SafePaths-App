const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {FieldValue, FieldPath, Timestamp} = require('firebase-admin/firestore');
const {hash, millis} = require('./domain.cjs');

const MAX_AGE = 24 * 60 * 60 * 1000;
const choices = ['still_flooded', 'appears_passable', 'cannot_confirm'];
const stamp = () => FieldValue.serverTimestamp();
const observationTime = report => millis(report.observedAt || report.lastUpdatedByUser || report.createdAt);
const needsCaution = state => ['reported_flooding', 'under_verification', 'outdated', 'admin_confirmed'].includes(state);

function newIncident(roadId, incidentId, observedAt) {
  return {roadId, incidentId, state: 'reported_flooding', startedAt: stamp(),
    lastObservedAt: observedAt, lastConfirmedAt: null, reviewedAt: null,
    counts: {still_flooded: 0, appears_passable: 0, cannot_confirm: 0},
    reviewRequired: true, revision: 1};
}

function createIncidentApi({db, authenticated, options}) {
  function operation(data) {
    if (!data || !/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId ?? '') ||
        typeof data.roadId !== 'string' || !data.roadId || data.roadId.length > 128 || data.roadId.includes('/') ||
        typeof data.incidentId !== 'string' || !/^[a-f0-9]{64}$/.test(data.incidentId)) {
      throw new HttpsError('invalid-argument', 'Invalid incident request.');
    }
  }

  async function mutate(request, review) {
    const uid = await authenticated(request);
    const data = request.data;
    operation(data);
    if (review) {
      if (!['passable', 'partial', 'not_passable'].includes(data.roadStatus) ||
          data.verifiedCurrentConditions !== true || typeof data.note !== 'string' ||
          data.note.trim().length < 10 || data.note.length > 1000 || !Number.isInteger(data.revision)) {
        throw new HttpsError('invalid-argument', 'Verify current conditions and provide a review note (10–1000 characters).');
      }
    } else if (!choices.includes(data.choice)) {
      throw new HttpsError('invalid-argument', 'Choose a valid observation.');
    }
    const observedAt = review ? null : Date.parse(data.observedAt);
    if (!review && !Number.isFinite(observedAt)) throw new HttpsError('invalid-argument', 'Invalid observation time.');
    // A durable receipt makes lost-response retries harmless, even after reopening.
    const receiptRef = db.collection('incident_requests').doc(hash(`${uid}|${data.requestId}`));
    const fingerprint = hash(JSON.stringify({...data, operation: review ? 'admin_review' : 'community_observation'}));
    const incidentRef = db.collection('road_incidents').doc(data.roadId);
    const roadRef = db.collection('roads').doc(data.roadId);
    const responseRef = incidentRef.collection('responses').doc(hash(`${data.incidentId}|${uid}`));
    const auditRef = db.collection('incident_audits').doc(hash(`${uid}|${data.requestId}`));
    return db.runTransaction(async tx => {
      const [receipt, incidentDoc, roadDoc, profile] = await Promise.all([
        tx.get(receiptRef), tx.get(incidentRef), tx.get(roadRef), tx.get(db.collection('users').doc(uid)),
      ]);
      if (review && profile.data()?.role !== 'admin') throw new HttpsError('permission-denied', 'Administrator access required.');
      if (receipt.exists) {
        if (receipt.data().fingerprint !== fingerprint) throw new HttpsError('already-exists', 'Request identifier already used.');
        return {saved: true, replay: true};
      }
      const incident = incidentDoc.data();
      if (!roadDoc.exists || !incident || incident.incidentId !== data.incidentId || incident.state === 'resolved') {
        throw new HttpsError('failed-precondition', 'This incident has changed or was resolved. Refresh the road details.');
      }
      let result;
      if (review) {
        // Do not clear a hazard when a new report/observation arrived during review.
        if (incident.revision !== data.revision) throw new HttpsError('failed-precondition', 'New information arrived. Review the latest observations before confirming.');
        const reports = await tx.get(db.collection('reports').where('incidentId', '==', data.incidentId));
        const state = data.roadStatus === 'passable' ? 'resolved' : 'admin_confirmed';
        result = {state, reviewRequired: false, reviewedAt: stamp(), reviewNote: data.note.trim(),
          lastObservedAt: stamp(), revision: incident.revision + 1};
        tx.update(roadRef, {status: data.roadStatus, notes: data.note.trim(), updatedAt: stamp(),
          source: 'manual', isVerified: true, updatedByUid: uid,
          communityCondition: state, communityReviewedAt: stamp()});
        // Verification of the incident does not award reputation or call the original
        // flood report false simply because the water subsequently receded.
        for (const report of reports.docs) if (['pending', 'under_review', 'expired'].includes(report.data().status)) {
          tx.update(report.ref, {status: 'resolved', reviewedAt: stamp(), incidentReviewStatus: data.roadStatus});
        }
      } else {
        if (observedAt > Date.now() + 60000 || Date.now() - observedAt > 5 * 60000) {
          throw new HttpsError('failed-precondition', 'OBSERVATION_STALE: Observe current conditions safely and submit again.');
        }
        const [previous, ownReports] = await Promise.all([
          tx.get(responseRef),
          tx.get(db.collection('reports').where('incidentId', '==', data.incidentId).where('userId', '==', uid).limit(1)),
        ]);
        if (!ownReports.empty) throw new HttpsError('failed-precondition', 'You reported this incident. Submit an updated report instead of confirming your own report.');
        if (Date.now() - millis(previous.data()?.submittedAt) < 60000) {
          throw new HttpsError('resource-exhausted', 'Please wait one minute before updating your observation.');
        }
        const counts = {...incident.counts};
        if (previous.exists) counts[previous.data().choice] = Math.max(0, (counts[previous.data().choice] ?? 0) - 1);
        counts[data.choice] = (counts[data.choice] ?? 0) + 1;
        // An apparent reopening is always reviewed. Community votes never reopen roads.
        const state = data.choice === 'appears_passable' ? 'under_verification'
          : data.choice === 'still_flooded' && incident.state !== 'under_verification' ? 'reported_flooding' : incident.state;
        result = {counts, state, revision: incident.revision + 1,
          ...(data.choice !== 'cannot_confirm' ? {lastObservedAt: Timestamp.fromMillis(Math.max(observedAt, millis(incident.lastObservedAt))), reviewRequired: true} : {}),
          ...(data.choice === 'still_flooded' ? {lastConfirmedAt: Timestamp.fromMillis(Math.max(observedAt, millis(incident.lastConfirmedAt)))} : {})};
        tx.set(responseRef, {uid, incidentId: data.incidentId, choice: data.choice,
          observedAt: Timestamp.fromMillis(observedAt), submittedAt: stamp()});
        if (roadDoc.data().communityCondition !== state) tx.update(roadRef, {communityCondition: state});
      }
      tx.update(incidentRef, result);
      tx.create(receiptRef, {fingerprint, createdAt: stamp()});
      tx.create(auditRef, {roadId: data.roadId, incidentId: data.incidentId, performedByUid: uid,
        action: review ? 'admin_review' : 'community_observation',
        ...(review ? {roadStatus: data.roadStatus, note: data.note.trim()} : {choice: data.choice, observedAt: Timestamp.fromMillis(observedAt)}), timestamp: stamp()});
      return {saved: true, replay: false};
    }).catch(error => {
      if ([10, 14, 4].includes(error.code)) throw new HttpsError('unavailable', 'Server is busy. Retry to confirm your observation or review.');
      throw error;
    });
  }

  // Also migrates pre-existing reports. Expiration runs before the weather check,
  // so an unavailable weather provider cannot leave old reports looking current.
  async function reconcile() {
    // Migrate historical records once, in bounded pages, rather than scanning
    // the entire report history every minute for the lifetime of the app.
    const migrationRef = db.doc('system/incident_migration');
    const migration = (await migrationRef.get()).data();
    let legacyPage;
    if (!migration?.complete) {
      let query = db.collection('reports').where('status', 'in', ['pending', 'under_review', 'expired'])
        .orderBy(FieldPath.documentId()).limit(100);
      if (migration?.cursor) query = query.startAfter(migration.cursor);
      legacyPage = await query.get();
    }
    const grouped = new Map();
    for (const doc of legacyPage?.docs ?? []) if (doc.data().roadId) {
      const roadId = doc.data().roadId;
      if (!grouped.has(roadId)) grouped.set(roadId, []);
      if (!doc.data().incidentId) grouped.get(roadId).push(doc.ref);
    }
    for (const [roadId, legacyRefs] of grouped) if (legacyRefs.length) {
      await db.runTransaction(async tx => {
        const roadRef = db.collection('roads').doc(roadId), incidentRef = db.collection('road_incidents').doc(roadId);
        const [road, incidentDoc, ...legacy] = await Promise.all([tx.get(roadRef), tx.get(incidentRef), ...legacyRefs.map(ref => tx.get(ref))]);
        if (!road.exists) return;
        const eligible = legacy.filter(doc => doc.exists && !doc.data().incidentId &&
          !(road.data().isVerified && road.data().status === 'passable' && millis(road.data().updatedAt) > observationTime(doc.data())));
        if (!eligible.length || incidentDoc.data()?.state === 'resolved') return;
        const observedAt = Math.max(...eligible.map(doc => {
          const time = observationTime(doc.data());
          return time <= Date.now() + 60000 ? time : 0;
        }));
        const incidentId = incidentDoc.data()?.incidentId || hash(`legacy|${roadId}|${eligible[0].id}`);
        if (!incidentDoc.exists) {
          const state = !observedAt || Date.now() - observedAt >= MAX_AGE ? 'outdated' : 'reported_flooding';
          tx.set(incidentRef, {...newIncident(roadId, incidentId, Timestamp.fromMillis(observedAt)), state});
          tx.update(roadRef, {communityCondition: state, activeIncidentId: incidentId});
        } else {
          const current = incidentDoc.data();
          const latest = Math.max(observedAt, millis(current.lastObservedAt));
          const state = current.state === 'outdated' && Date.now() - latest < MAX_AGE ? 'reported_flooding' : current.state;
          tx.update(incidentRef, {lastObservedAt: Timestamp.fromMillis(latest), state,
            reviewRequired: true, revision: current.revision + 1});
          tx.update(roadRef, {communityCondition: state});
        }
        for (const doc of eligible) tx.update(doc.ref, {incidentId});
      });
    }
    if (legacyPage) await migrationRef.set({complete: legacyPage.size < 100,
      cursor: legacyPage.docs.at(-1)?.id || migration?.cursor || null, updatedAt: stamp()});
    const incidents = await db.collection('road_incidents')
      .where('state', 'in', ['reported_flooding', 'under_verification', 'admin_confirmed'])
      .where('lastObservedAt', '<=', Timestamp.fromMillis(Date.now() - MAX_AGE)).limit(200).get();
    for (const doc of incidents.docs) await db.runTransaction(async tx => {
      const current = await tx.get(doc.ref), incident = current.data();
      if (!incident || !needsCaution(incident.state) || incident.state === 'outdated' || Date.now() - millis(incident.lastObservedAt) < MAX_AGE) return;
      const roadRef = db.collection('roads').doc(doc.id), road = await tx.get(roadRef);
      tx.update(doc.ref, {state: 'outdated', reviewRequired: true, revision: incident.revision + 1});
      if (road.exists) tx.update(roadRef, {communityCondition: 'outdated'});
    });
    // Age uses observation time, rather than refreshing old evidence when an admin opens it.
    const reports = await db.collection('reports').where('status', 'in', ['pending', 'under_review']).get();
    for (const doc of reports.docs) if (['pending', 'under_review'].includes(doc.data().status) && Date.now() - observationTime(doc.data()) >= MAX_AGE) {
      await db.runTransaction(async tx => {
        const current = await tx.get(doc.ref);
        if (current.exists && ['pending', 'under_review'].includes(current.data().status) && Date.now() - observationTime(current.data()) >= MAX_AGE) tx.update(doc.ref, {status: 'expired'});
      });
    }
  }

  return {observeRoadIncident: onCall(options, request => mutate(request, false)),
    reviewRoadIncident: onCall(options, request => mutate(request, true)), reconcile};
}
module.exports = {createIncidentApi, newIncident, observationTime, MAX_AGE, needsCaution};
