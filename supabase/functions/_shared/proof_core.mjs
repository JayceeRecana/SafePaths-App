import { assertBackendProfile, TEST_BACKEND } from "./backend_profile.mjs";
import {
  maxObservationAge,
  millis,
  serverTime,
  sha256,
} from "./proof_common.mjs";
import { calculateRisks, confidence } from "./risk_domain.mjs";
import { createWeather, usableWeather } from "./proof_weather.mjs";

const maxRoads = 1000, maxReports = 100;
const fields = [
  "status",
  "vulnerability",
  "neighbors",
  "updatedAt",
  "riskScore",
  "riskCategory",
  "warningStartTime",
  "propagationSource",
  "communityCondition",
  "isVerified",
  "source",
  "studyArea",
];
const inputs = (r) =>
  JSON.stringify([
    r.status,
    r.vulnerability,
    r.neighbors ?? [],
    millis(r.updatedAt),
    r.communityCondition,
    r.isVerified,
    r.source,
    r.studyArea,
  ]);
const observation = (r) =>
  millis(r.observedAt ?? r.lastUpdatedByUser ?? r.createdAt);
const different = (a, b) =>
  a.riskScore !== b.riskScore || a.riskCategory !== b.riskCategory ||
  millis(a.warningStartTime) !== millis(b.warningStartTime) ||
  (a.propagationSource ?? null) !== (b.propagationSource ?? null);
const day = (now) =>
  new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Los_Angeles",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);

