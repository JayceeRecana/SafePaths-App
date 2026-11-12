// This entry point intentionally has no emulator or production-project override.
// Firebase JWTs are verified in the handler; Supabase gateway JWT verification
// must be disabled for this one function only (see config.toml).
import {
  createFirebaseVerifier,
  FirestoreRest,
  GoogleCredential,
} from "../_shared/proof_firebase.mjs";
import { ProofStorage } from "../_shared/proof_storage.mjs";
import { createProofHandler } from "../_shared/proof_handler.mjs";
import { createProofPush, ProofFcm } from "../_shared/proof_push.mjs";
import { createCoreMaintenance } from "../_shared/proof_core.mjs";
import { createRoadMaintenance } from "../_shared/proof_roads.mjs";
import { createCommunications } from "../_shared/proof_communications.mjs";
import {
  createMediaWorkflow,
  ProofMediaStorage,
} from "../_shared/proof_media.mjs";
declare const EdgeRuntime: { waitUntil(task: Promise<unknown>): void };

try {
  const projectId = Deno.env.get("PROOF_FIREBASE_PROJECT_ID") ?? "";
  const credential = new GoogleCredential(
    JSON.parse(Deno.env.get("PROOF_GOOGLE_SERVICE_ACCOUNT_JSON") ?? "{}"),
    projectId,
  );
  const db = new FirestoreRest({ projectId, credential });
  const photos = new ProofStorage({
    url: Deno.env.get("SUPABASE_URL") ?? "",
    secret: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  });
  const allowedUids = new Set(
    (Deno.env.get("PROOF_ALLOWED_UIDS") ?? "").split(",").map((value) =>
      value.trim()
    ).filter(Boolean),
  );
  const workerSecret = Deno.env.get("PROOF_PUSH_WORKER_SECRET") ?? "";
  const communicationsEnabled =
    Deno.env.get("PROOF_COMMUNICATIONS_ENABLED") === "true";
  const mediaEnabled = Deno.env.get("PROOF_MEDIA_ENABLED") === "true";
  if (mediaEnabled && !communicationsEnabled) {
    throw new Error("Media requires the communication migration.");
  }
  const stores = mediaEnabled
    ? Object.fromEntries(
      ["avatar", "feedback"].map(
        (purpose) => [
          purpose,
          new ProofMediaStorage({
            url: Deno.env.get("SUPABASE_URL") ?? "",
            secret: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
          }, purpose),
        ],
      ),
    )
    : null;
  const media = stores ? createMediaWorkflow({ db, stores }) : null;
  const communications = communicationsEnabled
    ? createCommunications({
      db,
      allowedUids,
      feedbackPhotos: stores?.feedback ?? null,
    })
    : null;
  const push = Deno.env.get("PROOF_PUSH_ENABLED") === "true"
    ? createProofPush({
      db,
      allowedUids,
      communicationsEnabled,
      fcm: new ProofFcm({ projectId, credential }),
    })
    : null;
  const core = Deno.env.get("PROOF_CORE_ENABLED") === "true"
    ? createCoreMaintenance({ db })
    : null;
  const followupsEnabled =
    Deno.env.get("SPARK_PROOF_FOLLOWUPS_ENABLED") === "true";
  if (followupsEnabled && !core) {
    throw new Error("Follow-ups require the core reporting migration.");
  }
  const roadsEnabled = Deno.env.get("PROOF_ROADS_ENABLED") === "true";
  if (roadsEnabled && !core) {
    throw new Error("Road maintenance requires the core migration.");
  }
  const roads = roadsEnabled ? createRoadMaintenance({ db }) : null;
  if ((push || core) && !/^[A-Za-z0-9_-]{43,128}$/.test(workerSecret)) {
    throw new Error("Missing test push worker configuration.");
  }
  Deno.serve(
    createProofHandler({
      adminNotices: true,
      followupsEnabled,
      db,
      photos,
      allowedUids,
      verify: createFirebaseVerifier({ projectId, credential }),
      push,
      core,
      roads,
      communications,
      media,
      workerSecret,
      background: (task: Promise<unknown>) => EdgeRuntime.waitUntil(task),
    }),
  );
} catch (_) {
  // A malformed JSON secret must never appear in a startup error or stack trace.
  console.error(
    "Spark proof configuration is missing or invalid; no requests served.",
  );
  Deno.exit(1);
}
