# Feedback and broadcast communication

Implemented 2026-10-25 for the isolated `safepaths-test` / Supabase proof
environment. APK builds and installation remain on hold. Main Firebase,
billing and existing installers are unchanged. This extends the earlier
[report workflow](admin-resident-workflow.md) and [push sender](push-delivery.md).

## Feedback

Feedback ownership, initial status, timestamps and reviewer identity are now
assigned by the server. Submission validation rejects forged owner/reply/status
fields. A durable request receipt recovers a lost response without another
submission; a one-minute account cooldown limits new submissions.

Verified owners and authorized admins can read feedback. Another resident
cannot read it. Internal audits and retry records remain separate and
server-controlled. Private updates are append-only `feedback_messages`, paged
20 at a time. A legacy reply is retained when the new thread first receives an
update; missing legacy ownership or follow-up permission is not invented.

Opening review context is read-only. The dialog starts blank, keeps its draft
on save failure, and offers factual acknowledgement templates. Replying does
not silently close feedback. Closing requires a note, an explicit checked
outcome (addressed, recorded or duplicate), and confirmation. Recorded/duplicate
closure does not claim that a fix was implemented. Reopening is separate.

The reply, status, audit and optional notification event commit together. A
current admin role and the loaded record version are checked inside the
transaction, including on replay. Conflicting/stale reviews require refresh.
Optional notifications require an owned, allowlisted record with explicit
`allowFollowUp == true`. Missing/false consent suppresses optional contact;
the resident can still view the update in their own history.

## Broadcasts

Publishing validates title/message, severity, the fixed test study area, an
optional road link, and a validity period of 15 minutes to 24 hours. The author
and bounded eligible test recipients come from the server. One transaction
saves the alert, audit, retry receipt and optional per-recipient queue records.
Same-request retries recover the original publication and its original expiry.

Publishing never writes official road notes, status or verification timestamps.
Those changes require the explicit road-review workflow. Residents see active
scoped alerts; admins retain publication history. Withdrawal requires a current
context and a reason, preserves the record/audit, and suppresses pending work.
Expired or withdrawn alerts are shown as inactive when opened from a tap.

## Delivery and retries

The existing worker, device registration, account binding, leases, backoff and
expiry are reused. Report events retain compatibility. Feedback/broadcast events
have separate schemas and source authorization; no arbitrary client-controlled
recipient/body sender was introduced. New typed notifications have generic
copy, stable event/resource IDs and recipient binding. Private reply text,
screenshots and alert bodies are fetched through the current authorized record.

Broadcast device targets must have a matching registered study area. Older
registrations without area metadata do not inherit a broadcast audience.
Feedback/report updates use the private-update channel; broadcasts use the
alert channel. Separate collapse keys prevent feedback from replacing pending
report updates. Account changes are checked again on display/tap.

The scheduled drain reserves a slot for each available report/feedback/broadcast
class, with an oldest-record fallback, processing at most three events per run.
One publication cannot consume every available slot while report work is due.
Immediate attempts are still optional background work; scheduled retries retain
the existing five-minute cadence. Provider failures never undo a saved update.

The UI distinguishes saved/queued/provider acceptance from phone receipt. It
does not claim delivery or reading. A send already handed to the provider cannot
always be recalled, nor can the Firestore/FCM boundary guarantee exactly-once
delivery. Generic payloads and current-record checks limit stale disclosures.

## Controls and deployment

Native opt-in is `SPARK_PROOF_COMMUNICATIONS_ENABLED=true` under the pinned
`fieldtest` flavor/configuration. Push additionally requires the existing
`SPARK_PROOF_PUSH_ENABLED=true`. Main-project configuration is rejected.
No server key is embedded in a build. Media upload has separate
[test-only migration and acceptance](private-media-migration.md).

Managed `PROOF_COMMUNICATIONS_ENABLED=true` enables the typed routes and fair
queue reads. Firestore `system/communications.enabled=true` makes feedback and
alert writes server-only. App admins cannot modify that rollout control. Three
new queue/thread indexes must be READY before activation (14 total indexes).
Preparation backs up test communication data and tags legacy report queue
records without changing their state, recipients or scheduled times.

Disable new commands through the managed feature flag if necessary; already
queued valid work can still finish. Do not reopen broad client writes to bypass
a server failure. Preserve feedback, alerts and newer admin decisions when
recovering. No new scheduler or bucket is required.

## Verification and open acceptance

Local verification: 238 Flutter tests passed (one optional benchmark skipped),
35 tests passed with fieldtest/report/core/communication/push options enabled,
48 backend unit tests passed, and 80 emulator integration tests passed.
The new dialog fits a 360-pixel display at 1.8x text and retains drafts after a
failed save. Analysis has no compile errors or new warnings; four existing
warnings and informational/style findings remain. The actual Edge entry point
passes Deno checking.

All 14 indexes are READY and the rollout control is active. Eighteen hosted
communication checks passed, including actual owner/admin/peer access checks,
strict server-only writes, consent, stale reviews, reply/closure replay,
publication/withdrawal and unchanged official road fields. Both new payloads
passed actual Google validation-only requests. No active phone registration was
present, and no phone was targeted.

The existing hosted report-push suite passed all nine checks against this
updated backend, and the normal Dart report/photo pipeline passed all eight
hosted checks with one upload and two save attempts recovering the same report.
Actual scheduled runs after activation returned HTTP 200: push at 05:50 UTC
and core maintenance at 05:48 UTC on 2026-10-25. Both remain active; app roles
cannot execute either private signer. Local evidence is under the ignored
`.usability-work-baseline/communications-*` and `spark-proof-setup` files.
These checks establish test-backend acceptance, while phone behavior remains
open. Expiry affects validity/dispatch only; automatic record/photo deletion
has not been enabled. Native foreground/background delivery, denied permissions, taps,
restart, connectivity loss and account switching still require a later approved
phone build. The subsequent isolated [media migration](private-media-migration.md)
covers profile photos and feedback screenshots with its own acceptance evidence.
Performance/B-05, adviser privacy/retention/audience decisions and main-project
rollout remain separate gates.
