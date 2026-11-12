# SafePaths Spark capstone plan

**Rerouting recovery follow-up, 2026-10-25:** [current scenario acceptance](rerouting-scenario-acceptance.md)
records 297 full Flutter passes (one skipped) and 156 complete-fieldtest checks
after local advisory/staging/reopening/failure-feedback fixes. No backend or
native configuration changed. Main Spark integration, device/provider/workload
acceptance and the APK hold remain separate gates.

**Planner/rerouting follow-up, 2026-10-25:** [local reliability review](planner-rerouting-reliability.md)
fixes stale planning sessions, fabricated GPS origins, closure/start races and
GPS/reroute recovery. The full Flutter suite passes 278 tests (one skipped),
and 137 complete-fieldtest checks pass. This phase changes local Dart behavior
in both flavors; backend deployment/main integration, native navigation and
stress acceptance remain separate. The APK hold is still in force.

**Road-maintenance follow-up, 2026-10-25:** [protected maintenance](road-maintenance.md)
now fixes import/review overwrite and deletion/cache invalidation in the test
migration. Server transactions preserve official reviews/history, prune neighbors,
reject active-condition deletion and force the next worker to refresh topology.
Local/emulator and hosted acceptance pass; the next gate is the small capstone
workload test. Main-project integration, native acceptance and APK hold remain.

**Integration audit follow-up, 2026-10-25:** [full-app audit](full-app-integration-audit.md)
records the actual main/test path split, a fixed test map-import shortcut and
index-preparation selection, a complete candidate configuration, and bounded
push investigation. Road deletion/cache invalidation and import/review
concurrency are newly identified pre-build blockers. Current push checks pass;
the historical first failure remains unexplained. Main integration and the APK
hold remain in force.

**Current checkpoint, 2026-10-25:** the isolated proof now covers reporting,
resident observations, scheduled weather/risk/expiry, admin replies, feedback,
broadcasts, notification processing and [private profile/feedback media](private-media-migration.md).
Those paths have automated test-backend acceptance. Historical phase statements
below describe earlier checkpoints. Main-project integration/rollout, native
phone acceptance, performance/B-05 and adviser decisions remain open. APK
building, installation and distribution remain on hold.

