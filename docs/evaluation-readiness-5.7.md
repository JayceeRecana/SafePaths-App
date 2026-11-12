# Evaluation evidence and known limitations: section 5.7

**Current navigation follow-up, 2026-10-25:** [R-01 fix and readiness](planner-readiness-review.md)
prevents automatic critical-risk adoption and requires current explicit review.
331 full Flutter tests pass (one optional skip), 172 selected exact-fieldtest
checks pass; analyzer has zero errors and four unchanged warnings. FUMC's mapped
POI/address and Red Cross classification/address were corrected. Eight unresolved
records are withheld from catalog routing, and unapproved staging suggestions are
removed. Beneficiary entrance/designation approval remains open. The user has
authorized a separate test APK for [manual phone acceptance](navigation-phone-acceptance.md);
main rollout remains on hold. Physical tests and the wider gates remain open.

**Earlier quick-destination follow-up, 2026-10-25:** [updated all-category audit](quick-destinations-audit.md)
records 316 full Flutter passes (one benchmark skipped), 175 complete-fieldtest
checks and zero analyzer errors with the same four warnings. Category mixing,
old-route retention and implicit first selection are fixed; named destinations
require pin confirmation/adjustment. All eight stored quick-location pins remain
unchanged and require beneficiary entrance/designation verification. Native
map/pin/provider acceptance and existing wider gates remain open; no APK was built.

**Rerouting scenario follow-up, 2026-10-25:** [acceptance matrix](rerouting-scenario-acceptance.md)
records 297 full Flutter passes (one optional benchmark skipped) and 156 complete
fieldtest checks. Local fixes reconcile resolved advisories,
recheck staging options before adoption, preserve reopening work through GPS loss
and show first-failure feedback. Suggested locations are not certified safe and
no real facilities were added to the test area. Physical GPS/provider/voice,
two-phone, stress/B-05, main integration and policy acceptance remain open.

**Planner/rerouting checkpoint, 2026-10-25:** [findings and acceptance](planner-rerouting-reliability.md)
records 278 Flutter passes (one optional benchmark skipped), 137 checks under
the complete fieldtest configuration, and zero analyzer errors with four existing
warnings. Both flavors require real GPS or an explicit manual start; current
closures, shared start confirmation, GPS recovery and moving-origin reroutes
have local regression coverage. No backend deployment or new APK occurred.
Physical navigation, live map/provider checks, stress/B-05, main integration
and adviser decisions remain open. Earlier counts below are dated checkpoints.

**Road-maintenance checkpoint, 2026-10-25:** [scope and evidence](road-maintenance.md)
records 252 Flutter tests passed (one optional benchmark skipped), 49 complete
candidate tests, 60 backend tests and 98 emulator tests. Thirteen hosted
maintenance checks and seven actual Dart-client checks passed, together with
the existing eight normal-report, 18 communication and nine push regressions.
The isolated rules/function/control are active; current worker/cache topology
matches and existing jobs/indexes remain in place. Main Firebase and existing
APKs are unchanged. These results close the test implementation of the two
maintenance findings; phone/stress acceptance, main integration and policy gates
remain open.

**Integration-audit checkpoint, 2026-10-25:** [scope and findings](full-app-integration-audit.md)
records 247 Flutter tests passed (one benchmark skipped), 44 tests passed using
the complete candidate configuration, 57 Node tests passed, 12 bounded hosted
auth rejections and a passing nine-check push regression. There was no new
server/rule deployment or emulator run. The preceding 88 emulator tests remain
the media-phase baseline. Road maintenance/cache and import concurrency still
need work, and the historical first push failure remains unexplained. APK builds,
main rollout, phone/stress acceptance and adviser decisions stay open.

**Latest normal-report integration, 2026-10-25:** [evidence and scope](normal-report-integration.md) records **225 Flutter / 39 backend / 54 emulator tests passed**, 17 fieldtest-option checks and eight hosted checks through the normal form's Dart services. The chosen nearby test road/location and private photo survive response-loss retry; history/admin feeds include the saved report, and the official closure is retained. Android form/GPS/camera/push acceptance remains pending and no APK was built. Full main-app Spark migration and the earlier open policy/performance cases remain open.

