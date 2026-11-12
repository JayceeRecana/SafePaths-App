# Admin reporting notifications

Implemented 2026-11-02. The isolated `safepaths-report-proof` backend is ACTIVE at version 16. The Marulas handler contains the same implementation in source but was not deployed or activated by this change.

## Information flow

| Confirmed saved action | Recipient | Notification | Tap |
| --- | --- | --- | --- |
| Resident creates a new report | Eligible admins in that backend's area, excluding the submitting account | New report needs review | Exact report, with current review state |
| Resident answers an open clarification question | Eligible admins in that backend's area | Resident reply received | Same report, including its question and reply |
| Admin reviews, asks a question, or sends a private update | Original resident | Existing SafePaths report update | Current private report updates |

Push is a prompt to review saved information. It does not verify a report, change road status, award trust, confirm rescue dispatch or prove delivery. Road verification remains a separate deliberate action.

## Durable implementation

- New-report and clarification transactions save a server-owned parent event alongside the evidence. A report edit is not treated as a new report. Ordinary request retries do not create another parent event.
- The worker pages through twenty admin profiles at a time, using a validated document-reference cursor. Stable per-recipient event IDs and transactional cursor advances prevent repeated fanout.
- Each child uses the existing leased/retrying device sender. Recipient role, area, account eligibility and installation ownership are checked before delivery. Test recipients are additionally restricted to the existing synthetic UID allowlist; main recipients use current main-project membership checks.
- A notice requires the report to remain pending and its saved admin work ID to match. Starting/completing review or a newer clarification answer suppresses obsolete pending notices. An already accepted notification cannot be recalled; tapping always loads current server information.
- Audience failures retain durable retry work without undoing the resident's submission. Events expire after one hour; evidence and pending work remain in Reports even when push is delayed, expires or fails.
- Push payloads contain routing IDs and generic copy. Photos, private replies, exact coordinates, report descriptions and road names are not included. The road is shown after authenticated report loading.
- The existing sender schedule and private report notification channel are reused. No public topic, new database, scheduler, bucket or trust award was added. Phone delivery and every-event delivery are not guaranteed; the review queue remains authoritative.

Production handlers opt into `adminNotices`. The reusable handler/producer defaults remain off for older isolated fixtures and explicit rollback. Rolling back that option stops creation of new work; already queued valid work may still finish. Do not weaken client-write rules.

## Verification

Evidence folder: `.usability-work-baseline/admin-report-notices-20261102/`.

- 131 backend unit checks passed, including paging beyond twenty admins, concurrent expansion, obsolete events, foreign/revoked admins, account transfer/logout, expiry, private payloads and encoded cursor validation.
- 78 Firestore/Auth emulator integration checks passed. The new complete journey proves saved submission -> admin event -> clarification -> resident reply -> second admin event, idempotent retries, unchanged trust, and REST cursor paging. Push transport is faked; no real notifications are sent by these checks.
- 25 Flutter checks passed for account matching, registration, existing resident tap behavior and both admin notice types routing to the exact report. Repeated taps increase the report-open revision.
- Scoped analysis of account matching and its tests: no issues after lint cleanup.
- Test-only deployment succeeded; function list confirms version 16 ACTIVE. A read-only GET to `/submit-report` returned the expected 405, verifying handler startup without creating records or notifications.

Remaining device acceptance: notification permission denied/enabled, foreground/background/terminated app receipt, tap to the correct current report and logout/account changes. Use authorized test accounts and a deliberately submitted test report. No live report, real push test, main deployment, APK build or running-app reload was performed automatically.


## Marulas candidate rollout ? November 2, 2026

The user subsequently approved the separate Marulas setup. `safepaths-main` version 1 is active for controlled testing with the matching Marulas candidate APK. New dated follow-up reports also enter the durable admin-notice flow, using their own report ID and the existing ?New report needs review? notice. The main feature is no longer source-only; real-device receipt remains unaccepted. See [the main rollout record](marulas-main-integration.md).