**Normal reporting integration:** the [normal form's report/photo path](normal-report-integration.md) now uses the tested endpoint when explicitly enabled in the fieldtest flavor, including persistent retries, history/admin-feed confirmation and protected photo delivery. Native phone acceptance remains pending. Production defaults and remaining incident/weather/risk/broadcast/media paths still need migration; APK builds remain on hold.

**Report-update push follow-up:** the isolated proof now has a tested sender, protected device registration and scheduled retries. See [push evidence](push-delivery.md). Real phone receipt/taps, broadcast/weather push, resident incident observations, scheduled weather/risk work and complete main-app migration remain open. APK builds stay on hold by explicit user request.

**Admin extension, 2026-10-25:** the user explicitly approved implementing the resident/admin recommendations while the one-phone acceptance gate remains open. The isolated backend now includes explicit review, private replies, atomic moderation/road/trust/audit updates and protected resident edits. See [current workflow evidence](admin-resident-workflow.md). This advances the test proof; the main application and remaining scheduled/observation/push workflows still require migration and acceptance. The simultaneous two-phone gate remains pending.

Prepared 2026-10-24; proof status updated 2026-10-25. **The isolated report/photo backend is deployed and passes automated hosted checks. Its separate APK compiles; two-phone acceptance remains pending.** The main application has not been migrated. The user requires Firebase Spark and no linked billing account; a later beneficiary implementation is a separate decision. See [proof setup and evidence](spark-proof-setup.md).

## Intended result

Preserve the capstone's reporting, road information, routing and evaluation workflows while removing dependencies on Firebase Cloud Functions, its scheduled functions and Firebase report-photo storage. Keep the existing UI/reliability improvements. Verify each replacement before moving the next dependent workflow.

| Component | Intended home | Scope |
| --- | --- | --- |
| Login, password reset and verification | Firebase Authentication | Keep current identities and account flows. |
| Profiles, reports, roads, incidents and live app data | Firestore on Spark | Keep the current source of application records; budget database reads/writes and preserve access restrictions. |
| Report photos | Supabase Free Storage | Replace the report uploader and the server's Firebase-only photo validation together. Preserve compression, progress, retry identity and recoverable forms. |
| Trusted report/incident/admin/push operations | Supabase Free Edge Functions, subject to proof | Port server behavior and authentication explicitly; existing Firebase Node functions are not a drop-in Edge deployment. |
| Weather, risk, expiry and migration maintenance | Supabase scheduled functions, subject to proof | Process bounded work within both providers' free quotas and runtime limits. Preserve honest stale/unknown-road warnings. |
| Maps, route display, themes, localization and accessibility | Existing Flutter/Mapbox code | Retain behavior and include it in regression/device checks. Mapbox has its own account/usage requirements. |

The existing Supabase URL matches the user's **SafePaths Capstone** screenshot. The screenshot shows Free and Healthy; this is not proof of the bucket policies, Firebase-auth integration, function permissions or successful phone uploads. Existing feedback/avatar Supabase use does not establish that the new report backend is ready.

## 1. Preserve and identify the baseline

- Make a recoverable local checkpoint of the entire current source/configuration change set, including untracked work. Existing work is extensive and uncommitted; the repository HEAD alone is not a backup of these changes. Keep credentials out of shared archives and source commits.
- Record the installed older APK's version/build and observed behavior on the team's phone, retaining its installer if available. The historical repository snapshot writes reports directly to Firestore, but it has not been proven to be the exact source of the installed APK.
- Use synthetic test accounts/data to record login, report/photo, history, admin road update, route, feedback and notification behavior. A saved report without an attached photo is not a successful photo test.
- Preserve the current automated baseline: 200 Flutter tests, one opt-in benchmark skipped, 19 Node tests and 27 Firebase emulator tests passed. This is evidence for the current implementation, not the proposed Supabase backend.

**Exit evidence:** recoverable source checkpoint and recorded baseline; no data or code replaced on the installed app.

## 2. Prove one complete reporting flow in isolation

Prepare the replacement locally first, using synthetic data and a separate test configuration. Hosted verification must use an agreed test environment and keep the existing live app and its backend rules intact.

1. Reuse Firebase sign-in and pass its verified identity to the replacement server. Verify the expected project/token claims, current account state/session revocation and the server-side admin role; provider integration alone is not a replacement for these checks.
2. Upload a bounded image to an account-owned Supabase test location. The implemented proof compresses to JPEG and limits uploads to 2 MiB. Check actual file metadata/ownership at the server and use a tested display/delivery path. Do not introduce new public report-photo access while the adviser decision is pending.
3. Port report submission with atomic cooldowns, identity derivation, location checks, durable request receipts and safe replay. Keep Firestore as the record source for this proof; changing the database model is not part of the first step.
4. Use the explicit separate target `lib/main_spark_proof.dart` with the fieldtest flavor and public proof build defines. It has its own report/photo client; the normal fieldtest/main entry point and its upload/push defaults remain unchanged. Verify that test data cannot target the main project accidentally.
5. Verify that a resident saves a report/photo, their history shows the correct state, and an authorized admin on another phone sees it. Test unsigned/unverified access, another account's photo, cooldown collisions, response loss, retries and connection failures.

Privileged Firebase/Supabase credentials belong in the server's managed secret store, never in the APK. Authentication, Firestore transactions, media ownership and Edge runtime compatibility must be demonstrated before broad porting. Do not weaken direct client write rules to make a failing proof appear successful.

**Exit evidence:** successful two-phone report/photo flow, access-denial and concurrency/replay evidence, and recorded failure recovery. If it does not pass, keep the remaining workflows on the current branch and reassess this design; do not declare the whole migration validated.

## 3. Move the remaining server-dependent features in small batches

After the reporting proof passes:

1. Resident incident observations and admin incident reviews: preserve independent-account checks, current incident/revision validation, official closure behavior, durable receipts, audit history and concurrent-review rejection.
2. Notification sending: retain admin authorization and account-owned token access; test actual foreground/background/terminated receipt and tap behavior. FCM remains the delivery service; Supabase replaces the trusted sender.
3. Weather/risk/report-expiry/legacy migration: preserve bounded leases, conflict detection, unknown-road caution, idempotency and failure heartbeats. Review the actual study area and existing drill override behavior.
4. Review feedback screenshots and avatar storage paths so they work with the same authentication/access policy. Do not assume the legacy embedded-avatar fallback proves storage is healthy.

Record checks after each batch. Keep the existing Dart/Node risk fixtures as a cross-runtime reference when adapting server code. Replacing a Firebase dependency does not close photo-content moderation (4.2) or pending privacy decisions (5.6).

## 4. Budget the free quotas and test the complete app

The current risk scheduler reads and rewrites road records every minute. At 1,440 runs/day, 100 road writes per run alone would be **144,000 writes/day**, before reports or other activity. This is a calculation from the current schedule, not the measured size of the live road collection. Firestore's no-cost allowance includes 20,000 writes/day and 50,000 reads/day. Merely moving that unchanged scheduler to Supabase would not make it suitable for Spark.

- Measure actual road/report counts and expected usage, then set a database-operation budget with headroom for testers. Reduce unnecessary writes, bound scans and process changed/due work. Preserve response freshness and truthful health warnings when adjusting job timing.
- Check Supabase free quotas, runtime limits, storage/egress and Firebase third-party authentication setup using the actual project. Free does not mean unlimited capacity or guaranteed availability.
- Record the operational effect of Supabase pausing for low activity. Confirm the project and scheduled jobs are available before evaluation; do not use synthetic keep-alive traffic as a substitute for an availability plan.
- Rerun the meaningful Flutter/backend/access tests against the replacement, then perform Android acceptance: report/photo/retry/history/admin review, routes, outage recovery, account switching, feedback and real push.
- Retain the existing failed 20-user same-road stress result. Re-test the replacement at the capstone's intended small workload and record both first-attempt failures and recovery; claim only the workload actually measured.

**Exit evidence:** complete expected/actual test record, measured operation counts within quotas, documented provider limits and remaining known issues. The proof, test plan and future tests do not themselves certify privacy compliance or production capacity.

## 5. Prepare the review APK and coordinated rollout

Build a clearly identified APK for controlled review once its required test backend is ready. Record source snapshot/build identity, environment, schema/rule versions and test evidence. Inspect the APK for intended configuration and absence of private keys. The earlier test APK and its results do not establish acceptance of these new changes.

Keep existing live service changes and distribution on hold until the concrete replacement has passed its gates and its rollout is agreed. Coordinate endpoints, storage delivery, indexes/rules and the app so older installs are not silently broken. Privacy retention/contact/audience decisions, 4.2 moderation and physical/staging acceptance remain open in their own records.

## Sources used to assess feasibility

- [Supabase Firebase Authentication integration](https://supabase.com/docs/guides/auth/third-party/firebase-auth): existing Firebase identities can be used, with required configuration/claims.
- [Supabase Free quotas](https://supabase.com/docs/guides/platform/billing-on-supabase) and [Edge runtime limits](https://supabase.com/docs/guides/functions/limits): verify suitability and workload rather than assuming unlimited free processing.
- [Supabase scheduling](https://supabase.com/docs/guides/functions/schedule-functions): hosted cron can invoke Edge Functions using protected credentials.
- [Supabase project pausing](https://supabase.com/docs/guides/platform/free-project-pausing): low-activity Free projects can pause.
- [Firestore quotas](https://firebase.google.com/docs/firestore/quotas): the Spark database budget still matters when requests originate from another provider.


## Core migration update - 2026-10-25

Resident incident observations and weather/risk/expiry now have an implemented and hosted-verified **test-only** Spark migration. The signed maintenance schedule is active every four minutes, with an actual successful automatic run recorded. See [scope, evidence and remaining gates](spark-core-migration.md). This supersedes earlier statements that those test backend paths are unimplemented. Native acceptance, other media/notification paths and the main rollout remain open. No new APK was built or installed.


## Communication migration update - 2026-10-25

Feedback and broadcasts now have an implemented, hosted-verified **test-only** migration. Private owner history, explicit reply/closure, consent, idempotent scoped publications, expiry/withdrawal and typed fair notification processing are covered. Existing report push and report/photo hosted regressions also pass. See [current scope and evidence](communication-migration.md); older counts and deployment versions above are dated phase baselines. Profile/feedback media also has separate [test-only acceptance](private-media-migration.md). APK builds, native phone acceptance, performance/adviser decisions and main-project rollout remain open.
