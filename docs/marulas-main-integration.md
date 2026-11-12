# Marulas integration — prepared November 1, 2026

The main application reuses the improved UI and workflows. It retains Firebase
project `safepaths-92c3d`; `safepaths-test` remains a separate nearby test database.
No third database is required. Synthetic users, reports, photos and closures are
not transferred. Existing main record IDs and report history are retained.

## Service mapping

| Workflow | Main integration |
| --- | --- |
| Sign-in, account verification, profiles | Existing main Firebase Auth/profiles; server checks the current verified account and profile role |
| New report, edit, review, correction, private replies | Shared current workflow, separate `safepaths-main` endpoint |
| Report-linked or direct barangay road updates | Same evidence/source and concurrency guarantees; no automatic report verification or duplicate rewards |
| Reports/photos, profile and feedback images | New private `report-photos-marulas` bucket, with purpose/owner paths and protected reads; no direct client Storage grant |
| Resident observations | Same incident workflow; observations cannot reopen roads |
| Broadcasts and feedback replies | Main profiles, rather than the proof UID list; push audience capped at 200 eligible residents per publication, with an explicit failure before partial publication |
| Push registration, outbox and retries | Main Firebase sender, main worker key and separate paused schedules; provider acceptance is not proof of phone receipt |
| Weather, prediction/risk and incident maintenance | Marulas coordinates and area tag, same bounded workers; unknown weather is not manufactured as clear |
| Roads/import/graph/deletion | Same protected maintenance; existing name-based road IDs retained and exact duplicate geometry excluded from new OSM imports |
| Planner, destination catalog and rerouting | Shared current logic; Marulas geography/catalog selected by production flavor; unresolved destination pins remain unavailable |
| Follow-up evidence reports | Code is integrated, but the existing feature remains disabled pending coordinated follow-up acceptance. Private clarification replies remain available |

## Inventory and backup

Read-only inventory completed November 1: 175 Firestore documents, including
152 roads, six historical reports, and five profiles (one admin, four residents).
No nearby/synthetic candidates or active legacy reports were found by the
bounded automated inventory. This is not a claim that every record has been
manually approved. The 152 roads have usable geometry within the configured
Marulas envelope and need `studyArea: marulas` metadata. Their IDs, official
status, notes, verification and original update times must not be replaced.

Private export, source checkpoint, plan, public candidate configuration and
verification logs are grouped under
`.usability-work-baseline/marulas-integration-20261101/`. The Firestore export
includes nested collections and update times. It is a bounded read-only export,
not an atomic provider snapshot, and contains private data; do not distribute it.
Auth passwords/tokens and Storage objects were not exported. Accounts stay in
the same Firebase project. Back up deployed rules/indexes and check legacy photo
references before the actual cutover; local source is not a cloud-rules backup.

`inventory-main.cjs` makes no cloud writes. `prepare-main-integration.cjs` builds
an offline plan from that export. `apply-main-integration.cjs` is read-only unless
`--apply` is explicitly supplied; its atomic transaction fences road update
times and rejects unreviewed active legacy reports. It only adds area/input
metadata and prepares controls. It leaves `system/backend_rollout.enabled=false`.
No tool deletes main data, resets road conditions, creates synthetic main
accounts, or enables automatic retention.

## Release configuration and safeguards

The new main transport is an explicit complete bundle, using
`SAFEPATHS_BACKEND_ENABLED`, `SAFEPATHS_FIREBASE_PROJECT_ID` and
`SAFEPATHS_BACKEND_URL`. Main and proof targets reject each other's project,
flavor, credentials and protected photo references. A production startup without
the reviewed main configuration stops rather than silently mixing old/new
backend paths. Existing installed APKs are not modified by source changes.

The main Edge entry point requires separate `MARULAS_*` server secrets and
the exact main project. It shares business logic with the proof, whose defaults
and synthetic account restriction remain intact. Requests also require the
server-owned main rollout marker before they can mutate data. Client admins
cannot change that marker. Main Firebase/FCM adapters prohibit emulator hosts;
main workflow tests inject demo adapters only within the test harness.

`firebase.main.json` selects the current rules and complete 14-index configuration.
`main-private-bucket.sql`, `main-push-schedule.sql` and `main-core-schedule.sql`
use separate names. Schedules are created inactive and must use a distinct Vault
worker key. The old nearby schedules, bucket, secrets and endpoint are preserved.

## Coordinated cutover, still required

1. Refresh the private export and compare deployed rules/indexes. Confirm main
   admin sign-in/verification and legacy image accessibility. Keep a restore copy.
2. Prepare the distinct main secrets and private bucket; check hosted anonymous,
   resident-peer and authorized owner/admin access. Deploy the separate main
   function with its rollout marker closed. Never redeploy the proof to main.
3. Coordinate main rules/indexes, metadata/control migration and an identified
   main APK built with the reviewed main define file. Rules/control activation
   can block older APK write paths; do not apply this piecemeal.
4. Verify the whole resident → admin → road → resident flow, private replies,
   profile/feedback media, broadcasts, notification taps and offline/retry behavior.
   Confirm actual Marulas map/route data and beneficiary-approved destination pins.
5. Activate the main marker and its schedules only as part of the controlled
   acceptance window. Monitor failures and budget use. Keep the nearby setup for
   regression testing. If a problem occurs, close the main marker and pause the
   main schedules; retain reports/audits/rewards. Do not blindly restore an old
   snapshot over newer resident submissions.

