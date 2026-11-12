import { assertBackendProfile, TEST_BACKEND, eligibleMember } from "./backend_profile.mjs";
import {
  identifier,
  millis,
  ProofError,
  serverTime,
  sha256,
} from "./proof_common.mjs";

const hour = 3600000;
const categories = [
  "App Performance",
  "Map Accuracy",
  "Feature Suggestion",
  "Report a Bug",
  "General Feedback",
];
const invalid = (message) => {
  throw new ProofError("invalid-argument", message);
};
const conflict = () => {
  throw new ProofError(
    "failed-precondition",
    "New information arrived. Refresh before saving.",
    409,
  );
};
function keys(data, allowed) {
  if (
    !data || typeof data !== "object" || Array.isArray(data) ||
    Object.keys(data).some((k) => !allowed.includes(k))
  ) invalid("Check the action details.");
}
function request(data) {
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(data?.requestId ?? "")) {
    invalid("Invalid retry identifier.");
  }
}
function text(value, min, max) {
  return typeof value === "string" && value.trim().length >= min &&
    value.trim().length <= max;
}
function admin(profile) {
  if (profile.data.role !== "admin") {
    throw new ProofError(
      "permission-denied",
      "Administrator access required.",
      403,
    );
  }
}
const token = (uid, doc) =>
  sha256(
    JSON.stringify([
      uid,
      doc.path,
      doc.updateTime ?? null,
      doc.data.revision ?? 0,
      doc.data.status ?? null,
    ]),
  );
function event(data, now) {
  return {
    ...data,
    dispatchable: true,
    status: "queued",
    dueAt: new Date(now),
    expiresAt: new Date(now + hour),
    attempts: 0,
    accepted: {},
    discarded: {},
    createdAt: serverTime,
  };
}

