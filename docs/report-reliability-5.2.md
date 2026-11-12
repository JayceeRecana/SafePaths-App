# Report accuracy and reliability (section 5.2)

Implemented locally. Nothing in this change deploys Functions, rules or indexes, distributes an APK, enables billing, or changes live records. The team asked to finish fixes before the next review build. PAGASA integration and section 4.2 photo moderation remain follow-up work.

## Resident experience

- Reports distinguish server submission time from a reporter-supplied observation time. Residents can choose an observation within the last 24 hours. A failed submission retains the observation time on retry.
- Report details, personal history, and the admin inspector show relative ages and an explicit outdated warning. Missing/invalid legacy submission timestamps are treated as old, rather than replaced with the current time.
- Road details show a shared community incident, latest observation, last independent resident flood confirmation, admin review time/note, and response totals. Totals describe the current choice of each responding account during this incident; they are not a count of fresh observations or a safety verdict.
- Verified residents may select Still flooded, Appears passable, or Cannot confirm. One server-controlled current response per account per road incident replaces the previous choice; changes have a one-minute cooldown. Residents who filed a report in the incident cannot independently confirm it. Cannot confirm does not refresh observation/confirmation timestamps.
- Observation controls require an online server snapshot. Loading, unavailable/cached data, saving, saved, and retryable failures are visible. A timeout does not claim success. A durable request receipt prevents a retry from adding another response/audit event.
- Resident responses preserve their original claimed observation time across retries. Unsaved responses older than five minutes are rejected and require a new observation; a previously saved receipt can still be replayed safely. Receipt time and observation time are distinct, and neither independently proves what someone witnessed.
- Coordinate checks record GPS versus manual pin, client-reported GPS accuracy/time, road distance, and emergency bypass. They do not prove physical presence or authenticate a photograph/observation. Emergency distance bypass remains explicit. Device clocks, GPS spoofing, multiple accounts, and false statements are not solved by email verification or proximity checks.

## Conservative handling of stale/conflicting information

- Freshness uses observation time (legacy fallback: last resident edit, then submission time). The existing 24-hour limit is retained as a provisional setting, not a field-validated flood duration.
- A report being opened for admin review remains part of active risk calculation. Opening it does not refresh its observation age.
- Pending and under-review reports expire on the server even if weather fetching is unavailable. Unknown conditions persist on the road until an administrator verifies them.
- Roads with unresolved incidents cannot become green/passable merely because reports expire or their scores decay. A caution floor of 30 (Watch) is applied in the Dart/server risk engines. Routing and map rendering use the shared road effective-status guard, including during clear weather. Known official closures remain closed.
- Planner/preview badges show Unconfirmed instead of a numerical safety score when a route crosses unverified roads, including routes with mixed hazards. Navigation requires caution acknowledgement for these routes; the preview no longer describes unverified conditions as shallow water safe for the vehicle.
- Appears passable requests admin review; it never reopens a road or reduces the official closure on its own. Still flooded records fresh evidence; contradictory reopening requests remain flagged until review.

## Admin workflow

- Road details and the report inspector provide Review current conditions. Expired incident reports remain discoverable in the actionable queue while unresolved.
- An admin selects a verified road status, writes a 10–1000-character verification-source/findings note, and explicitly acknowledges verifying current conditions through field verification or a trusted official update.
- The server independently checks administrator authority and the incident generation/revision. New information arriving while a review is open rejects the stale review and requires reassessment.
- The verified road status, incident review, affected report resolution, durable receipt, and immutable server audit are committed together. An admin-confirmed reopening closes this incident; a subsequent report starts a new generation with fresh response totals. An admin-confirmed flood preserves the official hazard.
- This incident review marks affected pending/under-review/expired reports **resolved**. It does not declare every historical statement verified, award trust points, or penalize someone because water subsequently receded. Existing individual report-verification/reputation workflows remain separate.

## Abuse controls

- Normal reporting retains the atomic five-minute cooldown and durable request receipts.
- A strictly worsening severity on the same active report can be updated after one minute, at most once per five minutes. This does not bypass limits for a different road, repeated severity, or a new incident.
- Firestore rules reject direct incident/response/counter/audit writes, even by the admin app. Response documents are readable only by their owner or an admin; summaries require verified sign-in. Audit reads are admin-only. Privileged changes use authenticated callables.

## Rollout and acceptance

1. Finish local fixes; do not distribute the previously built APK as if it contains this change.
2. Deploy/review the new report incident/user index and incident state/observation-time index in staging before Functions. Follow the coordinated app/backend/rules rollout in `reliability-rollout.md`.
3. The risk scheduler migrates legacy pending/under-review/expired report records in pages of 100. Wait for `system/incident_migration.complete == true` and a successful risk heartbeat before opening the updated app to residents. Review migrated unknown roads with barangay staff. The cursor avoids rescanning the entire historical report collection every minute; up to 200 overdue incident summaries are processed per scheduler run. Confirm the backlog drains under staging load.
4. Test two resident accounts and an admin on Android: create/confirm/dispute, self-confirm rejection, replace response, cooldown/escalation, interrupted-response retry, cached-data controls, stale reports during weather failure, admin review with a concurrent new observation, reopening, and a new incident after reopening.
5. Test small screens/large fonts and clock changes. Calibrate freshness periods with barangay responders and field results; do not present provisional thresholds as validated accuracy.
6. No physical-device acceptance, live Functions/Storage test, load capacity, PAGASA advisory integration, or photo moderation is claimed by the local automated results.

## Verification

