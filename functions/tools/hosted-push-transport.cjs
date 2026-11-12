// Diagnostics for synthetic acceptance tools only. Never record bearer tokens,
// request/response bodies, signed URLs, account IDs or arbitrary provider text.
const endpoint = 'https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof';
const routes = new Set(['push-drain', 'push-preflight', 'push-device', 'push-status', 'admin-action']);
const safeCodes = new Set(['unauthenticated', 'permission-denied', 'unavailable', 'failed-precondition', 'invalid-argument', 'already-exists', 'not-found', 'resource-exhausted']);
const networkCodes = new Set(['ECONNRESET', 'ECONNREFUSED', 'ENOTFOUND', 'EAI_AGAIN', 'ETIMEDOUT', 'UND_ERR_CONNECT_TIMEOUT', 'UND_ERR_SOCKET', 'UND_ERR_HEADERS_TIMEOUT']);
async function observedPost({route, bearer, data, headers = {}, caseName, observe = () => {}, fetcher = fetch, timeoutMs = 45000}) {
  if (!routes.has(route) || !/^[a-z0-9_-]{1,64}$/.test(caseName ?? '')) throw new Error('Invalid diagnostic operation.');
  const start = Date.now(), observation = {case: caseName, route, startedAt: new Date(start).toISOString(), outcome: 'network-error', httpStatus: null};
  let response, body = {};
  try {
    response = await fetcher(`${endpoint}/${route}`, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(timeoutMs), headers: {'content-type': 'application/json', ...(bearer ? {authorization: `Bearer ${bearer}`} : {}), ...headers}, body: JSON.stringify({data})});
    observation.httpStatus = response.status;
    observation.outcome = 'http-response';
    const requestId = response.headers.get('sb-request-id');
    if (/^[a-f0-9-]{32,64}$/i.test(requestId ?? '')) observation.edgeRequestId = requestId;
    observation.noStore = response.headers.get('cache-control') === 'no-store';
    const reader = response.body?.getReader(), chunks = []; let size = 0;
    if (reader) {
      try {
        for (;;) {
          const {done, value} = await reader.read(); if (done) break;
          size += value.length; if (size > 20000) {await reader.cancel(); throw new Error('Bounded diagnostic response exceeded.');}
          chunks.push(value);
        }
      } finally {reader.releaseLock();}
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.length;}
    try {body = JSON.parse(new TextDecoder().decode(bytes)); observation.json = true;} catch (_) {observation.json = false;}
    if (safeCodes.has(body?.error?.code)) observation.errorCode = body.error.code;
  } catch (error) {
    observation.outcome = response ? 'response-read-error' : 'network-error';
    if (['TimeoutError', 'AbortError'].includes(error?.name)) observation.outcome = 'timeout';
    if (networkCodes.has(error?.cause?.code)) observation.networkCode = error.cause.code;
  }
  observation.elapsedMs = Date.now() - start;
  try {observe(observation);} catch (_) {} // Diagnostic failure must not mask the actual response.
  return {status: response?.status ?? null, data: body, observation};
}
async function withCleanup(work, cleanup, observe = () => {}) {
  let value, workError, cleanupError;
  try {value = await work();} catch (error) {workError = error;}
  try {await cleanup();} catch (error) {cleanupError = error;}
  try {observe({workFailed: !!workError, cleanupFailed: !!cleanupError, retainedFailure: workError ? 'work' : cleanupError ? 'cleanup' : null});} catch (_) {}
  // A Firestore/network error in cleanup must not replace the original failed
  // HTTP assertion and make its reported stage misleading.
  if (workError) throw workError;
  if (cleanupError) throw cleanupError;
  return value;
}
module.exports = {observedPost, withCleanup};
