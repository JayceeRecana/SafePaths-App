import { queueAdminReportNotice } from "./admin_report_notifications.mjs";
import {
  clamp,
  identifier,
  maxObservationAge,
  millis,
  ProofError,
  serverTime,
  sha256,
} from "./proof_common.mjs";

const changes = ["worsened", "improved", "cleared", "unchanged"];
const canonical = (v) =>
  v instanceof Date
    ? v.getTime()
    : Array.isArray(v)
    ? v.map(canonical)
    : v && typeof v === "object"
    ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, canonical(v[k])]))
    : v;
const digest = (v) => sha256(JSON.stringify(canonical(v)));
const fail = (code, message, status = 400) => {
  throw new ProofError(code, message, status);
};
const normalized = (value) =>
  String(value ?? "").trim().replace(/\s+/g, " ").toLowerCase();

export function originalSnapshot(report, now) {
  if (report.originalSubmission) return report.originalSubmission;
  return {
    title: report.title ?? "Report",
    description: report.description ?? "",
    severity: report.severity ?? "Unknown",
    observedAt: report.observedAt ?? report.lastUpdatedByUser ??
      report.createdAt ?? null,
    submittedAt: report.createdAt ?? null,
    imageUrl: report.imageUrl ?? null,
    photoSubmittedAt: report.photoSubmittedAt ?? null,
    snapshotType: "existing_record",
    recordedAt: new Date(now),
  };
}

