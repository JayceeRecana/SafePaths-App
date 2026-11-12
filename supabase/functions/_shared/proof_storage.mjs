import { assertBackendProfile, TEST_BACKEND } from "./backend_profile.mjs";
import {
  fetchJson,
  identifier,
  maxPhotoBytes,
  ProofError,
} from "./proof_common.mjs";

export class ProofStorage {
  constructor(
    { url, secret, fetcher = fetch, profile = TEST_BACKEND, bucket = profile.bucket },
  ) {
    assertBackendProfile(profile);
    const origin = new URL(url);
    if (
      origin.protocol !== "https:" ||
      !/^[a-z0-9]{20}\.supabase\.co$/.test(origin.hostname) ||
      origin.pathname !== "/" || origin.search || origin.hash ||
      origin.username || origin.password
    ) throw new Error("An exact hosted Supabase project URL is required.");
    if (!secret || bucket !== profile.bucket) {
      throw new Error(
        "A server-only Storage credential and the private proof bucket are required.",
      );
    }
    if (profile.name === "production" && origin.hostname !== "bbteuzgfgnrjjrqewidc.supabase.co") {
      throw new Error("Main Storage project mismatch.");
    }
    this.origin = origin.origin;
    this.secret = secret;
    this.bucket = bucket;
    this.fetcher = fetcher;
    this.endpoint = `${this.origin}/functions/v1/${profile.functionName}`;
  }
  path(uid, digest) {
    if (!identifier(uid) || !/^[a-f0-9]{64}$/.test(digest ?? "")) {
      throw new ProofError("invalid-argument", "Invalid photo reference.");
    }
    return `reports/${uid}/${digest}.jpg`;
  }
  reference(uid, digest) {
    return `${this.endpoint}/photo/${uid}/${digest}`;
  }
  parse(reference) {
    if (typeof reference !== "string") {
      throw new ProofError("invalid-argument", "Invalid photo reference.");
    }
    const prefix = `${this.endpoint}/photo/`;
    if (!reference.startsWith(prefix)) {
      throw new ProofError(
        "invalid-argument",
        "Use a photo uploaded through this test backend.",
      );
    }
    const [uid, digest, ...extra] = reference.slice(prefix.length).split("/");
    if (extra.length) {
      throw new ProofError("invalid-argument", "Invalid photo reference.");
    }
    this.path(uid, digest);
    return { uid, digest };
  }
  async json(path, options = {}) {
    return fetchJson(`${this.origin}/storage/v1/${path}`, {
      ...options,
      headers: {
        authorization: `Bearer ${this.secret}`,
        apikey: this.secret,
        ...options.headers,
      },
    }, async (url, init) => {
      const response = await this.fetcher(url, init);
      // Hosted Storage wraps a missing object's 404 in HTTP 400. Recognize
      // that exact shape so first uploads proceed; permission errors stay errors.
      if (response.status === 400) {
        const error = await response.clone().json().catch(() => null);
        if (
          String(error?.statusCode) === "404" && error?.error === "not_found"
        ) {
          return new Response(
            JSON.stringify({ error: { status: "NOT_FOUND" } }),
            {
              status: 404,
              headers: { "content-type": "application/json" },
            },
          );
        }
      }
      return response;
    });
  }
  async assertPrivate() {
    const bucket = await this.json(`bucket/${this.bucket}`);
    if (bucket?.id !== this.bucket || bucket.public !== false) {
      throw new ProofError(
        "unavailable",
        "The private photo test bucket is not ready.",
        503,
      );
    }
  }
  async info(uid, digest) {
    const path = this.path(uid, digest);
    const info = await this.json(`object/info/${this.bucket}/${path}`);
    const size = info?.size ?? info?.metadata?.size;
    const type = info?.contentType ?? info?.content_type ??
      info?.metadata?.mimetype;
    if (
      !Number.isFinite(size) || size <= 0 || size > maxPhotoBytes ||
      type !== "image/jpeg"
    ) {
      throw new ProofError(
        "invalid-argument",
        "The photo is unavailable or invalid.",
      );
    }
    return info;
  }
  async upload(uid, digest, bytes) {
    await this.assertPrivate();
    const path = this.path(uid, digest);
    try {
      await this.info(uid, digest);
      return this.reference(uid, digest); // Immutable content-addressed upload retry.
    } catch (error) {
      if (error.code !== "not-found") throw error;
    }
    try {
      await this.json(`object/${this.bucket}/${path}`, {
        method: "POST",
        headers: {
          "content-type": "image/jpeg",
          "x-upsert": "false",
          "cache-control": "private, max-age=0",
        },
        body: bytes,
      });
    } catch (error) {
      // A response can be lost or a duplicate can race. Confirm the immutable object.
      try {
        await this.info(uid, digest);
      } catch (_) {
        throw error;
      }
    }
    await this.info(uid, digest);
    return this.reference(uid, digest);
  }
  async validate(reference, uid) {
    const parsed = this.parse(reference);
    if (parsed.uid !== uid) {
      throw new ProofError(
        "permission-denied",
        "Use your own report photo.",
        403,
      );
    }
    await this.assertPrivate();
    try {
      await this.info(uid, parsed.digest);
    } catch(error) {
      if(['not-found','invalid-argument'].includes(error.code))throw new ProofError('photo-unavailable','Your uploaded photo is no longer available. Upload it again.');
      throw error;
    }
    return reference;
  }
  async signed(reference) {
    const { uid, digest } = this.parse(reference);
    await this.assertPrivate();
    await this.info(uid, digest);
    const data = await this.json(
      `object/sign/${this.bucket}/${this.path(uid, digest)}`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ expiresIn: 120 }),
      },
    );
    const relative = data?.signedURL ?? data?.signedUrl;
    if (
      typeof relative !== "string" ||
      !relative.startsWith(`/object/sign/${this.bucket}/`)
    ) {
      throw new ProofError(
        "unavailable",
        "Photo delivery is unavailable.",
        503,
      );
    }
    return { url: `${this.origin}/storage/v1${relative}`, expiresIn: 120 };
  }
}
