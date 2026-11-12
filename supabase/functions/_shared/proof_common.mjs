// Portable Web APIs only: shared by the Edge entry point and local proof tests.
export class ProofError extends Error {
  constructor(code, message, status = 400) {
    super(message);
    this.code = code;
    this.status = status;
  }
}
export const serverTime = Symbol("server-time");
export const maxPhotoBytes = 2 * 1024 * 1024;
export const maxObservationAge = 24 * 60 * 60 * 1000;
export const millis = (value) =>
  value instanceof Date ? value.getTime() : Number(value) || 0;
export const clamp = (n, low = 0, high = 100) =>
  Math.min(high, Math.max(low, n));
export const base64url = (bytes) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes))).replaceAll("+", "-")
    .replaceAll("/", "_").replace(/=+$/, "");
export function fromBase64url(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new ProofError("unauthenticated", "Invalid sign-in token.", 401);
  }
  return Uint8Array.from(
    atob(value.replaceAll("-", "+").replaceAll("_", "/")),
    (c) => c.charCodeAt(0),
  );
}
export async function sha256(value) {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        typeof value === "string" ? new TextEncoder().encode(value) : value,
      ),
    ),
  ].map((n) => n.toString(16).padStart(2, "0")).join("");
}
export function identifier(value) {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
}
export function assertProofProject(project) {
  if (
    !/^[a-z][a-z0-9-]{5,62}$/.test(project ?? "") ||
    project === "safepaths-92c3d" ||
    !/(?:^demo-|[-](?:test|staging)(?:-|$))/.test(project)
  ) {
    throw new Error(
      "The proof requires an explicitly named Firebase test/staging project; the main project is forbidden.",
    );
  }
}
export function assertLoopback(host) {
  const url = new URL(`http://${host}`);
  if (
    !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname) ||
    url.username || url.password || url.pathname !== "/" || url.search ||
    url.hash
  ) throw new Error("Proof emulators must use loopback hosts.");
  return url.origin;
}
export async function readBounded(request, maximum) {
  const declared = request.headers.get("content-length");
  if (
    declared != null && (!/^\d+$/.test(declared) || Number(declared) > maximum)
  ) {
    throw new ProofError(
      "too-large",
      "The attachment or request is too large.",
      413,
    );
  }
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > maximum) {
        await reader.cancel();
        throw new ProofError(
          "too-large",
          "The attachment or request is too large.",
          413,
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}
export async function fetchJson(url, options = {}, fetcher = fetch) {
  let response;
  try {
    response = await fetcher(url, {
      ...options,
      redirect: "error",
      signal: options.signal ?? AbortSignal.timeout(10000),
    });
  } catch (_) {
    throw new ProofError(
      "unavailable",
      "The service is unavailable. Preserve the form and retry.",
      503,
    );
  }
  let data;
  try {
    data = await response.json();
  } catch (_) {
    data = null;
  }
  if (!response.ok) {
    const status = data?.error?.status;
    if (response.status === 404) {
      throw new ProofError(
        "not-found",
        "The requested record is unavailable.",
        404,
      );
    }
    if (status === "ABORTED" || response.status === 409) {
      throw new ProofError("aborted", "Concurrent update. Retry.", 409);
    }
    throw new ProofError(
      "unavailable",
      "The service could not complete the request. Preserve the form and retry.",
      503,
    );
  }
  return data;
}