The local integration and demo tests do not establish hosted main readiness or
real-device delivery/rerouting. Stress testing, destination approvals, privacy
contact/audience/retention decisions, and follow-up feature acceptance retain
their existing unresolved status. This preparation does not change billing.

## Local verification

- Full default Flutter suite: 590 passed; one optional benchmark skipped.
- Selected tests with the reviewed Marulas configuration: 71 passed.
- Environment/service checks with explicit `--flavor fieldtest` and the current
  nearby configuration: 44 passed. The first attempt omitted the flavor and was
  correctly rejected against Flutter's default production flavor; no runtime
  guard was relaxed to make that mismatched command work.
- Backend unit checks: 119 passed.
- Demo Firestore/Auth/Storage workflow and security checks: 110 passed, including
  seven main-integration cases. The underlying test script exited successfully;
  PowerShell's native stderr wrapper reported a nonzero wrapper status alongside
  Java/runtime notices. Retained logs distinguish that wrapper status from the
  passing test result.
- Both main and proof Edge entry points pass `deno check`.
- Eight main workflows also pass with the full private-media configuration,
  including a valid JPEG submission and profile-image owner/admin/peer checks.
- Targeted Dart analysis reports zero errors and zero warnings; existing style
  information remains. No native main APK was built or installed in this phase.
- Read-only main transaction preflight: all 152 road versions matched the export;
  zero metadata writes and zero condition changes. It did not activate main.

The main weather test caught a nested worker provider that still used the test
profile. The provider now receives the selected profile; the passing transaction
test checks both Marulas coordinates and the stored weather area. Weather drills
also retain a separate profile binding from the admin's user-profile record.
Legacy segment identity, main-versus-test photos/tokens, partial migration denial,
stale metadata plans, report verification and one-time trust awards are covered.

## Subsequent manual test-activity cleanup — November 1

The user explicitly confirmed that all reports, report messages, alerts and
feedback in **both** projects were test records and requested resident reward
and report-count resets. Fresh private backups were completed before deletion.
This is a manual cleanup, not an automatic retention policy or a main rollout.

Main cleanup atomically removed 12 activity/derived records, including six
reports and one alert. Nearby cleanup atomically removed 110 activity/derived
records, including four reports, four feedback entries, one alert, private
messages, incident responses and the related request/reward/outbox records.
Independent road-check audits and idempotency records were retained, alongside
worker replay guards, road-maintenance history, accounts, templates, media
metadata and configuration. Resident scores/counters and the known test-route
metrics were reset. Two report-derived community road states and the nearby
risk cache were cleared; official road fields were preserved.

Read-back verification found the activity lists empty, all four resident
profiles in each project at 50 trust with zero report counts, all 152 main roads
and 736 nearby roads intact, and all five main/seven nearby accounts intact.
Official conditions, geometry, verification times, roles, profile photos,
notification tokens, templates and backend controls matched their backups.
No Firebase Auth account, Storage object or installed APK was deleted/changed.
No follow-up switch or main rollout was activated.

Evidence is grouped under `.usability-work-baseline/activity-cleanup-20261101/`,
including private backups, preflights, applied transaction results and read-back
verification. Three cleanup unit checks and three demo transaction checks passed,
including stale-record rejection and preservation of protected data. As with
the earlier emulator run, the underlying script passed despite PowerShell native
stderr-wrapper notices. The earlier 175-document/six-report main inventory is
historical; refresh the main inventory/plan before the eventual cutover.


## Controlled candidate activated ? November 2, 2026

This supersedes the earlier "prepared only" status. After the user's explicit approval, the separate main endpoint, private bucket, eighteen indexes, current rules, road-area metadata, server secrets and dedicated schedules were configured. `safepaths-main` is ACTIVE at version 1 and its rollout marker is enabled for controlled candidate testing. Both client and server follow-up switches are enabled. No nearby test data was copied; all 152 recorded road conditions and five profile roles were preserved and checked.

The universal candidate is `.usability-work-baseline/review-candidate/SafePaths-Marulas-20261102.apk`. Fresh backups, source configuration, SHA256, tests and handoff are grouped under `.usability-work-baseline/marulas-rollout-20261102/`. Private credentials/backups must not be distributed. Server credentials are not bundled in the APK.

New follow-ups also queue a server-owned admin review notice for their own linked report ID; retries do not create duplicate notices. Original evidence/rewards remain separate. The candidate configuration test now checks the selected follow-up flag instead of assuming it is always off; the legacy edit UI test explicitly checks that dated follow-ups replace in-place edits when enabled.

Validation: 131 backend unit checks, 87 demo main/Spark integration checks, 142 Flutter checks using the actual Marulas candidate flags, Deno type checking and release APK build passed. Hosted main workers and database-signed scheduler probes returned HTTP200; no reports or real pushes were created by those hosted checks. Anonymous access to a known private synthetic Storage fixture was denied, and the fixture was removed.

Device acceptance remains open. All five existing Firebase accounts were unverified at preflight; users must complete email verification through the app before protected operations work. Existing passwords, roles and verification flags were not changed. Install the matching APK before testing; older main write paths may be blocked. Actual photo/report/reply/follow-up/notification, native routing, destination approval and the existing privacy/retention/stress-test decisions are not declared complete by this setup.
