import { adminReportKinds, eligibleReportAdmin, expandAdminReportNotice } from "./admin_report_notifications.mjs";
import { assertBackendProfile, assertBackendProject, TEST_BACKEND, MARULAS_BACKEND, eligibleMember } from "./backend_profile.mjs";
import {
  identifier,
  millis,
  ProofError,
  serverTime,
  sha256,
} from "./proof_common.mjs";

const hour = 3600000, day = 24 * hour;
const terminal = new Set([
  "fcm_accepted",
  "no_device",
  "expired",
  "account_unavailable",
  "failed",
  "suppressed",
]);
const genericTitle = "SafePaths report update";
const genericBody =
  "An update is available in your report history. Open SafePaths to check it.";
const validToken = (value) =>
  typeof value === "string" && /^[A-Za-z0-9_:\-]{20,4096}$/.test(value);
function invalid(message) {
  throw new ProofError("invalid-argument", message);
}

// A successful FCM response means accepted by FCM, never confirmed on a phone.
export class ProofFcm {
  constructor({ projectId, credential, fetcher = fetch, clock = Date.now, profile = TEST_BACKEND }) {
    assertBackendProject(projectId, profile);
    this.profile = profile;
    this.projectId = projectId;
    this.credential = credential;
    this.fetcher = fetcher;
    this.clock = clock;
  }
  async account(uid) {
    const response = await this.fetcher(
      `https://identitytoolkit.googleapis.com/v1/projects/${this.projectId}/accounts:lookup`,
      {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(8000),
        headers: {
          authorization: `Bearer ${await this.credential.token()}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ localId: [uid] }),
      },
    );
    if (!response.ok) throw new Error("Account check unavailable.");
    const user = (await response.json()).users?.find((user) =>
      user.localId === uid
    );
    const validSince = Number(user?.validSince ?? 0) * 1000;
    return {
      enabled: !!user && !user.disabled && user.emailVerified === true &&
        Number.isFinite(validSince) && validSince >= 0,
      validSince,
    };
  }
  async send(
    {
      token,
      eventId,
      reportId,
      feedbackId,
      alertId,
      studyArea,
      kind = "report_update",
      uid,
      expiresAt,
    },
    { validateOnly = false } = {},
  ) {
    if (
      !["report_update", ...adminReportKinds, "feedback_update", "broadcast_update"].includes(kind)
    ) throw new Error("Invalid notification type.");
    const resource = (kind === "report_update" || adminReportKinds.includes(kind))
      ? { reportId }
      : kind === "feedback_update"
      ? { feedbackId }
      : { alertId, studyArea };
    if (
      !identifier(Object.values(resource)[0]) ||
      kind === "broadcast_update" && studyArea !== this.profile.area
    ) throw new Error("Invalid notification resource.");
    const copy = adminReportKinds.includes(kind)
      ? {title:kind === "report_new_admin" ? "New report needs review" : "Resident reply received",
         body:"Open SafePaths to review the report and its latest details."}
      : kind === "report_update"
      ? { title: genericTitle, body: genericBody }
      : kind === "feedback_update"
      ? {
        title: "SafePaths feedback update",
        body:
          "A private update is available in your feedback history. Open SafePaths to check it.",
      }
      : {
        title: "SafePaths area alert",
        body:
          "An alert is available for your area. Open SafePaths to check its current details.",
      };
    const ttl = Math.max(
      0,
      Math.min(3600, Math.floor((expiresAt - this.clock()) / 1000)),
    );
    const response = await this.fetcher(
      `https://fcm.googleapis.com/v1/projects/${this.projectId}/messages:send`,
      {
        method: "POST",
        redirect: "error",
        signal: AbortSignal.timeout(10000),
        headers: {
          authorization: `Bearer ${await this.credential.token()}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          validate_only: validateOnly,
          message: {
            ...(validateOnly
              ? { topic: "safepaths_proof_validation_only" }
              : { token }),
            notification: copy,
            data: {
              type: kind,
              eventId,
              ...resource,
              recipientUid: uid,
            },
            android: {
              priority: "HIGH",
              ttl: `${ttl}s`,
              restricted_package_name: this.profile === MARULAS_BACKEND
                ? "com.safepaths.safepaths_app"
                : "com.safepaths.safepaths_app.test",
              collapse_key: kind === "broadcast_update"
                ? "safepaths_area_alerts"
                : kind === "feedback_update"
                ? "safepaths_feedback_updates"
                : "safepaths_report_updates",
              notification: {
                channel_id: kind === "broadcast_update"
                  ? "safepaths_alerts"
                  : "safepaths_reports",
                tag: eventId,
                visibility: "PRIVATE",
              },
            },
          },
        }),
      },
    );
    const body = await response.json().catch(() => ({}));
    if (
      response.ok && typeof body.name === "string" &&
      body.name.startsWith(`projects/${this.projectId}/messages/`)
    ) return { status: "accepted" };
    const code = body.error?.details?.find((item) =>
      item["@type"] === "type.googleapis.com/google.firebase.fcm.v1.FcmError"
    )?.errorCode;
    if (response.status === 404 && code === "UNREGISTERED") {
      return { status: "invalid_token" };
    }
    // INVALID_ARGUMENT may describe our payload; never delete a token on it.
    const retryable = [408, 429, 500, 502, 503, 504].includes(response.status);
    const header = response.headers.get("retry-after");
    const after = header && /^\d+$/.test(header)
      ? Number(header) * 1000
      : header
      ? Date.parse(header) - this.clock()
      : 0;
    return {
      status: retryable ? "retry" : "failed",
      retryAfterMs: Number.isFinite(after) ? Math.max(0, after) : 0,
      code: response.status === 401 || response.status === 403
        ? "sender_authorization"
        : retryable
        ? "provider_temporary"
        : "provider_rejected",
    };
  }
}

export function createProofPush(
  {
    db,
    fcm,
    allowedUids = new Set(),
    profile = TEST_BACKEND,
    clock = Date.now,
    random = () => crypto.randomUUID(),
    communicationsEnabled = false,
  },
) {
  assertBackendProfile(profile);
  const area = profile.area;
  async function preflight(uid, data = {}) {
    const kind = data.kind ?? "report_update";
    if (
      !["report_update", ...adminReportKinds, "feedback_update", "broadcast_update"].includes(kind)
    ) invalid("Invalid notification type.");
    if ((await db.get(`users/${uid}`)).data.role !== "admin") {
      throw new ProofError(
        "permission-denied",
        "Administrator access required.",
        403,
      );
    }
    const result = await fcm.send({
      eventId: "0".repeat(64),
      kind,
      reportId: "spark-proof-validation",
      feedbackId: "spark-proof-validation",
      alertId: "spark-proof-validation",
      studyArea: area,
      uid,
      expiresAt: clock() + hour,
    }, { validateOnly: true });
    if (result.status !== "accepted") {
      throw new ProofError(
        "unavailable",
        "The test push sender could not be validated.",
        503,
      );
    }
    return { senderValidated: true, deviceDeliveryTested: false };
  }
  async function device(uid, data) {
    if (
      !data || !/^[A-Za-z0-9_-]{32,128}$/.test(data.installation ?? "") ||
      !Number.isSafeInteger(data.sequence) || data.sequence < 1 ||
      !["register", "unregister"].includes(data.mode)
    ) invalid("Invalid device registration.");
    if (data.mode === "register" && !validToken(data.token)) {
      invalid("Invalid notification token.");
    }
    const studyArea = data.studyArea ?? null;
    if (studyArea !== null && studyArea !== area) {
      invalid("Invalid test area.");
    }
    const id = await sha256(data.installation),
      tokenHash = data.mode === "register" ? await sha256(data.token) : null;
    return db.transaction(async (tx) => {
      const saved = await tx.get(`push_devices/${id}`), current = saved.data;
      if (saved.exists && data.sequence < current.sequence) {
        throw new ProofError(
          "failed-precondition",
          "A newer account registration already exists.",
          409,
        );
      }
      if (saved.exists && data.sequence === current.sequence) {
        if (
          current.userId === uid &&
          current.active === (data.mode === "register") &&
          (data.mode === "unregister" ||
            current.tokenHash === tokenHash &&
              (current.studyArea ?? null) === studyArea)
        ) return { registered: current.active, sequence: data.sequence };
        throw new ProofError(
          "already-exists",
          "This registration sequence was already used.",
          409,
        );
      }
      if (data.mode === "unregister") {
        if (saved.exists && current.userId !== uid) {
          throw new ProofError(
            "permission-denied",
            "This device belongs to another signed-in account.",
            403,
          );
        }
        if (current.tokenHash) {
          const index = await tx.get(`push_token_claims/${current.tokenHash}`);
          if (index.data.deviceId === id) {
            tx.set(index.path, { active: false }, { merge: true });
          }
        }
        tx.set(`push_devices/${id}`, {
          userId: uid,
          sequence: data.sequence,
          active: false,
          ownerKey: null,
          updatedAt: serverTime,
        }, { merge: true });
        return { registered: false, sequence: data.sequence };
      }
      const claim = await tx.get(`push_token_claims/${tokenHash}`);
      if (claim.data.active && claim.data.deviceId !== id) {
        throw new ProofError(
          "already-exists",
          "This token is registered to another installation.",
          409,
        );
      }
      const owned = await tx.query("push_devices", "ownerKey", uid, 4);
      if (
        owned.filter((doc) => doc.path !== `push_devices/${id}`).length >= 3
      ) {
        throw new ProofError(
          "resource-exhausted",
          "Three devices are already registered for this account.",
          429,
        );
      }
      if (current.tokenHash && current.tokenHash !== tokenHash) {
        const old = await tx.get(`push_token_claims/${current.tokenHash}`);
        if (old.data.deviceId === id) {
          tx.set(old.path, { active: false }, { merge: true });
        }
      }
      const version = current.active && current.userId === uid &&
          current.tokenHash === tokenHash &&
          (current.studyArea ?? null) === studyArea
        ? current.bindingVersion
        : random();
      tx.set(`push_devices/${id}`, {
        userId: uid,
        sequence: data.sequence,
        tokenHash,
        studyArea,
        token: data.token,
        active: true,
        ownerKey: uid,
        bindingVersion: version,
        registeredAt: serverTime,
        updatedAt: serverTime,
      });
      tx.set(`push_token_claims/${tokenHash}`, {
        deviceId: id,
        active: true,
        userId: uid,
      });
      return { registered: true, sequence: data.sequence };
    });
  }
  async function status(uid, data) {
    if (!/^[a-f0-9]{64}$/.test(data?.eventId ?? "")) {
      invalid("Choose a valid notification event.");
    }
    const event = await db.get(`notification_outbox/${data.eventId}`),
      profile = await db.get(`users/${uid}`);
    if (
      !event.exists ||
      (event.data.userId !== uid && profile.data.role !== "admin")
    ) {
      throw new ProofError(
        "permission-denied",
        "Notification status is unavailable for this account.",
        403,
      );
    }
    return {
      status: event.data.status,
      acceptedCount: Object.keys(event.data.accepted ?? {}).length,
      deviceReceiptConfirmed: false,
    };
  }
  async function finish(path, lease, changes) {
    return db.transaction(async (tx) => {
      const current = await tx.get(path);
      if (current.data.lease !== lease) return false;
      tx.set(path, {
        ...changes,
        lease: null,
        leaseUntil: null,
        updatedAt: serverTime,
      }, { merge: true });
      return true;
    });
  }
  const kindOf = (value) => value.kind ?? "report_update";
  async function authorized(event, eventId) {
    if (adminReportKinds.includes(kindOf(event))) {
      const [report, recipient] = await Promise.all([
        db.get(`reports/${event.reportId}`),db.get(`users/${event.userId}`),
      ]);
      return report.exists && report.data.status === "pending" &&
        report.data.adminNoticeEventId === event.parentEventId &&
        report.data.userId === event.sourceUid &&
        eligibleReportAdmin(recipient,profile,allowedUids,event.sourceUid);
    }
    if (profile === MARULAS_BACKEND && !eligibleMember(await db.get(`users/${event.userId}`), profile)) return false;
    const kind = kindOf(event);
    if (kind === "report_update") {
      const [report, message] = await Promise.all([
        db.get(`reports/${event.reportId}`),
        db.get(`report_messages/${eventId}`),
      ]);
      return report.exists && message.exists &&
        report.data.userId === event.userId &&
        message.data.userId === event.userId &&
        message.data.reportId === event.reportId;
    }
    if (kind === "feedback_update") {
      const [feedback, message] = await Promise.all([
        db.get(`feedbacks/${event.feedbackId}`),
        db.get(`feedback_messages/${eventId}`),
      ]);
      return feedback.exists && message.exists &&
        feedback.data.userId === event.userId &&
        feedback.data.allowFollowUp === true &&
        message.data.userId === event.userId &&
        message.data.feedbackId === event.feedbackId &&
        message.data.revision === event.revision &&
        feedback.data.revision >= event.revision;
    }
    if (kind === "broadcast_update") {
      const [alert, profile] = await Promise.all([
        db.get(`alerts/${event.alertId}`),
        db.get(`users/${event.userId}`),
      ]);
      return alert.exists && alert.data.sparkManaged === true &&
        alert.data.studyArea === event.studyArea &&
        event.studyArea === area && alert.data.status === "active" &&
        millis(alert.data.expiresAt) > clock() &&
        alert.data.revision === event.revision &&
        alert.data.requestHash === event.requestHash &&
        profile.data.role === "user" &&
        (profile.data.studyArea == null ||
          profile.data.studyArea === event.studyArea);
    }
    return false;
  }
  async function process(path) {
    const work = await db.get(path);
    if (work.data.kind === "report_admin_fanout") {
      try { return await expandAdminReportNotice({db,path,profile,allowedUids,clock}); }
      catch (_) {
        // Audience failures never roll back evidence; retain durable retry work.
        await db.transaction(async tx => {
          const current = await tx.get(path);
          if (current.data.dispatchable) tx.set(path,{dueAt:new Date(clock()+60000)}, {merge:true});
        });
        return "retry";
      }
    }
    const lease = random();
    const event = await db.transaction(async (tx) => {
      const doc = await tx.get(path), value = doc.data;
      if (
        !doc.exists || terminal.has(value.status) || !value.dispatchable ||
        millis(value.dueAt) > clock() || millis(value.leaseUntil) > clock()
      ) return null;
      if (
        (profile === TEST_BACKEND && !allowedUids.has(value.userId)) ||
        !["report_update", ...adminReportKinds, "feedback_update", "broadcast_update"].includes(
          kindOf(value),
        ) ||
        !identifier(
          (kindOf(value) === "report_update" || adminReportKinds.includes(kindOf(value)))
            ? value.reportId
            : kindOf(value) === "feedback_update"
            ? value.feedbackId
            : value.alertId,
        ) ||
        millis(value.expiresAt) <= clock()
      ) {
        tx.set(path, {
          status: "expired",
          dispatchable: false,
          updatedAt: serverTime,
        }, { merge: true });
        return null;
      }
      tx.set(path, {
        lease,
        leaseUntil: new Date(clock() + 90000),
        dueAt: new Date(clock() + 90000),
        status: "sending",
        attempts: (value.attempts ?? 0) + 1,
      }, { merge: true });
      return { ...value, attempts: (value.attempts ?? 0) + 1 };
    });
    if (!event) return "skipped";
    const eventId = path.split("/").at(-1),
      accepted = { ...(event.accepted ?? {}) },
      discarded = { ...(event.discarded ?? {}) };
    try {
      const [account, eligible] = await Promise.all([
        fcm.account(event.userId),
        authorized(event, eventId),
      ]);
      if (!account.enabled || !eligible) {
        const status = kindOf(event) === "report_update"
          ? "account_unavailable"
          : "suppressed";
        await finish(path, lease, { status, dispatchable: false });
        return status;
      }
      const devices = await db.query("push_devices", [[
        "ownerKey",
        "EQUAL",
        event.userId,
      ]], { limit: 4 });
      if (devices.length > 3) throw new Error("Unexpected device count.");
      const targets = event.targets ??
        Object.fromEntries(
          devices.filter((doc) =>
            doc.data.active &&
            (kindOf(event) !== "broadcast_update" ||
              doc.data.studyArea === event.studyArea)
          ).map(
            (doc) => [doc.path.split("/").at(-1), doc.data.bindingVersion],
          ),
        );
      // Persist a stable target snapshot before any external send. New logins do
      // not inherit an older account's pending notification.
      const claimed = await db.transaction(async (tx) => {
        const current = await tx.get(path);
        if (current.data.lease !== lease) return false;
        tx.set(path, { targets }, { merge: true });
        return true;
      });
      if (!claimed) return "skipped";
      let retry = false, retryAfter = 0, failed = false;
      for (const [id, version] of Object.entries(targets)) {
        if (
          millis(event.expiresAt) <= clock() ||
          kindOf(event) !== "report_update" && !await authorized(event, eventId)
        ) {
          await finish(path, lease, {
            accepted,
            discarded,
            status: "suppressed",
            dispatchable: false,
          });
          return "suppressed";
        }
        if (accepted[id] || discarded[id]) continue;
        const latest = await db.get(`push_devices/${id}`), value = latest.data;
        if (
          !value.active || value.userId !== event.userId ||
          value.bindingVersion !== version || !validToken(value.token) ||
          kindOf(event) === "broadcast_update" &&
            value.studyArea !== event.studyArea ||
          millis(value.registeredAt) <
            Math.max(account.validSince, clock() - 30 * day)
        ) {
          discarded[id] = "registration_changed";
          continue;
        }
        const renewed = await db.transaction(async (tx) => {
          const current = await tx.get(path);
          if (current.data.lease !== lease) return false;
          tx.set(path, {
            leaseUntil: new Date(clock() + 90000),
            dueAt: new Date(clock() + 90000),
          }, { merge: true });
          return true;
        });
        if (!renewed) return "skipped";
        const result = await fcm.send({
          token: value.token,
          eventId,
          kind: kindOf(event),
          ...((kindOf(event) === "report_update" || adminReportKinds.includes(kindOf(event)))
            ? { reportId: event.reportId }
            : kindOf(event) === "feedback_update"
            ? { feedbackId: event.feedbackId }
            : { alertId: event.alertId, studyArea: event.studyArea }),
          uid: event.userId,
          expiresAt: millis(event.expiresAt),
        });
        if (result.status === "accepted") accepted[id] = true;
        else if (result.status === "invalid_token") {
          discarded[id] = "unregistered";
          await db.transaction(async (tx) => {
            const current = await tx.get(latest.path);
            if (current.data.bindingVersion === version) {
              tx.set(latest.path, {
                active: false,
                ownerKey: null,
                updatedAt: serverTime,
              }, { merge: true });
              const claim = await tx.get(
                `push_token_claims/${value.tokenHash}`,
              );
              if (claim.data.deviceId === id) {
                tx.set(claim.path, { active: false }, { merge: true });
              }
            }
          });
        } else if (result.status === "failed") {
          discarded[id] = result.code ?? "provider_rejected";
          failed = true;
        } else {
          retry = true;
          retryAfter = Math.max(retryAfter, result.retryAfterMs ?? 0);
        }
        // A saved provider acknowledgement prevents another send on an ordinary
        // retry. A crash between provider acceptance and this write can duplicate
        // delivery; the stable event/tag also deduplicates the client display.
        await db.transaction(async (tx) => {
          const current = await tx.get(path);
          if (current.data.lease === lease) {
            tx.set(path, { accepted, discarded }, { merge: true });
          }
        });
      }
      if (retry) {
        const wait = Math.max(
          retryAfter,
          Math.min(hour, 60000 * 2 ** Math.min(event.attempts - 1, 6)),
        );
        const exhausted = event.attempts >= 8 ||
          clock() + wait >= millis(event.expiresAt);
        await finish(path, lease, {
          accepted,
          discarded,
          status: exhausted ? "failed" : "retry",
          dispatchable: !exhausted,
          dueAt: new Date(clock() + wait),
        });
        return exhausted ? "failed" : "retry";
      }
      const state = failed
        ? "failed"
        : Object.keys(accepted).length
        ? "fcm_accepted"
        : "no_device";
      await finish(path, lease, {
        accepted,
        discarded,
        status: state,
        dispatchable: false,
      });
      return state;
    } catch (_) {
      const wait = Math.min(hour, 60000 * 2 ** Math.min(event.attempts - 1, 6));
      const exhausted = event.attempts >= 8 ||
        clock() + wait >= millis(event.expiresAt);
      await finish(path, lease, {
        accepted,
        discarded,
        status: exhausted ? "failed" : "retry",
        dispatchable: !exhausted,
        dueAt: new Date(clock() + wait),
      });
      return exhausted ? "failed" : "retry";
    }
  }
  async function drain({ requestHash } = {}) {
    if (requestHash != null && !/^[a-f0-9]{64}$/.test(requestHash)) {
      invalid("Invalid saved request.");
    }
    let rows;
    if (requestHash) {
      rows = await db.query("notification_outbox", [[
        "requestHash",
        "EQUAL",
        requestHash,
      ], ["dispatchable", "EQUAL", true]], { limit: 3 });
    } else if (!communicationsEnabled) {
      rows = await db.query("notification_outbox", [[
        "dispatchable",
        "EQUAL",
        true,
      ], ["dueAt", "LESS_THAN_OR_EQUAL", new Date(clock())]], {
        limit: 3,
        orderBy: [{ field: { fieldPath: "dueAt" }, direction: "ASCENDING" }],
      });
    } else {
      const due = [["dispatchable", "EQUAL", true], [
        "dueAt",
        "LESS_THAN_OR_EQUAL",
        new Date(clock()),
      ]];
      const orderBy = [{
        field: { fieldPath: "dueAt" },
        direction: "ASCENDING",
      }];
      const [oldest, ...lanes] = await Promise.all([
        db.query("notification_outbox", due, { limit: 3, orderBy }),
        ...["report", "feedback", "broadcast"].map((queueClass) =>
          db.query("notification_outbox", [
            ["queueClass", "EQUAL", queueClass],
            ...due,
          ], { limit: 1, orderBy })
        ),
      ]);
      const selected = new Map();
      const legacy = oldest.find((row) => !row.data.queueClass);
      if (legacy) selected.set(legacy.path, legacy);
      for (const lane of lanes) {
        for (const row of lane) {
          if (selected.size < 3) selected.set(row.path, row);
        }
      }
      for (const row of oldest) {
        if (selected.size < 3) selected.set(row.path, row);
      }
      rows = [...selected.values()];
    }
    const result = {
      examined: rows.length,
      fcmAccepted: 0,
      retry: 0,
      finishedWithoutAcceptance: 0,
    };
    const started = Date.now();
    for (const row of rows) {
      if (Date.now() - started > 45000) break;
      const outcome = await process(row.path);
      if (outcome === "fcm_accepted") result.fcmAccepted++;
      else if (outcome === "retry") result.retry++;
      else result.finishedWithoutAcceptance++;
    }
    return result;
  }
  return { device, status, drain, process, preflight };
}

export async function verifyWorker(authorization, secret) {
  if (typeof secret !== "string" || !/^[A-Za-z0-9_-]{43,128}$/.test(secret)) {
    return false;
  }
  const value = authorization?.startsWith("Bearer ")
    ? authorization.slice(7)
    : "";
  return (await sha256(value)) === (await sha256(secret));
}

// pg_net can expose queued headers to database roles. Queue only a short-lived
// HMAC ticket; the reusable secret stays in Vault and managed server settings.
export async function verifyWorkerTicket(
  headers,
  secret,
  clock = Date.now,
  purpose = "",
) {
  if (typeof secret !== "string" || !/^[A-Za-z0-9_-]{43,128}$/.test(secret)) {
    return null;
  }
  const time = headers.get("x-proof-worker-time"),
    nonce = headers.get("x-proof-worker-nonce"),
    signature = headers.get("x-proof-worker-signature");
  if (
    !/^\d{10}$/.test(time ?? "") || !/^[a-f0-9]{32}$/.test(nonce ?? "") ||
    !/^[a-f0-9]{64}$/.test(signature ?? "") ||
    Math.abs(clock() - Number(time) * 1000) > 120000
  ) return null;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const bytes = Uint8Array.from(
    signature.match(/../g).map((pair) => parseInt(pair, 16)),
  );
  const valid = await crypto.subtle.verify(
    "HMAC",
    key,
    bytes,
    new TextEncoder().encode(`${time}.${nonce}${purpose ? `.${purpose}` : ""}`),
  );
  return valid ? nonce : null;
}
