# Reliability changes and rollout

**Normal report/photo follow-up, 2026-10-25:** [normal-form integration](normal-report-integration.md) connects those screens to the tested backend only through an explicit fieldtest option. Failure/retry/history/media-access evidence is recorded there. The standalone proof's fixed coordinates are not used by normal submissions. Main Firebase, existing APKs and billing remain unchanged; no new build or distribution occurred.

**Report push follow-up, 2026-10-25:** the [test-only report-update sender](push-delivery.md) adds server-owned token registration, durable retries and signed scheduled calls. Saved admin actions remain successful when push fails. Hosted validation does not establish actual phone receipt; builds remain on hold. Main Firebase, billing and existing installers are unchanged.

**Admin interaction follow-up, 2026-10-25:** the isolated Spark proof adds explicit review, private updates, protected resident edits and one transactional moderation decision. Its current rules/indexes and Supabase endpoint are test-only. See [workflow changes and acceptance](admin-resident-workflow.md). No main-project rollout or new main APK distribution occurred; normal source integration remains staged until the remaining Spark-dependent paths and device checks are complete.

## Confirmed billing prerequisite — 2026-10-24

The user reports that `safepaths-92c3d` is on **Spark**. The current backend requires Cloud Functions and Cloud Scheduler; it cannot be deployed as written while that project remains on Spark. This is a deployment prerequisite, not a failure of the emulator tests. The attempted read-only live function inventory failed, so the deployed function inventory remains unverified.

**User decision:** keep this capstone on Spark without a linked billing account. Treat that as an implementation constraint; do not continue toward a Blaze upgrade. The rollout below describes the existing Cloud Functions architecture and is blocked until a Spark-compatible design replaces its paid-service dependencies. Passing local tests and building an APK do not remove this blocker.

The active sequence is documented in [the Spark capstone plan](spark-capstone-plan.md): preserve and identify the baseline, prove a complete report/photo flow using Supabase Free, then port remaining server operations, budget quotas, verify devices and prepare a coordinated review build. On 2026-10-25 the isolated proof passed local checks, its separate test APK compiled, and its hosted test endpoint/private bucket passed automated report/photo/access checks. Rules and six indexes were deployed only to `safepaths-test`; the original test rules/index inventory was backed up first. Main Firebase, main APK files and existing Supabase app paths remain unchanged. The main application has not been migrated, and two-phone acceptance is pending. See [proof setup and evidence](spark-proof-setup.md).

The reusable local work includes UI/layout, password/verification flows, localization/accessibility, compression/retry coordination, bounded history, map caching, conservative route handling and privacy-safe diagnostics. The backend-dependent paths requiring adaptation are report submission (`submitReport`), resident observations/admin incident reviews (`observeRoadIncident`/`reviewRoadIncident`), app-triggered push sending (`sendNotification`), scheduled weather/risk/expiry/migration processing, and Firebase report-photo storage. FCM itself is a no-cost product; the present app's trusted sending endpoint is the blocked component. Firebase Authentication and Firestore remain candidates within Spark's limits; their availability does not automatically enable these callables.

The user authorized the staged Supabase Free proof. Review actual hosted bucket policies, permissions and quotas before accepting it. A supervised computer-hosted backend remains an alternative only if the hosted proof fails; it would require the team's computer/network to remain available. Preserve existing reliability/security invariants and rerun integration/device tests against the replacement. The local Storage protocol fixture does not establish hosted Supabase RLS or two-phone behavior.

