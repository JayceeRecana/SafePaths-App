import { assertBackendProfile, TEST_BACKEND } from "./backend_profile.mjs";
import { identifier, ProofError, serverTime, sha256 } from "./proof_common.mjs";
import { roadDistance } from "./proof_reports.mjs";
const maxRoads = 1000, maxWrites = 400;
function fail(code, message, status = 400) {
  throw new ProofError(code, message, status);
}
function check(value, keys) {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).some((k) => !keys.includes(k))
  ) fail("invalid-argument", "Check the road maintenance details.");
}
const canonical = (v) =>
  v instanceof Date
    ? v.toISOString()
    : Array.isArray(v)
    ? v.map(canonical)
    : v && typeof v === "object"
    ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, canonical(v[k])]))
    : v;
const digest = (v) => sha256(JSON.stringify(canonical(v)));
const revision = (marker) =>
  Number.isSafeInteger(marker.topologyRevision) && marker.topologyRevision >= 0
    ? marker.topologyRevision
    : 0;
function segments(geometry) {
  if (geometry?.type === "Feature") return segments(geometry.geometry);
  const parts = Array.isArray(geometry?.segments)
    ? geometry.segments.map((s) => s.points)
    : geometry?.type === "MultiLineString"
    ? geometry.coordinates
    : [geometry?.coordinates];
  return (parts ?? []).filter(Array.isArray).map((part) =>
    part.map((p) =>
      Array.isArray(p)
        ? { lng: p[0], lat: p[1] }
        : { lng: p?.lng ?? p?.lon, lat: p?.lat }
    ).filter((p) =>
      Number.isFinite(p.lat) && Number.isFinite(p.lng) &&
      Math.abs(p.lat) <= 90 && Math.abs(p.lng) <= 180
    )
  ).filter((part) => part.length >= 2);
}
function box(parts) {
  const points = parts.flat();
  if (!points.length) return null;
  return {
    south: Math.min(...points.map((p) => p.lat)),
    north: Math.max(...points.map((p) => p.lat)),
    west: Math.min(...points.map((p) => p.lng)),
    east: Math.max(...points.map((p) => p.lng)),
  };
}
const overlaps = (a, b, pad = 0.0003) =>
  !!a && !!b && a.south - pad <= b.north && b.south - pad <= a.north &&
  a.west - pad <= b.east && b.west - pad <= a.east;
