const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, Timestamp} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {getAuth} = require('firebase-admin/auth');
const {getStorage} = require('firebase-admin/storage');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {hash, millis, clamp, validateReport, roadDistance, confidence, calculateRisks} = require('./domain.cjs');
const {createIncidentApi, newIncident, observationTime, MAX_AGE} = require('./incidents.cjs');
initializeApp();
const db = getFirestore();
const options = {region: 'us-central1', timeoutSeconds: 30, maxInstances: 10};
const nowStamp = () => FieldValue.serverTimestamp();
async function authenticated(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Please sign in again.');
  if (request.auth.token?.email_verified !== true) throw new HttpsError('permission-denied', 'Verify your email before continuing.');
  let user;
  try { user = await getAuth().getUser(request.auth.uid); }
  catch (_) { throw new HttpsError('unauthenticated', 'Account is unavailable. Please sign in again.'); }
  const validAfter = Math.floor(Date.parse(user.tokensValidAfterTime || '1970-01-01') / 1000);
  if (user.disabled || !user.emailVerified || !Number.isFinite(request.auth.token.auth_time) || request.auth.token.auth_time < validAfter) {
    throw new HttpsError('unauthenticated', 'Session is no longer valid. Please sign in again.');
  }
  return request.auth.uid;
}
const incidentApi = createIncidentApi({db, authenticated, options});
exports.observeRoadIncident = incidentApi.observeRoadIncident;
exports.reviewRoadIncident = incidentApi.reviewRoadIncident;

