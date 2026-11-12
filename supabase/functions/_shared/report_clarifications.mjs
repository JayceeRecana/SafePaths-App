import { queueAdminReportNotice } from "./admin_report_notifications.mjs";
import { identifier, ProofError, serverTime, sha256 } from './proof_common.mjs';

// Clarifications add evidence to an existing observation. They never overwrite
// the original photo/time, create a new incident, change passability or award trust.
export function createReportClarifications({ db, photos, clock = Date.now, adminNotices = false }) {
  const fail = (code, message, status = 400) => { throw new ProofError(code, message, status); };
  async function context(uid, data) {
    if (!identifier(data?.reportId)) fail('invalid-argument', 'Choose a report.');
    const report = await db.get(`reports/${data.reportId}`);
    const viewer = await db.get(`users/${uid}`);
    if (!report.exists || report.data.userId !== uid && viewer.data.role !== 'admin')
      fail('permission-denied', 'Only the reporter and authorized admins can open this clarification.', 403);
    const requestId = report.data.clarificationRequestId;
    if (!identifier(requestId)) fail('failed-precondition', 'No clarification is requested for this report.');
    const request = await db.get(`report_clarifications/${requestId}`);
    if (!request.exists || request.data.reportId !== data.reportId || request.data.userId !== report.data.userId)
      fail('failed-precondition', 'The clarification could not be confirmed.');
    return { requestId, ...request.data, canReply: report.data.userId === uid &&
      report.data.status === 'waiting_resident' && !request.data.answered };
  }
  async function reply(uid, data) {
    if (!identifier(data?.reportId) || !identifier(data?.clarificationRequestId) ||
        !/^[A-Za-z0-9_-]{16,128}$/.test(data?.requestId ?? '') ||
        typeof data.message !== 'string' || data.message.trim().length < 10 || data.message.length > 2000 ||
        data.imageUrl != null && (typeof data.imageUrl !== 'string' || data.imageUrl.length > 2048))
      fail('invalid-argument', 'Describe the clarification (10–2000 characters).');
    const observed = data.imageUrl ? Date.parse(data.photoObservedAt) : null;
    if (data.imageUrl && (!Number.isFinite(observed) || observed > clock() || observed <= 0 || data.photoMatchesObservation !== true))
      fail('invalid-argument', 'Confirm when the attached photo was observed.');
    const receiptId = await sha256(`${uid}|${data.requestId}`);
    const fingerprint = await sha256(JSON.stringify([data.reportId, data.clarificationRequestId,
      data.message.trim(), data.imageUrl ?? null, observed]));
    // Check retry first: a previously saved attachment may no longer be available.
    const previous = await db.get(`clarification_requests/${receiptId}`);
    if (previous.exists) {
      if (previous.data.fingerprint !== fingerprint) fail('already-exists', 'Retry belongs to different details.', 409);
      return { reportId: data.reportId, replay: true };
    }
    if (data.imageUrl) await photos.validate(data.imageUrl, uid);
    return db.transaction(async tx => {
      const [report, request, receipt] = await Promise.all([
        tx.get(`reports/${data.reportId}`), tx.get(`report_clarifications/${data.clarificationRequestId}`),
        tx.get(`clarification_requests/${receiptId}`),
      ]);
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) fail('already-exists', 'Retry belongs to different details.', 409);
        return { reportId: data.reportId, replay: true };
      }
      if (!report.exists || report.data.userId !== uid || request.data.userId !== uid)
        fail('permission-denied', 'Only the original reporter can reply.', 403);
      if (report.data.status !== 'waiting_resident' || report.data.clarificationRequestId !== data.clarificationRequestId ||
          !request.exists || request.data.reportId !== data.reportId || request.data.answered)
        fail('failed-precondition', 'This request changed or was already answered. Refresh its updates.', 409);
      const response = { message: data.message.trim(), imageUrl: data.imageUrl ?? null,
        photoObservedAt: observed ? new Date(observed) : null, repliedAt: serverTime };
      tx.set(request.path, { answered: true, response }, { merge: true });
      const adminNoticeEventId = adminNotices ? await queueAdminReportNotice(tx, {
        reportId:data.reportId,userId:uid,requestHash:receiptId,kind:"report_reply_admin",now:clock(),
      }) : null;
      tx.set(report.path, { ...(adminNoticeEventId ? {adminNoticeEventId}:{}), status: 'pending', clarificationRepliedAt: serverTime,
        recordUpdatedAt: serverTime, reviewStartedAt: null, reviewStartedByUid: null,
        hasAdminUpdates: true }, { merge: true });
      tx.set(`report_messages/${receiptId}`, { reportId: data.reportId, userId: uid,
        senderUid: uid, sender: 'Resident clarification', message: data.message.trim(),
        createdAt: serverTime, imageUrl: response.imageUrl, photoObservedAt: response.photoObservedAt }, { create: true });
      tx.set(`clarification_requests/${receiptId}`, { fingerprint, reportId: data.reportId, createdAt: serverTime }, { create: true });
      return { reportId: data.reportId, replay: false };
    });
  }
  return { context, reply };
}