**Latest report-push verification, 2026-10-25:** [push delivery evidence](push-delivery.md) records **216 Flutter / 39 backend / 53 emulator tests passed**, nine hosted synthetic checks, and actual Google FCM validation-only acceptance. Test rules match source and all nine indexes are READY. The retry worker uses expiring one-use signatures; phone delivery and notification taps remain unverified because new APK builds are on hold. Broadcast/weather notifications and the remaining main-app Spark migration are not closed by this work.

**Latest workflow follow-up, 2026-10-25:** [resident/admin workflow evidence](admin-resident-workflow.md) records 211 Flutter tests passed (one benchmark skipped), 31 backend tests and 42 emulator integration tests. Test rules now include private admin messages and server-only moderation; main Firebase remains unchanged. Hosted admin acceptance/build details are recorded there separately. Physical acceptance, complete Spark migration, push sending, capacity, photo moderation and adviser privacy decisions remain open. Earlier counts below are dated evidence, not the latest totals.

The deployed test extension passed 13 hosted synthetic workflow checks; all eight indexes are READY and rules match source. New APK builds are explicitly on hold at the user's request. Existing main installers and the earlier proof APK are hash-verified unchanged.

Prepared 2026-10-24 against `SafePaths-Enhancements-Bugs-and-Recommendations.pdf` and the supplied `POST_IMPLEMENTATION-SURVEY-2.pdf`. **Evaluation readiness remains open.** This working record separates automated evidence, physical-device acceptance and policy decisions. Passing unit tests does not mean every reported bug is closed.

**Hosted backend prerequisite:** the user confirmed the main Firebase project is on Spark. The main app's current Cloud Functions/Firebase Storage architecture requires Blaze. No upgrade or main-project rollout occurred. The separate Supabase reporting proof is deployed, but full-feature device acceptance still requires the remaining main-app migration and verification. See [billing and rollout prerequisites](reliability-rollout.md).

The user has chosen to **remain on Spark for the capstone**. A Spark-compatible backend/storage redesign is required before treating the new main APK as fully functional. The first isolated report/photo proof is deployed and passes automated hosted checks; remaining workflows and physical acceptance are pending. The main application has not been migrated.

Follow [the staged Spark capstone plan](spark-capstone-plan.md) for the proposed replacement. Record proof-flow and replacement-backend results separately from the existing baseline below. In particular, a storage connection or a successful APK build does not prove report authorization, two-phone image delivery or the free-quota workload.

## Evidence baseline and current verification

The [2026-10-24 recheck](recheck-2026-10-24.md) recorded 197 Flutter tests passed, one opt-in benchmark skipped, 19 Node tests passed and 26 isolated Auth/Firestore/Storage integration tests passed. These counts predate the privacy changes below and are retained as a dated baseline.

Current privacy follow-up verification completed locally on 2026-10-24. Commands and raw local outputs are retained under ignored `.usability-work-baseline/privacy-*.txt`; no participant records are included in this document. The isolated demo emulators shut down after the successful run. No APK was built or deployed.

| Check | Expected | Actual |
| --- | --- | --- |
| Flutter regression suite | Existing tests plus follow-up-default and diagnostic-content regression cases pass | **200 passed**, one opt-in benchmark skipped |
| Application/test analysis | No compile errors or newly introduced warnings | No errors; five existing warnings and informational lints remain; analyzer exits nonzero for those findings |
| Node unit/parity/tool guards | Existing server and workload guard checks pass | **19 passed** |
| Isolated Auth/Firestore/Storage integration | Existing checks pass; diagnostics reject private fields, arbitrary codes and forged timestamps | **27 passed**, demo project only |

### Isolated Spark proof follow-up: 2026-10-25

This is additional local and hosted evidence, preserving the dated baseline above. See [proof setup and evidence](spark-proof-setup.md) for exact scope and remaining device cases. The user currently has one Android phone; resident/admin account-switch testing can proceed first, with simultaneous two-phone acceptance still pending.

