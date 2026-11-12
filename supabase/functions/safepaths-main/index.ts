// Main and proof have separate endpoints, credentials, private buckets and
// worker secrets. Never deploy a proof credential into this function.
import { MARULAS_BACKEND } from "../_shared/backend_profile.mjs";
import { GoogleCredential, FirestoreRest, createFirebaseVerifier } from "../_shared/proof_firebase.mjs";
import { ProofStorage } from "../_shared/proof_storage.mjs";
import { ProofMediaStorage, createMediaWorkflow } from "../_shared/proof_media.mjs";
import { createCommunications } from "../_shared/proof_communications.mjs";
import { createProofPush, ProofFcm } from "../_shared/proof_push.mjs";
import { createCoreMaintenance } from "../_shared/proof_core.mjs";
import { createRoadMaintenance } from "../_shared/proof_roads.mjs";
import { createProofHandler } from "../_shared/proof_handler.mjs";
declare const EdgeRuntime: { waitUntil(task: Promise<unknown>): void };

try {
  if (Deno.env.get("MARULAS_BACKEND_ENABLED") !== "true") throw new Error("Main rollout is disabled.");
  const profile = MARULAS_BACKEND;
  const projectId = Deno.env.get("MARULAS_FIREBASE_PROJECT_ID") ?? "";
  const credential = new GoogleCredential(
    JSON.parse(Deno.env.get("MARULAS_GOOGLE_SERVICE_ACCOUNT_JSON") ?? "{}"),
    projectId, fetch, Date.now, profile,
  );
  const db = new FirestoreRest({ projectId, credential, profile });
  const storage = {
    url: Deno.env.get("SUPABASE_URL") ?? "",
    secret: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", profile,
  };
  const workerSecret = Deno.env.get("MARULAS_WORKER_SECRET") ?? "";
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(workerSecret)) throw new Error("Worker configuration missing.");
  const stores = {
    avatar: new ProofMediaStorage(storage, "avatar"),
    feedback: new ProofMediaStorage(storage, "feedback"),
  };
  Deno.serve(createProofHandler({
      adminNotices: true,
    profile, db, photos: new ProofStorage(storage),
    verify: createFirebaseVerifier({ projectId, credential, profile }),
    // Enrollment uses current main-project user profiles and Firebase account
    // verification, not the proof's fixed synthetic UID list.
    communications: createCommunications({ db, profile, feedbackPhotos: stores.feedback }),
    media: createMediaWorkflow({ db, stores }),
    push: createProofPush({ db, profile, communicationsEnabled: true,
      fcm: new ProofFcm({ projectId, credential, profile }) }),
    core: createCoreMaintenance({ db, profile }),
    roads: createRoadMaintenance({ db, profile }),
    followupsEnabled: Deno.env.get("MARULAS_FOLLOWUPS_ENABLED") === "true",
    workerSecret,
    background: (task: Promise<unknown>) => EdgeRuntime.waitUntil(task),
  }));
} catch (_) {
  // Do not log private keys, provider responses or arbitrary exception text.
  console.error("Marulas configuration is unavailable; no requests served.");
  Deno.exit(1);
}
