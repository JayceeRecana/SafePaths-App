# Resident and administrator workflow

> Current status - November 4, 2026: this document preserves the original October 25 rollout record. The separate Marulas candidate was subsequently activated on November 2; see [Marulas integration](marulas-main-integration.md). The interaction audit records draft-isolation, live-inspector and follow-up exit-protection gaps now corrected in shared source (updated APK acceptance remains pending): [November 4 review](user-admin-interaction-review-20261104.md). Statements below about main rollout/builds being on hold describe their historical checkpoint.

Updated 2026-10-25. This is a test-only extension of the [Spark reporting proof](spark-proof-setup.md), approved by the user after discussing the resident/admin interactions. Firebase `safepaths-92c3d` and the existing main APKs have not been changed. The source changes are staged for a later coordinated main-app rollout; they do not establish full-app Spark compatibility.

**Push follow-up:** the [report-update sender](push-delivery.md) is now implemented in the test environment, with local/hosted checks and a protected retry worker. The admin-phase counts below are retained as its dated baseline. New APK builds and physical delivery/tap acceptance remain on hold/pending.

## Behavior

- Opening a report only reads it. **Start review** explicitly records the acknowledgement and changes an active report to `under_review`.
- Reply fields start blank. Optional templates acknowledge receipt or review; they do not claim that flooding was confirmed, a road was reopened, or a rescue team was dispatched.
- An admin verifies the reported observation separately from the road's present condition. A source/findings note and a current-condition confirmation are required. Verifying a flood report can correctly leave the road **Not passable**.
- Report, road and incident updates, actual trust changes, audit, private messages and notification outbox records commit in one Firestore transaction. Saved request receipts recover retries without a second award or duplicate message.
- A review token binds the loaded report, road and incident. New observations or another decision invalidate an old review. The server rechecks the live admin role, including on a saved retry.
- Duplicate/already-handled dismissals do not deduct trust. False/spam dismissal requires evidence acknowledgement; SOS dismissal requires an additional explicit acknowledgement and records no dispatch/completion.
- Trust messaging uses the actual capped change, including zero, rather than always promising ten points. A 12-hour per-road reward cooldown remains in force.
- Resident edits go through the authenticated server with ownership, cooldown and expected-version checks. Stale or reviewed forms cannot overwrite the decision or silently create a new report. A saved edit can still replay its receipt after review.

New message bodies live in `report_messages`, readable only by the verified reporter and authorized administrators. The public legacy report fields receive an update flag, not the new message body. Existing legacy replies and report/media audience policies are not migrated by this change. The thread loads 20 messages at a time and resets on account/report changes.

The transaction stores an `awaiting_sender` outbox record. The [push follow-up](push-delivery.md) processes it independently and records provider acceptance/failures. The admin acknowledgement continues to mean **saved in-app**, not delivered to a device. Actual phone acceptance remains pending. This work does not provide emergency dispatch.

## Verification

| Check | Result |
| --- | --- |
| Flutter suite | 211 passed; one opt-in benchmark skipped |
| Backend unit/parity/guard tests | 31 passed |
| Isolated Auth/Firestore/Storage integration | 42 passed |
| Full Flutter analysis | No compile errors; four pre-existing warnings and informational lints remain |
| Actual Edge entry point | Deno type check passed |
| Hosted admin acceptance | 13 synthetic checks passed against the deployed test endpoint |
| Updated APK | Not built; user explicitly requested holding builds while fixes continue |

Integration cases cover private access, direct client-write denial, two-admin conflicts, role removal, stale observations, exact capped points, cooldowns, SOS confirmations, resident edit replay, complete rollback on a failed commit, and recovery from a lost commit response. Widget tests cover preserved drafts after errors and a 360-pixel-wide review dialog with 1.8x text.

Logs and evidence are under ignored `.usability-work-baseline/admin-*.txt` and `spark-proof-setup/`. Earlier failed runs remain available; their final retries are separately identified. Emulator media uses a protocol fixture; hosted media/access evidence remains recorded separately in the original proof.

## Test rollout and recovery

The updated rules and eight indexes target **only `safepaths-test`**. They block direct report writes from older Test builds, including administrators. The backup immediately before this rollout is `spark-proof-setup/admin-cloud-before/`; the matching deployed-rule/index inventory is in `admin-cloud-after/`.

