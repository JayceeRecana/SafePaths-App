# Resident observations and weather/risk on Spark

APK build and installation remain on hold. This migration targets Firebase
`safepaths-test` and the existing isolated Supabase proof function. It does not
deploy to `safepaths-92c3d` or certify the main application.

## Implementation

- `proof_incidents.mjs` handles current resident observations with verified,
  allowlisted identities, atomic per-account counts, durable retry receipts,
  a one-minute update cooldown, and self-confirmation rejection. Apparent
  passability requests administrator review; it never changes official status.
- `proof_weather.mjs` retrieves Open-Meteo estimates for `nearby_test`. It checks
  units, ranges and the provider's observation timestamp. Precipitation covering
  the provider interval is converted to mm/hour. Hourly forecasts come from the
  provider; missing forecasts remain unavailable. These are weather model
  estimates, not official typhoon warnings. [Provider documentation](https://open-meteo.com/en/docs)
- Administrator drills are server-confirmed, expire after 5–30 minutes, and do
  not gain more time when a lost response is retried. Disabling a drill waits
  for real data rather than inventing clear conditions.
- `proof_core.mjs` expires active evidence before fetching weather. It retains
  road closures and historical evidence. An outage, conflict, quota guard or
  partial write cannot advance the successful risk heartbeat or cached graph.
  The portable risk formula is tested against `functions/domain.cjs`.

## Workload and freshness

The test inventory contained 737 roads. The backed-up bootstrap selected 736 in
the test area and excluded the earlier Marulas proof fixture. Official road
status, notes and verification timestamps are preserved.

The active four-minute worker caches the network, reconciles it hourly, polls
indexed `updatedAt` and `riskInputsUpdatedAt` changes, and writes only changed
derived risk fields. New graph/import/admin/report operations mark risk inputs.
Direct console edits without timestamps are detected by hourly reconciliation;
they should not be used for urgent condition updates.

Limits are explicit: 1,000 scoped roads, 100 active reports, 50 due incidents per
run, a 750 KB graph cache and a 95-second work deadline. Exceeding a limit marks
the job unavailable; it does not silently truncate a successful result.
Daily reservations conservatively allocate this worker up to 30,000 reads and
12,000 writes, using the Firestore quota day's Pacific timezone. Interrupted
runs retain their reservation. App traffic shares the same project quota, so
this is a guard, not a guarantee of free capacity. Firestore's free daily limits
are 50,000 document reads and 20,000 writes. [Firestore quotas](https://firebase.google.com/docs/firestore/quotas)
Supabase Free's function wall-time limit is 150 seconds. [Function limits](https://supabase.com/docs/guides/functions/limits)

## Rollout controls

The server requires `PROOF_CORE_ENABLED=true`. The native client independently
requires `SPARK_PROOF_CORE_ENABLED=true`, the `fieldtest` flavor, and the pinned
test Firebase configuration. Normal test reporting separately requires
`SPARK_PROOF_REPORTS_ENABLED=true`. Default fieldtest builds retain the previous
simulation behavior. No private server credential goes in a build.

`supabase/proof-core-schedule.sql` creates the schedule **inactive**. The signer
queues only two-minute, one-use, purpose-bound HMAC tickets. The reusable key
stays in Vault. Push tickets cannot authorize core work. Client administrators
cannot alter worker leases, cache, budgets, retry receipts or managed weather.

Preparation evidence and the private, timestamp-preserving data backup are in
the ignored `.usability-work-baseline/core-bootstrap` directory. Do not publish
that backup. Retention policy and automatic deletion remain unchanged.

Disable this test schedule if needed; a failed/stopped worker must leave its
heartbeat stale. Do not restore whole backed-up road records over later admin
decisions. Rollback should preserve newer official edits and reports.

## Acceptance and remaining scope

Local checks: 230 Flutter tests passed (one optional benchmark skipped), 45
backend unit tests passed, and 65 emulator tests passed. Full analysis found no
compile errors and four existing warnings; style/information findings remain.
Seven hosted checks and 27 fieldtest opt-in checks also passed. All 11 test
indexes are READY. The signed probe returned HTTP 200, and the automatic run at
2026-10-25 04:56 UTC completed successfully (14 reads, 3 writes recorded by the
worker; no changed road writes). The existing push schedule remains active.
Evidence is in the ignored verification artifacts. Native phone acceptance is
still required.

This covers the two quoted core areas, not every Spark-dependent feature.
Broadcast/feedback communication now has a separately verified test migration;
see [communication results](communication-migration.md). Profile/feedback media
now has separate [test-only acceptance](private-media-migration.md). The
[full-app audit](full-app-integration-audit.md) identified road deletion/cache
invalidation and import/review concurrency; these now have separate
[test-only maintenance acceptance](road-maintenance.md). The main-project rollout,
physical-device push receipt, offline/resume flows, performance burst check,
and unresolved adviser privacy decisions remain open.