export function createCommunications(
  {
    db,
    allowedUids = new Set(),
    profile: backendProfile = TEST_BACKEND,
    clock = Date.now,
    feedbackPhotos =
      /** @type {import("./proof_media.mjs").ProofMediaStorage|null} */ (null),
  },
) {
  assertBackendProfile(backendProfile);
  const area = backendProfile.area;
  async function context(uid, data, kind) {
    keys(data, [kind === "feedback" ? "feedbackId" : "alertId"]);
    const id = kind === "feedback" ? data.feedbackId : data.alertId;
    if (!identifier(id)) invalid("Choose a valid record.");
    const [profile, doc] = await Promise.all([
      db.get(`users/${uid}`),
      db.get(`${kind === "feedback" ? "feedbacks" : "alerts"}/${id}`),
    ]);
    admin(profile);
    if (!doc.exists) {
      throw new ProofError("not-found", "This record is unavailable.", 404);
    }
    return {
      token: await token(uid, doc),
      revision: doc.data.revision ?? 0,
      status: doc.data.status ?? "new",
      ...(kind === "feedback"
        ? {
          allowFollowUp: doc.data.allowFollowUp === true,
          owned: identifier(doc.data.userId),
        }
        : { studyArea: doc.data.studyArea ?? null }),
    };
  }
  async function submit(uid, data) {
    keys(data, [
      "requestId",
      "category",
      "rating",
      "comments",
      "allowFollowUp",
      "imageUrl",
    ]);
    request(data);
    if (
      !categories.includes(data.category) || !Number.isInteger(data.rating) ||
      data.rating < 1 || data.rating > 5 || !text(data.comments, 0, 2000) ||
      typeof data.allowFollowUp !== "boolean"
    ) invalid("Choose a category, rating and valid feedback.");
    const payload = {
      category: data.category,
      rating: data.rating,
      comments: data.comments.trim(),
      allowFollowUp: data.allowFollowUp,
      ...(data.imageUrl != null ? { imageUrl: data.imageUrl } : {}),
    };
    const id = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await sha256(
        JSON.stringify({ operation: "feedback-submit", ...payload }),
      );
    let prior = null;
    if (data.imageUrl != null) {
      if (!feedbackPhotos) invalid("Feedback attachments are not enabled.");
      prior = await db.get(`communication_requests/${id}`);
      if (!prior.exists) await feedbackPhotos.validate(data.imageUrl, uid);
    }
    return db.transaction(async (tx) => {
      const [profile, receipt] = await Promise.all([
        tx.get(`users/${uid}`),
        tx.get(`communication_requests/${id}`),
      ]);
      if (!profile.exists) {
        throw new ProofError(
          "failed-precondition",
          "Complete the test profile.",
          409,
        );
      }
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          invalid("This retry belongs to another action.");
        }
        return { ...receipt.data.result, replay: true };
      }
      if (prior?.exists) conflict();
      if (millis(profile.data.lastFeedbackAt) > clock() - 60000) {
        throw new ProofError(
          "resource-exhausted",
          "Wait one minute before submitting more feedback.",
          429,
        );
      }
      const result = {
        saved: true,
        operation: "feedback-submit",
        resourceId: id,
        revision: 1,
        replay: false,
        notification: "saved_in_app",
        queuedCount: 0,
      };
      tx.set(`feedbacks/${id}`, {
        ...payload,
        userId: uid,
        timestamp: serverTime,
        status: "new",
        revision: 1,
        sparkManaged: true,
        hasAttachment: data.imageUrl != null,
        imageUrl: data.imageUrl ?? null,
        adminReply: null,
      }, { create: true });
      tx.set(profile.path, { lastFeedbackAt: serverTime }, { merge: true });
      tx.set(receipt.path, { fingerprint, result, createdAt: serverTime }, {
        create: true,
      });
      return result;
    });
  }
  async function feedback(uid, data) {
    keys(data, [
      "requestId",
      "feedbackId",
      "contextToken",
      "action",
      "note",
      "notify",
      "outcome",
      "confirmed",
    ]);
    request(data);
    if (
      !identifier(data.feedbackId) ||
      !/^[a-f0-9]{64}$/.test(data.contextToken ?? "") ||
      !["review", "reply", "resolve", "reopen"].includes(data.action) ||
      typeof data.notify !== "boolean"
    ) invalid("Choose a valid feedback action.");
    const note = typeof data.note === "string" ? data.note.trim() : "";
    if (
      note.length > 2000 || data.action === "reply" && !text(note, 1, 2000) ||
      data.action === "resolve" &&
        (!text(note, 10, 2000) ||
          !["addressed", "recorded", "duplicate"].includes(data.outcome) ||
          data.confirmed !== true)
    ) invalid("Confirm the closure outcome and provide an accurate note.");
    const hash = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await sha256(JSON.stringify({
        operation: "feedback-action",
        feedbackId: data.feedbackId,
        contextToken: data.contextToken,
        action: data.action,
        note,
        notify: data.notify,
        outcome: data.action === "resolve" ? data.outcome : null,
        confirmed: data.action === "resolve" ? data.confirmed : null,
      }));
    return db.transaction(async (tx) => {
      const [profile, receipt, doc] = await Promise.all([
        tx.get(`users/${uid}`),
        tx.get(`communication_requests/${hash}`),
        tx.get(`feedbacks/${data.feedbackId}`),
      ]);
      admin(profile);
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          invalid("This retry belongs to another action.");
        }
        return { ...receipt.data.result, replay: true };
      }
      if (!doc.exists || await token(uid, doc) !== data.contextToken) {
        conflict();
      }
      const value = doc.data;
      if (
        data.action === "review" && value.status === "resolved" ||
        data.action === "reopen" && value.status !== "resolved" ||
        data.action === "resolve" && value.status === "resolved" ||
        data.action === "reply" && value.status === "resolved"
      ) conflict();
      const owner = identifier(value.userId) ? value.userId : null;
      const legacyId = await sha256(`legacy-feedback|${data.feedbackId}`);
      const legacy = note && typeof value.adminReply === "string" &&
          value.adminReply.trim() && value.hasAdminUpdates !== true
        ? await tx.get(`feedback_messages/${legacyId}`)
        : null;
      const revision = (Number.isInteger(value.revision) ? value.revision : 0) +
        1;
      const status = data.action === "resolve"
        ? "resolved"
        : data.action === "reopen" || data.action === "review" ||
            data.action === "reply" && value.status === "new"
        ? "reviewed"
        : value.status;
      // Optional notifications require explicit original consent and an owned,
      // allowlisted record. The private update is saved regardless of push.
      const queue = !!note && data.notify && value.allowFollowUp === true &&
        !!owner && (backendProfile === TEST_BACKEND ? allowedUids.has(owner) : eligibleMember(await tx.get(`users/${owner}`), backendProfile));
      const result = {
        saved: true,
        operation: "feedback-action",
        resourceId: data.feedbackId,
        revision,
        replay: false,
        notification: "saved_in_app",
        queuedCount: queue ? 1 : 0,
      };
      tx.set(doc.path, {
        status,
        revision,
        sparkManaged: true,
        reviewedAt: serverTime,
        adminUid: uid,
        ...(note ? { adminReply: note, hasAdminUpdates: true } : {}),
        ...(data.action === "resolve"
          ? { resolutionOutcome: data.outcome }
          : data.action === "reopen"
          ? { resolutionOutcome: null }
          : {}),
      }, { merge: true });
      if (legacy && !legacy.exists) {
        tx.set(legacy.path, {
          feedbackId: data.feedbackId,
          userId: owner,
          body: value.adminReply.trim(),
          createdAt: value.reviewedAt instanceof Date
            ? value.reviewedAt
            : value.timestamp instanceof Date
            ? value.timestamp
            : new Date(clock()),
          legacy: true,
        }, { create: true });
      }
      if (note) {
        tx.set(`feedback_messages/${hash}`, {
          feedbackId: data.feedbackId,
          userId: owner,
          body: note,
          createdAt: serverTime,
          action: data.action,
          revision,
        }, { create: true });
      }
      if (queue) {
        tx.set(
          `notification_outbox/${hash}`,
          event({
            kind: "feedback_update",
            queueClass: "feedback",
            feedbackId: data.feedbackId,
            userId: owner,
            revision,
            requestHash: hash,
          }, clock()),
          { create: true },
        );
      }
      tx.set(`communication_audits/${hash}`, {
        operation: "feedback-action",
        action: data.action,
        resourceId: data.feedbackId,
        performedByUid: uid,
        revision,
        createdAt: serverTime,
      }, { create: true });
      tx.set(receipt.path, { fingerprint, result, createdAt: serverTime }, {
        create: true,
      });
      return result;
    });
  }
  async function publish(uid, data) {
    keys(data, [
      "requestId",
      "title",
      "message",
      "severity",
      "roadId",
      "sendPush",
      "minutes",
      "studyArea",
    ]);
    request(data);
    if (
      !text(data.title, 2, 120) || !text(data.message, 10, 2000) ||
      !["Advisory", "Warning", "Critical"].includes(data.severity) ||
      typeof data.sendPush !== "boolean" || !Number.isInteger(data.minutes) ||
      data.minutes < 15 || data.minutes > 1440 || data.studyArea !== area ||
      data.roadId != null && !identifier(data.roadId)
    ) invalid("Check the alert, test area and validity period.");
    const payload = {
      title: data.title.trim(),
      message: data.message.trim(),
      severity: data.severity,
      roadId: data.roadId ?? null,
      sendPush: data.sendPush,
      minutes: data.minutes,
      studyArea: area,
    };
    const hash = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await sha256(
        JSON.stringify({ operation: "broadcast-publish", ...payload }),
      );
    return db.transaction(async (tx) => {
      const recipientsQuery = !payload.sendPush ? Promise.resolve([]) : backendProfile === TEST_BACKEND
        ? Promise.all([...allowedUids].map((id) => tx.get(`users/${id}`)))
        : tx.queryWhere("users", [["role", "EQUAL", "user"]], 201);
      const [author, receipt, road, profiles] = await Promise.all([
        tx.get(`users/${uid}`),
        tx.get(`communication_requests/${hash}`),
        payload.roadId ? tx.get(`roads/${payload.roadId}`) : null,
        recipientsQuery,
      ]);
      admin(author);
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          invalid("This retry belongs to another action.");
        }
        return { ...receipt.data.result, replay: true };
      }
      if (millis(author.data.lastBroadcastAt) > clock() - 60000) {
        throw new ProofError(
          "resource-exhausted",
          "Wait one minute before publishing another alert.",
          429,
        );
      }
      if (road && (!road.exists || road.data.studyArea !== area)) {
        throw new ProofError(
          "failed-precondition",
          "Choose a road in the test area.",
          409,
        );
      }
      if (profiles.length > 200) throw new ProofError("resource-exhausted", "Broadcast audience exceeds the verified capstone limit.", 429);
      const eligible = profiles.filter((p) =>
        p.exists && p.data.role === "user" && (backendProfile === TEST_BACKEND || eligibleMember(p, backendProfile)) &&
        (p.data.studyArea == null || p.data.studyArea === area)
      );
      const recipients = payload.sendPush ? eligible : [];
      const result = {
        saved: true,
        operation: "broadcast-publish",
        resourceId: hash,
        revision: 1,
        replay: false,
        notification: "saved_in_app",
        queuedCount: recipients.length,
      };
      const expiresAt = new Date(clock() + payload.minutes * 60000);
      tx.set(`alerts/${hash}`, {
        title: payload.title,
        message: payload.message,
        severity: payload.severity,
        category: payload.severity === "Advisory"
          ? "WEATHER UPDATE"
          : payload.severity === "Warning"
          ? "SYSTEM"
          : "EMERGENCY",
        ...(road
          ? {
            roadId: payload.roadId,
            roadName: typeof road.data.name === "string"
              ? road.data.name.slice(0, 120)
              : "",
          }
          : {}),
        studyArea: area,
        status: "active",
        revision: 1,
        sparkManaged: true,
        expiresAt,
        createdAt: serverTime,
        createdByUid: uid,
        requestHash: hash,
      }, { create: true });
      for (const recipient of recipients) {
        const userId = recipient.path.split("/").at(-1),
          id = await sha256(`${hash}|broadcast|${userId}`);
        tx.set(`notification_outbox/${id}`, {
          ...event({
            kind: "broadcast_update",
            queueClass: "broadcast",
            alertId: hash,
            userId,
            studyArea: area,
            revision: 1,
            requestHash: hash,
          }, clock()),
          expiresAt: new Date(Math.min(clock() + hour, expiresAt.getTime())),
        }, { create: true });
      }
      tx.set(author.path, { lastBroadcastAt: serverTime }, { merge: true });
      tx.set(`communication_audits/${hash}`, {
        operation: "broadcast-publish",
        resourceId: hash,
        performedByUid: uid,
        revision: 1,
        createdAt: serverTime,
      }, { create: true });
      tx.set(receipt.path, { fingerprint, result, createdAt: serverTime }, {
        create: true,
      });
      return result;
    });
  }
  async function withdraw(uid, data) {
    keys(data, ["requestId", "alertId", "contextToken", "note"]);
    request(data);
    if (
      !identifier(data.alertId) ||
      !/^[a-f0-9]{64}$/.test(data.contextToken ?? "") ||
      !text(data.note, 10, 1000)
    ) invalid("Provide a withdrawal reason.");
    const hash = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await sha256(
        JSON.stringify({
          operation: "broadcast-action",
          alertId: data.alertId,
          contextToken: data.contextToken,
          note: data.note.trim(),
        }),
      );
    return db.transaction(async (tx) => {
      const [profile, receipt, doc] = await Promise.all([
        tx.get(`users/${uid}`),
        tx.get(`communication_requests/${hash}`),
        tx.get(`alerts/${data.alertId}`),
      ]);
      admin(profile);
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          invalid("This retry belongs to another action.");
        }
        return { ...receipt.data.result, replay: true };
      }
      if (
        !doc.exists || doc.data.sparkManaged !== true ||
        await token(uid, doc) !== data.contextToken ||
        doc.data.status === "withdrawn"
      ) conflict();
      const revision = doc.data.revision + 1,
        result = {
          saved: true,
          operation: "broadcast-action",
          resourceId: data.alertId,
          revision,
          replay: false,
          notification: "saved_in_app",
          queuedCount: 0,
        };
      tx.set(doc.path, {
        status: "withdrawn",
        revision,
        withdrawnAt: serverTime,
        withdrawalReason: data.note.trim(),
      }, { merge: true });
      tx.set(`communication_audits/${hash}`, {
        operation: "broadcast-action",
        resourceId: data.alertId,
        performedByUid: uid,
        revision,
        note: data.note.trim(),
        createdAt: serverTime,
      }, { create: true });
      tx.set(receipt.path, { fingerprint, result, createdAt: serverTime }, {
        create: true,
      });
      return result;
    });
  }
  return {
    submit,
    feedback,
    publish,
    withdraw,
    feedbackContext: (uid, data) => context(uid, data, "feedback"),
    broadcastContext: (uid, data) => context(uid, data, "broadcast"),
  };
}