export function roadSegmentKeys(geometry) {
  return segments(geometry).map((line) => {
    const points = line.map(p => `${p.lng.toFixed(7)},${p.lat.toFixed(7)}`);
    const forward = points.join(";"), reverse = [...points].reverse().join(";");
    return forward < reverse ? forward : reverse;
  });
}
function normalize(data, profile) {
  check(data, ["id", "name", "geometry"]);
  if (
    !/^osm_way_[1-9][0-9]{0,19}$/.test(data.id ?? "") ||
    typeof data.name !== "string" || !data.name.trim() ||
    data.name.trim().length > 200
  ) fail("invalid-argument", "Choose valid OSM road segments.");
  check(data.geometry, ["type", "segments"]);
  if (
    data.geometry.type !== "MultiLineString" ||
    !Array.isArray(data.geometry.segments) || !data.geometry.segments.length ||
    data.geometry.segments.length > 20
  ) fail("invalid-argument", "Choose bounded road geometry.");
  let count = 0;
  for (const segment of data.geometry.segments) {
    check(segment, ["points"]);
    if (!Array.isArray(segment.points) || segment.points.length < 2) {
      fail("invalid-argument", "Each road segment needs two points.");
    }
    for (const point of segment.points) {
      check(point, ["lat", "lng"]);
      if (
        !Number.isFinite(point.lat) || !Number.isFinite(point.lng) ||
        Math.abs(point.lat) > 90 || Math.abs(point.lng) > 180
      ) fail("invalid-argument", "Invalid road coordinates.");
      count++;
    }
  }
  if (
    count > 1024 ||
    !overlaps(box(segments(data.geometry)), profile.bounds, 0)
  ) fail("invalid-argument", "Use bounded geometry in the test study area.");
  return { id: data.id, name: data.name.trim(), geometry: data.geometry };
}
// Spatial pruning and a hard operation budget keep dense/malformed imports
// bounded. Test actual segments; disconnected pieces never become a bridge.
export function roadAdjacency(roads, additions = null) {
  const ids = new Set(roads.map((r) => r.id)),
    lines = new Map(roads.map((r) => [r.id, segments(r.geometry)]));
  if ([...lines.values()].reduce((n, p) => n + p.flat().length, 0) > 40000) {
    fail(
      "resource-exhausted",
      "The test road graph needs a smaller maintenance batch.",
      429,
    );
  }
  const boxes = new Map([...lines].map(([id, parts]) => [id, box(parts)]));
  const links = new Map(
    roads.map((r) => [
      r.id,
      new Set(
        additions
          ? (Array.isArray(r.neighbors) ? r.neighbors : []).filter((id) =>
            ids.has(id) && id !== r.id
          )
          : [],
      ),
    ]),
  );
  let operations = 0;
  for (let i = 0; i < roads.length; i++) {
    for (let j = i + 1; j < roads.length; j++) {
      const a = roads[i], b = roads[j];
      if (additions && !additions.has(a.id) && !additions.has(b.id)) {
        continue;
      }
      if (!overlaps(boxes.get(a.id), boxes.get(b.id))) continue;
      const pa = lines.get(a.id),
        pb = lines.get(b.id),
        na = pa.reduce((n, s) => n + s.length, 0),
        nb = pb.reduce((n, s) => n + s.length, 0);
      operations += na * nb * 2;
      if (operations > 1000000) {
        fail(
          "resource-exhausted",
          "Import fewer or simpler segments; existing road decisions are unchanged.",
          429,
        );
      }
      if (
        pa.flat().some((p) => roadDistance(p, b.geometry) < 25) ||
        pb.flat().some((p) => roadDistance(p, a.geometry) < 25)
      ) {
        links.get(a.id).add(b.id);
        links.get(b.id).add(a.id);
      }
    }
  }
  return new Map([...links].map(([id, set]) => [id, [...set].sort()]));
}
function stats(links) {
  const counts = [...links.values()].map((v) => v.length), seen = new Set();
  let components = 0;
  for (const id of links.keys()) {
    if (!seen.has(id)) {
      components++;
      const stack = [id];
      while (stack.length) {
        const next = stack.pop();
        if (seen.has(next)) continue;
        seen.add(next);
        for (
          const neighbor of links.get(next) ?? []
        ) if (!seen.has(neighbor)) stack.push(neighbor);
      }
    }
  }
  return {
    totalRoads: links.size,
    avgNeighbors: counts.reduce((n, v) => n + v, 0) / Math.max(1, links.size),
    disconnectedRoads: counts.filter((n) => !n).length,
    maximumNeighbors: Math.max(0, ...counts),
    connectedComponents: components,
  };
}
export function createRoadMaintenance({ db, profile = TEST_BACKEND }) {
  assertBackendProfile(profile);
  const area = profile.area;
  async function admin(get, uid) {
    const [actor, control] = await Promise.all([
      get(`users/${uid}`),
      get("system/road_maintenance"),
    ]);
    if (!actor.exists || actor.data.role !== "admin") {
      fail("permission-denied", "Use the current administrator account.", 403);
    }
    if (control.data.enabled !== true) {
      fail(
        "unavailable",
        "Road maintenance is not enabled for this test.",
        503,
      );
    }
  }
  async function snapshot(tx) {
    const docs = await tx.queryWhere(
      "roads",
      [["studyArea", "EQUAL", area]],
      maxRoads + 1,
    );
    if (docs.length > maxRoads) {
      fail("resource-exhausted", "The test road graph limit is reached.", 429);
    }
    return docs;
  }
  function command(data, keys) {
    check(data, ["requestId", ...keys]);
    if (!/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId ?? "")) {
      fail(
        "invalid-argument",
        "Keep the original maintenance request for retry.",
      );
    }
  }
  async function run(uid, operation, data, work) {
    const id = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await digest({ operation, ...data });
    return db.transaction(async (tx) => {
      await admin((path) => tx.get(path), uid);
      const receipt = await tx.get(`road_maintenance_requests/${id}`);
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          fail(
            "already-exists",
            "This retry belongs to another maintenance command.",
            409,
          );
        }
        return { ...receipt.data.result, replay: true };
      }
      const marker = await tx.get("system/road_inputs"),
        next = revision(marker.data) + 1;
      const details = await work(tx, next, id);
      const result = {
        saved: true,
        operation,
        resourceId: id,
        revision: details.changed ? next : Math.max(1, revision(marker.data)),
        replay: false,
        notification: "saved_in_app",
        queuedCount: 0,
        ...details.result,
      };
      if (details.changed) {
        tx.set(marker.path, { topologyRevision: next, updatedAt: serverTime }, {
          merge: true,
        });
      }
      tx.set(receipt.path, { fingerprint, result, createdAt: serverTime }, {
        create: true,
      });
      tx.set(`road_maintenance_audits/${id}`, {
        actorUid: uid,
        operation,
        createdAt: serverTime,
        ...details.audit,
      }, { create: true });
      return result;
    });
  }
  async function importRoads(uid, data) {
    command(data, ["roads"]);
    if (
      !Array.isArray(data.roads) || !data.roads.length || data.roads.length > 10
    ) fail("invalid-argument", "Import one to ten road segments per command.");
    const proposed = data.roads.map((road) => normalize(road, profile));
    if (
      new Set(proposed.map((r) => r.id)).size !== proposed.length ||
      proposed.reduce((n, r) => n + segments(r.geometry).flat().length, 0) >
        2048
    ) fail("invalid-argument", "Choose unique, bounded segments.");
    return run(uid, "road-import", data, async (tx, next, id) => {
      const [existing, selected] = await Promise.all([
        snapshot(tx),
        Promise.all(proposed.map((r) => tx.get(`roads/${r.id}`))),
      ]);
      const additions = proposed.filter((_, i) => !selected[i].exists),
        newIds = new Set(additions.map((r) => r.id));
      if (profile.name === "production") {
        // Legacy Marulas records use name-based IDs. Do not import the same
        // mapped segment again under a new OSM ID and split its report history.
        const known = new Set(existing.flatMap(d => roadSegmentKeys(d.data.geometry)));
        for (const road of additions) {
          const keys = roadSegmentKeys(road.geometry);
          if (keys.some(key => known.has(key))) {
            fail("failed-precondition", "This segment is already monitored. Update the existing road instead.", 409);
          }
          keys.forEach(key => known.add(key));
        }
      }
      if (existing.length + additions.length > maxRoads) {
        fail(
          "resource-exhausted",
          "The test road graph limit is reached.",
          429,
        );
      }
      const roads = [
          ...existing.map((d) => ({ ...d.data, id: d.path.split("/").at(-1) })),
          ...additions,
        ],
        links = roadAdjacency(roads, newIds);
      const updates = existing.filter((d) =>
        JSON.stringify(d.data.neighbors ?? []) !==
          JSON.stringify(links.get(d.path.split("/").at(-1)))
      );
      if (updates.length + additions.length > maxWrites) {
        fail(
          "resource-exhausted",
          "Repair the test graph in a smaller maintenance operation.",
          429,
        );
      }
      // Every proposed ID was read in the same transaction. A concurrent import
      // retries and skips it; official status/notes/trust are never merged over.
      for (const road of additions) {
        tx.set(`roads/${road.id}`, {
          name: road.name,
          geometry: road.geometry,
          neighbors: links.get(road.id),
          studyArea: area,
          status: "passable",
          notes: "",
          vulnerability: "medium",
          source: "osm",
          isVerified: false,
          riskScore: 0,
          riskCategory: "Unknown",
          importedAt: serverTime,
          updatedAt: serverTime,
          riskInputsUpdatedAt: serverTime,
          maintenanceGeneration: id,
        }, { create: true });
      }
      for (const doc of updates) {
        tx.set(doc.path, {
          neighbors: links.get(doc.path.split("/").at(-1)),
          riskInputsUpdatedAt: serverTime,
        }, { merge: true });
      }
      return {
        changed: !!(additions.length || updates.length),
        result: {
          createdCount: additions.length,
          skippedCount: proposed.length - additions.length,
          createdIds: [...newIds],
          graphStats: stats(links),
        },
        audit: { roadIds: proposed.map((r) => r.id), createdIds: [...newIds] },
      };
    });
  }
  async function deletion(uid, get, query, roadId) {
    if (!identifier(roadId)) fail("invalid-argument", "Choose a road.");
    const [road, incident, active] = await Promise.all([
      get(`roads/${roadId}`),
      get(`road_incidents/${roadId}`),
      query("reports", [["status", "IN", ["pending", "under_review", "waiting_resident"]]], 101),
    ]);
    if (!road.exists) fail("not-found", "This road is no longer present.", 404);
    if (road.data.studyArea !== area) {
      fail("permission-denied", "Choose a road in the test study area.", 403);
    }
    if (active.length > 100) {
      fail(
        "resource-exhausted",
        "Resolve active reports before network maintenance.",
        429,
      );
    }
    const canDelete = road.data.status === "passable" &&
      (!incident.exists || incident.data.state === "resolved") &&
      !active.some((d) => d.data.roadId === roadId);
    const token = await digest({
      uid,
      roadId,
      name: road.data.name,
      geometry: road.data.geometry,
      status: road.data.status,
      notes: road.data.notes,
      updatedAt: road.data.updatedAt,
      vulnerability: road.data.vulnerability,
      isVerified: road.data.isVerified,
      importedAt: road.data.importedAt,
      maintenanceGeneration: road.data.maintenanceGeneration,
      incident: incident.exists ? incident.data : null,
    });
    return { road, canDelete, token };
  }
  async function context(uid, data) {
    check(data, ["roadId"]);
    await admin((path) => db.get(path), uid);
    const loaded = await deletion(
      uid,
      (path) => db.get(path),
      (collection, filters, limit) => db.query(collection, filters, { limit }),
      data.roadId,
    );
    return {
      ownerUid: uid,
      roadId: data.roadId,
      name: loaded.road.data.name ?? data.roadId,
      token: loaded.token,
      canDelete: loaded.canDelete,
      reason: loaded.canDelete
        ? "Deletion removes the road and neighbor links. Report history and photos are retained."
        : "Resolve active reports/incidents and review any road closure before deletion.",
    };
  }
  async function remove(uid, data) {
    command(data, ["roadId", "contextToken", "confirmed"]);
    if (
      data.confirmed !== true ||
      !/^[a-f0-9]{64}$/.test(data.contextToken ?? "") ||
      !identifier(data.roadId)
    ) {
      fail(
        "invalid-argument",
        "Review and confirm the current road before deletion.",
      );
    }
    return run(uid, "road-delete", data, async (tx) => {
      const loaded = await deletion(
        uid,
        (path) => tx.get(path),
        (collection, filters, limit) =>
          tx.queryWhere(collection, filters, limit),
        data.roadId,
      );
      if (loaded.token !== data.contextToken || !loaded.canDelete) {
        fail(
          "failed-precondition",
          "The road changed or has active conditions. Refresh its review before deletion.",
          409,
        );
      }
      const incoming = await tx.queryWhere("roads", [[
        "neighbors",
        "ARRAY_CONTAINS",
        data.roadId,
      ]], 201);
      if (
        incoming.length > 200 || incoming.some((d) => d.data.studyArea !== area)
      ) {
        fail(
          "failed-precondition",
          "Review the neighbor graph before deleting this road.",
          409,
        );
      }
      for (const neighbor of incoming) {
        if (neighbor.path !== loaded.road.path) {
          tx.set(neighbor.path, {
            neighbors: neighbor.data.neighbors.filter((id) =>
              id !== data.roadId
            ),
            riskInputsUpdatedAt: serverTime,
          }, { merge: true });
        }
      }
      tx.delete(loaded.road.path);
      return {
        changed: true,
        result: {
          deletedRoadId: data.roadId,
          prunedNeighbors: incoming.filter((d) =>
            d.path !== loaded.road.path
          ).length,
        },
        audit: { roadId: data.roadId, prunedNeighbors: incoming.length },
      };
    });
  }
  async function rebuild(uid, data) {
    command(data, []);
    return run(uid, "road-graph-rebuild", data, async (tx) => {
      const docs = await snapshot(tx),
        roads = docs.map((d) => ({ ...d.data, id: d.path.split("/").at(-1) })),
        links = roadAdjacency(roads),
        updates = docs.filter((d) =>
          JSON.stringify(d.data.neighbors ?? []) !==
            JSON.stringify(links.get(d.path.split("/").at(-1)))
        );
      if (updates.length > maxWrites) {
        fail(
          "resource-exhausted",
          "The graph repair exceeds this test transaction budget.",
          429,
        );
      }
      for (const doc of updates) {
        tx.set(doc.path, {
          neighbors: links.get(doc.path.split("/").at(-1)),
          riskInputsUpdatedAt: serverTime,
        }, { merge: true });
      }
      return {
        changed: !!updates.length,
        result: { changedRoads: updates.length, graphStats: stats(links) },
        audit: { changedRoads: updates.length },
      };
    });
  }
  return { importRoads, context, remove, rebuild };
}
