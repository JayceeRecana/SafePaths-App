# Profile photos, feedback screenshots and reliability gaps

This migration is for the isolated `safepaths-test` Firebase project and the
`safepaths-report-proof` Supabase function. It does not activate these paths in
the main Firebase project or update installed apps. APK building, installation,
distribution and physical phone testing remain on hold.

## Resulting behavior

Profile photos and optional feedback screenshots use the existing private
`report-photos-proof` bucket, under separate owner/content-hash paths. The app
sends a verified Firebase session to upload, save and fetch bytes. New references
are opaque resource identifiers; they are not public or signed download links.
The backend checks current ownership or admin role and the current profile or
feedback binding before and after fetching bytes. A staged upload cannot be
viewed until saved to its record. Removing/replacing an avatar revokes subsequent
reads of the old binding. Already downloaded bytes cannot be retroactively erased.

Profile edits save only the name, location and an explicit keep/set/remove photo
choice. The backend derives the account identity, preserves role/trust/account
email, checks a profile revision, and records an idempotent receipt. Unrelated
report or notification activity does not invalidate the edit context. Sign-in
email is read-only here: changing profile metadata did not change the Firebase
Auth sign-in address. Any existing mismatch needs a separate account review.

Feedback with an attachment must confirm that attachment before saving. Failed
upload/preparation keeps the draft and explains the failure. The user must
explicitly remove the attachment or continue without it. A save retry reuses the
confirmed upload and original command. Screenshots in owner history and admin
review are fetched with the feedback record ID; another resident or a different
record cannot open them. No screenshot is included in a push payload.

Images are decoded with existing source-size/pixel bounds, resized while
preserving their proportions and re-encoded onto a fresh RGB canvas. This strips
source EXIF/GPS and avoids embedding an oversized source image in Firestore.
Avatar output is at most 256 pixels on its longest side and 256 KiB; screenshots
are at most 1600 pixels and 2 MiB. Server JPEG structure, dimensions, metadata,
content hash and stored bytes are checked. These checks do not constitute a full
server image decoder or content moderation. Report preparation now also strips
metadata, and media-enabled report uploads receive the stricter JPEG check.

For this small proof, unique uploads have a per-account budget of 20/day and
16 MiB/day, plus 100 and 32 MiB in total. Retrying identical content/purpose does
not spend a second reservation. Failed or abandoned unique uploads retain their
reservation conservatively. The quota day uses Pacific time. These limits bound
this proof; they are not a load/capacity certification.

## Gaps found and addressed

| Gap | Change | Remaining limit |
| --- | --- | --- |
| An avatar upload could fall through multiple services and appear successful as inline Base64 | Removed new public/inline fallback writes; one confirmed private upload on the migrated path | Main-build compatibility still has its Firebase-only upload branch until main rollout |
| Old profile/feedback code points to `report-images`, which is absent in the connected Supabase project | Reused the confirmed private bucket with explicit namespaces | No claim that a public legacy bucket or exposed objects were found |
| Profile edits could fall back to a passed-in user ID | Current authenticated UID is required; actor is assigned on the server | Native account-switch behavior still needs a phone check |
| Email appeared editable without updating sign-in email | Show the actual Auth email as read-only | A proper verified email-change flow is separate work |
| Upload failure could silently discard a feedback screenshot | Failed attachment blocks submission until explicit removal/retry | Gallery/permission/native failure cases still need phone acceptance |
| Image dimensions could be distorted and source metadata retained | Aspect-preserving resize and fresh metadata-free re-encode | No automated visual moderation; PDF section 4.2 remains deferred |
| A pending image future could retain the previous account's image | Key/clear image state by account, reference and record; discard late results | Bytes already viewed/downloaded cannot be recalled |
| A report JPEG was checked mostly by its signature bytes | Media-enabled server path validates bounded JPEG structure/dimensions/metadata too | Not a full decoder or fraud detector |
| An unused weather API key was present in a production source asset | Privately backed up configuration, removed the unused entry from source/example | Existing APKs were not rebuilt; provider key rotation/revocation was not performed |

