import { assertBackendProject, TEST_BACKEND } from "./backend_profile.mjs";
import {
  assertLoopback,
  base64url,
  fetchJson,
  fromBase64url,
  identifier,
  ProofError,
  serverTime,
} from "./proof_common.mjs";

const encoder = new TextEncoder();
// Provider and runtime clocks can differ slightly. Expiry and revocation stay
// strict; only issuance/authentication timestamps get this bounded allowance.
const maxFutureClockSkewSeconds = 30;
function decodePart(value) {
  try {
    return JSON.parse(new TextDecoder().decode(fromBase64url(value)));
  } catch (_) {
    throw new ProofError("unauthenticated", "Invalid sign-in token.", 401);
  }
}

export class GoogleCredential {
  constructor(account, projectId, fetcher = fetch, clock = Date.now, profile = TEST_BACKEND) {
    assertBackendProject(projectId, profile);
    if (
      account?.project_id !== projectId ||
      !account?.client_email?.endsWith(
        `@${projectId}.iam.gserviceaccount.com`,
      ) || !account.private_key
    ) {
      throw new Error(
        "Use credentials belonging to the proof Firebase project only.",
      );
    }
    this.account = account;
    this.fetcher = fetcher;
    this.clock = clock;
  }
  async token() {
    if (this.cached && this.cached.expires > this.clock() + 60000) {
      return this.cached.value;
    }
    if (this.pending) return this.pending;
    this.pending = this.createToken();
    try {
      return await this.pending;
    } finally {
      this.pending = null;
    }
  }
  async createToken() {
    const now = Math.floor(this.clock() / 1000);
    const header = base64url(
      encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
    );
    const payload = base64url(
      encoder.encode(
        JSON.stringify({
          iss: this.account.client_email,
          scope:
            "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase.messaging",
          aud: "https://oauth2.googleapis.com/token",
          iat: now,
          exp: now + 3600,
        }),
      ),
    );
    if (!this.key) {
      const pem = this.account.private_key.replace(/-----[^-]+-----/g, "")
        .replace(/\s/g, "");
      const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
      this.key = await crypto.subtle.importKey(
        "pkcs8",
        der,
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["sign"],
      );
    }
    const signing = `${header}.${payload}`;
    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      this.key,
      encoder.encode(signing),
    );
    const data = await fetchJson("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: `${signing}.${base64url(signature)}`,
      }),
    }, this.fetcher);
    if (
      typeof data?.access_token !== "string" ||
      !Number.isFinite(data.expires_in)
    ) {
      throw new ProofError(
        "unavailable",
        "Server credentials are unavailable.",
        503,
      );
    }
    this.cached = {
      value: data.access_token,
      expires: this.clock() + data.expires_in * 1000,
    };
    return data.access_token;
  }
}