| Check | Actual |
| --- | --- |
| Flutter regression suite including isolated proof client | **205 passed**, one opt-in benchmark skipped |
| Node tests including portable Edge logic, credential/setup guards and real Storage error compatibility | **31 passed** |
| Combined Firebase emulator suite | **32 passed**; new proof cases use Auth/Firestore REST and a Storage protocol fixture |
| Focused analysis of new Flutter proof files | **No issues found**; full application analysis still has five pre-existing warnings |
| Actual Edge entry point, Deno 2.9.6 | Type check passed |
| Separate release APK compilation | Passed; test application ID `com.safepaths.safepaths_app.test`, native Firebase project `safepaths-test` |
| Hosted Supabase Storage/RLS and Edge endpoint | Deployed for synthetic accounts only; report/photo, replay/cooldown, access denial, disabled/revoked-session and signed-link expiry checks passed |
| Two-phone flow | **Pending**; separate APK not installed or distributed; main app migration remains open |

Logs are retained under ignored `.usability-work-baseline/spark-proof-*.txt`; hosted evidence is in `.usability-work-baseline/spark-proof-setup/`. Live checks found and corrected a three-second provider/runtime clock difference and Storage's HTTP-400-wrapped missing-object response; their regression checks pass. These results do not close B-05, photo moderation, privacy decisions, production capacity or full-app Spark compatibility.

## Test cases and actual evidence by module

References contain the detailed repeatable procedures and earlier results. Device tests in this table have **not** been executed during this review.

| ID / category | Exercise | Expected behavior | Actual evidence / remaining acceptance |
| --- | --- | --- | --- |
| TC-01 / Functionality, B-01 | Choose FROM manually while GPS is loading; restore GPS | Manual pin persists until changed; route uses chosen start | Local regression covered; physical pin/permission/navigation test pending. See [IT review](it-expert-review.md). |
| TC-02 / Functionality, B-02 | Known/unknown search, fast query changes and outage | Local matches, bounded remote wait, obsolete results discarded, honest empty/failure state | Local regression covered; live Mapbox credentials and local coverage pending. |
| TC-03 / Usability, B-03 | Narrow screen, large fonts, long route text | Critical controls remain readable and reachable | Layout fixes local; exact expert screen and physical large-font checks pending. |
| TC-04 / Security, E-01/E-02, 5.1 | Password visibility/validation; verify/reset; stale/revoked session | Separate visibility controls, enforced client rules, verification/session gates | Automated client/server checks in baseline; Firebase console password policy and real email delivery pending. See [5.1](account-security-5.1.md). |
| TC-05 / Reliability, B-04, 5.3 | Large/corrupt photos; cancel; leave screen; upload outage and retry | Bounded decoding, responsive form, recoverable errors, no false success or duplicate report | Automated photo/submission checks covered; real camera/gallery, interruption and live storage acceptance pending. See [5.3](photo-upload-5.3.md). |
| TC-06 / Security, Reliability, 5.2 | Forged writes; response-loss replay; concurrent submissions; cooldown | Server derives identity, rejects tampering and preserves one saved result per request | Emulator/unit evidence in baseline; callable HTTP staging, indexes and legacy incident migration pending. See [5.2](report-reliability-5.2.md). |
| TC-07 / Functionality, Reliability | Road closes/unknown/outdated during preview or navigation | Hazard/caution remains visible; obsolete routes cannot stay selected; recovery uses current state | Controlled routing/risk tests covered; outdoor GPS and real Mapbox detours pending. See [field test](fieldtest-setup.md). |
| TC-08 / Reliability, Efficiency, B-05, 5.4 | Reproduce expert failure; repeated maps/photos; concurrent same-road reports | No crash/ANR or hidden hazards; measured latency/memory; recoverable failure | **OPEN:** local 5/10-user bursts passed, retained 20-user initial report burst failed (1/20 saved initially; retries saved all). No established production capacity. Phone profiling and original B-05 reproduction pending. See [5.4](performance-5.4.md). |
| TC-09 / Reliability, 5.4 | 85 equal-time historical reports plus 35 active hazards | Stable nonduplicating pages; history bounds do not remove active hazards | Emulator pagination check covered; physical history memory/network test pending. |
| TC-10 / Reliability, Usability, 5.5 | Cold offline restart, stale feed, retry and reconnect | Cached state is dated and read-only where required; no empty-data false claim; session gates remain | Automated helper/widget checks covered; real offline restart and native cache retention pending. See [5.5](usability-accessibility-5.5.md). |
| TC-11 / Usability, Portability | English/Filipino, TalkBack, large text, light/dark native map | Understandable controls, readable contrast and intact road/route overlays | Local localization/theme/accessibility checks covered; Filipino review, TalkBack and native phone checks pending. |
| TC-12 / Compatibility, Reliability | Verify same account, receive push, tap foreground/background/terminated, switch account | Token registers after verification; tap opens correct account's content | Registration timing regression covered; real FCM delivery, permission and lifecycle acceptance pending. |
| TC-13 / Security, 5.6 | Read another resident's report/photo/feedback and inspect public URLs | Access matches approved notice and adviser-authorized recipients | **OPEN:** policy awaits adviser guidance; current raw report and public media access do not meet the proposed private-detail policy. See [5.6](privacy-consent-5.6.md). |
| TC-14 / Security, 5.6 | Submit diagnostic with private message/UID, arbitrary code or forged time; inspect log | Only safe event type/category and server timestamp persist | New regression cases added; current results in verification table above. This is not a full provider-log audit. |
| TC-15 / Security, 5.6 | New feedback and legacy missing follow-up choice | Contact follow-up starts off; only explicit opt-in enables it | New regression case added; no existing explicit choice rewritten. Feedback remains account-linked. |
| TC-16 / Security, 5.6 | Privacy links, location explanation, correction/withdrawal and retention exercise | Actual processing matches readable notice and approved request/retention procedures | **OPEN:** project email, controller, retention and report audience unresolved; notice/purpose screens and request procedure incomplete. |
| TC-17 / Maintainability | Modify a risk fixture, run Dart/Node parity and regression suites | Both runtimes agree; test failure identifies behavior change | Shared fixture/parity tests exist and passed baseline. Record final build/version and rerun after remaining fixes. |
| TC-18 / Portability, Compatibility | Install agreed build on team's Android phones; GPS/camera/maps/notifications | Correct environment/project, working permissions and hardware/service integration | Isolated report/photo proof APK compiles; it does not exercise maps/push or establish full-app acceptance. Installation/distribution and physical checks remain pending. |

