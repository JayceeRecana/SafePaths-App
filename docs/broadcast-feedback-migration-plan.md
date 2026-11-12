# Broadcast and feedback communication migration plan

Proposed 2026-10-25; subsequently implemented and hosted-verified in the
isolated test environment. See [results and remaining acceptance](communication-migration.md).
The steps below are retained as the agreed plan. Keep APK builds on hold. Start in `safepaths-test` and the existing
isolated Supabase function, with the current synthetic-account allowlist.

## Current findings

| Path | Current behavior | Required change |
| --- | --- | --- |
| Feedback | Admin directly updates the feedback, then calls the legacy notification function. The history screen queries the owner's feedback, but rules allow only admins to read it. Notifications include the reply text; the UI can call provider acceptance delivery. | Authenticated server actions, owner-only history access, private replies, truthful status and durable notification retries. |
| Broadcast | Alert creation and the optional push are separate. A lost response can lead to another alert on retry. Linked alerts overwrite road notes and `updatedAt`. | Atomic alert/outbox save, durable request IDs, explicit audience/expiry and no implicit road verification changes. |
| Shared sender | Both use `BackendService.call('sendNotification')`. The tested replacement sender currently validates report-specific ownership/messages. | Extend it with separate, validated feedback and broadcast event types; do not make it a generic client-controlled recipient/message sender. |

## 1. Feedback first

- Add server-confirmed feedback submission and administrative review/reply
  operations with strict field validation, live admin-role checks, durable
  request receipts, version/conflict checks and audit records. Clients must not
  supply an authoritative owner, admin reply, review status or reviewer identity.
- Make submission ownership server-assigned. Allow verified owners to read their
  own feedback/history; peers cannot read it. Keep internal audit data separate
  from resident-visible replies. Review existing records without inventing an
  owner or follow-up consent where none exists.
- Save reply/status and its notification event in the same transaction. Preserve
  the reply in history when push is unavailable. A reply and resolution are
  separate actions; sending a reply must not silently mark an issue fixed.
- Respect `allowFollowUp` for optional contact/push. Default missing consent to
  no optional contact. Anonymous/unowned records receive internal review only.
- Start replies blank. Replace unverified claims about fixes, road crews and
  dispatch with factual acknowledgement templates. Require an explicit outcome
  and note when resolving feedback.
- Use generic notification text and an identifier. Fetch the authorized current
  feedback when tapped, with account-switch protection. Never put the private
  reply or screenshot in the notification payload.

## 2. Broadcasts second

- Add an admin-only publish operation that atomically records one alert, audit
  and optional notification work. Derive the author and eligible recipients on
  the server; validate severity, study area, linked road and validity period.
- Preserve request IDs after uncertain saves. Retrying the same publication
  must not create another alert or another ordinary notification event.
- Show the saved alert in the in-app feed even if push fails. Display expiry,
  and suppress expired/withdrawn notification work. Notification taps fetch the
  current alert rather than trusting old payload text.
- Link broadcasts to roads without overwriting official road notes or refreshing
  road verification timestamps. Road condition changes use the existing explicit
  road-review workflow.
- For this small capstone test, use bounded delivery to eligible registered test
  accounts/devices in the intended area. Do not reuse the legacy topic send as
  an unrestricted replacement. Keep bulk work from starving report updates.

## 3. Reuse and protect the proven delivery infrastructure

Reuse verified device registration, leases, retry/backoff, expiry, account
binding and the existing protected scheduled worker. Add event-specific
authorization and payload validation while preserving existing report events.
Record saved, queued, provider-accepted, unavailable and expired states
accurately. Provider acceptance must never appear as confirmed delivery or read.
Retain in-app access independently of push.

Test permissions, consent, stale reviews, two-admin conflicts, response loss,
duplicate retries, expired alerts, notification failure and account changes.
Rerun report-communication regressions after extending the worker. Hosted checks
use synthetic accounts and validation-only provider checks before phone testing.
Record added operation counts against the existing project budgets.

## Completion gate

Close implementation only after local/emulator and hosted checks pass for both
paths and existing report delivery remains correct. Then perform the approved
phone acceptance: foreground/background/taps, denied permissions, restart,
connectivity loss and account switching. Main-project rollout is separate.

The subsequent [screenshot/profile media migration](private-media-migration.md)
has separate isolated-test acceptance. Adviser privacy/retention/audience
decisions and main rollout remain open. Do not widen media access or claim
screenshot upload acceptance as part of a notification-only check.