[Firebase requires Blaze to deploy Cloud Functions](https://firebase.google.com/docs/functions/get-started). Its [current Storage guidance](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024) also requires Blaze for Firebase Cloud Storage access, effective February 3, 2026. Photo storage therefore needs explicit live verification as well; do not assume an older installed app's uploads are working merely because local code has not changed. Supabase paths are separate and do not make this backend Spark-compatible.

No billing upgrade is authorized. Before choosing Blaze, review the project's actual storage region, road/report volumes, scheduler activity, Firebase/Google Cloud costs and available spending controls with the team. The risk job currently runs every minute and reads/revises road records even with no active residents, so a handful of users is not a zero-cost guarantee. [Budget alerts alone do not cap charges](https://firebase.google.com/docs/projects/billing/advanced-billing-alerts-logic); review available service spend caps and their coverage/limitations using [Firebase billing guidance](https://firebase.google.com/docs/projects/billing/avoid-surprise-bills).

Follow the selected Spark plan and its isolated hosted proof before adapting the remaining trusted server, scheduler and media operations. Do not restore privileged client writes or bundle server credentials. Each replacement needs implementation, regression and hosted/device verification. Building an APK alone does not make its required services available.

## Implemented locally

- Road records, shared audits, and report moderation are restricted to administrators or trusted server code. Residents cannot change trust scores, moderation state, identity, or submission cooldowns. Profile/token updates remain available; other users' private profiles and FCM tokens are not readable by residents.
- Firebase Storage writes use account-owned paths, image content types and a 10 MB cap. Existing public image URLs remain readable. This change does not claim to add private photo moderation.
- Report submission uses an authenticated Firebase callable and a server transaction. The transaction validates the road and coordinates, derives identity/reputation, enforces the five-minute cooldown, selects a pending report using server state, and writes a durable request receipt atomically. Persistent per-form request IDs make response-loss retries idempotent. A completed report is retained in history when a later submission starts a new report.
- Push sending uses the deployed function's credentials and requires an administrator profile. The app no longer contains service-account authentication code. Invalid device tokens are removed. UI feedback distinguishes acceptance for sending from confirmed device receipt.
- Shared weather fetching, risk scoring, report expiry, and consensus audits run in scheduled backend functions. Risk processing uses a lease, batched writes with version preconditions, and an observable success/failure heartbeat. Weather failures retain previous scores and mark the backend unhealthy instead of publishing a new safe score.
- Weather is fetched for the Marulas production area. Existing drill overrides expire; these production scheduled functions must not be deployed into a field-test project without adapting its area/simulation settings.
- Firestore listeners include metadata updates, report errors, preserve prior data on malformed documents, and retry with backoff. A persistent banner warns when data is cached, updates fail, or the risk scheduler's last success is over five minutes old. Retry is available. Navigation requires caution confirmation when live road/weather data cannot be confirmed.
- New route calculations immediately invalidate previous routes; failure cannot leave the old destination's route selectable.
- Notification startup is detached from app startup, and optional setup/profile reads have bounded waits. Notification failure no longer masquerades as Firebase initialization failure.

## Source locations

- `functions/index.cjs`: report/push callables and scheduled production weather/risk jobs.
- `functions/domain.cjs`: validation, geometry, confidence and risk functions.
- `firestore.rules`, `storage.rules`, `firestore.indexes.json`: backend access and query requirements.
- `lib/services/backend_service.dart`: authenticated callable protocol; region `us-central1`.
- `lib/services/sync_health.dart`, `lib/widgets/sync_status_banner.dart`: sync/scheduler health.
- `test/risk-parity-fixtures.json`: shared regression fixtures exercised by both Dart and Node.

## Required rollout (not deployed by this change)

This section retains the **main app's legacy Cloud Functions rollout** as reference. Do not execute it while Spark is the selected architecture. The separate proof's completed test-only deployment and remaining phone gates are recorded in [proof setup](spark-proof-setup.md).

This is a coordinated backend-and-app change. Deploying only the rules will stop older clients from submitting reports or writing shared risk scores. Releasing only the app will leave report/push calls unavailable until its functions are deployed.

1. Verify the Firebase project is `safepaths-92c3d`, the production storage bucket is `safepaths-92c3d.firebasestorage.app`, and the project can run Functions/Scheduler. The server defaults to that project's `.firebasestorage.app` bucket; `REPORT_STORAGE_BUCKET` can override it for a different existing bucket. Review billing before creating production resources.
2. Install the locked backend dependencies with `npm ci --prefix functions`. Use Node 22 for deployment and Java 21+ for current Firebase emulator tests.
3. Deploy `firestore:indexes` first and wait for the reports index to become ready. Then deploy `functions` and verify a successful weather refresh and `system/risk_job.lastSuccess`. The canonical jobs must be running before claiming live risk updates.
4. Smoke-test a resident report, replay, cooldown, admin review, and admin push in a staging project. Verify the actual callable HTTP authentication envelope and FCM behavior on an Android device; emulator tests exercise callable handlers and rules, not live FCM delivery.
5. During a coordinated rollout, deploy the Firestore/Storage rules and distribute the updated app. Require testers to use the new build. Retest profile edits, FCM token registration, image uploads, report history, and admin moderation.
6. Check existing profiles/roads for incorrect data that may have been written under the earlier broad permissions. Rule changes do not repair existing records.
7. If retired FCM entries were present in `.env`, they were moved to ignored `.env.server-only.backup` and removed from the bundled asset and example. If any real key was distributed in an older APK, revoke/rotate it. The new backend uses its runtime identity and does not need that key file.

No live rules, functions, indexes, billing settings, or distribution were changed by this work. Do not restore the old broad write permissions as a rollback strategy.

## Verification

Run Flutter tests with `flutter test --no-pub` and backend unit tests with `npm --prefix functions test`.
For isolated integration tests (never use a real project ID):

```
firebase emulators:exec --project demo-safepaths-reliability --only firestore,storage,auth "npm --prefix functions run test:emulator"
```

Coverage includes unauthorized road/trust/cooldown changes, profile edits, private profile access, storage ownership/type/size, simultaneous submissions, response-loss replay, updating an active report, forged location/photo URLs, notification authorization, server expiry/risk updates without an active app, scheduler failure with stale weather, stale-route removal, sync health, and nine cross-language risk fixtures.

Actual device stress testing, long outages, process termination during uploads, and background notification receipt remain device acceptance work. General load capacity has not been established.

Firebase references: [callable functions](https://firebase.google.com/docs/functions/callable), [callable HTTP protocol](https://firebase.google.com/docs/functions/callable-reference).

Final local results: **141 Flutter tests, 13 Node unit/parity tests, and 11 Firestore/Storage emulator integration tests passed**. Flutter analysis has no compile errors; existing lint warnings remain. Tracked-file whitespace checks and backend syntax checks passed.

## Section 5.1 follow-up

See `account-security-5.1.md` for email-verification gates, login/reset safeguards, inactivity timeouts, revocation checks, and the required Firebase console/email delivery checks. The emulator command now also needs `auth` in `--only firestore,storage,auth`.

- [ ] Before resident release, revisit deferred section **4.2 photo moderation**. This is a checklist reminder, not a scheduled notification.

## Section 5.2 follow-up

See `report-reliability-5.2.md` for resident observations, unknown-road caution, admin incident reviews, and the additional indexes/callables. Wait for the paginated legacy migration (`system/incident_migration.complete`) and verify staging acceptance before resident rollout. The team is continuing fixes; no new APK distribution or production deployment is authorized at this stage.

## Section 5.4 follow-up

See `performance-5.4.md` for the complete active-feed/paged-history split, required `reports(userId, createdAt desc)` index, map update/retry changes, and local measurements. The 20-user same-road burst failed with retryable contention; recovery preserved reports without duplicates. Staging contention/latency and physical Android profiling are open release checks. Passing regression tests does not close B-05 or establish production capacity.

## Section 5.5 acceptance

Follow `usability-accessibility-5.5.md` before marking usability/accessibility complete. In particular, test the restricted saved-road viewer after a real offline restart without weakening verification/session expiry, confirm native road/route overlays after theme changes, and record actual notification receipt/tap behavior on physical Android phones. Review Filipino wording and dynamic English fallbacks. This work does not authorize an APK rollout or production deployment; the existing backend/index/migration and section 5.4 release gates still apply.


## Core migration update - 2026-10-25

Resident incident observations and weather/risk/expiry now have an implemented and hosted-verified **test-only** Spark migration. The signed maintenance schedule is active every four minutes, with an actual successful automatic run recorded. See [scope, evidence and remaining gates](spark-core-migration.md). This supersedes earlier statements that those test backend paths are unimplemented. Native acceptance, other media/notification paths and the main rollout remain open. No new APK was built or installed.


## Communication migration update - 2026-10-25

Feedback and broadcasts now have an implemented, hosted-verified **test-only** migration. Private owner history, explicit reply/closure, consent, idempotent scoped publications, expiry/withdrawal and typed fair notification processing are covered. Existing report push and report/photo hosted regressions also pass. See [current scope and evidence](communication-migration.md); older counts and deployment versions above are dated phase baselines. Profile/feedback media also has separate [test-only acceptance](private-media-migration.md). APK builds, native phone acceptance, performance/adviser decisions and main-project rollout remain open.