The storage audit found `report-photos-proof` private, JPEG-only and capped at
2 MiB, with a restrictive policy excluding client access to that bucket. No
bucket or storage policy was changed. Legacy references and bounded inline
images remain readable for compatibility; this phase neither converts nor
deletes historical data. A credential-name/JWT-role audit of current client env
assets found no server/admin credentials. That limited source audit is not a
claim about historical APK contents or every credential ever issued.

## Rollout and recovery

Native opt-in: `SPARK_PROOF_MEDIA_ENABLED=true` with the existing fieldtest and
communication flags. Backend opt-in: `PROOF_MEDIA_ENABLED=true`, requiring
`PROOF_COMMUNICATIONS_ENABLED=true`. `system/media.enabled` in the test Firebase
project protects direct name/location/email/photo/revision writes, including
admin writes. Existing session/token updates retain their permitted behavior.
New media upload/limit/profile receipt collections are server-only. No additional
Firestore index, bucket or scheduler is needed.

`prepare-media.cjs` defaults to read-only preparation and rejects non-test
credentials. Its `--apply` snapshots the three synthetic profiles, existing
feedback and media records before creating a disabled control. The guarded
`activate-media.cjs --apply` enables the prepared control after the new rules and
function are staged. Keep source, server flag and rollout control coordinated.
Disabling the feature may pause profile/screenshot commands; do not reopen
unrestricted direct writes to work around a service failure. Preserve saved
receipts and newer decisions during recovery.

The hosted media acceptance helper uses only a generated JPEG and the three
allowlisted synthetic accounts. It restores the original synthetic profile via
the protected API. It retains its synthetic feedback, receipts and private
objects as evidence. Automatic deletion is off because retention is undecided.
Private credentials, account fixtures, configuration backups and test state
under `.usability-work-baseline` must not be included in an APK or shared folder.

## Verification

Final local checks: 247 Flutter tests passed (one optional benchmark skipped),
44 feature-enabled Flutter tests passed, 51 backend unit tests passed and 88
emulator integration tests passed. Deno checked the actual Edge entry point.
Analysis reports zero errors and four existing warnings; 305 findings include
informational/style items and have not all been resolved.

Fourteen hosted media checks and eight checks through the actual Dart media
codec/client passed. They cover private binding/access, explicit missing-image
failure, forged ownership, stale edits, upload reuse, lost-save replay, default
avatar removal and restoration of the synthetic profile. The existing eight
normal report/photo checks, 18 communication checks and nine push checks passed
against the updated backend. One initial push run failed at its authorization
assertion; its root cause was not confirmed. A rerun on the same deployed backend
passed, after adding numeric-only diagnostics to the test helper. The failed log
is retained; these results do not establish flawless networking or capacity.

All 14 indexes remain READY. Actual automatic runs after activation returned
HTTP 200: push at 07:15 UTC and core maintenance at 07:16 UTC on 2026-10-25.
Both schedules remain active, and anonymous/authenticated database roles cannot
invoke either private signer. Four existing APK artifacts are hash-verified
unchanged. No phone registration was active at final verification.

The machine-readable summary, detailed checks and source/checkpoint hashes are
in the ignored `.usability-work-baseline/media-verification.json`; private setup
and backup files in that directory are not distribution artifacts.

## Still open before completion of the app

The subsequent [integration audit](full-app-integration-audit.md) records
the main/test path split and push investigation. Its road deletion/cache and
import concurrency findings now have [separate test-only fixes](road-maintenance.md).

Main-project migration/configuration and a coordinated compatible build remain
separate. The deployed proof remains limited to three synthetic accounts; it
cannot certify the whole main app as Spark-compatible. Validate the actual
phone's gallery/camera permissions, large images, connectivity loss, process
restart, repeated taps and account switching before calling native media done.
The same later build must also validate foreground/background push and taps.

Performance/stress acceptance (including B-05), adviser decisions on report
audience and retention, the separate project privacy email and deferred section
4.2 remain open. This phase does not settle those decisions or enable automatic
deletion. Main legacy photo audience/access and compatibility references need
their own review before any privacy flip or historical conversion.
