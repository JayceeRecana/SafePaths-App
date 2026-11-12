import {
  clamp,
  identifier,
  millis,
  ProofError,
  serverTime,
  sha256,
} from "./proof_common.mjs";

const active = (status) => ["pending", "under_review", "waiting_resident"].includes(status);
const roadLabels = {
  passable: "Passable",
  partial: "Partially passable",
  not_passable: "Not passable",
};
const canonical = (value) =>
  value instanceof Date
    ? value.getTime()
    : Array.isArray(value)
    ? value.map(canonical)
    : value && typeof value === "object"
    ? Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonical(value[key])]),
    )
    : value;
const digest = (value) => sha256(JSON.stringify(canonical(value)));
function fail(code, message, status = 400) {
  throw new ProofError(code, message, status);
}
function ids(data) {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    fail("invalid-argument", "Invalid review details.");
  }
  if (data.reportId != null && !identifier(data.reportId)) {
    fail("invalid-argument", "Choose a valid report.");
  }
  const roads = data.roadIds ?? [];
  if (
    !Array.isArray(roads) || roads.length > 20 ||
    roads.some((id) => !identifier(id)) ||
    new Set(roads).size !== roads.length ||
    (!data.reportId && !roads.length)
  ) fail("invalid-argument", "Choose one report or up to twenty roads.");
  if (data.reportId && roads.length) {
    fail(
      "invalid-argument",
      "Review the report's linked road separately from bulk edits.",
    );
  }
  if (data.sourceReportId != null &&
      (!identifier(data.sourceReportId) || data.reportId != null || roads.length !== 1)) {
    fail("invalid-argument", "Link a source report to its one road only.");
  }
  return roads;
}
async function load(get, data) {
  let roadIds = ids(data), report = null, rootReport = null, sourceReport = null;
  if (data.sourceReportId != null) {
    sourceReport = await get(`reports/${data.sourceReportId}`);
    if (!sourceReport.exists) fail("not-found", "The source report is no longer available.", 404);
    if (sourceReport.data.roadId !== roadIds[0] || !identifier(sourceReport.data.userId)) {
      fail("failed-precondition", "The source report does not match this road.", 409);
    }
  }
  if (data.reportId) {
    report = await get(`reports/${data.reportId}`);
    if (!report.exists) {
      fail("not-found", "This report is no longer available.", 404);
    }
    roadIds = identifier(report.data.roadId) ? [report.data.roadId] : [];
    if (report.data.reportType === "followup") {
      if (!identifier(report.data.rootReportId)) {
        fail("failed-precondition", "The original report link is invalid.");
      }
      rootReport = await get(`reports/${report.data.rootReportId}`);
      if (
        !rootReport.exists || rootReport.data.userId !== report.data.userId ||
        rootReport.data.incidentId !== report.data.incidentId
      ) {
        fail(
          "failed-precondition",
          "The linked original report could not be confirmed.",
        );
      }
    }
  }
  const roads = await Promise.all(
    roadIds.map(async (id) => ({
      road: await get(`roads/${id}`),
      incident: await get(`road_incidents/${id}`),
    })),
  );
  if (roads.some((item) => !item.road.exists)) {
    fail("not-found", "A selected road is no longer available.", 404);
  }
  const token = await digest({
    report: report?.data ?? null,
    rootReport: rootReport?.data ?? null,
    sourceReport: sourceReport ? { id: data.sourceReportId, data: sourceReport.data } : null,
    roads: roads.map(({ road, incident }) => ({
      id: road.path,
      status: road.data.status,
      notes: road.data.notes ?? null,
      updatedAt: road.data.updatedAt ?? null,
      vulnerability: road.data.vulnerability ?? null,
      isVerified: road.data.isVerified ?? null,
      updatedByUid: road.data.updatedByUid ?? null,
      source: road.data.source ?? null,
      name: road.data.name ?? null,
      // An independent current-condition check is not a review of resident
      // evidence. New incident counters must not invalidate that check. The
      // transaction still reads the latest incident and preserves report reviews.
      // Evidence decisions remain bound to the full incident and report snapshot.
      incident: report && incident.exists ? incident.data : null,
    })),
  });
  return { report, rootReport, sourceReport, roads, token };
}
export function createAdminWorkflow(
  { db, clock = Date.now, followupsEnabled = false },
) {
  async function context(uid, data) {
    if ((await db.get(`users/${uid}`)).data.role !== "admin") {
      fail("permission-denied", "Administrator access required.", 403);
    }
    const state = await load((path) => db.get(path), data);
    return {
      workflowVersion: 2,
      reportRoadLinkSupported: true,
      token: state.token,
      sourceReport: state.sourceReport ? {
        id: data.sourceReportId,
        roadId: state.sourceReport.data.roadId,
        status: state.sourceReport.data.status,
      } : null,
      report: state.report ? { ...state.report.data, id: data.reportId } : null,
      rootReport: state.rootReport
        ? { ...state.rootReport.data, id: state.report.data.rootReportId }
        : null,
      selfReview: state.report?.data.userId === uid,
      roads: state.roads.map(({ road, incident }) => ({
        id: road.path.split("/").at(-1),
        name: road.data.name ?? "Road",
        status: road.data.status,
        isVerified: road.data.isVerified === true,
        updatedAt: road.data.updatedAt ?? null,
        incidentId: incident.data.incidentId ?? null,
        incidentRevision: incident.data.revision ?? null,
      })),
    };
  }
  async function action(uid, data) {
    ids(data);
    if (
      !/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId ?? "") ||
      ![
        "start",
        "reply",
        "verify",
        "dismiss",
        "road_review",
        "correct_followup",
        "request_clarification",
      ].includes(
        data.action,
      )
    ) fail("invalid-argument", "Invalid review request.");
    if (data.action !== "road_review" && !data.reportId) {
      fail("invalid-argument", "Choose a report for this action.");
    }
    if (data.action === "road_review" && data.reportId) {
      fail("invalid-argument", "Use report verification for a linked report.");
    }
    if (data.sourceReportId != null && data.action !== "road_review") {
      fail("invalid-argument", "A source-report reference is only for a separate road update.");
    }
    const message = typeof data.message === "string" ? data.message.trim() : "";
    if (data.action === "reply" && (!message || message.length > 1000)) {
      fail("invalid-argument", "Enter a message of 1–1000 characters.");
    }
    const review = ["verify", "road_review"].includes(data.action);
    const observationOnly = data.action === "verify" && data.observationOnly === true;
    if (
      data.vulnerability != null &&
      !["low", "medium", "high"].includes(data.vulnerability)
    ) fail("invalid-argument", "Choose a valid road vulnerability.");
    const note = typeof data.note === "string" ? data.note.trim() : "";
    if (
      data.action === "correct_followup" && (!followupsEnabled ||
        !["mistaken_approval", "confirmed_false"].includes(data.reason) ||
        note.length < 10 || note.length > 1000 ||
        data.reason === "confirmed_false" && data.confirmedFalseReport !== true)
    ) {
      fail(
        "invalid-argument",
        "Describe the correction and explicitly confirm any evidence of a false submission.",
      );
    }
    if (
      review && !observationOnly &&
      (!Object.hasOwn(roadLabels, data.roadStatus) ||
        data.verifiedCurrentConditions !== true || note.length < 10 ||
        note.length > 1000)
    ) {
      fail(
        "invalid-argument",
        "Confirm current conditions and describe the source and findings (10–1000 characters).",
      );
    }
    if ((data.action === "request_clarification" || observationOnly || data.action === "dismiss") &&
        (note.length < 10 || note.length > 1000)) {
      fail("invalid-argument", "Explain this decision for the resident (10-1000 characters).");
    }
    if (observationOnly && (data.roadStatus != null || data.verifiedCurrentConditions === true)) {
      fail("invalid-argument", "An observation-only review must not change the road.");
    }
    if (
      data.action === "dismiss" &&
      !["spam_false", "duplicate_resolved", "needs_correction", "unable_to_verify"].includes(
        data.reason,
      )
    ) fail("invalid-argument", "Choose a dismissal reason.");
    if (
      data.action !== "reply" && !/^[a-f0-9]{64}$/.test(data.contextToken ?? "")
    ) {
      fail(
        "failed-precondition",
        "Refresh the report before reviewing it.",
        409,
      );
    }
    const requestHash = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await digest(data);
    return db.transaction(async (tx) => {
      const [admin, receipt] = await Promise.all([
        tx.get(`users/${uid}`),
        tx.get(`admin_requests/${requestHash}`),
      ]);
      if (admin.data.role !== "admin") {
        fail("permission-denied", "Administrator access required.", 403);
      }
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          fail(
            "already-exists",
            "This retry identifier belongs to a different action.",
            409,
          );
        }
        return { ...receipt.data.result, replay: true };
      }
      const state = await load((path) => tx.get(path), data),
        report = state.report;
      if (
        report?.data.userId === uid &&
        ["start", "verify", "dismiss", "correct_followup", "request_clarification"].includes(data.action)
      ) {
        fail(
          "self-review",
          "Another administrator must review your own report or follow-up.",
          403,
        );
      }
      if (data.action !== "reply" && state.token !== data.contextToken) {
        fail(
          "failed-precondition",
          "New information arrived. Refresh and review it before saving.",
          409,
        );
      }
      if (
        ["start", "verify", "dismiss", "request_clarification"].includes(data.action) &&
        !active(report.data.status)
      ) {
        fail(
          "failed-precondition",
          "This report was already reviewed. Refresh its current outcome.",
          409,
        );
      }
      if (
        data.action === "dismiss" && report.data.isEmergency &&
        data.confirmEmergency !== true
      ) {
        fail(
          "failed-precondition",
          "Explicitly acknowledge dismissal of this SOS report.",
        );
      }
      if (
        data.action === "dismiss" && data.reason === "spam_false" &&
        data.confirmedFalseReport !== true
      ) {
        fail(
          "failed-precondition",
          "Confirm evidence of a false or spam report before deducting trust.",
        );
      }
      if (review && !observationOnly && !state.roads.length) {
        fail(
          "failed-precondition",
          "Link this report to an existing road before verifying it.",
        );
      }
      if (
        data.action === "verify" && !observationOnly && state.roads[0].incident.exists &&
        report.data.incidentId !== state.roads[0].incident.data.incidentId
      ) {
        fail(
          "failed-precondition",
          "This report belongs to an older incident. Review the current road incident instead.",
          409,
        );
      }
      if (report && !identifier(report.data.userId)) {
        fail(
          "failed-precondition",
          "This report has no valid reporter account.",
        );
      }
      const owner = report ? await tx.get(`users/${report.data.userId}`) : null;
      const isFollowup = report?.data.reportType === "followup";
      if (
        isFollowup && data.action === "verify" &&
        active(state.rootReport.data.status)
      ) {
        fail(
          "failed-precondition",
          "Review the original observation before verifying its follow-up.",
          409,
        );
      }
      if (
        isFollowup && data.action === "dismiss" &&
        ["spam_false", "needs_correction"].includes(data.reason) &&
        (note.length < 10 || note.length > 1000)
      ) {
        fail(
          "invalid-argument",
          "Explain the evidence decision or the clarification being requested.",
        );
      }
      if (isFollowup && !followupsEnabled) {
        fail("unavailable", "Follow-up review is not enabled yet.", 503);
      }
      if (data.reason === "needs_correction" && !isFollowup) {
        fail("invalid-argument", "Use the original-report dismissal reasons.");
      }
      if (
        data.action === "correct_followup" &&
        (!isFollowup || report.data.status !== "verified" ||
          report.data.rewardCorrectedAt)
      ) {
        fail(
          "failed-precondition",
          "Only an uncorrected verified follow-up can be corrected.",
          409,
        );
      }
      const rewardPath = report && followupsEnabled
        ? `incident_rewards/${await sha256(
          `${report.data.userId}|${report.data.incidentId ?? report.path}`,
        )}`
        : null;
      const reward = rewardPath ? await tx.get(rewardPath) : null;
      const incidentHistory = [];
      const related = [];
      if (review) {
        for (const item of state.roads) {
          const reports = item.incident.exists
            ? await tx.query(
              "reports",
              "incidentId",
              item.incident.data.incidentId,
              101,
            )
            : [];
          if (reports.length > 100) {
            fail(
              "resource-exhausted",
              "This incident requires a smaller supervised review batch.",
              429,
            );
          }
          related.push(
            ...reports.filter((doc) =>
              active(doc.data.status) || doc.data.status === "expired"
            ),
          );
          incidentHistory.push(...reports);
        }
      }
      if (related.length > 80) {
        fail("resource-exhausted", "Review fewer roads at a time.", 429);
      }
      const result = {
        saved: true,
        action: data.action,
        reportId: data.reportId ?? null,
        pointsAwarded: 0,
        replay: false,
        notification: "saved_in_app",
        ...(state.sourceReport ? { sourceReportId: data.sourceReportId } : {}),
        ...(isFollowup ? { reportType: "followup" } : {}),
      };
      const updates = new Map(), messages = new Map();
      const patch = (doc, value) =>
        updates.set(doc.path, { ...(updates.get(doc.path) ?? {}), ...value });
      const messageFor = (doc, text) => messages.set(doc.path, { doc, text });
      if (data.action === "start" && report.data.status !== "pending") {
        fail("failed-precondition", "This report is already being reviewed or awaiting a reply.", 409);
      }
      if (data.action === "request_clarification" && report.data.status === "waiting_resident") {
        fail("failed-precondition", "A clarification request is already waiting for this resident.", 409);
      }
      if (data.action === "request_clarification") {
        patch(report, { status: "waiting_resident", clarificationRequestId: requestHash,
          clarificationRequestedAt: serverTime, clarificationRepliedAt: null });
        tx.set(`report_clarifications/${requestHash}`, { reportId: data.reportId,
          userId: report.data.userId, question: note, createdAt: serverTime,
          requestedByUid: uid, answered: false }, { create: true });
        messageFor(report, `Please clarify your report: ${note} Reply from this report's updates. No trust points were deducted. Only respond from a safe place; do not enter floodwater.`);
      } else if (data.action === "start") {
        patch(report, {
          status: "under_review",
          reviewStartedAt: serverTime,
          reviewStartedByUid: uid,
        });
        messageFor(
          report,
          "An administrator has started reviewing your report. This does not confirm rescue dispatch.",
        );
      } else if (data.action === "reply") messageFor(report, message);
      else if (data.action === "dismiss") {
        const spam = data.reason === "spam_false",
          score = Number.isFinite(owner.data.trustScore)
            ? Math.round(clamp(owner.data.trustScore))
            : 50;
        const penalty = owner.exists && spam
          ? -Math.min(isFollowup ? 5 : 15, score)
          : 0;
        patch(report, {
          status: "dismissed",
          dismissReason: data.reason,
          reviewedAt: serverTime,
          dismissedAt: serverTime,
          reviewedByUid: uid,
          pointsAwarded: penalty,
        });
        if (owner.exists && spam) {
          tx.set(owner.path, {
            trustScore: score + penalty,
            dismissedReports: (Number.isInteger(owner.data.dismissedReports)
              ? owner.data.dismissedReports
              : 0) + 1,
          }, { merge: true });
        }
        result.pointsAwarded = penalty;
        messageFor(
          report,
          spam
            ? `Your ${
              isFollowup ? "follow-up" : "report"
            } was dismissed as false or spam after review. Trust change: ${penalty}.${
              isFollowup
                ? ` ${note} Your original report keeps its recorded outcome.`
                : ` ${note}`
            }`
            : data.reason === "unable_to_verify"
            ? `We could not verify this observation. ${note} No trust points were deducted. The road condition was not changed.`
            : data.reason === "needs_correction"
            ? `Your follow-up needs correction or clearer evidence. ${note} No trust points were deducted. Your original report keeps its recorded outcome.`
            : `Your submission was recorded as a duplicate. ${note} No trust points were deducted.`,
        );
      } else if (data.action === "correct_followup") {
        const score = owner.exists && Number.isFinite(owner.data.trustScore)
          ? Math.round(clamp(owner.data.trustScore))
          : 0;
        const previousPoints = Number.isInteger(report.data.pointsAwarded)
          ? Math.max(0, Math.min(5, report.data.pointsAwarded))
          : 0;
        const reversed = Math.min(score, previousPoints);
        const penalty = data.reason === "confirmed_false"
          ? Math.min(score - reversed, 5)
          : 0;
        result.pointsAwarded = -reversed - penalty;
        result.pointsReversed = reversed;
        result.falsePenalty = penalty;
        patch(report, {
          status: "dismissed",
          dismissReason: data.reason,
          rewardCorrectedAt: serverTime,
          rewardCorrection: { reversed, penalty, adminUid: uid, note },
          reviewedAt: serverTime,
        });
        if (owner.exists) {
          tx.set(owner.path, { trustScore: score - reversed - penalty }, {
            merge: true,
          });
        }
        if (reward?.exists) {
          tx.set(reward.path, {
            correctedFollowupId: data.reportId,
            correctedAt: serverTime,
          }, { merge: true });
        }
        for (const item of state.roads) {
          if (
            item.incident.exists &&
            item.incident.data.incidentId === report.data.incidentId
          ) {
            tx.set(item.incident.path, {
              state: "under_verification",
              reviewRequired: true,
              revision: item.incident.data.revision + 1,
            }, { merge: true });
            tx.set(item.road.path, {
              communityCondition: "under_verification",
              riskInputsUpdatedAt: serverTime,
            }, { merge: true });
          }
        }
        messageFor(
          report,
          `Follow-up review corrected. Bonus reversal: -${reversed}. False-submission penalty: -${penalty}. ${note} Your original report's outcome and reward were not changed.`,
        );
      } else if (review) {
        const roadStatus = observationOnly ? null : data.roadStatus,
          condition = roadStatus === "passable"
            ? "resolved"
            : "admin_confirmed";
        for (const { road, incident } of observationOnly ? [] : state.roads) {
          tx.set(road.path, {
            status: roadStatus,
            notes: note,
            updatedAt: serverTime,
            riskInputsUpdatedAt: serverTime,
            updatedByUid: uid,
            source: "manual",
            isVerified: true,
            ...(data.vulnerability == null
              ? {}
              : { vulnerability: data.vulnerability }),
            ...(incident.exists
              ? {
                communityCondition: condition,
                communityReviewedAt: serverTime,
              }
              : {}),
          }, { merge: true });
          if (incident.exists) {
            tx.set(incident.path, {
              state: condition,
              reviewRequired: false,
              reviewedAt: serverTime,
                  lastObservedAt: serverTime,
              expiresAt: new Date(clock() + 24 * 3600000),
              revision: incident.data.revision + 1,
            }, { merge: true });
          }
        }
        if (roadStatus === "passable") {
          for (const doc of related) {
            // Updating the road never completes another resident's evidence review.
            patch(doc, { incidentReviewedAt: serverTime, incidentReviewStatus: roadStatus });
            messageFor(
              doc,
              `The road incident was reviewed. Current road condition: ${
                roadLabels[roadStatus]
              }. ${note} Your observation still awaits its own review. No additional trust points have been awarded.`,
            );
          }
        }
        if (report) {
          const lastGain = millis(
            owner.data.roadReputationGains?.[report.data.roadId],
          );
          const score = Number.isFinite(owner.data.trustScore)
            ? Math.round(clamp(owner.data.trustScore))
            : 50;
          let points = owner.exists &&
              (!lastGain || clock() - lastGain >= 12 * 60 * 60 * 1000)
            ? Math.min(10, 100 - score)
            : 0;
          if (followupsEnabled) {
            const historicalBase = incidentHistory.some((doc) =>
              doc.path !== report.path &&
              doc.data.userId === report.data.userId &&
              doc.data.reportType !== "followup" &&
              doc.data.status === "verified"
            );
            const baseClaimed = reward?.data.baseClaimed === true ||
              historicalBase;
            const bonusClaimed = reward?.data.followupClaimed === true ||
              incidentHistory.some((doc) =>
                doc.path !== report.path &&
                doc.data.userId === report.data.userId &&
                doc.data.reportType === "followup" &&
                doc.data.meaningfulFollowup === true &&
                doc.data.status === "verified"
              );
            if (isFollowup) {
              const meaningful = data.meaningfulFollowup === true &&
                report.data.conditionChange !== "unchanged";
              points = owner.exists && meaningful && !bonusClaimed
                ? Math.min(5, 100 - score)
                : 0;
              patch(report, { meaningfulFollowup: meaningful });
              tx.set(rewardPath, {
                userId: report.data.userId,
                incidentId: report.data.incidentId,
                baseClaimed,
                followupClaimed: bonusClaimed || meaningful,
                ...(meaningful && !bonusClaimed
                  ? { followupReportId: data.reportId }
                  : {}),
                updatedAt: serverTime,
              }, { merge: true });
            } else {
              if (baseClaimed) points = 0;
              tx.set(rewardPath, {
                userId: report.data.userId,
                incidentId: report.data.incidentId,
                baseClaimed: true,
                followupClaimed: bonusClaimed,
                baseReportId: data.reportId,
                updatedAt: serverTime,
              }, { merge: true });
            }
          }
          result.pointsAwarded = points;
          patch(report, {
            status: "verified",
            reviewedAt: serverTime,
            resolvedAt: serverTime,
            reviewedByUid: uid,
            ...(observationOnly ? {} : { incidentReviewStatus: roadStatus }),
              observationOnlyReview: observationOnly,
            pointsAwarded: points,
          });
          if (owner.exists) {
            tx.set(owner.path, {
              trustScore: score + points,
              [isFollowup ? "verifiedFollowups" : "verifiedReports"]:
                (Number.isInteger(
                    owner.data[
                      isFollowup ? "verifiedFollowups" : "verifiedReports"
                    ],
                  )
                  ? owner
                    .data[isFollowup ? "verifiedFollowups" : "verifiedReports"]
                  : 0) + 1,
              ...(points && !isFollowup
                ? {
                  roadReputationGains: {
                    ...(owner.data.roadReputationGains ?? {}),
                    [report.data.roadId]: new Date(clock()),
                  },
                }
                : {}),
            }, { merge: true });
          }
          messageFor(
            report,
            `Your observation was verified. ${observationOnly ? "The current road condition was not changed." : `Road condition: ${roadLabels[roadStatus]}.`} ${note}${
              points
                ? ` Trust change: +${points}.`
                : " No additional trust points were awarded."
            }`,
          );
        }
        if (state.sourceReport) {
          // A contextual link is not verification of this resident's evidence.
          // The map key also replaces a generic reopen message, avoiding duplicates.
          messageFor(state.sourceReport,
            `Road update linked to your report: ${roadLabels[roadStatus]}. ${note} ` +
            (active(state.sourceReport.data.status)
              ? "Your observation still awaits its own review. "
              : "Your report's existing review outcome was not changed. ") +
            "No additional trust points were awarded for this road update.");
        }
        if (!observationOnly) result.roadStatus = roadStatus;
        result.observationOnly = observationOnly;
      }
      for (const { doc, text } of messages.values()) {
        const messageId = await sha256(`${requestHash}|${doc.path}`);
        // Message bodies stay in owner/admin-only records, outside the legacy
        // report feed. Existing legacy replies are not copied or republished.
        patch(doc, { hasAdminUpdates: true, adminRepliedAt: serverTime });
        tx.set(`report_messages/${messageId}`, {
          reportId: doc.path.split("/").at(-1),
          userId: doc.data.userId,
          message: text,
          senderUid: uid,
          sender: "SafePaths administrator",
          createdAt: serverTime,
        }, { create: true });
        tx.set(`notification_outbox/${messageId}`, {
          kind: "report_update",
          queueClass: "report",
          requestHash,
          reportId: doc.path.split("/").at(-1),
          userId: doc.data.userId,
          eventId: messageId,
          body: text,
          createdAt: serverTime,
          status: "awaiting_sender",
          dispatchable: true,
          dueAt: new Date(clock()),
          expiresAt: new Date(clock() + 3600000),
        }, { create: true });
      }
      tx.set("system/road_inputs", { updatedAt: serverTime }, { merge: true });
      for (const [path, value] of updates) tx.set(path, { ...value, recordUpdatedAt: serverTime }, { merge: true });
      tx.set(`admin_audits/${requestHash}`, {
        action: data.action,
        reportId: data.reportId ?? null,
        sourceReportId: data.sourceReportId ?? null,
        roadIds: state.roads.map(({ road }) => road.path.split("/").at(-1)),
        performedByUid: uid,
        pointsAwarded: result.pointsAwarded,
        note: review || data.action === "correct_followup" ||
            data.action === "dismiss" || data.action === "request_clarification"
          ? note
          : null,
        ...(data.action === "correct_followup"
          ? {
            pointsReversed: result.pointsReversed,
            falsePenalty: result.falsePenalty,
          }
          : {}),
        createdAt: serverTime,
      }, { create: true });
      tx.set(`admin_requests/${requestHash}`, {
        fingerprint,
        result,
        createdAt: serverTime,
      }, { create: true });
      return result;
    });
  }
  return { context, action };
}