export function createReportFollowups({ db, photos, clock = Date.now, adminNotices = false }) {
  async function load(get, query, uid, rootReportId) {
    if (!identifier(rootReportId)) {
      fail("invalid-argument", "Choose the original report.");
    }
    const [root, user] = await Promise.all([
      get(`reports/${rootReportId}`),
      get(`users/${uid}`),
    ]);
    if (
      !root.exists || !user.exists ||
      (root.data.userId !== uid && user.data.role !== "admin")
    ) {
      fail(
        "permission-denied",
        "Only the reporter and authorized admins can view this condition history.",
        403,
      );
    }
    if (
      root.data.reportType === "followup" || !identifier(root.data.roadId) ||
      !identifier(root.data.incidentId)
    ) {
      fail(
        "failed-precondition",
        "Open the original road-linked report to add a follow-up.",
        409,
      );
    }
    const [road, incident, updates] = await Promise.all([
      get(`roads/${root.data.roadId}`),
      get(`road_incidents/${root.data.roadId}`),
      query("reports", "rootReportId", rootReportId, 101),
    ]);
    if (updates.length > 100) {
      fail("resource-exhausted", "This history needs supervised review.", 429);
    }
    updates.sort((a, b) =>
      millis(a.data.observedAt) - millis(b.data.observedAt) ||
      a.path.localeCompare(b.path)
    );
    const active = road.exists && incident.exists &&
      incident.data.state !== "resolved" &&
      incident.data.incidentId === root.data.incidentId &&
      root.data.status !== "dismissed";
    const token = await digest({
      root: root.data,
      incident: incident.data,
      road: {
        status: road.data.status ?? null,
        updatedAt: road.data.updatedAt ?? null,
        notes: road.data.notes ?? null,
      },
      count: updates.length,
    });
    return { root, user, road, incident, updates, active, token };
  }

  async function context(uid, data) {
    const s = await load(
      (p) => db.get(p),
      (c, f, v, n) => db.query(c, [[f, "EQUAL", v]], { limit: n }),
      uid,
      data?.rootReportId,
    );
    return {
      token: s.token,
      rootReport: {
        ...s.root.data,
        id: data.rootReportId,
        originalSubmission: originalSnapshot(s.root.data, clock()),
      },
      updates: s.updates.map((doc) => ({
        ...doc.data,
        id: doc.path.split("/").at(-1),
      })),
      road: s.road.exists
        ? {
          id: s.root.data.roadId,
          name: s.road.data.name,
          status: s.road.data.status,
        }
        : null,
      canSubmit: s.active && s.root.data.userId === uid,
      viewerIsAdmin: s.user.data.role === "admin",
      closedReason: s.active
        ? null
        : "This incident is closed or has changed. Submit a new report for a new event.",
    };
  }

  async function submit(uid, data) {
    if (
      !data || !identifier(data.rootReportId) ||
      !/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId ?? "") ||
      !/^[a-f0-9]{64}$/.test(data.contextToken ?? "") ||
      !changes.includes(data.conditionChange) ||
      !["Low", "Medium", "High"].includes(data.severity) ||
      typeof data.description !== "string" || !data.description.trim() ||
      data.description.length > 2000 ||
      data.isEmergency != null && typeof data.isEmergency !== "boolean" ||
      typeof data.observedAt !== "string" ||
      !Number.isFinite(Date.parse(data.observedAt)) ||
      data.imageUrl != null && typeof data.imageUrl !== "string" ||
      data.imageUrl && data.photoMatchesObservation !== true ||
      data.conditionChange === "cleared" && data.severity !== "Low"
    ) {
      fail(
        "invalid-argument",
        "Choose the changed condition, observation time and description. Confirm any attached photo.",
      );
    }
    const payload = {
      rootReportId: data.rootReportId,
      contextToken: data.contextToken,
      conditionChange: data.conditionChange,
      severity: data.severity,
      description: data.description.trim(),
      observedAt: new Date(data.observedAt),
      imageUrl: data.imageUrl ?? null,
      isEmergency: data.isEmergency === true,
    };
    const id = await sha256(`${uid}|followup|${data.requestId}`),
      fingerprint = await digest(payload);
    const receiptPath = `followup_requests/${id}`;
    const replay = (doc) => {
      if (doc.data.fingerprint !== fingerprint) {
        fail("already-exists", "This retry belongs to another follow-up.", 409);
      }
      return { reportId: id, rootReportId: payload.rootReportId, replay: true };
    };
    const receipt = await db.get(receiptPath);
    if (receipt.exists) return replay(receipt);
    const root = await db.get(`reports/${payload.rootReportId}`);
    if (!root.exists || root.data.userId !== uid) {
      fail(
        "permission-denied",
        "Only the original reporter can add this follow-up.",
        403,
      );
    }
    if (payload.imageUrl) await photos.validate(payload.imageUrl, uid);
    return db.transaction(async (tx) => {
      const saved = await tx.get(receiptPath);
      if (saved.exists) return replay(saved);
      const s = await load(
        (p) => tx.get(p),
        (...args) => tx.query(...args),
        uid,
        payload.rootReportId,
      );
      if (s.root.data.userId !== uid) {
        fail(
          "permission-denied",
          "Only the original reporter can add this follow-up.",
          403,
        );
      }
      if (!s.active) {
        fail(
          "failed-precondition",
          "The road incident is closed or changed. Refresh the condition history.",
          409,
        );
      }
      if (s.token !== payload.contextToken) {
        fail(
          "failed-precondition",
          "New information arrived. Refresh the condition history before submitting.",
          409,
        );
      }
      const now = clock(), observed = payload.observedAt.getTime();
      const previous = s.updates.at(-1)?.data ?? s.root.data;
      const previousTime = millis(
        previous.observedAt ?? previous.lastUpdatedByUser ?? previous.createdAt,
      );
      if (
        observed > now + 60000 || now - observed >= maxObservationAge ||
        observed <= previousTime
      ) {
        fail(
          "observation-stale",
          "Choose an observation newer than the last submission and within the past 24 hours.",
          409,
        );
      }
      const history = [s.root, ...s.updates];
      if (
        payload.imageUrl &&
        history.some((doc) =>
          doc.data.imageUrl === payload.imageUrl ||
          doc.data.originalSubmission?.imageUrl === payload.imageUrl
        )
      ) {
        fail(
          "duplicate-evidence",
          "This photo already belongs to an earlier submission. Choose a current photo or continue without a photo.",
          409,
        );
      }
      if (
        !payload.imageUrl &&
        normalized(previous.description) === normalized(payload.description) &&
        previous.severity === payload.severity &&
        !["cleared", "unchanged"].includes(payload.conditionChange)
      ) {
        fail(
          "duplicate-evidence",
          "Describe what changed instead of repeating the previous observation.",
          409,
        );
      }
      const rank = { Low: 0, Medium: 1, High: 2 },
        elapsed = now - millis(s.user.data.lastReportAt);
      const escalation = (payload.conditionChange === "worsened" &&
          rank[payload.severity] > rank[previous.severity] ||
        payload.isEmergency && previous.isEmergency !== true) &&
        elapsed >= 60000 &&
        now - millis(s.user.data.lastEscalationAt) >= 300000;
      if (elapsed < 300000 && !escalation) {
        fail(
          "resource-exhausted",
          "Wait five minutes between submissions, or one minute for an eligible worsening condition.",
          429,
        );
      }
      const allIncidentReports = await tx.query(
        "reports",
        "incidentId",
        s.root.data.incidentId,
        101,
      );
      if (allIncidentReports.length >= 100) {
        fail(
          "resource-exhausted",
          "This incident needs supervised review before more reports can be added.",
          429,
        );
      }
      const state = ["improved", "cleared"].includes(payload.conditionChange) ||
          s.incident.data.state === "under_verification"
        ? "under_verification"
        : "reported_flooding";
      const trust = Number.isFinite(s.user.data.trustScore)
        ? s.user.data.trustScore
        : 25;
      const adminNoticeEventId = adminNotices ? await queueAdminReportNotice(tx, {
        reportId:id,userId:uid,requestHash:id,kind:"report_new_admin",now,
      }) : null;
      tx.set(`reports/${id}`, {
        ...(adminNoticeEventId ? {adminNoticeEventId}:{}),
        reportType: "followup",
        rootReportId: payload.rootReportId,
        incidentId: s.root.data.incidentId,
        roadId: s.root.data.roadId,
        userId: uid,
        title: `Condition update: ${s.road.data.name ?? "Road"}`,
        description: payload.description,
        severity: payload.severity,
        conditionChange: payload.conditionChange,
        status: "pending",
        isEmergency: payload.isEmergency,
        authorityScore: clamp(trust + (payload.imageUrl ? 30 : 0)),
        confidenceScore: 0,
        observedAt: payload.observedAt,
        createdAt: serverTime,
        lastUpdatedByUser: serverTime,
        expiresAt: new Date(observed + maxObservationAge),
        locationCheck: {
          method: "linked_original_report",
          currentGpsProvided: false,
        },
        ...(payload.imageUrl
          ? {
            imageUrl: payload.imageUrl,
            photoSubmittedAt: serverTime,
            photoMatchesObservation: true,
          }
          : {}),
      }, { create: true });
      tx.set(s.root.path, {
        originalSubmission: originalSnapshot(s.root.data, now),
        followupCount: s.updates.length + 1,
        lastFollowupAt: serverTime,
      }, { merge: true });
      const latest = Math.max(observed, millis(s.incident.data.lastObservedAt));
      tx.set(s.incident.path, {
        state,
        reviewRequired: true,
        revision: s.incident.data.revision + 1,
        lastObservedAt: new Date(latest),
        expiresAt: new Date(latest + maxObservationAge),
      }, { merge: true });
      tx.set(s.road.path, {
        communityCondition: state,
        riskInputsUpdatedAt: serverTime,
      }, { merge: true });
      tx.set("system/road_inputs", { updatedAt: serverTime }, { merge: true });
      tx.set(s.user.path, {
        lastReportAt: serverTime,
        ...(escalation ? { lastEscalationAt: serverTime } : {}),
      }, { merge: true });
      tx.set(receiptPath, {
        userId: uid,
        fingerprint,
        reportId: id,
        rootReportId: payload.rootReportId,
        createdAt: serverTime,
      }, { create: true });
      tx.set(`followup_audits/${id}`, {
        action: "submit_followup",
        userId: uid,
        reportId: id,
        rootReportId: payload.rootReportId,
        createdAt: serverTime,
      }, { create: true });
      return {
        reportId: id,
        rootReportId: payload.rootReportId,
        replay: false,
      };
    });
  }
  return { context, submit };
}