export function createFirebaseVerifier(
  {
    projectId,
    credential,
    fetcher = fetch,
    clock = Date.now,
    emulatorAuthHost = null,
    profile = TEST_BACKEND,
  },
) {
  assertBackendProject(projectId, profile);
  let authBase = "https://identitytoolkit.googleapis.com";
  if (emulatorAuthHost) {
    if (!projectId.startsWith("demo-")) {
      throw new Error(
        "Unsigned emulator tokens are forbidden outside a demo project.",
      );
    }
    authBase = `${
      assertLoopback(emulatorAuthHost)
    }/identitytoolkit.googleapis.com`;
  }
  let keys = null, expires = 0, loading;
  async function loadKeys() {
    const response = await fetcher(
      "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
      { redirect: "error", signal: AbortSignal.timeout(8000) },
    );
    if (!response.ok) {
      throw new ProofError(
        "unavailable",
        "Sign-in verification is unavailable.",
        503,
      );
    }
    const data = await response.json();
    if (!Array.isArray(data.keys)) {
      throw new ProofError(
        "unavailable",
        "Sign-in verification is unavailable.",
        503,
      );
    }
    keys = data.keys;
    const maxAge = Number(
      /max-age=(\d+)/.exec(response.headers.get("cache-control") ?? "")?.[1] ??
        300,
    );
    expires = clock() + Math.min(maxAge, 3600) * 1000;
  }
  return async (authorization) => {
    const token = /^Bearer ([A-Za-z0-9_.-]+)$/.exec(authorization ?? "")?.[1];
    if (!token || token.length > 16384) {
      throw new ProofError("unauthenticated", "Please sign in again.", 401);
    }
    const parts = token.split(".");
    if (parts.length !== 3) {
      throw new ProofError("unauthenticated", "Invalid sign-in token.", 401);
    }
    const header = decodePart(parts[0]), claims = decodePart(parts[1]);
    const now = Math.floor(clock() / 1000);
    if (
      claims.aud !== projectId ||
      claims.iss !== `https://securetoken.google.com/${projectId}` ||
      !identifier(claims.sub) || !Number.isInteger(claims.exp) ||
      claims.exp <= now ||
      !Number.isInteger(claims.iat) ||
      claims.iat > now + maxFutureClockSkewSeconds ||
      !Number.isInteger(claims.auth_time) ||
      claims.auth_time > now + maxFutureClockSkewSeconds ||
      claims.auth_time > claims.iat ||
      claims.firebase?.sign_in_provider === "anonymous" ||
      claims.email_verified !== true
    ) {
      throw new ProofError(
        "unauthenticated",
        "Use a verified account from the test project.",
        401,
      );
    }
    if (!emulatorAuthHost) {
      if (header.alg !== "RS256" || typeof header.kid !== "string") {
        throw new ProofError(
          "unauthenticated",
          "Invalid sign-in signature.",
          401,
        );
      }
      if (!keys || clock() >= expires) {
        loading ??= loadKeys();
        try {
          await loading;
        } catch (_) {
          throw new ProofError(
            "unavailable",
            "Sign-in verification is unavailable.",
            503,
          );
        } finally {
          loading = null;
        }
      }
      const jwk = keys.find((key) =>
        key.kid === header.kid && key.kty === "RSA"
      );
      if (!jwk) {
        throw new ProofError(
          "unauthenticated",
          "Refresh your sign-in and retry.",
          401,
        );
      }
      const key = await crypto.subtle.importKey(
        "jwk",
        jwk,
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["verify"],
      );
      if (
        !await crypto.subtle.verify(
          "RSASSA-PKCS1-v1_5",
          key,
          fromBase64url(parts[2]),
          encoder.encode(`${parts[0]}.${parts[1]}`),
        )
      ) {
        throw new ProofError(
          "unauthenticated",
          "Invalid sign-in signature.",
          401,
        );
      }
    } else if (header.alg !== "none") {
      throw new ProofError(
        "unauthenticated",
        "Unexpected emulator token.",
        401,
      );
    }
    const accessToken = await credential.token();
    const data = await fetchJson(
      `${authBase}/v1/projects/${projectId}/accounts:lookup`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ localId: [claims.sub] }),
      },
      fetcher,
    );
    const account = data?.users?.find((user) => user.localId === claims.sub);
    if (
      !account || account.disabled || account.emailVerified !== true ||
      !Number.isFinite(Number(account.validSince ?? 0)) ||
      claims.auth_time < Number(account.validSince ?? 0)
    ) {
      throw new ProofError(
        "unauthenticated",
        "The account or session is no longer valid.",
        401,
      );
    }
    return claims.sub;
  };
}

export function encodeValue(value) {
  if (value === null) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number" && Number.isFinite(value)) {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  if (value && typeof value === "object") {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map((
            [key, entry],
          ) => [key, encodeValue(entry)]),
        ),
      },
    };
  }
  throw new Error("Unsupported Firestore proof value.");
}
export function decodeValue(value) {
  if ("nullValue" in value) return null;
  if ("timestampValue" in value) return new Date(value.timestampValue);
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("arrayValue" in value) {
    return (value.arrayValue.values ?? []).map(decodeValue);
  }
  if ("mapValue" in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue.fields ?? {}).map((
        [key, entry],
      ) => [key, decodeValue(entry)]),
    );
  }
  throw new Error("Unsupported Firestore proof response.");
}

