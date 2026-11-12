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

export function validateReport(data, now = Date.now()) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new ProofError("invalid-argument", "Invalid report.");
  }
  for (
    const [key, maximum] of [["requestId", 128], ["roadId", 128], [
      "title",
      200,
    ], ["description", 2000]]
  ) {
    if (
      typeof data[key] !== "string" || !data[key].trim() ||
      data[key].length > maximum
    ) throw new ProofError("invalid-argument", `Invalid ${key}.`);
  }
  if (
    !/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId) || !identifier(data.roadId)
  ) throw new ProofError("invalid-argument", "Invalid report identifier.");
  if (
    !["Low", "Medium", "High"].includes(data.severity) ||
    typeof data.isEmergency !== "boolean"
  ) throw new ProofError("invalid-argument", "Invalid severity.");
  const { lat, lng } = data.location ?? {};
  if (
    !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 ||
    Math.abs(lng) > 180
  ) throw new ProofError("invalid-argument", "Invalid location.");
  const observedAt = data.observedAt == null
    ? null
    : Date.parse(data.observedAt);
  if (observedAt !== null && !Number.isFinite(observedAt)) {
    throw new ProofError("invalid-argument", "Invalid observation time.");
  }
  const location = { lat, lng };
  if (["gps", "manual"].includes(data.location.source)) {
    location.source = data.location.source;
  }
  if (data.location.gpsAccuracyMeters != null) {
    if (
      !Number.isFinite(data.location.gpsAccuracyMeters) ||
      data.location.gpsAccuracyMeters < 0
    ) throw new ProofError("invalid-argument", "Invalid GPS accuracy.");
    location.gpsAccuracyMeters = data.location.gpsAccuracyMeters;
  }
  if (data.location.gpsCapturedAt != null) {
    const timestamp = Date.parse(data.location.gpsCapturedAt);
    if (!Number.isFinite(timestamp) || timestamp > now + 60000) {
      throw new ProofError("invalid-argument", "Invalid GPS timestamp.");
    }
    location.gpsCapturedAt = data.location.gpsCapturedAt;
  }
  return {
    title: data.title.trim(),
    description: data.description.trim(),
    severity: data.severity,
    roadId: data.roadId,
    isEmergency: data.isEmergency,
    observedAt,
    location,
  };
}

// Matches the existing report geometry behavior; checked against its domain fixtures.
function points(value) {
  if (!value) return [];
  if (Array.isArray(value)) {
    if (value.length >= 2 && value.slice(0, 2).every(Number.isFinite)) {
      return [value.slice(0, 2)];
    }
    return value.flatMap(points);
  }
  const lng = value.lon ?? value.lng ?? value.longitude,
    lat = value.lat ?? value.latitude;
  return Number.isFinite(lng) && Number.isFinite(lat) ? [[lng, lat]] : [];
}
function lines(geometry) {
  if (!geometry) return [];
  if (geometry.type === "Feature") return lines(geometry.geometry);
  if (Array.isArray(geometry.segments)) {
    return geometry.segments.map((s) => points(s.points)).filter((s) =>
      s.length >= 2
    );
  }
  if (geometry.type === "MultiLineString") {
    return (geometry.coordinates ?? []).map(points).filter((s) =>
      s.length >= 2
    );
  }
  const line = points(geometry.coordinates);
  return line.length >= 2 ? [line] : [];
}
function distance(a, b) {
  const rad = Math.PI / 180, lat = (a[1] + b[1]) / 2 * rad;
  return Math.hypot((a[0] - b[0]) * rad * Math.cos(lat), (a[1] - b[1]) * rad) *
    6371000;
}
export function roadDistance(location, geometry) {
  const p = [location.lng, location.lat];
  let best = Infinity;
  for (const line of lines(geometry)) {
    for (let i = 0; i < line.length; i++) {
      const a = line[i], b = line[i + 1];
      best = Math.min(best, distance(p, a));
      if (!b) continue;
      const cos = Math.cos(p[1] * Math.PI / 180),
        dx = (b[0] - a[0]) * cos,
        dy = b[1] - a[1];
      const t = clamp(
        (((p[0] - a[0]) * cos) * dx + (p[1] - a[1]) * dy) /
          (dx * dx + dy * dy || 1),
        0,
        1,
      );
      best = Math.min(
        best,
        distance(p, [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]),
      );
    }
  }
  return best;
}

