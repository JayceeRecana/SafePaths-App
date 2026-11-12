# Resident/admin interaction review - November 4, 2026

> Resolution later on November 4: F1-F3 are now fixed in shared source. The installed November 2/3 APKs predate these corrections. See the resolution record at the end; the findings below describe the reproduced pre-fix behavior.

Scope: the current shared reporting source, including the activated Marulas candidate and the nearby test build. This is a local source/widget review. No live data, cloud configuration, installed app, APK or runtime implementation was changed during this review.

## The intended information flow

1. The resident submits an observation with its time and any supporting photo. The saved report waits for admin review.
2. Opening the report reads it. Start review records a separate acknowledgement.
3. If evidence is unclear, the admin asks a specific private question. The report waits for the resident; an answer returns the same report to the admin review queue without awarding points.
4. The admin records an evidence decision. Verified means the observation was accepted; it does not mean the road is currently passable.
5. The barangay separately records a current road check, using its own CCTV, field confirmation or available verification. A report can be linked as supporting context without being the only way to update a road.
6. Residents receive saved private updates; push prompts them to open current information. A dated follow-up has its own reviewable report ID and links back to the original. Original evidence and rewards remain separate.

The core separation of observation, evidence review and current road condition is appropriate for the beneficiary's command-center workflow. Quick observations supplement the incident; they do not replace evidence review or authorize road reopening. NOAH remains modeled awareness context rather than road-update authority.

## Findings, in implementation order

### F1 - High: an admin draft can follow a different report through search or notification entry

`lib/screens/admin/user_reports_screen.dart` stores message text in one `_privateUpdateController`. List selection through `_selectReport` saves the previous report's draft and restores the newly selected report's draft. `_openReport`, used by ID search and notification entry, directly replaces `_selectedReportId` and `_directReport` without either operation.

Concrete path: write a private update for report A, cancel its dialog (the external controller keeps the draft), then open report B through ID search or a notification and choose to message its reporter. The dialog binds B's report ID but reuses the controller still containing A's text. A server cannot distinguish this from a deliberately written message to B; its ordinary permission checks do not prevent the content mistake.

Evidence: source trace of `_openReport`, `_selectReport`, `_sendPrivateUpdate` and the externally controlled `AdminReplyDialog`. This path was not exercised against a live backend during the review; do not describe it as an observed production disclosure.

Refinement: one report-selection transition for all entry paths, with report-ID-bound drafts. Preserve A's draft and open B with only B's draft. A late search response must not override a newer selection or an active save. Add real widget regression cases for list -> search, notification entry and repeated/same-report entry.

### F2 - Medium: selected historical report details can remain stale after another admin reviews it

The global report stream intentionally contains only pending, under-review and waiting-for-resident records. The history page is a paged snapshot. The inspector merges a selected snapshot with records that remain in the active feed but does not subscribe to the selected report document itself.

When another admin completes a report, that report disappears from the active feed. A selected history/ID-search snapshot can still show the former under-review/pending status and old available actions. The server's fresh review context and transaction checks prevent a duplicate evidence decision, but the screen can mislead the admin until refreshed.

Evidence: an actual-widget characterization test loaded a historical under-review report, changed its backing fake document to verified and removed it from the active feed. The open `AdminReportInspector` still showed under_review. The test passed by confirming the gap, not corrected behavior.

Refinement: subscribe only to the currently selected report while details are open, including history and notification entry. Keep its latest authoritative state even when it leaves the queue; show unavailable/retry when access or loading fails. Preserve current road context and keep actions consistent with the refreshed report state.

### F3 - Medium: a follow-up draft is lost on Back without a discard confirmation

`ReportFollowupScreen` uses `PopScope(canPop: !_saving)`. It preserves a draft across failed saves, but normal Back/navigation is allowed while unsent text, selected conditions or a photo remain. The draft lives only in the disposed screen. Clarification replies already have a more protective leave-confirmation pattern.

Evidence: an actual-widget characterization test entered a condition change and description, pressed Android Back, saw the route close without a confirmation, and reopened a blank form.