export class FirestoreRest {
  constructor({ projectId, credential, fetcher = fetch, emulatorHost = null, profile = TEST_BACKEND }) {
    assertBackendProject(projectId, profile);
    this.credential = credential;
    this.fetcher = fetcher;
    this.database = `projects/${projectId}/databases/(default)`;
    let base = "https://firestore.googleapis.com";
    if (emulatorHost) {
      if (!projectId.startsWith("demo-")) {
        throw new Error("The Firestore emulator requires a demo project.");
      }
      base = assertLoopback(emulatorHost);
    }
    this.base = `${base}/v1/${this.database}/documents`;
  }
  async request(suffix, body, method = "POST") {
    return fetchJson(`${this.base}${suffix}`, {
      method,
      headers: {
        authorization: `Bearer ${await this.credential.token()}`,
        "content-type": "application/json",
      },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }, this.fetcher);
  }
  document(path) {
    if (!path.split("/").every(identifier) || path.split("/").length % 2) {
      throw new Error("Invalid Firestore proof path.");
    }
    return `${this.database}/documents/${path}`;
  }
  async get(path, transaction) {
    this.document(path);
    try {
      // Use batchGet for transactional reads. Besides supporting the hosted REST
      // API, this avoids the emulator's broken bytes-in-query-string adapter.
      let doc;
      if (transaction) {
        const result = await this.request(":batchGet", {
          documents: [this.document(path)],
          transaction,
        });
        doc = result.find((entry) => entry.found)?.found;
        if (!doc) return { path, exists: false, data: {} };
      } else {
        doc = await this.request(`/${path}`, undefined, "GET");
      }
      return {
        path,
        exists: true,
        updateTime: doc.updateTime,
        data: Object.fromEntries(
          Object.entries(doc.fields ?? {}).map((
            [key, value],
          ) => [key, decodeValue(value)]),
        ),
      };
    } catch (error) {
      if (error.code === "not-found") return { path, exists: false, data: {} };
      throw error;
    }
  }
  async queryPage(
    collection,
    filters = [],
    { limit = 100, orderBy = [], startAfter = null, afterDocument = null, select = [], transaction } =
      {},
  ) {
    if (
      !identifier(collection) || !Number.isInteger(limit) || limit < 1 ||
      limit > 1001 ||
      !Array.isArray(filters) ||
      filters.some(([field, op]) =>
        !identifier(field) ||
        !["EQUAL", "LESS_THAN_OR_EQUAL", "GREATER_THAN", "IN", "ARRAY_CONTAINS"]
          .includes(op)
      ) ||
      select.some((field) => !identifier(field))
    ) throw new Error("Invalid bounded worker query.");
    if (afterDocument != null && (typeof afterDocument !== "string" ||
        !new RegExp(`^${collection}/[A-Za-z0-9_-]{1,128}$`).test(afterDocument) ||
        startAfter || orderBy.length !== 1 || orderBy[0].field?.fieldPath !== "__name__")) {
      throw new Error("Invalid document cursor.");
    }
    const predicates = filters.map(([field, op, value]) => ({
      fieldFilter: {
        field: { fieldPath: field },
        op,
        value: encodeValue(value),
      },
    }));
    const response = await this.request(":runQuery", {
      ...(transaction ? { transaction } : {}),
      structuredQuery: {
        from: [{ collectionId: collection }],
        ...(predicates.length
          ? {
            where: predicates.length === 1
              ? predicates[0]
              : { compositeFilter: { op: "AND", filters: predicates } },
          }
          : {}),
        ...(orderBy.length ? { orderBy } : {}),
        ...(afterDocument ? { startAt: { values: [{referenceValue:`${this.database}/documents/${afterDocument}`}], before:false } } : {}),
        ...(startAfter
          ? { startAt: { values: startAfter.map(encodeValue), before: false } }
          : {}),
        ...(select.length
          ? {
            select: { fields: select.map((field) => ({ fieldPath: field })) },
          }
          : {}),
        limit,
      },
    });
    const readTime =
      response.map((row) => row.readTime).filter(Boolean).sort()[0];
    return {
      readTime,
      docs: response.filter((row) => row.document).map(({ document: doc }) => ({
        path: doc.name.split("/documents/")[1],
        exists: true,
        updateTime: doc.updateTime,
        data: Object.fromEntries(
          Object.entries(doc.fields ?? {}).map((
            [key, value],
          ) => [key, decodeValue(value)]),
        ),
      })),
    };
  }
  async query(collection, filters, options = {}) {
    return (await this.queryPage(collection, filters, options)).docs;
  }
  async transaction(work) {
    let retryTransaction;
    for (let attempt = 0; attempt < 5; attempt++) {
      const { transaction } = await this.request(":beginTransaction", {
        options: { readWrite: retryTransaction ? { retryTransaction } : {} },
      });
      const writes = [];
      const documents = this;
      const tx = {
        get: (path) => documents.get(path, transaction),
        queryWhere: (collection, filters, limit = 100) =>
          documents.query(collection, filters, { limit, transaction }),
        async query(collection, field, value, limit = 101) {
          if (!identifier(collection) || !identifier(field) || limit > 201) {
            throw new Error("Invalid bounded proof query.");
          }
          const response = await documents.request(":runQuery", {
            transaction,
            structuredQuery: {
              from: [{ collectionId: collection }],
              where: {
                fieldFilter: {
                  field: { fieldPath: field },
                  op: "EQUAL",
                  value: encodeValue(value),
                },
              },
              limit,
            },
          });
          return response.filter((entry) => entry.document).map((
            { document: doc },
          ) => ({
            path: doc.name.split("/documents/")[1],
            exists: true,
            data: Object.fromEntries(
              Object.entries(doc.fields ?? {}).map((
                [key, value],
              ) => [key, decodeValue(value)]),
            ),
          }));
        },
        async pending(uid, roadId) {
          const response = await documents.request(":runQuery", {
            transaction,
            structuredQuery: {
              from: [{ collectionId: "reports" }],
              where: {
                compositeFilter: {
                  op: "AND",
                  filters: [["userId", uid], ["roadId", roadId], [
                    "status",
                    "pending",
                  ]].map(([field, value]) => ({
                    fieldFilter: {
                      field: { fieldPath: field },
                      op: "EQUAL",
                      value: encodeValue(value),
                    },
                  })),
                },
              },
              limit: 1,
            },
          });
          const doc = response.find((entry) => entry.document)?.document;
          return doc
            ? {
              path: doc.name.split("/documents/")[1],
              exists: true,
              data: Object.fromEntries(
                Object.entries(doc.fields ?? {}).map((
                  [key, value],
                ) => [key, decodeValue(value)]),
              ),
            }
            : null;
        },
        set(path, data, { merge = false, create = false } = {}) {
          const fields = {}, transforms = [];
          // Firestore timestamps can also occur inside response/evidence maps.
          // Keep those as server transforms rather than encoding the sentinel.
          const fieldPath = (parts) => parts.map((part) =>
            /^[A-Za-z_][A-Za-z_0-9]*$/.test(part) ? part :
              "`" + part.replace(/\\/g, "\\\\").replace(/`/g, "\\`") + "`"
          ).join(".");
          const writeValue = (value, parts) => {
            if (value === serverTime) {
              transforms.push({ fieldPath: fieldPath(parts), setToServerValue: "REQUEST_TIME" });
              return undefined;
            }
            if (value && typeof value === "object" && !Array.isArray(value) && !(value instanceof Date)) {
              const nested = {};
              for (const [key, entry] of Object.entries(value)) {
                const encoded = writeValue(entry, [...parts, key]);
                if (encoded !== undefined) nested[key] = encoded;
              }
              return { mapValue: { fields: nested } };
            }
            return encodeValue(value);
          };
          for (const [key, value] of Object.entries(data)) {
            if (!/^[A-Za-z_][A-Za-z_0-9]*$/.test(key)) {
              throw new Error("Invalid proof field.");
            }
            const encoded = writeValue(value, [key]);
            if (encoded !== undefined) fields[key] = encoded;
          }
          writes.push({
            update: { name: documents.document(path), fields },
            ...(merge
              ? { updateMask: { fieldPaths: Object.keys(fields) } }
              : {}),
            ...(create ? { currentDocument: { exists: false } } : {}),
            ...(transforms.length ? { updateTransforms: transforms } : {}),
          });
        },
        delete(path) {
          writes.push({
            delete: documents.document(path),
            currentDocument: { exists: true },
          });
        },
      };
      try {
        const result = await work(tx);
        await this.request(":commit", { transaction, writes });
        return result;
      } catch (error) {
        try {
          await this.request(":rollback", { transaction });
        } catch (_) {}
        if (!["aborted", "unavailable"].includes(error.code) || attempt === 4) {
          if (error.code === "aborted") {
            throw new ProofError(
              "unavailable",
              "The server is busy. Preserve the form and retry.",
              503,
            );
          }
          throw error;
        }
        retryTransaction = error.code === "aborted" ? transaction : undefined;
        // Exponential jitter avoids both clients retrying in lockstep. The
        // aborted transaction hint preserves Firestore's retry priority.
        const backoff = Math.min(1200, 200 * 2 ** attempt);
        await new Promise((resolve) =>
          setTimeout(resolve, Math.floor(backoff * (0.5 + Math.random())))
        );
      }
    }
  }
}