export function createReportSubmitter(
  { db, photos, clock = Date.now, followupsEnabled = false, adminNotices = false },
) {
  return async (uid, data) => {
    const payload = validateReport(data, clock());
    const imageUrl = data.location?.imageUrl ?? null;
    if (imageUrl !== null && typeof imageUrl !== "string") {
      throw new ProofError("invalid-argument", "Invalid photo reference.");
    }
    if (data.expectedReportId != null && !identifier(data.expectedReportId)) {
      throw new ProofError("invalid-argument", "Invalid report to update.");
    }
    const id = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await sha256(
        JSON.stringify({
          payload,
          imageUrl,
          ...(data.expectedReportId
            ? { expectedReportId: data.expectedReportId }
            : {}),
        }),
      );
    const receiptPath = `report_requests/${id}`;
    const receipt = await db.get(receiptPath);
    function replay(document) {
      if (document.data.fingerprint !== fingerprint) {
        throw new ProofError(
          "already-exists",
          "Request identifier already used for different content.",
          409,
        );
      }
      return { reportId: document.data.reportId, replay: true };
    }
    if (receipt.exists) return replay(receipt);
    if (imageUrl) await photos.validate(imageUrl, uid);
    const slotPath = `report_slots/${await sha256(`${uid}|${payload.roadId}`)}`;
    return db.transaction(async (tx) => {
      const [saved, user, road, slot] = await Promise.all([
        tx.get(receiptPath),
        tx.get(`users/${uid}`),
        tx.get(`roads/${payload.roadId}`),
        tx.get(slotPath),
      ]);
      if (saved.exists) return replay(saved);
      if (!user.exists) {
        throw new ProofError(
          "failed-precondition",
          "Create the test account profile before reporting.",
        );
      }
      if (!road.exists) {
        throw new ProofError(
          "not-found",
          "Selected road is no longer available.",
          404,
        );
      }
      const now = clock();
      if (
        payload.observedAt !== null &&
        (payload.observedAt > now + 60000 ||
          now - payload.observedAt >= maxObservationAge)
      ) {
        throw new ProofError(
          "invalid-argument",
          "Observation time must be within the last 24 hours.",
        );
      }
      const existing = data.expectedReportId
        ? await tx.get(`reports/${data.expectedReportId}`)
        : slot.exists
        ? await tx.get(`reports/${slot.data.reportId}`)
        : await tx.pending(uid, payload.roadId);
      const incidentPath = `road_incidents/${payload.roadId}`,
        incidentDoc = await tx.get(incidentPath),
        incident = incidentDoc.data;
      const continuing = incidentDoc.exists && incident.state !== "resolved";
      const isUpdate = existing?.exists && !existing.data.clarificationRequestId &&
        ["pending", "under_review"].includes(existing.data.status) &&
        (!incidentDoc.exists || continuing);
      if (
        followupsEnabled && continuing && existing?.exists &&
        existing.data.userId === uid && existing.data.status !== "dismissed" &&
        existing.data.incidentId === incident.incidentId
      ) {
        throw new ProofError(
          "followup-required",
          "Add a dated follow-up to your existing report instead of replacing its evidence.",
          409,
        );
      }
      if (
        data.expectedReportId &&
        (!isUpdate || existing.data.userId !== uid ||
          (slot.exists && slot.data.reportId !== data.expectedReportId) ||
          existing.path !== `reports/${data.expectedReportId}` ||
          millis(existing.data.lastUpdatedByUser ?? existing.data.createdAt) !==
            data.expectedUpdatedAt)
      ) {
        throw new ProofError(
          "failed-precondition",
          "This report changed or was reviewed. Refresh before updating it.",
          409,
        );
      }
      const rank = { Low: 0, Medium: 1, High: 2 },
        elapsed = now - millis(user.data.lastReportAt);
      const escalation = isUpdate &&
        rank[payload.severity] > rank[existing.data.severity] &&
        elapsed >= 60000 && now - millis(user.data.lastEscalationAt) >= 300000;
      if (elapsed < 300000 && !escalation) {
        throw new ProofError("resource-exhausted", "SPAM_COOLDOWN", 429);
      }
      const proximity = roadDistance(payload.location, road.data.geometry);
      if (
        !payload.isEmergency && (!Number.isFinite(proximity) || proximity > 500)
      ) throw new ProofError("failed-precondition", "OUT_OF_RANGE");
      const reportPath = isUpdate ? existing.path : `reports/${id}`,
        incidentId = continuing ? incident.incidentId : id;
      const responsePath = `${incidentPath}/responses/${await sha256(
          `${incidentId}|${uid}`,
        )}`,
        response = await tx.get(responsePath);
      const observedAt = new Date(payload.observedAt ?? now),
        trust = Number.isFinite(user.data.trustScore)
          ? user.data.trustScore
          : 25;
      const write = {
        ...payload,
        observedAt,
        expiresAt: new Date(observedAt.getTime() + maxObservationAge),
        incidentId,
        userId: uid,
        authorityScore: clamp(trust + (imageUrl ? 30 : 0)),
        updatedAt: serverTime,
        lastUpdatedByUser: serverTime,
        locationCheck: {
          method: "provided_coordinates",
          distanceMeters: Number.isFinite(proximity) ? proximity : null,
          emergencyBypass: payload.isEmergency,
          gpsCapturedAt: payload.location.gpsCapturedAt ?? null,
          gpsAccuracyMeters: payload.location.gpsAccuracyMeters ?? null,
          source: payload.location.source ?? "unspecified",
        },
        ...(imageUrl ? { imageUrl } : {}),
      };
      if (!isUpdate) {
        Object.assign(write, {
          status: "pending",
          createdAt: serverTime,
          confidenceScore: 0,
          originalSubmission: {
            title: payload.title,
            description: payload.description,
            severity: payload.severity,
            observedAt,
            submittedAt: new Date(now),
            imageUrl,
            photoSubmittedAt: imageUrl ? new Date(now) : null,
            snapshotType: "original_submission",
            recordedAt: new Date(now),
          },
          ...(imageUrl ? { photoSubmittedAt: serverTime } : {}),
        });
      }
      if (!imageUrl && isUpdate && existing.data.imageUrl) {
        write.authorityScore = clamp(trust + 30);
      }
      const state = continuing && incident.state === "under_verification"
        ? "under_verification"
        : "reported_flooding";
      const counts = { ...incident.counts },
        withdraw = response.exists && !response.data.withdrawnByReport;
      if (withdraw) {
        counts[response.data.choice] = Math.max(
          0,
          (counts[response.data.choice] ?? 0) - 1,
        );
        tx.set(responsePath, { withdrawnByReport: true }, { merge: true });
      }
      if (continuing) {
        tx.set(incidentPath, {
          state,
          expiresAt: new Date(
            Math.max(observedAt.getTime(), millis(incident.lastObservedAt)) +
              maxObservationAge,
          ),
          lastObservedAt: new Date(
            Math.max(observedAt.getTime(), millis(incident.lastObservedAt)),
          ),
          ...(withdraw ? { counts } : {}),
          reviewRequired: true,
          revision: incident.revision + 1,
        }, { merge: true });
      } else {tx.set(incidentPath, {
          roadId: payload.roadId,
          incidentId,
          state: "reported_flooding",
          startedAt: serverTime,
          lastObservedAt: observedAt,
          expiresAt: new Date(observedAt.getTime() + maxObservationAge),
          lastConfirmedAt: null,
          reviewedAt: null,
          counts: { still_flooded: 0, appears_passable: 0, cannot_confirm: 0 },
          reviewRequired: true,
          revision: 1,
        });}
      if (
        road.data.communityCondition !== state ||
        road.data.activeIncidentId !== incidentId
      ) {
        tx.set(road.path, {
          communityCondition: state,
          activeIncidentId: incidentId,
          riskInputsUpdatedAt: serverTime,
        }, { merge: true });
      }
      tx.set("system/road_inputs", { updatedAt: serverTime }, { merge: true });
      if (adminNotices && !isUpdate) write.adminNoticeEventId = await queueAdminReportNotice(tx, {
        reportId:reportPath.split("/").at(-1),userId:uid,requestHash:id,
        kind:"report_new_admin",now:clock(),
      });
      tx.set(reportPath, write, { merge: true });
      const reportId = reportPath.split("/").at(-1);
      tx.set(slotPath, { userId: uid, roadId: payload.roadId, reportId });
      tx.set(user.path, {
        lastReportAt: serverTime,
        ...(escalation ? { lastEscalationAt: serverTime } : {}),
      }, { merge: true });
      tx.set(receiptPath, {
        userId: uid,
        fingerprint,
        reportId,
        createdAt: serverTime,
        ...(data.editFingerprint
          ? { editFingerprint: data.editFingerprint }
          : {}),
      }, { create: true });
      return { reportId, replay: false };
    });
  };
}

