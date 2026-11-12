# Normal report and photo integration

Updated 2026-10-25. The normal reporting screen now supports the tested Spark backend through an explicit **Test-app option**. APK builds remain on hold. Main Firebase, billing, native project files and existing APKs are unchanged.

## What is connected

`ReportSubmissionScreen` uses `ReportPhotoUploader`, and `AppStateService.submitReport` uses `ReportSubmissionRepository`. With `SPARK_PROOF_REPORTS_ENABLED=true`, they use the existing authenticated Supabase proof endpoint and private report-photo bucket. This uses the normal form's selected road, manual/GPS coordinates, observation time, description, severity and SOS choice. It does not substitute the standalone proof screen's fixed road or coordinates.

`SparkBackendService` centralizes the existing account-pinned client used by report/photo, admin reviews, resident edits, protected images and device registration. It requires a verified signed-in test account and validates the native flavor, Firebase project and exact backend URL. Main-project requests and contradictory configuration fail closed. Existing server-side token/current-account/role checks and the three synthetic-account allowlist remain authoritative.

The current default is deliberately unchanged: normal fieldtest reporting is disabled unless opted in; generic fieldtest uploads remain disabled. Production defaults retain their older service paths and still require the remaining Spark migration before a new main-app rollout.

For a later approved Test build targeting `lib/main.dart`, the public settings are:

| Setting | Value |
| --- | --- |
| Flavor | `fieldtest` |
| `SPARK_PROOF_REPORTS_ENABLED` | `true` |
| `SPARK_PROOF_FIREBASE_PROJECT_ID` | `safepaths-test` |
| `SPARK_PROOF_BACKEND_URL` | `https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof` |
| Optional report push | `SPARK_PROOF_PUSH_ENABLED=true` |

No server key, scheduler credential or synthetic account password belongs in these settings or the APK. Report push startup is now also connected to the normal fieldtest entry point when explicitly enabled; it remains detached from startup success.

## Retry and form behavior

- The form retains its entered information after a failed submission. The coordinator retains a confirmed photo reference, so an uncertain report-save response does not require another upload.
- Retry identifiers persist before sending. Their keys hash the environment, account and complete report payload, including the attached photo. Preferences store only opaque identifiers, not the notes, coordinates, photo reference or report text.
- Identical overlapping saves share one in-flight operation. A server acknowledgement must contain a valid report ID and replay flag before the form shows success. Account changes before/after requests cannot confirm a save for the next account.
- A failed preference write prevents sending without a durable ID. Cleanup failure after a confirmed save does not turn that saved result into failure.
- If an owned uploaded photo is missing, the backend returns `photo-unavailable`. The form clears that cached reference and can upload the attachment again. Ownership denial and provider/network failure remain distinct. Already committed reports still replay their receipt if their photo becomes unavailable later.
- Upload progress remains truthful: the Supabase HTTP uploader shows indeterminate progress until its server confirmation, then advances to saving. The existing Firebase uploader retains its original byte progress in the legacy path.
- Back navigation is blocked during upload/save, matching the existing “keep this screen open” progress message. Full draft restoration after killing/restarting the app is not added by this step; entered fields/photo retention is tested within the open form, while request IDs persist separately.

Late GPS results cannot overwrite a returned manual pin. Nearest-road selection preserves disconnected geometry segments, avoiding a fictional connecting road through their gap. Photo watermarks use the configured study-area name. SOS acknowledgement continues to say that saving a report does not confirm rescue dispatch.

## Hosted test data and evidence

The previous proof road lies in Marulas; the normal Test app uses its existing `nearby_test` area. A labelled synthetic closed road, `spark-normal-form-road`, was created for the earlier reporting checks. **That fixture is now retired:** phone testing showed its artificial closure crossed the resident's starting location and contaminated the baseline. `test/normal-report-fixture.json` marks it retired; `functions/tools/prepare-normal-report-fixture.cjs` refuses `--apply` before credentials or cloud access. Preserve its report/incident history, remove its active road/cache entry through protected test administration, and agree on a public test segment before creating any future closure drill. See [current phone acceptance](navigation-phone-acceptance.md).

The opt-in hosted Flutter test runs the **same Dart uploader, coordinator and repository** used by the normal form. It reads synthetic credentials locally at runtime, sends a synthetic JPEG/report to the deployed test endpoint, injects loss of the save response after server acknowledgement, recreates the repository and retries the preserved request. Native camera/GPS or actual form taps are not simulated as completed device acceptance.

| Check | Actual result |
| --- | --- |
| Full Flutter regression suite | **225 passed**, one opt-in benchmark skipped |
| Fieldtest flavor with normal-report option enabled | **17 passed**; subset of the regression cases |
| Backend unit/parity/guard tests | **39 passed** |
| Combined local Auth/Firestore/Storage integration | **54 passed**, including removed-photo recovery and receipt replay |
| Full Flutter analysis | No compile errors or new warnings; four pre-existing warnings and informational lints remain |
| Edge entry point | Deno type check passed |
| Hosted normal-form service flow | **8 checks passed**; one photo-upload request and two save attempts for the same synthetic operation |
| Physical Android form/receipt/GPS | Pending; no APK built, installed or distributed |

The hosted checks establish:

1. Correct native test-project/package metadata, the configured nearby study area and real sign-in of the existing three synthetic accounts.
2. Uncertain-save handling preserves the pending request and uploaded photo.
3. Retry returns the same report ID and an explicit replay acknowledgement, without another photo upload.
4. The chosen road/location, reporter and protected photo are saved; opening admin context does not start review.
5. Reporter and admin obtain working signed photo URLs with the expected JPEG bytes.
6. A peer resident cannot open the photo.
7. The normal resident history and indexed admin feed include the saved report.
8. The official test-road closure remains `not_passable`.

Logs are under ignored `.usability-work-baseline/normal-report-*.txt`; hosted evidence and a replay-safe synthetic state snapshot are in `spark-proof-setup/normal-form-*.json`. Passwords, ID tokens and signed URLs are not written to that evidence. Source/installer hashes and deployment metadata are in `normal-report-verification.json`.

Earlier failed setup attempts are retained: the first opt-in unit invocation supplied a fieldtest environment with the default production flavor and correctly failed the configuration guard. Retesting with `--flavor fieldtest` passed. The initial fixture creation failed; using Firestore-supported map/point geometry succeeded without replacing existing data.

## Remaining scope and recovery

The source checkpoint before this step is `.usability-work-baseline/checkpoints/normal-report-before-20261025/` (210 hash-verified files, 2,725,353 bytes). The existing main installers and earlier proof APK are retained and checked independently. Only the isolated proof function's missing-photo response was updated; no new bucket, managed credential, billing change, rule/index deployment or scheduled job was introduced here.

Actual normal-form interaction, Mapbox/GPS, image-picker permissions, offline interruption, account changes and notification receipt/taps still need the later Android test build. Existing pending-report updates may retain the earlier photo when no replacement is supplied; this step does not implement photo deletion/retention policy.

Resident incident observations and weather/risk/expiry jobs now have a separately verified, opted-in test migration; see [core migration](spark-core-migration.md). Native acceptance remains open. Broadcast/feedback communication now has a separately verified [test migration](communication-migration.md). Profile/feedback media, performance/B-05 and adviser privacy/moderation decisions still need their own completion and acceptance. Keep the main rollout separate from these Test integrations.
