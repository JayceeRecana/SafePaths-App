import { assertBackendProfile, TEST_BACKEND, MARULAS_BACKEND, requireMainMember, requireMainRoadScope } from "./backend_profile.mjs";
import { createReportClarifications } from "./report_clarifications.mjs";
import { validateMediaJpeg } from "./proof_media.mjs";
import {
  identifier,
  maxPhotoBytes,
  ProofError,
  readBounded,
  sha256,
} from "./proof_common.mjs";
import {
  createReportSubmitter,
  createResidentUpdater,
} from "./proof_reports.mjs";
import { createAdminWorkflow } from "./admin_workflow.mjs";
import { createReportFollowups } from "./report_followups.mjs";
import { createResidentObservations } from "./proof_incidents.mjs";
import { verifyWorker, verifyWorkerTicket } from "./proof_push.mjs";

export function createProofHandler(
  {
    db,
    photos,
    verify,
    allowedUids = new Set(),
    profile = TEST_BACKEND,
    clock = Date.now,
    followupsEnabled = false,
    adminNotices = false,
    push =
      /** @type {ReturnType<typeof import('./proof_push.mjs').createProofPush>|null} */ (null),
    workerSecret = "",
    roads =
      /** @type {ReturnType<typeof import('./proof_roads.mjs').createRoadMaintenance>|null} */ (null),
    media =
      /** @type {ReturnType<typeof import("./proof_media.mjs").createMediaWorkflow>|null} */ (null),
    communications =
      /** @type {ReturnType<typeof import("./proof_communications.mjs").createCommunications>|null} */ (null),
    core =
      /** @type {ReturnType<typeof import("./proof_core.mjs").createCoreMaintenance>|null} */ (null),
    background = /** @type {((task:Promise<unknown>)=>void)|null} */ (null),
  },
) {
  assertBackendProfile(profile);
  if (profile === TEST_BACKEND && (
    !(allowedUids instanceof Set) || allowedUids.size < 1 ||
    allowedUids.size > 10 || ![...allowedUids].every(identifier)
  )) {
    throw new Error(
      "Configure one to ten explicitly allowed synthetic test accounts.",
    );
  }
  const submit = createReportSubmitter({ db, photos, clock, followupsEnabled, adminNotices });
  const update = createResidentUpdater({ db, photos, clock, followupsEnabled });
  const observe = createResidentObservations({ db, clock });
  const admin = createAdminWorkflow({ db, clock, followupsEnabled });
  const clarifications = createReportClarifications({ db, photos, clock, adminNotices });
  const followups = createReportFollowups({ db, photos, clock, adminNotices });
  function kickAdminNotices(uid, data) {
    if (adminNotices && push && background) {
      try { background((async () => {
        const requestHash = await sha256(`${uid}|${data.requestId}`);
        // First pass expands the audience; second pass starts bounded delivery.
        await push.drain({requestHash}); await push.drain({requestHash});
      })().catch(() => {})); } catch (_) { /* durable worker retries */ }
    }
  }
  const json = (data, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: {
        "content-type": "application/json",
        "cache-control": "no-store",
        "x-content-type-options": "nosniff",
      },
    });
  async function assertMainRollout() {
    if (profile !== MARULAS_BACKEND) return;
    const rollout = await db.get("system/backend_rollout");
    if (rollout.data.enabled !== true || rollout.data.version !== 1 ||
        rollout.data.studyArea !== profile.area) {
      throw new ProofError("unavailable", "The Marulas service is not activated.", 503);
    }
  }
  return async (request) => {
    try {
      // Hosted gateways and direct Edge runtime calls use these two prefixes.
      const route = new URL(request.url).pathname.match(
        new RegExp(`^/(?:functions/v1/)?${profile.functionName}(/[^?#]*)$`),
      )?.[1];
      if (!route) {
        throw new ProofError("not-found", "Unknown proof operation.", 404);
      }
      if (request.method !== "POST") {
        throw new ProofError(
          "method-not-allowed",
          "Use POST for proof operations.",
          405,
        );
      }
      if (route === "/core-maintenance") {
        const direct = core &&
          await verifyWorker(
            request.headers.get("authorization"),
            workerSecret,
          );
        const nonce = !direct && core
          ? await verifyWorkerTicket(
            request.headers,
            workerSecret,
            clock,
            "core-maintenance",
          )
          : null;
        if (!direct && !nonce) {
          throw new ProofError(
            "unauthenticated",
            "Worker authorization required.",
            401,
          );
        }
        await readBounded(request, 256);
        await assertMainRollout();
        if (nonce) {
          await db.transaction(async (tx) => {
            const path = `core_worker_requests/${await sha256(nonce)}`,
              saved = await tx.get(path);
            if (saved.exists) {
              throw new ProofError(
                "already-exists",
                "Worker ticket already used.",
                409,
              );
            }
            tx.set(path, { usedAt: new Date(clock()) }, { create: true });
          });
        }
        return json({ result: await core.run() });
      }
      if (route === "/push-drain") {
        const direct = push &&
          await verifyWorker(
            request.headers.get("authorization"),
            workerSecret,
          );
        const nonce = !direct && push
          ? await verifyWorkerTicket(request.headers, workerSecret, clock)
          : null;
        if (!direct && !nonce) {
          throw new ProofError(
            "unauthenticated",
            "Worker authorization required.",
            401,
          );
        }
        await readBounded(request, 256);
        await assertMainRollout();
        if (nonce) {
          const receipt = await sha256(nonce);
          await db.transaction(async (tx) => {
            const saved = await tx.get(`push_worker_requests/${receipt}`);
            if (saved.exists) {
              throw new ProofError(
                "already-exists",
                "Worker ticket already used.",
                409,
              );
            }
            tx.set(saved.path, { usedAt: new Date(clock()) }, { create: true });
          });
        }
        return json({ result: await push.drain() });
      }
      const uid = await verify(request.headers.get("authorization"));
      if (!identifier(uid)) {
        throw new ProofError("unauthenticated", "Invalid account.", 401);
      }
      if (profile === TEST_BACKEND && !allowedUids.has(uid)) {
        throw new ProofError(
          "permission-denied",
          "Use an authorized synthetic test account.",
          403,
        );
      }
      if (profile === MARULAS_BACKEND) await requireMainMember(db, uid);
      await assertMainRollout();
      if (
        route === "/media-upload/avatar" || route === "/media-upload/feedback"
      ) {
        if (!media) {
          throw new ProofError(
            "unavailable",
            "Test media is not enabled.",
            503,
          );
        }
        if (
          request.headers.get("content-type")?.split(";")[0] !== "image/jpeg"
        ) throw new ProofError("invalid-argument", "Attach a JPEG image.");
        const purpose = route.split("/").at(-1),
          bytes = await readBounded(
            request,
            purpose === "avatar" ? 256 * 1024 : maxPhotoBytes,
          );
        return json(await media.upload(uid, purpose, bytes));
      }
      if (route === "/photo-upload") {
        if (
          request.headers.get("content-type")?.split(";")[0] !== "image/jpeg"
        ) throw new ProofError("invalid-argument", "Attach a JPEG photo.");
        const bytes = await readBounded(request, maxPhotoBytes);
        if (
          bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216 ||
          bytes[2] !== 255 || bytes.at(-2) !== 255 || bytes.at(-1) !== 217
        ) {
          throw new ProofError(
            "invalid-argument",
            "The photo is not a valid JPEG attachment.",
          );
        }
        if (media) validateMediaJpeg(bytes, "feedback");
        const digest = await sha256(bytes);
        return json({ imageUrl: await photos.upload(uid, digest, bytes) });
      }
      const bytes = await readBounded(
        request,
        route === "/road-import" ? 200000 : 16000,
      );
      let body;
      try {
        body = JSON.parse(new TextDecoder().decode(bytes));
      } catch (_) {
        throw new ProofError("invalid-argument", "Invalid request.");
      }
      if (profile === MARULAS_BACKEND) await requireMainRoadScope(db, body?.data);
      if (
        [
          "/road-import",
          "/road-delete-context",
          "/road-delete",
          "/road-graph-rebuild",
        ].includes(route)
      ) {
        if (!roads) {
          throw new ProofError(
            "unavailable",
            "Test road maintenance is not enabled.",
            503,
          );
        }
        const operations = {
          "/road-import": roads.importRoads,
          "/road-delete-context": roads.context,
          "/road-delete": roads.remove,
          "/road-graph-rebuild": roads.rebuild,
        };
        return json({ result: await operations[route](uid, body.data) });
      }
      if (
        ["/media-read", "/profile-context", "/profile-save"].includes(route)
      ) {
        if (!media) {
          throw new ProofError(
            "unavailable",
            "Test media is not enabled.",
            503,
          );
        }
        if (route === "/profile-context") {
          if (!body.data || Object.keys(body.data).length) {
            throw new ProofError(
              "invalid-argument",
              "Profile identity is assigned by the server.",
            );
          }
          return json({ result: await media.context(uid) });
        }
        if (route === "/profile-save") {
          return json({ result: await media.save(uid, body.data) });
        }
        return new Response(await media.read(uid, body.data), {
          headers: {
            "content-type": "image/jpeg",
            "cache-control": "no-store",
            "x-content-type-options": "nosniff",
          },
        });
      }
      if (
        [
          "/feedback-submit",
          "/feedback-context",
          "/feedback-action",
          "/broadcast-publish",
          "/broadcast-context",
          "/broadcast-action",
        ].includes(route)
      ) {
        if (!communications) {
          throw new ProofError(
            "unavailable",
            "Communication test migration is not enabled.",
            503,
          );
        }
        const operations = {
          "/feedback-submit": communications.submit,
          "/feedback-context": communications.feedbackContext,
          "/feedback-action": communications.feedback,
          "/broadcast-publish": communications.publish,
          "/broadcast-context": communications.broadcastContext,
          "/broadcast-action": communications.withdraw,
        };
        const result = await operations[route](uid, body.data);
        if (result.queuedCount > 0 && push && background) {
          const requestHash = await sha256(`${uid}|${body.data.requestId}`);
          try {
            background(push.drain({ requestHash }).catch(() => {}));
          } catch (_) {}
        }
        return json({ result });
      }
      if (route === "/observe-incident" || route === "/weather-override") {
        if (!core) {
          throw new ProofError(
            "unavailable",
            "Core test migration is not enabled.",
            503,
          );
        }
        return json({
          result: route === "/observe-incident"
            ? await observe(uid, body.data)
            : await core.override(uid, body.data),
        });
      }
      if (route === "/submit-report") {
        const result = await submit(uid, body.data);
        kickAdminNotices(uid, body.data);
        return json({ result });
      }
      if (["/followup-context", "/followup-submit"].includes(route)) {
        if (!followupsEnabled) {
          throw new ProofError(
            "unavailable",
            "Follow-up reporting is not enabled for this test build yet.",
            503,
          );
        }
        const result = await (route === "/followup-context" ? followups.context : followups.submit)(uid, body.data);
        if (route === "/followup-submit") kickAdminNotices(uid, body.data);
        return json({ result });
      }
      if (["/clarification-context", "/clarification-reply"].includes(route)) {
        const result = await (route === "/clarification-context" ? clarifications.context : clarifications.reply)(uid, body.data);
        if (route === "/clarification-reply") kickAdminNotices(uid, body.data);
        return json({ result });
      }
      if (route === "/update-report") {
        return json({ result: await update(uid, body.data) });
      }
      if (route === "/admin-context") {
        return json({ result: await admin.context(uid, body.data) });
      }
      if (route === "/admin-action") {
        const result = await admin.action(uid, body.data);
        if (push && background) {
          const requestHash = await sha256(`${uid}|${body.data.requestId}`);
          try {
            background(push.drain({ requestHash }).catch(() => {}));
          } catch (_) {
            // A saved review remains successful if the optional immediate kick
            // cannot be scheduled. The durable queue is retried by the worker.
          }
        }
        return json({ result });
      }
      if (route === "/push-device" || route === "/push-status") {
        if (!push) {
          throw new ProofError(
            "unavailable",
            "Test push is not configured.",
            503,
          );
        }
        return json({
          result: route === "/push-device"
            ? await push.device(uid, body.data)
            : await push.status(uid, body.data),
        });
      }
      if (route === "/push-preflight") {
        if (!push) {
          throw new ProofError(
            "unavailable",
            "Test push is not configured.",
            503,
          );
        }
        return json({ result: await push.preflight(uid, body.data ?? {}) });
      }
      if (route === "/photo-url") {
        const reference = body.imageUrl, parsed = photos.parse(reference);
        if (parsed.uid !== uid) {
          const profile = await db.get(`users/${uid}`);
          if (profile.data.role !== "admin") {
            throw new ProofError(
              "permission-denied",
              "Only the reporter or an authorized test admin can open this photo.",
              403,
            );
          }
        }
        return json(await photos.signed(reference));
      }
      throw new ProofError("not-found", "Unknown proof operation.", 404);
    } catch (error) {
      if (error instanceof ProofError) {
        return json(
          { error: { code: error.code, message: error.message } },
          error.status,
        );
      }
      // No raw provider response, URL, token, request body or UID is logged/returned.
      return json({
        error: {
          code: "unavailable",
          message:
            "The proof service could not complete the request. Preserve the form and retry.",
        },
      }, 503);
    }
  };
}
