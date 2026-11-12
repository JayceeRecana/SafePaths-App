# Isolated Spark report/photo proof

**Normal-form integration, 2026-10-25:** the [normal reporting screen and shared services](normal-report-integration.md) now support the test endpoint with explicit `SPARK_PROOF_REPORTS_ENABLED=true`. Current evidence is 225 Flutter / 39 backend / 54 emulator tests, 17 fieldtest-option checks and eight hosted normal-service checks. Main Firebase and existing APKs are unchanged; builds remain on hold. The original standalone proof details below are dated baselines.

**Report push follow-up, 2026-10-25:** [push implementation and evidence](push-delivery.md) records 216 Flutter / 39 backend / 53 emulator tests, nine hosted checks, real FCM validation-only acceptance, nine READY test indexes, and a signed retry worker. Physical delivery and APK builds remain on hold/pending. Earlier proof counts and APK details below are dated baselines.

**Admin-workflow extension, 2026-10-25:** see [resident/admin workflow](admin-resident-workflow.md) for the latest test deployment, 211 Flutter / 31 backend / 42 emulator results and planned one-phone procedure. The user has explicitly put new APK builds on hold while fixes continue. The original reporting-proof evidence below is retained as a dated baseline. Main Firebase and existing main installers remain unchanged; normal app source integration is staged and requires a later coordinated rollout.

The extension also passed 13 hosted synthetic admin checks. The deployed test rules match source and all eight indexes are READY. New messages are owner/admin-only, atomic moderation is active on the isolated endpoint, and push sending remains pending. The earlier proof APK below predates this extension.

Updated 2026-10-25. **Hosted test backend deployed; automated hosted checks pass. Physical phone acceptance remains pending.** This first proof keeps Firebase Authentication/Firestore and replaces only synthetic report/photo operations with a portable Supabase Edge endpoint. It is a gate for the larger [Spark plan](spark-capstone-plan.md), not a completed main-app migration. The separate APK has not been installed or distributed.

## Isolation and recovery

- Main Firebase project `safepaths-92c3d` is rejected by the setup tool, Edge configuration and proof client. Use only `safepaths-test`; a main-project service-account JSON cannot substitute.
- The separate Flutter target is `lib/main_spark_proof.dart`. Its fieldtest application ID is `com.safepaths.safepaths_app.test`. Installing it later replaces the existing **SafePaths Test** application, not the main app.
- The normal `main.dart`, backend/uploader selection, production rules and existing Supabase `report-images` bucket/policies have not been changed by this proof.
- The private source checkpoint is `.usability-work-baseline/checkpoints/spark-before-20261024T151756Z/`: 340 hash-verified files, 3,976,163 bytes. It includes local configuration/credentials; do not share it. Previous APKs and hashes are in its `apk-before-proof/` directory.
- Only synthetic records and the three allowlisted accounts below may use the proof. Its fixed road coordinates are a fixture, not a GPS observation or emergency tool.

## Local evidence

| Check | Observed result |
| --- | --- |
| Flutter regression suite | 205 passed; one opt-in benchmark skipped |
| Node unit/parity/guard suite | 31 passed, including wrapped Storage errors and bounded token clock skew |
| Combined Firebase emulator suite | 32 passed; original 27 plus five REST reporting/access cases |
| New Flutter proof files, focused analysis | No issues found |
| Full application analysis | No compile errors; five existing warnings and informational findings remain |
| Actual Edge entry point, Deno 2.9.6 | Type check passed |
| Fieldtest release APK, separate proof target | Built successfully; native package/test-project configuration inspected |

Local logs: `.usability-work-baseline/spark-proof-*.txt`. The Storage tests use a protocol fixture, **not actual hosted Supabase Storage or SQL/RLS**. Emulator tests cover report identity, transactions/cooldown, replay, retained photos, closure preservation, verification, revocation and photo authorization. Failed earlier harness runs are retained: transactional GET query decoding and mixed emulator project/reset conflicts were corrected; the final combined run exited successfully. These are local results, not a capacity or availability guarantee.

## Hosted resources created

The following were created/deployed only for this proof. The user supplied the correct test-project credential and completed Supabase CLI login privately. No key, password, personal access token or signed photo URL is included in this document.

