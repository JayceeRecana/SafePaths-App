# Full-app integration audit and push investigation

**November 1 main-integration follow-up:** the local Marulas service mapping,
read-only main inventory/backup, fenced metadata plan and separate main transport
are documented in [Marulas main integration](marulas-main-integration.md).
The historical main-path findings below describe the pre-integration state.
Main hosted deployment, activation and physical acceptance remain separate;
the nearby proof is preserved.

**Maintenance follow-up:** the two road-maintenance findings now have
[implemented and verified test-only fixes](road-maintenance.md). Protected
create-only imports preserve newer reviews; versioned deletion prunes neighbor
links and invalidates the worker cache atomically. Earlier audit totals below
remain dated evidence. Main integration, phone/stress acceptance and policy
decisions remain open.

Reviewed on 2026-10-25 after the private-media phase. Scope: source/configuration
audit, one small test-app routing fix, test-tool diagnostics and bounded hosted
push verification. No APK build/install/distribution, device inventory, main
Firebase change, billing change, Edge deployment or scheduler change was made.
This is not a new stress/capacity result.

## Current integration map

| Workflow | Complete opted-in fieldtest path | Main/current-default path and remaining gate |
| --- | --- | --- |
| Sign-in, verification, reset and profiles | Firebase Auth and Firestore; native test config is separately pinned | Firebase Auth/Firestore retained; real email/permission/account lifecycle acceptance remains open |
| New report and photo | `ReportSubmissionRepository` and `ReportPhotoUploader` use the proof endpoint when the reports flag is set | Defaults use the older Firebase callable and Firebase Storage; main migration not complete |
| Report edits, admin review/replies and incident review | `ResidentReportUpdate`, `AdminReportService`, current review dialogs and resource contexts use the proof endpoint | These current UI paths invoke the test-pinned service directly; its deliberate main-project rejection blocks a ready main build until a separate main integration is implemented |
| Resident condition confirmations | `RoadIncidentService` maps to `observe-incident` with the core flag | Older `observeRoadIncident` callable remains the default branch; old review helper is not used by the current review UI |
| Weather, risk and expiry | Core-enabled reader/override routes and existing signed four-minute worker; fixed test study area | Older production scheduled-function architecture remains; main data/bootstrap/area and budget review required |
| Broadcasts and feedback | Communication flag chooses server-owned commands/history; media flag enables private screenshots | Legacy direct writes and callable notification sender remain outside those flags |
| Avatar/profile edits | Media flag chooses private upload, authenticated bytes and protected profile command | Production compatibility has a Firebase-only avatar branch and direct profile metadata edits |
| Push registration, processing and taps | Push flag chooses test registration; typed report/feedback/broadcast queue uses current identity/area | Main uses older token/profile/topic and callable-sender paths; phone delivery/taps not verified |
| Road imports/graph maintenance | Protected create-only imports, graph repair and versioned deletion now maintain neighbor links and worker topology atomically | Legacy production branch remains part of main integration; test implementation acceptance is recorded in the maintenance follow-up |
| Maps, navigation, cached road feeds, templates and alert dismissals | Existing Mapbox/Firestore UI and local preferences retained; these are not all server migrations | Phone GPS/detour/offline/cache/accessibility and performance acceptance still required |

Audit anchors: `lib/main.dart`, `lib/config/app_environment.dart`,
`lib/services/backend_service.dart`, `spark_backend_service.dart`, report/core/
communication/media/notification services, admin/resident screens and the Edge
handler/entry point. A source scan found no remaining direct client Supabase
object upload after the media phase; production still initializes the Supabase
SDK, although these media paths no longer use it. That initialization is a
bounded startup dependency/cleanup candidate, not evidence that the production
workflow is migrated or that the installed older app is broken.

## Findings and actions

| ID | Finding | Action/status |
| --- | --- | --- |
| I-01 | The main build is incomplete: some flows retain Firebase server/storage dependencies, while new admin/report-edit flows deliberately reject the main project | **OPEN, main release blocker.** Keep the isolation guard. Prepare separate main integration/configuration and data/legacy compatibility; do not repoint main users to this proof |
| I-02 | Independent flags and old build instructions can create a partially migrated test build while the test rules already protect direct writes | Prepared a local candidate defines file with all five feature flags and the exact test project/endpoint. Actual 44-test feature suite is run using that file. This does not authorize or create an APK |
| I-03 | Test-app map-tap/name search could auto-import a name-derived road ID with no study-area/worker markers, beside stable OSM-way records | **Fixed in source for fieldtest:** route the shortcut to the dedicated preview/select Import Roads screen. Existing monitored-road taps still open review/details; main compatibility path retained. Native navigation acceptance remains open |
| I-04 | Direct road deletion could leave the worker's cached graph stale until the hourly scan | **Implemented and verified in the test migration.** Protected deletion checks current conditions, atomically prunes links and advances topology revision; the next worker performs a full scan. Empty networks, stale reviews, reimport/replay, history and concurrent input fencing are tested. See [maintenance evidence](road-maintenance.md); main/native rollout remains separate |
| I-05 | The old preparation command selects the baseline 13-index config; the migrated road report-history query needs the additional `reports(roadId ASC, createdAt DESC)` index | **Fixed in the preparation script:** explicit `-DeployRules` now pins `safepaths-test` and selects `firebase.spark-proof.json` (14 indexes). The option was not executed in this phase |
| I-06 | A newly registered account is not part of the proof's three synthetic allowed UIDs | **Intentional isolation/rollout gate.** Authentication success does not authorize proof commands. Use the existing synthetic cohort; main or broader review membership requires explicit provisioning/review |
| I-07 | Historical push failure records only a coarse stage and category; it lacks the HTTP status/request ID/transport cause and cleanup could obscure the primary failing stage | Added bounded, allowlisted response/network diagnostics; distinguish admin session, wrong key, missing credential and invalid ticket. Cleanup preserves the original check error and records cleanup failures separately. New result files start as failed/pending, and pass only after confirmed synthetic-device cleanup. Historical cause remains unconfirmed |