Only Supabase function `safepaths-report-proof` is updated. Its existing private photo bucket, strict Firebase token/account checks, managed secrets and three synthetic-account allowlist remain in use. No billing upgrade occurred. No main service-account key is used.

The normal admin and resident screens now share the staged review/edit services. Those services require explicit `SPARK_PROOF_*` build values and reject the main project. **Do not distribute a newly compiled normal main APK as a completed Spark migration.** Continue testing with the separate proof target; port the remaining server-dependent workflows and coordinate the eventual main release first.

The private source checkpoint before this phase is `checkpoints/spark-before-20261024T172001Z/` (360 verified files). The earlier proof APK and main installers are retained. Checkpoints include private local configuration; never upload them to Drive or source control. Do not restore broad client-write permissions to work around a server error.

## One-phone acceptance

APK building/distribution is on hold at the user's explicit request. The procedure below is for a later approved test build. The earlier `SafePaths-Spark-Proof.apk` predates these interaction changes and cannot establish their phone acceptance. Use only the generated synthetic credentials in local `spark-proof-setup/PRIVATE-test-accounts.json`; keep that file private.

1. Sign in as the synthetic resident. Choose a non-personal test image, submit once, and confirm report/photo history. Retry a lost response using the same form; observe the five-minute cooldown rather than repeatedly starting new submissions.
2. Sign out and sign in as the test admin. Merely opening the report must leave it received/pending. Select **Start review** and confirm the explicit acknowledgement.
3. Send a private factual update. It should appear once after retry. Sign in as the resident to read it, then as the peer account to confirm it cannot read the resident's private thread/photo.
4. While the report is active, try a resident edit after cooldown. Reopen the admin review afterward. An old review must require refresh when its context changed.
5. Verify the observation with a synthetic source note and keep the road **Not passable**. Confirm both the separate report outcome and recorded road condition, the actual trust change, and exactly one saved review. A reviewed report cannot be edited afterward.
6. On another synthetic report, test duplicate dismissal without a trust deduction. Use false/spam and SOS only as labelled synthetic cases; their explicit confirmations must be required.
7. Repeat with large system text, a restart, and a temporary network interruption. A failed save must retain the draft and must not display success. Reopen signed photos after expiry rather than relying on a saved URL.

Record expected/actual results and device model/Android version. One phone can check the account-switch sequence; simultaneous two-phone synchronization, native maps/GPS, push delivery, and measured capacity remain pending. Adviser decisions on project privacy email, retention and report/photo audience, plus deferred photo-content moderation, remain open.

## Current hosted/build record

All 13 synthetic hosted admin checks passed: authenticated submission; read-only context; resident role-spoof denial; explicit review start/replay; concurrent private-message retries; owner/admin indexed message queries; peer read/query denial; direct admin report-write denial; stale-review rejection; transactional verification with actual trust/audit/outbox; no duplicate award; retained road closure; and rejection of resident edits after review.

The first hosted pass stopped when the new message indexes were still building. After all eight indexes became READY, the resumed checks passed. Deployed rules match the staged source. Evidence: `spark-proof-setup/admin-hosted-result.json`, `admin-cloud-after/inspection.json`, and `.usability-work-baseline/admin-hosted-check-retry.txt`. The initial failed attempt remains recorded separately. The earlier reporting/photo/access evidence is retained as a dated baseline, not rerun or overwritten by these checks.

The proposed updated APK build was declined, and the user confirmed that builds should wait while fixes continue. No updated APK was built or installed. Hash checks confirm that both main installers and the earlier proof APK are unchanged. Do not treat local/hosted automated checks as physical-device acceptance.


## Communication migration update - 2026-10-25

Feedback and broadcasts now have an implemented, hosted-verified **test-only** migration. Private owner history, explicit reply/closure, consent, idempotent scoped publications, expiry/withdrawal and typed fair notification processing are covered. Existing report push and report/photo hosted regressions also pass. See [current scope and evidence](communication-migration.md); older counts and deployment versions above are dated phase baselines. Profile/feedback media also has separate [test-only acceptance](private-media-migration.md). APK builds, native phone acceptance, performance/adviser decisions and main-project rollout remain open.
