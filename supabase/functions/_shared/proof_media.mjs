import { ProofStorage } from "./proof_storage.mjs";
import {
  identifier,
  ProofError,
  readBounded,
  serverTime,
  sha256,
} from "./proof_common.mjs";

export const mediaLimits = {
  avatar: { bytes: 256 * 1024, side: 512 },
  feedback: { bytes: 2 * 1024 * 1024, side: 1600 },
};
function invalid(
  message = "Choose a valid, resized JPEG without embedded metadata.",
) {
  throw new ProofError("invalid-argument", message);
}
// Structural validation is bounded; it is not visual/content moderation. Scan
// every marker, including between progressive scans, and reject metadata that
// could disclose GPS or other source-file details. Decoding happens on-device.
export function validateMediaJpeg(bytes, purpose) {
  const limits = mediaLimits[purpose];
  if (
    !limits || bytes.length > limits.bytes || bytes.length < 16 ||
    bytes[0] !== 255 || bytes[1] !== 216
  ) invalid();
  let at = 2, width = 0, height = 0, scan = false, inScan = false;
  while (at < bytes.length) {
    if (inScan) {
      while (at < bytes.length && bytes[at] !== 255) at++;
      if (at >= bytes.length) invalid();
    }
    if (bytes[at++] !== 255) invalid();
    while (bytes[at] === 255) at++;
    const marker = bytes[at++];
    if (inScan && (marker === 0 || marker >= 208 && marker <= 215)) continue;
    inScan = false;
    if (marker === 217) {
      if (at !== bytes.length || !width || !scan) invalid();
      return { width, height };
    }
    if (
      marker === 216 || marker === 0 || marker === 1 ||
      marker >= 208 && marker <= 215
    ) invalid();
    if (at + 2 > bytes.length) invalid();
    const length = bytes[at] * 256 + bytes[at + 1];
    if (length < 2 || at + length > bytes.length) invalid();
    if (
      marker >= 224 && marker <= 239 && ![224, 238].includes(marker) ||
      marker === 254
    ) invalid();
    if ([192, 193, 194].includes(marker)) {
      if (length < 8 || bytes[at + 2] !== 8) invalid();
      const h = bytes[at + 3] * 256 + bytes[at + 4],
        w = bytes[at + 5] * 256 + bytes[at + 6];
      if (
        !w || !h || w > limits.side || h > limits.side ||
        width && (width !== w || height !== h)
      ) invalid();
      width = w;
      height = h;
    } else if (
      marker >= 192 && marker <= 207 && ![196, 200, 204].includes(marker)
    ) invalid();
    if (marker === 218) {
      if (!width || length < 6) invalid();
      scan = true;
      inScan = true;
    }
    at += length;
  }
  invalid();
}

export class ProofMediaStorage extends ProofStorage {
  constructor(options, purpose) {
    super(options);
    if (!mediaLimits[purpose]) throw new Error("Unknown media purpose.");
    this.purpose = purpose;
  }
  path(uid, digest) {
    if (!identifier(uid) || !/^[a-f0-9]{64}$/.test(digest ?? "")) {
      invalid("Invalid image reference.");
    }
    return `${
      this.purpose === "avatar" ? "avatars" : "feedback"
    }/${uid}/${digest}.jpg`;
  }
  reference(uid, digest) {
    this.path(uid, digest);
    return `${this.endpoint}/media/${this.purpose}/${uid}/${digest}`;
  }
  parse(value) {
    const prefix = `${this.endpoint}/media/${this.purpose}/`;
    if (typeof value !== "string" || !value.startsWith(prefix)) {
      invalid("Use an image uploaded for this purpose.");
    }
    const [uid, digest, ...extra] = value.slice(prefix.length).split("/");
    if (extra.length) invalid();
    this.path(uid, digest);
    return { uid, digest };
  }
  async read(reference) {
    const { uid, digest } = this.parse(reference);
    await this.assertPrivate();
    await this.info(uid, digest);
    const response = await this.fetcher(
      `${this.origin}/storage/v1/object/authenticated/${this.bucket}/${
        this.path(uid, digest)
      }`,
      {
        method: "GET",
        redirect: "error",
        signal: AbortSignal.timeout(10000),
        headers: {
          authorization: `Bearer ${this.secret}`,
          apikey: this.secret,
        },
      },
    );
    let missing = response.status === 404;
    if (response.status === 400) {
      const data = await response.clone().json().catch(() => null);
      missing = String(data?.statusCode) === "404" &&
        data?.error === "not_found";
    }
    if (missing) {
      throw new ProofError(
        "media-unavailable",
        "The image is unavailable. Attach it again.",
        409,
      );
    }
    if (
      !response.ok ||
      response.headers.get("content-type")?.split(";")[0] !== "image/jpeg"
    ) {
      throw new ProofError(
        "unavailable",
        "Image delivery is unavailable.",
        503,
      );
    }
    const bytes = await readBounded(response, mediaLimits[this.purpose].bytes);
    validateMediaJpeg(bytes, this.purpose);
    if (await sha256(bytes) !== digest) {
      throw new ProofError(
        "media-unavailable",
        "The stored image could not be verified. Attach it again.",
        409,
      );
    }
    return bytes;
  }
  async upload(uid, digest, bytes) {
    validateMediaJpeg(bytes, this.purpose);
    if (await sha256(bytes) !== digest) invalid();
    const reference = await super.upload(uid, digest, bytes);
    await this.read(reference);
    return reference;
  }
  async validate(reference, uid) {
    const parsed = this.parse(reference);
    if (parsed.uid !== uid) {
      throw new ProofError(
        "permission-denied",
        "Use an image owned by this account.",
        403,
      );
    }
    try {
      await this.read(reference);
    } catch (error) {
      if (["not-found", "invalid-argument", "too-large"].includes(error.code)) {
        throw new ProofError(
          "media-unavailable",
          "The uploaded image is unavailable. Attach it again.",
          409,
        );
      }
      throw error;
    }
    return reference;
  }
  async signed() {
    throw new ProofError(
      "permission-denied",
      "Use authenticated image delivery.",
      403,
    );
  }
}