The importer concurrency finding now has a create-only server transaction in the
migrated test path. Current server reads, create preconditions and retry receipts
preserve existing decisions; graph links are saved atomically with imports.
Emulators exercise simultaneous imports and a concurrent official review, while
hosted checks confirm a stale selection preserves a newer closure. The older
production compatibility branch remains part of the separate main migration.

Direct admin road/template/dismissal operations are not automatically errors:
Firestore rules intentionally permit some of them. The audit distinguishes those
from privileged report/trust/notification commands and their required atomic
side effects. Report raw-data audience, legacy media and privacy/retention are
still adviser/main-rollout decisions; this phase does not widen access.

## Push investigation

The earlier media phase's first push run reported `worker-secret-required` and
`http-or-assertion`. A passing rerun did not establish why that first run failed.
The retained data cannot prove whether it was a handler authorization response,
gateway/network failure or a later cleanup error. Do not label it a fixed
authorization bug, weaken worker verification or introduce automatic retries
that hide the first failure.

This phase ran a fixed 12-request probe: three rounds of ordinary admin session,
wrong worker key, no credential and a bad HMAC ticket. Every request returned the
handler's expected HTTP 401/`unauthenticated` with `no-store`; no retries were
used. The probe sent no valid worker secret/ticket and targeted no phone.
Local handler tests also prove ordinary admin sessions and invalid credentials
are rejected before account verification, database access or queue draining.

The complete existing nine-check hosted push regression passed once with the
new diagnostics, including actual FCM validation-only acceptance, synthetic
device transfer/stale-update denial, unregister, no-device saved-message recovery
and private status/replay. Its synthetic installation was confirmed inactive.
These are current positive observations; **the historical intermittent failure
remains an unresolved observation**. No physical delivery or networking/capacity
guarantee is inferred.

Diagnostics retain only route/case, time/duration, HTTP status, a restricted error
code, valid-format provider request ID and known network cause. They do not log
tokens, account IDs, bodies, private replies, signed URLs or arbitrary provider
messages. They distinguish a JSON handler rejection from non-JSON gateway errors
and response-read/network/timeout failures. Capture is size-bounded; mutation
checks retain their existing request/receipt behavior and do not gain retries.

## Verification

247 Flutter tests passed (one optional benchmark skipped), and all 44 selected
tests passed using the generated complete candidate defines file. All 57 Node
tests passed, including new diagnostic redaction/bounds/network classification,
worker-auth ordering and main-project/credential/configuration rejection checks.
Full analysis reports zero errors, four existing warnings and 305 total findings
including informational/style items. Native map/import navigation is not proven
by these host tests and remains part of phone acceptance.

The 12-request hosted authorization probe and nine-check push regression passed;
the regression confirms synthetic-device cleanup before marking itself passed.
No automatic retry was added. The previous 88-test emulator result remains the
media-phase baseline; it was not rerun here because no deployed server/rule logic
changed. No new Edge deployment or schedule activation was required.

Source checkpoint: 250 relevant files copied and hash-verified before edits.
Current source/configuration hashes and unchanged installer hashes are recorded
in the ignored `.usability-work-baseline/integration-verification.json`.
Sanitized request observations are retained under `spark-proof-setup`; the
original failed media-phase push log is preserved. Private fixtures/backups
remain outside shareable documents and APK inputs.

## Next implementation and acceptance gates

1. I-04 and the import concurrency case have test implementation acceptance in
   [the maintenance follow-up](road-maintenance.md). Preserve their active-condition,
   history, revision and concurrency guarantees during main integration.
2. Run the small capstone workload against the complete test paths, with database
   operation/latency/error/retry evidence. The existing cohort is two residents
   and one admin; that alone cannot establish five, ten or twenty independent
   simultaneous users. Any larger cohort must be deliberately provisioned.
3. Prepare the coordinated main integration for I-01 and review the actual area,
   legacy records, private credentials, rules/indexes, controls and rollback.
   Preserve the main project and installed apps until that separate rollout.
4. After build approval, create an identified review APK and use the available
   phone for permissions, offline/restart/account changes, real photos/maps and
   push/taps. A later second phone is needed for simultaneous end-to-end checks.

Adviser retention/audience/contact decisions and deferred section 4.2 stay open.
Current source audit and test checks do not close B-05 or authorize distribution.