exports.submitReport = onCall(options, async request => {
  const uid = await authenticated(request);
  let payload;
  try { payload = validateReport(request.data); }
  catch (e) { throw new HttpsError('invalid-argument', e.message); }
  const id = hash(`${uid}|${request.data.requestId}`);
  const fingerprint = hash(JSON.stringify(payload));
  const receiptRef = db.collection('report_requests').doc(id);
  // A replay can return before looking at storage: lost responses remain safe to retry.
  const receipt = await receiptRef.get();
  if (receipt.exists) {
    if (receipt.data().fingerprint !== fingerprint) throw new HttpsError('already-exists', 'Request identifier already used for different content.');
    return {reportId: receipt.data().reportId, replay: true};
  }
  let imageUrl = request.data.location?.imageUrl;
  if (imageUrl != null) {
    try {
      const url = new URL(imageUrl);
      const project = process.env.GCLOUD_PROJECT;
      const bucket = process.env.REPORT_STORAGE_BUCKET || `${project}.firebasestorage.app`;
      const prefix = `/v0/b/${bucket}/o/`;
      if (url.protocol !== 'https:' || url.hostname !== 'firebasestorage.googleapis.com' || !url.pathname.startsWith(prefix)) throw new Error();
      const path = decodeURIComponent(url.pathname.slice(prefix.length));
      if (!path.startsWith(`reports/${uid}/`) || path.split('/').length !== 3) throw new Error();
      const [metadata] = await getStorage().bucket(bucket).file(path).getMetadata();
      if (!['image/jpeg', 'image/png'].includes(metadata.contentType) || Number(metadata.size) > 10 * 1024 * 1024) throw new Error();
      if (!(metadata.metadata?.firebaseStorageDownloadTokens ?? '').split(',').includes(url.searchParams.get('token'))) throw new Error();
      imageUrl = url.toString();
    } catch (_) { throw new HttpsError('invalid-argument', 'Photo is unavailable or is not owned by this account. Please attach it again.'); }
  }
  const userRef = db.collection('users').doc(uid);
  const slotRef = db.collection('report_slots').doc(hash(`${uid}|${payload.roadId}`));
  return db.runTransaction(async tx => {
    const [receiptDoc, userDoc, roadDoc, slotDoc] = await Promise.all([
      tx.get(receiptRef), tx.get(userRef), tx.get(db.collection('roads').doc(payload.roadId)), tx.get(slotRef),
    ]);
    if (receiptDoc.exists) {
      if (receiptDoc.data().fingerprint !== fingerprint) throw new HttpsError('already-exists', 'Request identifier already used.');
      return {reportId: receiptDoc.data().reportId, replay: true};
    }
    if (!roadDoc.exists) throw new HttpsError('not-found', 'Selected road is no longer available.');
    if (payload.observedAt != null && (payload.observedAt > Date.now() + 60000 || Date.now() - payload.observedAt >= MAX_AGE)) {
      throw new HttpsError('invalid-argument', 'Observation time must be within the last 24 hours.');
    }
    let existing;
    if (slotDoc.exists) existing = await tx.get(db.collection('reports').doc(slotDoc.data().reportId));
    else {
      // Migrate pending reports created by earlier versions, without trusting a phone's cache.
      const legacy = await tx.get(db.collection('reports').where('userId', '==', uid)
        .where('roadId', '==', payload.roadId).where('status', '==', 'pending').limit(1));
      existing = legacy.docs[0];
    }
    const incidentRef = db.collection('road_incidents').doc(payload.roadId);
    const incidentDoc = await tx.get(incidentRef);
    const incident = incidentDoc.data();
    const continuing = incident && incident.state !== 'resolved';
    const isUpdate = existing?.exists && ['pending', 'under_review'].includes(existing.data().status) && (!incident || continuing);
    const severityRank = {Low: 0, Medium: 1, High: 2};
    const elapsed = Date.now() - millis(userDoc.data()?.lastReportAt);
    const escalation = isUpdate && severityRank[payload.severity] > severityRank[existing.data().severity]
      && elapsed >= 60000 && Date.now() - millis(userDoc.data()?.lastEscalationAt) >= 5 * 60000;
    if (elapsed < 5 * 60000 && !escalation) throw new HttpsError('resource-exhausted', 'SPAM_COOLDOWN');
    const distance = roadDistance(payload.location, roadDoc.data().geometry);
    if (!payload.isEmergency && (!Number.isFinite(distance) || distance > 500)) throw new HttpsError('failed-precondition', 'OUT_OF_RANGE');
    const reportRef = isUpdate ? existing.ref : db.collection('reports').doc(id);
    const incidentId = continuing ? incident.incidentId : id;
    const responseRef = incidentRef.collection('responses').doc(hash(`${incidentId}|${uid}`));
    const ownResponse = await tx.get(responseRef);
    const observedAt = payload.observedAt == null ? Timestamp.now() : Timestamp.fromMillis(payload.observedAt);
    const trust = userDoc.data()?.trustScore;
    const authorityScore = clamp((Number.isFinite(trust) ? trust : 25) + (imageUrl ? 30 : 0));
    const write = {...payload, observedAt, incidentId, userId: uid, authorityScore, updatedAt: nowStamp(), lastUpdatedByUser: nowStamp(),
      locationCheck: {method: 'provided_coordinates', distanceMeters: Number.isFinite(distance) ? distance : null,
        emergencyBypass: payload.isEmergency, gpsCapturedAt: payload.location.gpsCapturedAt ?? null,
        gpsAccuracyMeters: payload.location.gpsAccuracyMeters ?? null, source: payload.location.source ?? 'unspecified'},
      ...(imageUrl ? {imageUrl} : {})};
    if (!isUpdate) {
      Object.assign(write, {status: 'pending', createdAt: nowStamp(), confidenceScore: 0});
    }
    // Omitted photo on edit retains existing evidence and its authority bonus.
    if (!imageUrl && isUpdate && existing.data().imageUrl) write.authorityScore = clamp((Number.isFinite(trust) ? trust : 25) + 30);
    const state = continuing && incident.state === 'under_verification' ? 'under_verification' : 'reported_flooding';
    const counts = {...incident?.counts};
    const withdrawResponse = ownResponse.exists && !ownResponse.data().withdrawnByReport;
    if (withdrawResponse) {
      const choice = ownResponse.data().choice;
      counts[choice] = Math.max(0, (counts[choice] ?? 0) - 1);
      tx.update(responseRef, {withdrawnByReport: true});
    }
    if (continuing) tx.update(incidentRef, {state,
      lastObservedAt: Timestamp.fromMillis(Math.max(observedAt.toMillis(), millis(incident.lastObservedAt))),
      ...(withdrawResponse ? {counts} : {}),
      reviewRequired: true, revision: incident.revision + 1});
    else tx.set(incidentRef, newIncident(payload.roadId, incidentId, observedAt));
    if (roadDoc.data().communityCondition !== state || roadDoc.data().activeIncidentId !== incidentId) {
      tx.update(roadDoc.ref, {communityCondition: state, activeIncidentId: incidentId});
    }
    tx.set(reportRef, write, {merge: true});
    tx.set(slotRef, {userId: uid, roadId: payload.roadId, reportId: reportRef.id});
    tx.set(userRef, {lastReportAt: nowStamp(), ...(escalation ? {lastEscalationAt: nowStamp()} : {})}, {merge: true});
    tx.create(receiptRef, {userId: uid, fingerprint, reportId: reportRef.id, createdAt: nowStamp()});
    return {reportId: reportRef.id, replay: false};
  }).catch(error => {
    if ([10, 14, 4].includes(error.code)) throw new HttpsError('unavailable', 'Server is busy. Your form is preserved; retry to confirm the report.');
    throw error;
  });
});