export function createResidentUpdater(
  { db, photos, clock = Date.now, followupsEnabled = false },
) {
  const submit = createReportSubmitter({ db, photos, clock, followupsEnabled });
  return async (uid, data) => {
    if (
      !data || !identifier(data.reportId) ||
      !/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId ?? "") ||
      !Number.isFinite(data.expectedUpdatedAt) ||
      !["Low", "Medium", "High"].includes(data.severity) ||
      typeof data.description !== "string" || !data.description.trim() ||
      data.description.length > 2000 ||
      !Number.isFinite(Date.parse(data.observedAt))
    ) {
      throw new ProofError(
        "invalid-argument",
        "Check the updated report details.",
      );
    }
    const editFingerprint = await sha256(
      JSON.stringify({
        reportId: data.reportId,
        severity: data.severity,
        description: data.description.trim(),
        observedAt: data.observedAt,
        expectedUpdatedAt: data.expectedUpdatedAt,
      }),
    );
    const receipt = await db.get(
      `report_requests/${await sha256(`${uid}|${data.requestId}`)}`,
    );
    if (receipt.exists) {
      if (
        receipt.data.editFingerprint !== editFingerprint ||
        receipt.data.reportId !== data.reportId
      ) {
        throw new ProofError(
          "already-exists",
          "This retry identifier belongs to another update.",
          409,
        );
      }
      return { reportId: data.reportId, replay: true };
    }
    const report = await db.get(`reports/${data.reportId}`);
    if (!report.exists || report.data.userId !== uid) {
      throw new ProofError(
        "permission-denied",
        "Only the reporter can update this report.",
        403,
      );
    }
    if (followupsEnabled || report.data.reportType === "followup") {
      throw new ProofError(
        "followup-required",
        "Add a dated follow-up instead of editing earlier evidence.",
        409,
      );
    }
    return submit(uid, {
      requestId: data.requestId,
      title: report.data.title,
      description: data.description.trim(),
      severity: data.severity,
      roadId: report.data.roadId,
      isEmergency: report.data.isEmergency === true,
      observedAt: data.observedAt,
      location: {
        ...report.data.location,
        ...(report.data.imageUrl ? { imageUrl: report.data.imageUrl } : {}),
      },
      expectedReportId: data.reportId,
      expectedUpdatedAt: data.expectedUpdatedAt,
      editFingerprint,
    });
  };
}
