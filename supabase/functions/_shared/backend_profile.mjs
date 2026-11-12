import { assertProofProject, identifier, ProofError } from "./proof_common.mjs";

/** @typedef {Readonly<{name:string,area:string,functionName:string,bucket:string,
 * latitude:number,longitude:number,projectId?:string,
 * bounds:Readonly<{south:number,north:number,west:number,east:number}>}>} BackendProfile */

// Explicit server-owned targets. The existing proof remains the default and
// cannot be repointed to the main project by changing an environment variable.
/** @type {BackendProfile} */
export const TEST_BACKEND = Object.freeze({
  name: "fieldtest", area: "nearby_test", functionName: "safepaths-report-proof",
  bucket: "report-photos-proof", latitude: 14.676139, longitude: 121.009417,
  bounds: Object.freeze({ south: 14.667156, north: 14.685122, west: 121.000131, east: 121.018703 }),
});
/** @type {BackendProfile} */
export const MARULAS_BACKEND = Object.freeze({
  name: "production", area: "marulas", projectId: "safepaths-92c3d",
  functionName: "safepaths-main", bucket: "report-photos-marulas",
  latitude: 14.6761, longitude: 120.9842,
  bounds: Object.freeze({ south: 14.6660, north: 14.6855, west: 120.9680, east: 120.9995 }),
});
export function assertBackendProfile(profile) {
  if (profile !== TEST_BACKEND && profile !== MARULAS_BACKEND) {
    throw new Error("Use an explicit server-owned backend profile.");
  }
  return profile;
}
export function assertBackendProject(project, profile = TEST_BACKEND) {
  assertBackendProfile(profile);
  if (profile === TEST_BACKEND) return assertProofProject(project);
  if (project !== MARULAS_BACKEND.projectId) throw new Error("Main backend project mismatch.");
}
export function eligibleMember(doc, profile = MARULAS_BACKEND) {
  return doc?.exists === true && ["user", "admin"].includes(doc.data.role) &&
    doc.data.disabled !== true && doc.data.isTestAccount !== true &&
    (doc.data.studyArea == null || doc.data.studyArea === profile.area);
}
export async function requireMainMember(db, uid) {
  if (!identifier(uid) || !eligibleMember(await db.get(`users/${uid}`))) {
    throw new ProofError("permission-denied", "A current SafePaths account is required.", 403);
  }
}
export async function requireMainRoadScope(db, data = {}) {
  const ids = new Set();
  for (const id of [data.roadId, ...(Array.isArray(data.roadIds) ? data.roadIds : [])]) {
    if (id != null) {
      if (!identifier(id) || ids.size >= 20) throw new ProofError("invalid-argument", "Choose valid roads.");
      ids.add(id);
    }
  }
  for (const reportId of [data.reportId, data.parentReportId, data.rootReportId, data.sourceReportId]) {
    if (reportId == null) continue;
    if (!identifier(reportId)) throw new ProofError("invalid-argument", "Choose a valid report.");
    const report = await db.get(`reports/${reportId}`);
    if (report.exists && identifier(report.data.roadId)) ids.add(report.data.roadId);
  }
  for (const id of ids) {
    const road = await db.get(`roads/${id}`);
    if (!road.exists || road.data.studyArea !== MARULAS_BACKEND.area) {
      throw new ProofError("failed-precondition", "Choose a monitored Marulas road.", 409);
    }
  }
}