exports.sendNotification = onCall(options, async request => {
  const uid = await authenticated(request);
  const profile = await db.collection('users').doc(uid).get();
  if (profile.data()?.role !== 'admin') throw new HttpsError('permission-denied', 'Administrator access required.');
  const {title, body, userId, data} = request.data ?? {};
  if (typeof title !== 'string' || title.length < 1 || title.length > 200 || typeof body !== 'string' || body.length > 2000 ||
      (userId !== undefined && (typeof userId !== 'string' || userId.includes('/')))) throw new HttpsError('invalid-argument', 'Invalid notification.');
  if (data != null && (typeof data !== 'object' || Array.isArray(data) || Object.keys(data).length > 20 || Object.values(data).some(v => typeof v !== 'string' || v.length > 1000))) throw new HttpsError('invalid-argument', 'Invalid notification data.');
  const message = {notification: {title, body}, ...(data ? {data} : {}), android: {priority: 'high', notification: {channelId: 'safepaths_alerts', sound: 'default'}}};
  if (!userId) {
    await getMessaging().send({...message, topic: 'safepaths_alerts'});
    return {acceptedCount: 1};
  }
  const userRef = db.collection('users').doc(userId);
  const target = await userRef.get();
  const tokens = [...new Set((target.data()?.fcmTokens ?? []).filter(t => typeof t === 'string'))];
  if (!tokens.length) return {acceptedCount: 0};
  let acceptedCount = 0;
  for (let i = 0; i < tokens.length; i += 500) {
    const batch = tokens.slice(i, i + 500);
    const result = await getMessaging().sendEachForMulticast({...message, tokens: batch});
    acceptedCount += result.successCount;
    const invalid = batch.filter((_, index) => ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(result.responses[index].error?.code));
    if (invalid.length) await userRef.update({fcmTokens: FieldValue.arrayRemove(...invalid)});
  }
  return {acceptedCount};
});

// Weather is fetched once for everyone, rather than by every installed app.
exports.refreshWeather = onSchedule({schedule: 'every 5 minutes', region: 'us-central1', timeoutSeconds: 60, maxInstances: 1}, async () => {
  const ref = db.doc('system/weather');
  const previous = await ref.get();
  if (previous.data()?.isOverrideMode && millis(previous.data().overrideExpiresAt) > Date.now()) return;
  const url = 'https://api.open-meteo.com/v1/forecast?latitude=14.6761&longitude=120.9842&current=temperature_2m,relative_humidity_2m,precipitation,rain,weather_code,wind_speed_10m&timezone=Asia%2FManila';
  const response = await fetch(url, {signal: AbortSignal.timeout(10000)});
  if (!response.ok) throw new Error(`Weather HTTP ${response.status}`);
  const {current} = await response.json();
  const intensity = current?.rain ?? current?.precipitation;
  const wind = current?.wind_speed_10m / 3.6;
  if (![intensity, wind, current?.temperature_2m, current?.relative_humidity_2m, current?.weather_code].every(Number.isFinite)) throw new Error('Incomplete weather response');
  const code = current.weather_code;
  const state = wind > 30 || intensity > 50 ? 'typhoon' : code >= 95 || [65, 67].includes(code) || intensity > 15 ? 'heavyRain'
    : [61, 63].includes(code) || intensity > 2 ? 'moderateRain' : code >= 51 && code <= 57 || intensity > 0 ? 'lightRain'
    : [1, 2, 3].includes(code) ? 'partlyCloudy' : 'clear';
  await db.runTransaction(async tx => {
    const latest = await tx.get(ref);
    if (latest.data()?.isOverrideMode && millis(latest.data().overrideExpiresAt) > Date.now()) return;
    tx.set(ref, {currentState: state, isOverrideMode: false, precipitationIntensity: intensity, windSpeed: wind,
      temperature: current.temperature_2m, humidity: current.relative_humidity_2m, lastFetched: nowStamp(), source: 'open-meteo'}, {merge: true});
  });
});