| Location | Actual change |
| --- | --- |
| Firebase `safepaths-test` | Three synthetic Auth accounts and matching `users` profiles: `spark-proof-resident`, `spark-proof-admin`, `spark-proof-other` |
| Same test Firestore | Fixture road `roads/spark-proof-road`; one synthetic report and corresponding receipts, slot and incident state written through the hosted endpoint |
| Same test Firestore | Staged rules match the deployed rules; all six indexes are READY, retaining the previously deployed feedback index |
| Supabase `bbteuzgfgnrjjrqewidc` | New private bucket `report-photos-proof`, JPEG only, maximum 2 MiB; synthetic JPEG uploaded |
| Same Supabase project | Restrictive `spark_proof_server_only` policy for that bucket, leaving access to other buckets governed by their existing policies |
| Same Supabase project | New function `safepaths-report-proof` and three managed `PROOF_*` secrets |

The Supabase project is configured in the existing feedback/avatar code. The read-only preflight found no hosted Storage buckets, Storage policies, Edge functions or custom function secrets. This is an inventory result, not proof of how an older installed APK behaved. Every new resource is scoped to the proof. No billing change occurred.

Before deployment, the test Firestore rules/release and its existing index were saved under ignored `spark-proof-setup/cloud-before-test-deploy/`. Verification after deployment is in `cloud-after-test-deploy/`. The main Firebase project was not deployed to or modified.

## Hosted evidence

| Exercise | Actual result |
| --- | --- |
| Three synthetic email/password accounts | Real sign-in, signed token verification, current account lookup and portable Firestore REST reads passed |
| Photo upload and duplicate retry | Real JPEG stored in the private bucket; repeated upload returns the same protected reference |
| Owner/admin versus peer | Owner and test admin obtain working short-lived photo URLs; another resident is denied even when supplying an admin role field |
| Report save, history and admin feed | Real report saved, both indexed feeds include it, identity/photo/authority are server-derived, official road closure retained |
| Replay and cooldown | Same request replays one saved result; changed content with that ID is rejected; two concurrent submissions during cooldown are rejected |
| Direct client access | Anonymous endpoint denied; direct resident Firestore update denied; valid anonymous Storage client cannot read/list/upload/delete the synthetic object |
| Authenticated Storage role | Real SQL/RLS read/update/insert denied; direct delete also blocked by provider protection; all test metadata writes rolled back |
| Current account state | Existing tokens rejected after verification removal, account disable and session revocation; restored account signs in again and remains denied another resident's photo |
| Signed URL expiry | Fresh URL retrieves the photo; the same URL is denied after its 120-second lifetime |

Evidence: `spark-proof-setup/hosted-smoke-result.json`, `hosted-access-result.json`, `firebase-live-check.json` and `supabase-authenticated-rls-result.json`. These checks ran from this computer, **not two phones**. The peer account was restored to enabled/verified after its access checks; it needs a fresh sign-in after deliberate session revocation.

The first live checks exposed two compatibility issues that local emulators/fixtures had not established: a signed token arrived three seconds ahead of the local clock, and Storage represented missing-object metadata as HTTP 400 with `statusCode: "404", error: "not_found"`. The backend now permits at most 30 seconds of future issue/authentication time while keeping expiration and revocation strict. Storage recognizes only the exact wrapped missing-object shape; other permission/provider errors still fail. New regression checks and the final 31 Node/32 emulator tests pass. Failed attempts remain in the private local record; they have not been relabeled as passes.

## 1. Obtain the test credential privately

