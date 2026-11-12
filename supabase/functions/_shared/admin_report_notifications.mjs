import { identifier, millis, serverTime, sha256 } from "./proof_common.mjs";
import { TEST_BACKEND, eligibleMember } from "./backend_profile.mjs";

export const adminReportKinds = ["report_new_admin", "report_reply_admin"];
// Called inside the successful report transaction. No audience lookup or push
// provider can prevent a resident from saving their evidence.
export async function queueAdminReportNotice(tx, { reportId, userId, requestHash, kind, now }) {
  const eventId = await sha256(`${requestHash}|admin-report|${kind}`);
  tx.set(`notification_outbox/${eventId}`, {
    kind: "report_admin_fanout", noticeKind: kind, queueClass: "report",
    reportId, sourceUid: userId, requestHash, createdAt: serverTime,
    dueAt: new Date(now), expiresAt: new Date(now + 3600000),
    status: "awaiting_sender", dispatchable: true,
  }, { create: true });
  return eventId;
}
export function eligibleReportAdmin(doc, profile, allowedUids, sourceUid) {
  const uid = doc.path.split("/").at(-1);
  return identifier(uid) && uid !== sourceUid && doc.exists &&
    doc.data.role === "admin" && doc.data.disabled !== true &&
    (doc.data.studyArea == null || doc.data.studyArea === profile.area) &&
    (profile === TEST_BACKEND ? allowedUids.has(uid) : eligibleMember(doc, profile));
}
// Twenty admins per worker page, cursor by document name. Stable child IDs
// make retries/competing workers safe without making report submission wait.
export async function expandAdminReportNotice({ db, path, profile, allowedUids, clock }) {
  const source = await db.get(path), event = source.data;
  if (!source.exists || event.kind !== "report_admin_fanout" || !event.dispatchable ||
      millis(event.dueAt) > clock()) return "skipped";
  const parentId = path.split("/").at(-1);
  if (millis(event.expiresAt) <= clock()) {
    await db.transaction(async tx => {
      const current = await tx.get(path);
      if (current.data.dispatchable) tx.set(path, {status:"expired",dispatchable:false}, {merge:true});
    });
    return "expired";
  }
  if (!adminReportKinds.includes(event.noticeKind) || !identifier(event.reportId)) throw new Error("Invalid admin work event.");
  const report = await db.get(`reports/${event.reportId}`);
  const currentReport = doc => doc.exists && doc.data.status === "pending" &&
    doc.data.userId === event.sourceUid && doc.data.adminNoticeEventId === parentId;
  if (!currentReport(report)) {
    await db.transaction(async tx => {
      const current = await tx.get(path);
      if (current.data.dispatchable) tx.set(path, {status:"suppressed",dispatchable:false}, {merge:true});
    });
    return "suppressed";
  }
  const admins = await db.query("users", [["role", "EQUAL", "admin"]], {
    limit:20, orderBy:[{field:{fieldPath:"__name__"},direction:"ASCENDING"}],
    afterDocument:event.cursor ?? null,
  });
  const targets = await Promise.all(admins.filter(doc => eligibleReportAdmin(doc,profile,allowedUids,event.sourceUid))
    .map(async doc => ({userId:doc.path.split("/").at(-1), id:await sha256(`${parentId}|${doc.path}`)})));
  return db.transaction(async tx => {
    const [latest, freshReport, ...existing] = await Promise.all([
      tx.get(path), tx.get(report.path), ...targets.map(t=>tx.get(`notification_outbox/${t.id}`)),
    ]);
    if (!latest.data.dispatchable || (latest.data.cursor ?? null) !== (event.cursor ?? null)) return "skipped";
    if (!currentReport(freshReport) || millis(latest.data.expiresAt) <= clock()) {
      tx.set(path,{status:"suppressed",dispatchable:false},{merge:true});return "suppressed";
    }
    for (const [index,target] of targets.entries()) if (!existing[index].exists) {
      tx.set(`notification_outbox/${target.id}`, {
        kind:event.noticeKind, queueClass:"report", reportId:event.reportId,
        userId:target.userId, sourceUid:event.sourceUid, parentEventId:parentId,
        requestHash:event.requestHash, createdAt:serverTime,
        dueAt:new Date(clock()), expiresAt:event.expiresAt,
        dispatchable:true,status:"awaiting_sender",
      },{create:true});
    }
    const more = admins.length === 20;
    tx.set(path,{cursor:admins.at(-1)?.path ?? event.cursor ?? null,
      dispatchable:more,status:more?"awaiting_sender":"expanded",
      dueAt:new Date(clock()+1000)}, {merge:true});
    return more ? "retry" : "expanded";
  });
}