exports.refreshRisk = onSchedule({schedule: 'every 1 minutes', region: 'us-central1', timeoutSeconds: 120, maxInstances: 1}, async () => {
  const lease = db.doc('system/risk_job');
  const token = hash(`${Date.now()}|${Math.random()}`);
  const acquired = await db.runTransaction(async tx => {
    const state = await tx.get(lease);
    if (millis(state.data()?.leaseUntil) > Date.now()) return false;
    tx.set(lease, {token, leaseUntil: Timestamp.fromMillis(Date.now() + 180000)}, {merge: true});
    return true;
  });
  if (!acquired) return;
  try {
    await incidentApi.reconcile();
    const [roadSnapshot, reportSnapshot, weatherSnapshot] = await Promise.all([
      db.collection('roads').get(), db.collection('reports').where('status', 'in', ['pending', 'under_review']).get(), db.doc('system/weather').get(),
    ]);
    const now = Date.now(), weather = weatherSnapshot.data();
    const override = weather?.isOverrideMode && millis(weather.overrideExpiresAt) > now;
    if (!weather || !override && now - millis(weather.lastFetched) > 30 * 60000 || weather.isOverrideMode && !override) throw new Error('Weather is unavailable or outdated; previous risk retained');
    const roads = roadSnapshot.docs.map(d => ({...d.data(), id: d.id}));
    const reports = reportSnapshot.docs.map(d => ({...d.data(), id: d.id})).filter(r => now - observationTime(r) < MAX_AGE);
    const results = calculateRisks(roads, reports, weather.currentState, now);
    const writer = db.bulkWriter();
    writer.onWriteError(error => error.failedAttempts < 3 && ['aborted', 'unavailable', 10, 14].includes(error.code));
    const writes = results.map((result, i) => {
      const {id, warningStartTime, ...fields} = result;
      return writer.update(db.collection('roads').doc(id), {...fields,
        warningStartTime: warningStartTime === null ? null : Timestamp.fromMillis(warningStartTime), riskUpdatedAt: nowStamp()},
        {lastUpdateTime: roadSnapshot.docs[i].updateTime});
    });
    // Always observe rejected writes: a concurrent admin edit must not be silently overwritten.
    const settled = Promise.allSettled(writes);
    await writer.close();
    const outcomes = await settled;
    if (outcomes.some(r => r.status === 'rejected')) throw new Error('Some risk writes conflicted or failed; retry on next run');
    for (const road of roads) {
      const group = reports.filter(r => r.roadId === road.id);
      const unique = [...new Map(group.sort((a, b) => millis(a.createdAt) - millis(b.createdAt)).map(r => [r.userId, r])).values()];
      if (unique.length < 3) continue;
      const counts = {};
      for (const r of unique) counts[r.severity] = (counts[r.severity] ?? 0) + 1;
      const [severity, count] = Object.entries(counts).sort((a,b) => b[1] - a[1])[0];
      const agreement = count / unique.length;
      const avg = unique.filter(r => r.severity === severity).reduce((sum,r) => sum + confidence(r, roads, reports, weather.currentState, now), 0) / count;
      if (!(agreement >= 0.7 && (count >= 5 || count >= 3 && avg >= 85) || agreement >= 0.5 && agreement < 0.7)) continue;
      const auditRef = db.collection('consensus_audits').doc(hash(`${road.id}|${Math.floor(now / 10800000)}`));
      await db.runTransaction(async tx => {
        if ((await tx.get(auditRef)).exists) return;
        tx.create(auditRef, {roadId: road.id, roadName: road.name ?? '', timestamp: nowStamp(), algorithmVersion: 'server-v1',
          alertType: agreement >= 0.7 ? 'Consensus Alert' : 'Under Verification', dominantSeverity: severity,
          agreementRate: agreement, averageConfidence: avg, totalReports: unique.length, severityDistribution: counts});
      });
    }
    await lease.set({lastSuccess: nowStamp(), error: null}, {merge: true});
  } catch (e) {
    await lease.set({lastFailure: nowStamp(), error: String(e.message).slice(0, 500)}, {merge: true});
    throw e;
  } finally {
    await db.runTransaction(async tx => {
      const latest = await tx.get(lease);
      if (latest.data()?.token === token) tx.update(lease, {leaseUntil: Timestamp.fromMillis(0)});
    });
  }
});