// Conservative operation accounting, including transaction retries. This limits
// this worker's share; Firestore's quota also includes app/listener traffic.
function metered(db, deadline, clock) {
  const usage = { reads: 0, writes: 0 };
  function charge(kind, n) {
    if (clock() > deadline) throw new Error("core-time-budget");
    usage[kind] += n;
    if (usage.reads > 2200 || usage.writes > 1200) {
      throw new Error("core-work-limit");
    }
  }
  const wrap = (tx) => ({
    get: (path) => {
      charge("reads", 1);
      return tx.get(path);
    },
    queryWhere: async (...args) => {
      charge("reads", 1);
      const docs = await tx.queryWhere(...args);
      charge("reads", Math.max(0, docs.length - 1));
      return docs;
    },
    set: (...args) => {
      charge("writes", 1);
      return tx.set(...args);
    },
  });
  return {
    usage,
    get: (path) => {
      charge("reads", 1);
      return db.get(path);
    },
    queryPage: async (...args) => {
      charge("reads", 1);
      const page = await db.queryPage(...args);
      charge("reads", Math.max(0, page.docs.length - 1));
      return page;
    },
    query: async (...args) => {
      charge("reads", 1);
      const docs = await db.query(...args);
      charge("reads", Math.max(0, docs.length - 1));
      return docs;
    },
    transaction: (work) => db.transaction((tx) => work(wrap(tx))),
  };
}
export function createCoreMaintenance(
  { db, clock = Date.now, fetcher = fetch, profile = TEST_BACKEND },
) {
  assertBackendProfile(profile);
  const area = profile.area;
  const weather = createWeather({ db, clock, fetcher, profile });
  async function run() {
    const now = clock(),
      token = await sha256(`${now}|${crypto.randomUUID()}`),
      budgetDay = day(now);
    const acquired = await db.transaction(async (tx) => {
      const [lease, budget, setup] = await Promise.all([
        tx.get("system/risk_job"),
        tx.get("system/core_budget"),
        tx.get("system/core_setup"),
      ]);
      if (setup.data.version !== 1 || setup.data.studyArea !== area) {
        throw new Error("core-bootstrap-required");
      }
      if (millis(lease.data.leaseUntil) > now) return false;
      const reads = budget.data.day === budgetDay ? budget.data.reads ?? 0 : 0,
        writes = budget.data.day === budgetDay ? budget.data.writes ?? 0 : 0;
      if (reads + 2200 > 30000 || writes + 1200 > 12000) {
        tx.set(lease.path, {
          error: "core-daily-budget",
          lastFailure: serverTime,
        }, { merge: true });
        return false;
      }
      tx.set(budget.path, {
        day: budgetDay,
        reads: reads + 2200,
        writes: writes + 1200,
      });
      tx.set(lease.path, { token, leaseUntil: new Date(now + 180000) }, {
        merge: true,
      });
      return true;
    });
    if (!acquired) return { completed: false, reason: "busy-or-budget" };
    const work = metered(db, now + 95000, clock),
      provider = createWeather({ db: work, clock, fetcher, profile });
    let error = null, changed = 0, expiredReports = 0, expiredIncidents = 0;
    try {
      // Expiry runs even if fetching weather fails. It never deletes evidence,
      // reopens a road, or refreshes its official verification timestamp.
      // Observation freshness affects risk, not whether an admin still owes a review.
      // Pending reports stay in the queue until a reasoned review is saved.
      const due = await work.query("road_incidents", [["state", "IN", [
        "reported_flooding",
        "under_verification",
        "admin_confirmed",
      ]], [
        "lastObservedAt",
        "LESS_THAN_OR_EQUAL",
        new Date(clock() - maxObservationAge),
      ]], { limit: 51 });
      if (due.length > 50) throw new Error("core-expiry-backlog");
      for (const doc of due) {
        await work.transaction(async (tx) => {
          const [current, road] = await Promise.all([
            tx.get(doc.path),
            tx.get(`roads/${doc.path.split("/").at(-1)}`),
          ]);
          if (
            !current.exists ||
            !["reported_flooding", "under_verification", "admin_confirmed"]
              .includes(current.data.state) ||
            clock() - observation(
                    current.data.lastObservedAt
                      ? { observedAt: current.data.lastObservedAt }
                      : current.data,
                  ) < maxObservationAge
          ) return;
          tx.set(current.path, {
            state: "outdated",
            reviewRequired: true,
            revision: current.data.revision + 1,
          }, { merge: true });
          if (road.exists) {
            tx.set(road.path, {
              communityCondition: "outdated",
              riskInputsUpdatedAt: serverTime,
            }, { merge: true });
          }
          tx.set("system/road_inputs", { updatedAt: serverTime }, {
            merge: true,
          });
          expiredIncidents++;
        });
      }
      const live = await provider.refresh();
      if (!usableWeather(live.data, clock(), profile)) {
        throw new Error("weather-unavailable");
      }
      const [cached, marker] = await Promise.all([
        work.get("system/core_cache"),
        work.get("system/road_inputs"),
      ]);
      const active = await work.query("reports", [["status", "IN", [
        "pending",
        "under_review",
        "waiting_resident",
      ]], ["observedAt", "GREATER_THAN", new Date(clock() - maxObservationAge)]], { limit: maxReports + 1 });
      if (active.length > maxReports) throw new Error("core-report-limit");
      let graph, scanTime, fullAt = cached.data.fullAt;
      const full = !cached.exists || !cached.data.scanTime ||
        (cached.data.topologyRevision ?? 0) !==
          (marker.data.topologyRevision ?? 0) ||
        clock() - millis(fullAt) >= 3600000;
      if (full) {
        const page = await work.queryPage("roads", [[
          "studyArea",
          "EQUAL",
          area,
        ]], { limit: maxRoads + 1, select: fields });
        if (page.docs.length > maxRoads) throw new Error("core-road-limit");
        graph = new Map(
          page.docs.map((d) => [d.path.split("/").at(-1), d.data]),
        );
        scanTime = page.readTime;
        fullAt = new Date(clock());
      } else {
        graph = new Map((cached.data.roads ?? []).map((r) => [r.id, r]));
        const pages = await Promise.all(
          ["riskInputsUpdatedAt", "updatedAt"].map((field) =>
            work.queryPage("roads", [
              ["studyArea", "EQUAL", area],
              [field, "GREATER_THAN", cached.data.scanTime],
            ], { limit: maxRoads + 1, select: fields })
          ),
        );
        for (const page of pages) {
          if (page.docs.length > maxRoads) throw new Error("core-road-limit");
          for (const d of page.docs) {
            graph.set(d.path.split("/").at(-1), d.data);
          }
        }
        scanTime = pages.map((p) => p.readTime).filter(Boolean).sort()[0];
      }
      if (!scanTime || graph.size > maxRoads) {
        throw new Error("core-road-cache-invalid");
      }
      const reports = active.filter((r) =>
        graph.has(r.data.roadId) &&
        clock() - observation(r.data) < maxObservationAge
      ).map((r) => ({ ...r.data, id: r.path.split("/").at(-1) }));
      const roads = [...graph].map(([id, data]) => ({ ...data, id }));
      for (const id of new Set(reports.map((r) => r.roadId))) {
        const fresh = await work.get(`roads/${id}`),
          road = roads.find((r) => r.id === id);
        if (!fresh.exists || inputs(fresh.data) !== inputs(road)) {
          throw new Error("core-input-conflict");
        }
        road.geometry = fresh.data.geometry;
      }
      const results = calculateRisks(
        roads,
        reports,
        live.data.currentState,
        clock(),
      );
      const updates = results.filter((r) => different(graph.get(r.id), r));
      // Fence each chunk against weather changes, resident updates and admin
      // decisions. Partial progress never advances lastSuccess or the cache.
      async function fence(tx) {
        const [lease, currentMarker, currentWeather] = await Promise.all([
          tx.get("system/risk_job"),
          tx.get(marker.path),
          tx.get(live.path),
        ]);
        if (
          lease.data.token !== token ||
          millis(lease.data.leaseUntil) <= clock() ||
          currentMarker.updateTime !== marker.updateTime ||
          currentWeather.updateTime !== live.updateTime ||
          !usableWeather(currentWeather.data, clock(), profile)
        ) throw new Error("core-input-conflict");
      }
      for (let offset = 0; offset < updates.length; offset += 75) {
        const chunk = updates.slice(offset, offset + 75);
        await work.transaction(async (tx) => {
          await fence(tx);
          const fresh = await Promise.all(
            chunk.map((r) => tx.get(`roads/${r.id}`)),
          );
          for (let i = 0; i < chunk.length; i++) {
            if (
              !fresh[i].exists ||
              inputs(fresh[i].data) !== inputs(graph.get(chunk[i].id))
            ) throw new Error("core-input-conflict");
          }
          for (const result of chunk) {
            const { id, warningStartTime, ...derived } = result;
            tx.set(`roads/${id}`, {
              ...derived,
              warningStartTime: warningStartTime === null
                ? null
                : new Date(warningStartTime),
              riskUpdatedAt: serverTime,
            }, { merge: true });
          }
        });
        changed += chunk.length;
      }
      // Preserve the existing bounded consensus audit, without changing road
      // status or treating community agreement as official verification.
      for (
        const road of roads.filter((r) =>
          reports.some((p) => p.roadId === r.id)
        )
      ) {
        const unique = [
          ...new Map(
            reports.filter((r) => r.roadId === road.id).sort((a, b) =>
              millis(a.createdAt) - millis(b.createdAt)
            ).map((r) => [r.userId, r]),
          ).values(),
        ];
        if (unique.length < 3) continue;
        const counts = {};
        for (const r of unique) {
          counts[r.severity] = (counts[r.severity] ?? 0) + 1;
        }
        const [severity, count] = Object.entries(counts).sort((a, b) =>
            b[1] - a[1]
          )[0],
          agreement = count / unique.length;
        const avg = unique.filter((r) => r.severity === severity).reduce(
          (s, r) =>
            s + confidence(r, roads, reports, live.data.currentState, clock()),
          0,
        ) / count;
        if (
          !(agreement >= 0.7 && (count >= 5 || count >= 3 && avg >= 85) ||
            agreement >= 0.5 && agreement < 0.7)
        ) continue;
        await work.transaction(async (tx) => {
          await fence(tx);
          const audit = await tx.get(
            `consensus_audits/${await sha256(
              `${road.id}|${Math.floor(clock() / 10800000)}`,
            )}`,
          );
          if (!audit.exists) {
            tx.set(audit.path, {
              roadId: road.id,
              timestamp: serverTime,
              algorithmVersion: "server-v1",
              alertType: agreement >= 0.7
                ? "Consensus Alert"
                : "Under Verification",
              dominantSeverity: severity,
              agreementRate: agreement,
              averageConfidence: avg,
              totalReports: unique.length,
              severityDistribution: counts,
            }, { create: true });
          }
        });
      }
      for (const result of results) {
        Object.assign(graph.get(result.id), {
          ...result,
          warningStartTime: result.warningStartTime === null
            ? null
            : new Date(result.warningStartTime),
        });
      }
      const cache = {
        roads: [...graph].map(([id, r]) => ({ ...r, id })),
        scanTime: new Date(scanTime),
        fullAt,
        topologyRevision: marker.data.topologyRevision ?? 0,
      };
      if (new TextEncoder().encode(JSON.stringify(cache)).length > 750000) {
        throw new Error("core-cache-size");
      }
      await work.transaction(async (tx) => {
        await fence(tx);
        tx.set(cached.path, cache);
        tx.set("system/risk_job", {
          lastSuccess: serverTime,
          error: null,
          studyArea: area,
          roadCount: roads.length,
          changedRoads: changed,
        }, { merge: true });
      });
    } catch (e) {
      error = /^(core-[a-z-]+|weather-unavailable)$/.test(e.message ?? "")
        ? e.message
        : "core-unavailable";
    } finally {
      // If the runtime is killed, the reservation stays charged and the lease
      // expires. It cannot silently spend the same reserved quota twice.
      await db.transaction(async (tx) => {
        const [lease, budget] = await Promise.all([
          tx.get("system/risk_job"),
          tx.get("system/core_budget"),
        ]);
        if (lease.data.token !== token) return;
        tx.set(lease.path, {
          leaseUntil: new Date(0),
          ...(error ? { lastFailure: serverTime, error } : {}),
        }, { merge: true });
        if (budget.data.day === budgetDay) {
          tx.set(budget.path, {
            reads: budget.data.reads - 2200 +
              Math.min(2200, work.usage.reads + 5),
            writes: budget.data.writes - 1200 +
              Math.min(1200, work.usage.writes + 4),
          }, { merge: true });
        }
      });
    }
    return {
      completed: !error,
      error,
      changedRoads: changed,
      expiredReports,
      expiredIncidents,
      reads: work.usage.reads,
      writes: work.usage.writes,
    };
  }
  return { run, override: weather.override };
}