Automated checks cover freshness/unknown routing, report risk during review, Dart/server parity, narrow-screen controls, progress/error/cached states, explicit admin verification, server authorization, private responses, concurrency/idempotency, incident generations, stale review rejection, weather outage expiration, paginated legacy migration, delayed observation retries, and bounded escalation.

Final local results (2026-10-23): **171 Flutter tests, 17 backend unit/parity tests, and 25 Firebase Auth/Firestore/Storage emulator integration tests passed**. Targeted analysis of the seven new/updated incident UI, service, model and test files found no issues. Broader analysis of the changed screens/services had no errors or warnings; existing informational style/lifecycle lints remain. Backend syntax checks and the targeted tracked-file whitespace check passed. No additional APK was built, installed or distributed during this work.


## Dated follow-ups implemented locally on 2026-10-26

The original report, description, photo and observation/submission times are preserved. Later observations are new records linked to the same original report and road incident. Existing legacy records are labelled as earlier saved evidence; an overwritten historical version cannot be reconstructed. Photos are optional, carry their own submission time, and must not reuse an earlier attachment reference. This detects identical stored attachments, not copied, cropped or recompressed images. The app cannot certify a gallery photo's capture time or authenticity.

Reporters open condition history from their report history, report update notification, or their own active incident on road details. A follow-up explicitly describes whether flooding increased, decreased, cleared or appears unchanged, with a new observation time and optional new photo. The original report's photo and GPS position are never presented as fresh follow-up evidence. Urgent review is a separate opt-in request and does not confirm rescue dispatch. Closed or replaced incidents retain their history; a new event needs a new report.

An eligible verified original earns up to +10; one meaningful, independently verified follow-up can earn up to +5 per resident per incident. The overall score remains capped at 100. Original rewards retain the 12-hour per-road cooldown. A server-only transactional incident ledger prevents repeated bonuses, concurrent-admin duplication and reward recycling after a correction. Repeated uploads, quick observations, unchanged-condition updates and retries earn no automatic bonus. Admins cannot review their own evidence. The original observation must receive its review first.

Unclear evidence or a wrong attachment can be marked Needs correction with a required explanatory private message and no trust penalty. The resident supplies a new dated update; the earlier record remains. A false/spam follow-up requires an evidence note and explicit admin acknowledgement before deducting up to 5 points. A valid original retains its recorded outcome and reward. If an already-approved follow-up is disproved, the admin separately records the reversal of its awarded bonus and, only for a confirmed false submission, any additional penalty up to 5. Repeated requests cannot apply these adjustments twice. An invalidated current follow-up also returns the incident to current-condition review.

Reviewing current road passability and reviewing each observation are separate decisions. Reopening a road leaves pending follow-ups available for their own evidence/reward review, marked as historical observations. They no longer contribute to live flood-risk consensus. For live pending evidence, the risk engine counts only the most recent observation from each resident on a road; several follow-ups from one resident cannot act as several independent witnesses. The Dart, Firebase and Spark risk implementations share parity fixtures for these cases.

Observation times, follow-up history, private admin-message times and navigation update times now use a 12-hour clock. Both observation-time pickers offer AM/PM, including Filipino (whose standard Material picker otherwise defaults to 24 hours) and devices set to 24-hour time. Server timestamps and freshness calculations retain their original representation and duration rules.

### Staging and coordinated test rollout

The implementation is disabled in the current public test configuration and server default. Enable only in the isolated test area with `SPARK_PROOF_FOLLOWUPS_ENABLED=true` on the backend and in the newly built app, alongside the existing Spark core/report flags. An enabled configuration is staged in `.usability-work-baseline/report-followups-20261026/enabled-test-defines.json`; it is not a production configuration. Main-project behavior must not be switched to this test-only workflow.

1. Review the local verification results and preserve current APKs and source checkpoints.
2. Prepare the updated test resident/admin clients and install both during the coordinated test rollout. Older test builds use an edit path the enabled backend intentionally rejects. No automatic APK build or deployment is part of this local change.
3. Deploy the tested backend code and Firestore rules to the isolated test project only, then enable the server flag. Enable the matching app define and fully restart the Flutter run; hot reload does not update compile-time defines.
4. On the resident phone and admin emulator, submit an original report and photo, append a changed-condition update, review the original, then review the follow-up. Confirm private messages, notification delivery, preserved evidence, +10/+5 eligibility, reopening with a follow-up still awaiting review, and safe correction without duplicating points.
5. Check response-loss retry, authorization changes, a wrong attachment requiring clarification, and a later disproved award. Do not claim phone acceptance until these have been observed.

The 12-hour display changes can be hot-reloaded into the current debug run independently of enabling follow-ups. No APK, cloud deployment, production migration or physical-device acceptance is claimed by the local implementation.

### Local verification for this checkpoint

The final enabled-fieldtest regression run passed **396 Flutter tests, with one optional test skipped**. Backend unit/parity checks passed **94 tests**, and the demo Firebase Auth/Firestore/Storage integration run passed **100 tests**, including the new REST follow-up flow. The Supabase entry point passed Deno type checking. The tracked files changed in this task passed the targeted whitespace check.

Static analysis of `lib` and `test` found no errors. Three unused-declaration/variable warnings remain in untouched admin-panel, consensus-audit and map-dashboard screens, alongside informational style lints. Analysis is not claimed to be entirely warning-free. Archived source snapshots/tooling were excluded from the scoped source-analysis run.

Logs, source hashes and the enabled test-only configuration are grouped under `.usability-work-baseline/report-followups-20261026/`. Phone acceptance, attachment authenticity, push delivery for these new events and the coordinated online rollout remain to be checked; previous communication tests do not establish acceptance of this new workflow.