Refinement: consistently guard both header Back and system Back when unsent changes exist. Offer Keep editing / Discard draft, and bypass the prompt after a confirmed successful save. Preserve existing safe account-change clearing, read-only history behavior and busy-state guards. Do not add automatic private draft persistence without a separate need.

## Other observations

- The ask-question dialog has a similar cancel/Back draft-loss pattern; align it with the same leave-protection refinement after the resident follow-up case.
- The admin can read a report without starting review, and can send a factual acknowledgement without changing its evidence outcome. These are intentional separate actions; wording must continue to make that distinction visible.
- The test and Marulas follow-up switches intentionally differ. Test remains disabled, while the Marulas candidate enables follow-ups for controlled acceptance. That is configuration, not proof of a broken shared flow.
- Some early workflow documents begin with obsolete test-only rollout descriptions. A current-status note is needed before those historical sections so a panel explanation uses the activated main architecture.
- No new chat, analytics, scoring system or broad visual redesign is required to address the three findings.

## Validation and limits

- 53 selected existing Flutter checks passed for conversation refresh, clarification changes, failed-save draft retention, report decisions, follow-up forms, retry handling, account boundaries and notification entry points.
- Two additional local characterization checks reproduced F2 and F3. They are retained under `.usability-work-baseline/interaction-review-20261104/audit_test.dart`; these checks assert the observed gaps and are not acceptance tests for a fix.
- 67 backend unit checks passed for reporting/follow-ups, clarification round trips, permissions, idempotent decisions/rewards, typed notifications and main/test isolation.
- This review did not execute F1 against a live service, send a real report/message/push, rerun hosted acceptance, inspect an actual phone screen or implement the proposed fixes. Physical foreground/background notification delivery and simultaneous admin/resident acceptance remain separate.

Logs are grouped under `.usability-work-baseline/interaction-review-20261104/`. Fix F1 first, then F2 and the leave-protection pattern. Follow with one controlled report -> question -> reply -> decision -> road update journey on Marulas, including a second-admin update while details are open.


## Resolution - shared source, November 4

- All report entry paths now use one selection transition. It stores the outgoing report's draft and restores only the incoming report's draft. Same-report entry keeps its current text. Search responses cannot override a newer selection, and notification-driven opening waits until an active message/review interaction ends. Account changes clear the selected detail and in-memory drafts.
- The selected inspector now watches its own report document, independently of the active feed and paged history. A completed review stays visible with its current outcome when it leaves the queue. Missing/malformed records and stream errors replace the inspector with a recoverable unavailable state; Retry reconnects the selected document. A late cached missing document does not establish deletion.
- Follow-up Back, header Back and the admin question dialog's Cancel/Back now offer Keep editing / Discard draft when unsent changes exist. Text-only changes are included; busy saves and photo processing cannot be interrupted. Successful follow-up saves clear the draft before normal navigation. The confirmation fits enlarged English/Filipino text with the keyboard open. No additional private draft persistence was added.

Regression tests: `test/admin_report_interaction_test.dart` and `test/report_draft_exit_test.dart`. The earlier characterization tests in the review evidence folder intentionally assert pre-fix gaps and are retained as historical reproduction evidence; they are not part of acceptance for the corrected source. The existing inspector-list test now supplies explicit source/stream fixtures instead of depending on a failed backend lookup leaving a stale fallback inspector visible.

Verification: 702 Flutter tests passed, one optional benchmark skipped. A further 29 tests passed using `config/build/marulas.json`. Scoped analyzer output contains zero errors/warnings; informational style notices remain. Evidence is grouped under `.usability-work-baseline/interaction-fixes-20261104/`.

No cloud records/configuration or installed APKs were changed. Both app flavors share these client fixes; new release APKs are needed for phone acceptance. A running debug session should use a hot restart because report-selection lifecycle/state changed. Next device checks should exercise a second admin completing an open report, a notification arriving while drafting another report's message, and Keep editing/Discard from the resident follow-up form.
