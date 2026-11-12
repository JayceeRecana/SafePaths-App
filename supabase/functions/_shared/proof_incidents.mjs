import {
  identifier,
  maxObservationAge,
  millis,
  ProofError,
  serverTime,
  sha256,
} from "./proof_common.mjs";

const choices = ["still_flooded", "appears_passable", "cannot_confirm"];
export function createResidentObservations({ db, clock = Date.now }) {
  return async (uid, data) => {
    if (
      !data || !identifier(data.roadId) ||
      !/^[a-f0-9]{64}$/.test(data.incidentId ?? "") ||
      !/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId ?? "") ||
      !choices.includes(data.choice)
    ) {
      throw new ProofError(
        "invalid-argument",
        "Choose a valid current observation.",
      );
    }
    const observedAt = Date.parse(data.observedAt);
    if (!Number.isFinite(observedAt)) {
      throw new ProofError(
        "invalid-argument",
        "Choose a valid observation time.",
      );
    }
    const hash = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await sha256(
        JSON.stringify({
          roadId: data.roadId,
          incidentId: data.incidentId,
          choice: data.choice,
          observedAt: data.observedAt,
          operation: "community_observation",
        }),
      );
    return db.transaction(async (tx) => {
      const [receipt, incident, road] = await Promise.all([
        tx.get(`incident_requests/${hash}`),
        tx.get(`road_incidents/${data.roadId}`),
        tx.get(`roads/${data.roadId}`),
      ]);
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          throw new ProofError(
            "already-exists",
            "This retry belongs to another observation.",
            409,
          );
        }
        return { saved: true, replay: true };
      }
      if (
        !road.exists || !incident.exists ||
        incident.data.incidentId !== data.incidentId ||
        incident.data.state === "resolved"
      ) {
        throw new ProofError(
          "failed-precondition",
          "This incident changed or was resolved. Refresh the road details.",
          409,
        );
      }
      if (observedAt > clock() + 60000 || clock() - observedAt > 300000) {
        throw new ProofError(
          "observation-stale",
          "Observe current conditions safely and submit again.",
          409,
        );
      }
      const [previous, ownReports] = await Promise.all([
        tx.get(
          `${incident.path}/responses/${await sha256(
            `${data.incidentId}|${uid}`,
          )}`,
        ),
        tx.queryWhere("reports", [["incidentId", "EQUAL", data.incidentId], [
          "userId",
          "EQUAL",
          uid,
        ]], 1),
      ]);
      if (ownReports.length) {
        throw new ProofError(
          "self-confirmation",
          "Update your report instead of confirming your own incident.",
          409,
        );
      }
      if (
        previous.exists && clock() - millis(previous.data.submittedAt) < 60000
      ) {
        throw new ProofError(
          "resource-exhausted",
          "Wait one minute before updating your observation.",
          429,
        );
      }
      const counts = Object.fromEntries(
        choices.map(
          (choice) => [
            choice,
            Math.max(
              0,
              Number.isInteger(incident.data.counts?.[choice])
                ? incident.data.counts[choice]
                : 0,
            ),
          ],
        ),
      );
      if (
        previous.exists && choices.includes(previous.data.choice) &&
        !previous.data.withdrawnByReport
      ) {
        counts[previous.data.choice] = Math.max(
          0,
          counts[previous.data.choice] - 1,
        );
      }
      counts[data.choice]++;
      const state = data.choice === "appears_passable"
        ? "under_verification"
        : data.choice === "still_flooded" &&
            incident.data.state !== "under_verification"
        ? "reported_flooding"
        : incident.data.state;
      const latest = Math.max(observedAt, millis(incident.data.lastObservedAt));
      tx.set(incident.path, {
        counts,
        state,
        revision: incident.data.revision + 1,
        ...(data.choice !== "cannot_confirm"
          ? {
            lastObservedAt: new Date(latest),
            expiresAt: new Date(latest + maxObservationAge),
            reviewRequired: true,
          }
          : {}),
        ...(data.choice === "still_flooded"
          ? {
            lastConfirmedAt: new Date(
              Math.max(observedAt, millis(incident.data.lastConfirmedAt)),
            ),
          }
          : {}),
      }, { merge: true });
      tx.set(previous.path, {
        uid,
        incidentId: data.incidentId,
        choice: data.choice,
        observedAt: new Date(observedAt),
        submittedAt: serverTime,
        withdrawnByReport: false,
      });
      if (road.data.communityCondition !== state) {
        tx.set(road.path, {
          communityCondition: state,
          riskInputsUpdatedAt: serverTime,
        }, { merge: true });
      }
      tx.set("system/road_inputs", { updatedAt: serverTime }, { merge: true });
      tx.set(`incident_requests/${hash}`, {
        fingerprint,
        createdAt: serverTime,
      }, { create: true });
      tx.set(`incident_audits/${hash}`, {
        roadId: data.roadId,
        incidentId: data.incidentId,
        performedByUid: uid,
        action: "community_observation",
        choice: data.choice,
        observedAt: new Date(observedAt),
        timestamp: serverTime,
      }, { create: true });
      return { saved: true, replay: false };
    });
  };
}