Open [Firebase Console service accounts for safepaths-test](https://console.firebase.google.com/project/safepaths-test/settings/serviceaccounts/adminsdk). Confirm the **project ID**, then choose **Firebase Admin SDK → Generate new private key → Generate key**. Save the JSON privately outside source control and provide only its local path. Do not paste its contents into chat, embed it in Flutter assets or use the main-project credential. These are [Firebase's documented service-account steps](https://firebase.google.com/docs/admin/setup).

The setup helper creates synthetic Auth accounts and therefore needs test-project Auth account administration and Firestore write permissions. The hosted runtime needs Firestore read/write and Auth account lookup; use a dedicated runtime identity with appropriate least-privilege permissions when provisioning it. Do not assume an Auth viewer can create the setup accounts. Neither credential needs access to the main project.

## 2. Prepare synthetic accounts and private local files

From the repository root, substitute the actual local test credential path. The first command is a dry run with no cloud writes:

```powershell
node functions/tools/prepare-spark-proof.cjs --project=safepaths-test --credentials="C:\PRIVATE\test-service-account.json" --supabase-ref=bbteuzgfgnrjjrqewidc
```

After confirming the test environment, run the same command with `--apply`. The helper refuses mismatched credentials/conflicting fixtures. It creates three verified **synthetic** email/password accounts, profiles (one test admin), and a closed synthetic road. It sends no verification email. Generated passwords and server secrets are written only to ignored `.usability-work-baseline/spark-proof-setup/`:

- `PRIVATE-test-accounts.json`: local synthetic sign-in credentials.
- `PRIVATE-secrets.env`: test project ID, allowlisted UIDs and test server credential.
- `public-build-defines.json`: public project/endpoint build values only.

No Supabase resources, rules or APK installation are performed by this helper. Its preflight checks run before cloud writes; a provider failure after writes start can still leave partial fixtures. Keep the local credential file and rerun the same helper to recover; do not overwrite unrelated records.

## 3. Deploy only the test Firestore configuration

```powershell
firebase deploy --project safepaths-test --config firebase.spark-proof.json --only 'firestore:rules,firestore:indexes'
```

Review the target before executing. These staged rules can block older Test builds from submitting reports directly. Preserve their installers and coordinate Test-app use. The proof index file retains existing indexes and adds the road/history query. Wait until indexes are ready before checking the admin feed. Do not run this command against the main project.

## 4. Configure only the new Supabase proof resources

Use an authenticated [Supabase CLI](https://supabase.com/docs/guides/functions/deploy) or the project dashboard. CLI 2.122.0 is installed in ignored `.usability-work-baseline/supabase-cli/`; the user completed its login and access to SafePaths Capstone was verified. The commands below use `supabase` as shorthand for that local CLI. Keep personal access tokens out of chat.

1. Inspect `storage.buckets` and `pg_policies`. If `report-photos-proof` or its policy name already exists, verify its configuration rather than changing an unknown resource.
2. Review and execute `supabase/proof-private-bucket.sql` in this project's SQL editor. It inserts a private bucket without overwriting an existing bucket. Its restrictive policy prevents old permissive client policies from granting access to the new bucket; the server service role retains access. Verify the actual resulting policy and bucket settings.
3. Set secrets from the private local file; never include the JSON key on a command line:

```powershell
supabase secrets set --project-ref bbteuzgfgnrjjrqewidc --env-file .usability-work-baseline/spark-proof-setup/PRIVATE-secrets.env
supabase functions deploy safepaths-report-proof --project-ref bbteuzgfgnrjjrqewidc --use-api --no-verify-jwt
```

The function uses built-in `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. `supabase/config.toml` disables the gateway's Supabase-JWT requirement **only for this function** because its handler verifies Firebase signatures, expected project/claims, current account/revocation state, verified email and the test UID allowlist. There is no hosted emulator-token mode. Missing/invalid configuration fails closed with a generic startup error.

Do not replace other functions, publish the bucket or add public client upload policies. Avoid CLI commands that print stored secrets. See [Supabase secret management](https://supabase.com/docs/guides/functions/secrets).

## 5. Separate APK and two-phone acceptance

The local compile used:

```powershell
flutter build apk --flavor fieldtest --release --no-pub --target lib/main_spark_proof.dart --dart-define=SPARK_PROOF_FIREBASE_PROJECT_ID=safepaths-test --dart-define=SPARK_PROOF_BACKEND_URL=https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof
```

The artifact is a synthetic report/photo screen with its own login, gallery compression/upload, durable retry identity, bounded history and authorized photo viewing. It does not provide the full SafePaths UI. Upload progress is indeterminate until confirmed; the HTTP client does not claim measured byte progress. No private credential is a build define or Flutter asset. Build output and an inspection record are retained locally under `.usability-work-baseline/spark-proof-artifacts/`.

The hosted cases above passed. Run the following with agreed phone installs, recording actual results and failures. **Physical phone cases remain pending.**

| Case | Required observation |
| --- | --- |
| Resident on phone A, admin on phone B | Upload photo, submit one synthetic report, see correct resident history and admin feed, open photo on both |
| Third allowlisted resident | Cannot obtain the owner's photo URL; forging paths/identity/role does not grant access |
| Invalid account/token | Anonymous, unverified, disabled, revoked, wrong-project and non-allowlisted identities denied |
| Direct Storage access | Anonymous and ordinary authenticated clients cannot read/list/write/delete proof objects, including through older permissive policies |
| Save/replay/concurrency | Lost-response retries preserve one result; changed payload/photo with reused ID is rejected; concurrent cooldown applies |
| Edits and road closure | Current pending report updated correctly, retained evidence preserved, official road closure remains |
| Private photo delivery | Persisted report contains protected reference; only a fresh authorized request obtains a signed URL; URL expires after 120 seconds |
| Phone/network lifecycle | Gallery denial, large/corrupt image, interruption, retry, reconnect and account switching recover without false success or cross-account UI |

The hosted smoke harness is `functions/tools/prove-spark-hosted.cjs`. It requires `--apply --credentials=PRIVATE_TEST_KEY_PATH`, validates the fixed test project/host/fixture accounts, and retains request state locally. It uploads only the synthetic `spark-proof-setup/synthetic-proof.jpg`. If an earlier cooldown has elapsed it primes another synthetic update before testing denial; it preserves the initial receipt for replay. It is a targeted acceptance check, not a load test. `supabase/proof-private-access-check.sql` repeats the authenticated-role metadata checks inside a transaction that rolls back its attempted changes.

### First check with the user's one available phone

The user confirmed one Android phone is available. Start with this account-switch sequence and retain the simultaneous two-phone case as pending:

1. Transfer the inspected `.usability-work-baseline/spark-proof-artifacts/SafePaths-Spark-Proof.apk` to the phone. Install it as **SafePaths Test**. It replaces an existing Test install; the main package is different. It displays a synthetic reporting screen, not the complete map application.
2. Open `.usability-work-baseline/spark-proof-setup/PRIVATE-test-accounts.json` locally on the computer for synthetic sign-in details. Keep this file and its passwords out of shared evidence/chat. Use the resident account first.
3. Choose an ordinary test photo with no participant details. Submit a synthetic report for the fixed proof road. If a recent automated submission is still within the five-minute cooldown, wait for it to expire; do not remove cooldowns to make the check pass.
4. Confirm the report appears in resident history and its photo opens. Close/reopen the app and verify the saved report remains available online.
5. Sign out, sign in as the test admin, confirm the same report appears in its feed and open the photo. Record any gallery, login, feed or display error and the Android model/version.
6. Sign out and use the third test account: it must not gain access to the resident's photo. The synthetic raw report record remains governed by the current test Firestore rules; a visible protected reference does not grant photo access.

No phone result has been recorded yet. One-phone account switching does not establish simultaneous synchronization, multi-device sessions or full SafePaths behavior.

A signed URL is a bearer link while valid; disabling an account does not retract a URL already issued. Do not log/share signed URLs. Path/metadata/JPEG-header validation is not photo-content moderation. Retention is undecided, so automatic deletion remains off; synthetic proof records require a reviewed cleanup later.

## Remaining migration and evaluation work

Do not port remaining workflows until the agreed phone report/photo acceptance passes, retaining the two-phone gate in the staged plan. Incident observation/review, trusted push sending, weather/risk/expiry jobs, maps/routes, real GPS/camera, accessibility, full-app lifecycle and quotas still need their own migration/regression/device checks. Main report-photo storage and callable operations have not been made Spark-compatible by this separate proof.

Check [Supabase Free quotas](https://supabase.com/docs/guides/platform/billing-on-supabase), [Edge runtime limits](https://supabase.com/docs/guides/functions/limits) and [low-activity pausing](https://supabase.com/docs/guides/platform/free-project-pausing) against the actual project. The every-minute road rewrite job must be redesigned for the [Firestore daily budget](https://firebase.google.com/docs/firestore/quotas). Local passing results do not establish that budget or hosted availability.

B-05/stress failures, deferred 4.2 moderation and 5.6 project email/retention/report-audience decisions remain open. Existing raw report/public media access has not been changed into an approved privacy policy by this test bucket. See [evaluation evidence](evaluation-readiness-5.7.md).