const contextToken = (uid, data) =>
  sha256(
    JSON.stringify([
      uid,
      data.profileRevision ?? 0,
      data.name ?? "",
      data.location ?? "",
      data.photoUrl ?? null,
    ]),
  );
const day = (now) =>
  new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Los_Angeles",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
export function createMediaWorkflow({ db, stores, clock = Date.now }) {
  async function upload(uid, purpose, bytes) {
    if (!mediaLimits[purpose]) invalid();
    validateMediaJpeg(bytes, purpose);
    const digest = await sha256(bytes),
      id = await sha256(`${purpose}|${uid}|${digest}`),
      windowDay = day(clock());
    await db.transaction(async (tx) => {
      const [saved, budget] = await Promise.all([
        tx.get(`media_uploads/${id}`),
        tx.get(`media_limits/${uid}`),
      ]);
      if (saved.exists) {
        if (
          saved.data.uid !== uid || saved.data.purpose !== purpose ||
          saved.data.bytes !== bytes.length
        ) invalid();
        return;
      }
      const value = budget.data,
        count = value.windowDay === windowDay ? value.dayCount ?? 0 : 0,
        size = value.windowDay === windowDay ? value.dayBytes ?? 0 : 0;
      if (
        count >= 20 || size + bytes.length > 16 * 1024 * 1024 ||
        (value.count ?? 0) >= 100 ||
        (value.bytes ?? 0) + bytes.length > 32 * 1024 * 1024
      ) {
        throw new ProofError(
          "resource-exhausted",
          "The test image allowance is reached. Contact the project team.",
          429,
        );
      }
      tx.set(saved.path, {
        uid,
        purpose,
        digest,
        bytes: bytes.length,
        status: "reserved",
        createdAt: serverTime,
      }, { create: true });
      tx.set(budget.path, {
        windowDay,
        dayCount: count + 1,
        dayBytes: size + bytes.length,
        count: (value.count ?? 0) + 1,
        bytes: (value.bytes ?? 0) + bytes.length,
      });
    });
    const reference = await stores[purpose].upload(uid, digest, bytes);
    await db.transaction(async (tx) => {
      const saved = await tx.get(`media_uploads/${id}`);
      if (!saved.exists || saved.data.uid !== uid) {
        throw new Error("Missing image reservation.");
      }
      tx.set(saved.path, { status: "ready", verifiedAt: serverTime }, {
        merge: true,
      });
    });
    return { reference };
  }
  async function context(uid) {
    const profile = await db.get(`users/${uid}`);
    if (!profile.exists) {
      throw new ProofError(
        "failed-precondition",
        "Complete the test profile.",
        409,
      );
    }
    let photoUrl = null;
    try {
      const parsed = stores.avatar.parse(profile.data.photoUrl);
      if (parsed.uid === uid) photoUrl = profile.data.photoUrl;
    } catch (_) {}
    return {
      token: await contextToken(uid, profile.data),
      ownerUid: uid,
      revision: profile.data.profileRevision ?? 0,
      name: profile.data.name ?? "",
      location: profile.data.location ?? "",
      hasPhoto: !!profile.data.photoUrl,
      photoUrl,
      legacyPhoto: !!profile.data.photoUrl && !photoUrl,
    };
  }
  async function save(uid, data) {
    const allowed = [
      "requestId",
      "contextToken",
      "name",
      "location",
      "photoMode",
      "photoUrl",
    ];
    if (
      !data || Object.keys(data).some((k) => !allowed.includes(k)) ||
      !/^[A-Za-z0-9_-]{16,128}$/.test(data.requestId ?? "") ||
      !/^[a-f0-9]{64}$/.test(data.contextToken ?? "") ||
      typeof data.name !== "string" || data.name.trim().length < 2 ||
      data.name.trim().length > 120 || typeof data.location !== "string" ||
      data.location.trim().length > 250 ||
      !["keep", "set", "remove"].includes(data.photoMode) ||
      data.photoMode !== "set" && data.photoUrl != null
    ) invalid("Check the profile name, location and selected photo.");
    const payload = {
      contextToken: data.contextToken,
      name: data.name.trim(),
      location: data.location.trim(),
      photoMode: data.photoMode,
      photoUrl: data.photoMode === "set" ? data.photoUrl : null,
    };
    const id = await sha256(`${uid}|${data.requestId}`),
      fingerprint = await sha256(JSON.stringify(payload));
    const prior = await db.get(`profile_requests/${id}`);
    if (!prior.exists && data.photoMode === "set") {
      await stores.avatar.validate(data.photoUrl, uid);
    }
    return db.transaction(async (tx) => {
      const [profile, receipt] = await Promise.all([
        tx.get(`users/${uid}`),
        tx.get(`profile_requests/${id}`),
      ]);
      if (!profile.exists) {
        throw new ProofError(
          "failed-precondition",
          "This profile is unavailable.",
          409,
        );
      }
      if (receipt.exists) {
        if (receipt.data.fingerprint !== fingerprint) {
          invalid("This retry belongs to another profile action.");
        }
        return { ...receipt.data.result, replay: true };
      }
      if (
        prior.exists ||
        await contextToken(uid, profile.data) !== data.contextToken
      ) {
        throw new ProofError(
          "failed-precondition",
          "The profile changed. Refresh before saving.",
          409,
        );
      }
      const revision = (profile.data.profileRevision ?? 0) + 1,
        result = {
          saved: true,
          operation: "profile-save",
          resourceId: uid,
          revision,
          replay: false,
          notification: "saved_in_app",
          queuedCount: 0,
        };
      tx.set(profile.path, {
        name: payload.name,
        location: payload.location,
        profileRevision: revision,
        updatedAt: serverTime,
        ...(data.photoMode === "keep"
          ? {}
          : { photoUrl: data.photoMode === "remove" ? null : data.photoUrl }),
      }, { merge: true });
      tx.set(receipt.path, { fingerprint, result, createdAt: serverTime }, {
        create: true,
      });
      return result;
    });
  }
  async function mayRead(uid, purpose, reference, feedbackId) {
    const parsed = stores[purpose].parse(reference);
    const [actor, record] = await Promise.all([
      db.get(`users/${uid}`),
      db.get(
        purpose === "avatar"
          ? `users/${parsed.uid}`
          : `feedbacks/${feedbackId}`,
      ),
    ]);
    return actor.exists && record.exists &&
      (uid === parsed.uid || actor.data.role === "admin") &&
      (purpose === "avatar"
        ? record.data.photoUrl === reference
        : record.data.userId === parsed.uid &&
          record.data.imageUrl === reference);
  }
  async function read(uid, data) {
    if (
      !data ||
      Object.keys(data).some((k) => !["reference", "feedbackId"].includes(k)) ||
      typeof data.reference !== "string"
    ) invalid();
    const purpose =
      data.reference.startsWith(`${stores.avatar.endpoint}/media/avatar/`)
        ? "avatar"
        : "feedback";
    if (purpose === "feedback" && !identifier(data.feedbackId)) {
      invalid("Choose the feedback record for this attachment.");
    }
    if (!await mayRead(uid, purpose, data.reference, data.feedbackId)) {
      throw new ProofError(
        "permission-denied",
        "This image is unavailable for this account or record.",
        403,
      );
    }
    const bytes = await stores[purpose].read(data.reference);
    if (!await mayRead(uid, purpose, data.reference, data.feedbackId)) {
      throw new ProofError(
        "permission-denied",
        "The image changed or access was removed.",
        403,
      );
    }
    return bytes;
  }
  return { upload, context, save, read };
}