## Before respondent evaluation

- Finish agreed fixes, record the exact source revision/build, app flavor, backend/rules/index versions, devices, Android versions, network conditions and test date. Existing work is uncommitted; the current working tree is not an immutable release identifier.
- Execute the physical/staging cases above and write observed results, failures, evidence links and retest dates. Do not replace a failed attempt with only its successful retry.
- Resolve each PDF issue or document it as a specific known limitation. B-05, section 4.2 photo moderation, privacy decisions and staging/device gates remain explicitly open. A confidentiality/access mismatch needs correction or an adviser-approved protocol change before handling affected participant data; a survey score does not resolve it.
- Give respondents accurate scope/limitations and approved consent materials before the evaluation. Let them skip answers as the consent form states; adviser should reconcile the conflicting declaration and signature handling. Report measured results independently of questionnaire ratings.
- Coordinate the later app/backend rollout using [the rollout checklist](reliability-rollout.md). This document authorizes no APK distribution, deployment, paid resource or production load test.

For an executed case record: **case ID, build/backend identity, date/tester, device/network, setup/input, expected result, actual result, pass/fail/blocked, evidence, issue and retest**. Use synthetic records for automated/stress tests and redact participant identifiers and bearer photo URLs from shared evidence.


## Core migration update - 2026-10-25

Resident incident observations and weather/risk/expiry now have an implemented and hosted-verified **test-only** Spark migration. The signed maintenance schedule is active every four minutes, with an actual successful automatic run recorded. See [scope, evidence and remaining gates](spark-core-migration.md). This supersedes earlier statements that those test backend paths are unimplemented. Native acceptance, other media/notification paths and the main rollout remain open. No new APK was built or installed.


## Communication migration update - 2026-10-25

Feedback and broadcasts now have an implemented, hosted-verified **test-only** migration. Private owner history, explicit reply/closure, consent, idempotent scoped publications, expiry/withdrawal and typed fair notification processing are covered. Existing report push and report/photo hosted regressions also pass. See [current scope and evidence](communication-migration.md); older counts and deployment versions above are dated phase baselines. Profile/feedback media also has separate [test-only acceptance](private-media-migration.md), with final totals of 247 Flutter, 51 backend and 88 emulator tests passed. APK builds, native phone acceptance, performance/adviser decisions and main-project rollout remain open.
