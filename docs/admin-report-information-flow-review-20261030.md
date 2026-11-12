# Admin report information flow and workload review - 30 October 2026

This document retains the initial audit, followed by the implementation record below. The workflow changes are now implemented locally and tested. Hosted backend, index/rule deployment and paired-device acceptance are still outstanding.

## Intended journey

Resident records what they observed (road/location, flood condition, notes, photo where supplied and observation time) ? confirmed submission becomes Needs review ? admin checks that exact evidence against current road information ? a reasoned outcome is saved ? resident sees that outcome and any next step in the same report history ? the report remains traceable after the road condition changes.

Observation verification and current road passability are distinct facts. An old true photo cannot establish that the road is still flooded or now passable. Current restrictions must not be cleared because evidence is old, a resident says it looks passable or a report is dismissed.

## Confirmed strengths

- Reports are directly accessible from admin bottom navigation and dashboard cards open an identified inspector.
- Pending/under-review reports come from an uncapped active query; history uses 30-record pages. The active pending feed is not limited to one history page.
- Badges distinguish Needs review, Under review, Verified, Reviewed, Dismissed, Outdated and correction outcomes.
- History groups by submission date, shows observation time separately when different, and retains reviewed/dismissed records.
- The inspector separates this report's outcome from the current road state; technical IDs/trust/coordinates are under More details.
- Review/dismissal reload current context; the backend rejects stale or already-reviewed decisions, requires current-condition verification for road review, and validates dismissal reasons.
- Outcome history and resident messages already exist; notification receipt alone is not an authoritative outcome.

## Findings and implementation order

These are the **original audit findings**, written before the implementation. They are retained to explain why the changes were made. Current status:

| Finding | Current status |
| --- | --- |
| 1. Unclear evidence has no suitable decision path | Implemented locally: private clarification request/reply, optional supporting photo, no-penalty unable-to-verify outcome, and observation-only verification. |
| 2. Queue priority differs | Implemented locally: Dashboard and Reports share urgency-first, oldest-work ordering. |
| 3. Lifecycle filters and paging | Implemented locally: Review queue / History, status filters before pagination, optional last 48 hours and exact report-ID lookup. Free-text road/person search is deferred. |
| 4. Review and road rechecks are mixed | Implemented locally: report outcomes and current road checks are separate; reopening a road leaves other reports awaiting their own decision. |
| 5. Review progress is hidden | Implemented locally: visible Start review, Under review filter and recorded review-start event. Staff assignment/ownership UI is deferred. |
| 6. Notifications lose report context | Implemented locally: validated report-ID navigation, direct fetch outside the loaded page and repeated-open support. |
| 7. Empty queue freshness is unclear | Implemented locally: report-channel live/cached/unavailable wording and unknown counts instead of assumed zero. |
| 8. Related records and follow-up rollout | Still open: follow-ups remain disabled, and broader related-report grouping is deferred. Original-report clarification is implemented separately. |

All implemented items still require matching test-backend/rule/index deployment and paired resident/admin acceptance. Local test results appear below; these statuses do not claim availability in the installed app.

1. **Decision gap for unclear initial evidence.** Original-report dismissal only offers duplicate/already handled or confirmed false/spam. The needs_correction path is restricted to follow-ups in both UI and backend, and follow-ups remain feature-gated. Lack of sufficient evidence is not proof of dishonesty. Design a complete, no-penalty clarification path for initial reports, including the resident's ability to supply the requested evidence and the admin's ability to see that revision. Do not merely add a button or change a label. The current standard edit action covers flood level/notes; it is not a complete replacement-photo correction loop. Preserve observation timestamps, previous evidence and retry identity. Decide explicitly how a truthful historical observation is recorded when today's road condition cannot be confirmed; do not force a current-condition claim to close a report.

2. **Queue priority differs across entry points.** Reports puts emergencies first, then actionable records, then live confidence. Dashboard puts pending before under review, then confidence, and shows three records. A reviewing urgent request can therefore be absent from the dashboard's first three records. Use one shared transparent workload policy. Keep urgent assistance visibly prioritized; use waiting time for review workload rather than relying on confidence, which incorporates authority/photo/age/weather/consensus. Confidence may inform evidence review but must not quietly starve older or lower-trust submissions. Keep submission age and observation freshness distinct.

3. **Lifecycle organization is not directly selectable.** Current main views are Needs attention, Last 48 hours and All reports. There is no direct Verified/Dismissed/Under review selection or report search. Recent 48 hours explicitly removes dismissed reports after fetching a history page, which can leave an apparently empty page even when other relevant records are later. Use a simple review queue plus history, with a status/date filter when needed. Apply status filters before pagination; filtering only a loaded page is insufficient. Keep precise Verified and Reviewed meanings distinct.

4. **Report review and road rechecks are mixed.** Needs attention includes completed reports when a matching road incident needs verification, but the live feed mostly contains active reports, making this behavior dependent on which completed records are present. Separate report decisions from road-condition checks. Keep access to road rechecks without making an already verified report appear unverified again. The existing road-reminder section follows report cards, so ordinary reminders do not bury reports.

5. **Review progress is too hidden.** Start review is inside More details. Make it visible near the report status. The backend already stores reviewStartedByUid, but UserReport does not expose it; do not invent assignment/ownership from the current client model. A small in-progress filter and actual review-start age should precede any elaborate team assignment system.

6. **Direct notification context can be improved.** AdminHome currently switches to Reports for report-type notifications and does not select the payload's report ID. Wire exact-record navigation using validated payload identifiers and a safe direct fetch for completed records outside the live feed. Keep the resident-side account-scoped report update path intact.

7. **Empty queue must distinguish freshness.** Global SyncStatusBanner already exists and can warn that live updates are unavailable. Its wording and last-sync detail emphasize roads; the report queue itself still shows a generic empty state while its report channel may be connecting/cached/failed. Add report-specific loading/saved/unavailable wording, so a count of zero is not mistaken for a confirmed empty workload. Do not claim there is currently no global sync warning.

8. **Related records and follow-ups need honest scope.** Linked follow-up UI exists, but the test build's follow-up rollout remains disabled. Do not present the complete follow-up/correction loop as live acceptance. Later, group related road/incident records for context without merging separate residents' evidence or auto-verifying them.

## Smallest coherent improvement

Use two clear areas: a review queue (new/in-progress, urgent/age visible) and report history (outcome/date filters). Keep road checks separate. In each inspector show evidence ? current road information ? decision ? resident-facing reason. A missing-evidence case stays an explicit, tracked clarification task rather than a false/spam dismissal. Save/notification/history all refer to the same report ID. Delay charts, bulk approval and elaborate assignment until this journey is understood by an unfamiliar admin.

Suggested panel explanation: ?Residents submit observations with evidence and time. The barangay reviews the evidence and checks current conditions, records a reasoned outcome and sends the resident an update. The report history keeps that decision, while the road's current status is maintained separately.?

## Initial audit verification (before workflow implementation)

The reporting recheck initially passed 58 of 59 tests and exposed a duplicate Expired translation key introduced with the recent alert catalog. The duplicate was removed from admin_alerts_fil.json, retaining the existing shared translation. All 16 affected accessibility/catalog tests then passed, giving 59 distinct reporting/date/inspector/history/accessibility checks passing across the review runs. No report queue, approval/rejection logic, backend rule, feature flag, production deployment, APK or automatic reload changed in this review. The only runtime-source correction was the duplicate translation entry.


## Local implementation - 30 October 2026

The reporting journey now has explicit next steps:

1. A resident submits their observation with its original evidence and time.
2. The report enters the Review queue. Urgent requests come first, then oldest submitted work. Dashboard and Reports share this ordering. Opening a report is distinct from starting its review.
3. The admin can verify the observation, request clarification, or record another decision with an explanation. Unable to verify and duplicate submission do not deduct trust. False/abusive decisions retain their existing explicit safeguards.
4. A clarification request moves the report to Waiting for resident. The original reporter can open the private request, reply and optionally attach supporting evidence with its own observation time. The answer is appended; it does not replace the original photo, date or description. It earns no additional points.
5. A confirmed reply returns the same report to Needs review with a Resident replied badge. The private history retains the question and answer. This is a focused clarification exchange, not unrestricted chat. A subsequent clarification round requires another admin request.
6. The admin records the outcome and the resident sees it on the same report. Verifying a historical observation does not require changing today's road condition. A separate, explicit current-condition check is required to update the road. Reopening a road does not complete other residents' reports.

Residents reach a requested clarification from Report History or the report opened from its notification. Admins reach it from the inspector's clarification action. Existing report messages remain private to the reporter and authorized admins. Other residents cannot reply on someone else's report. A resident reply becomes visible in the live review queue; this pass does not add an admin push notification for each reply.

Old observation age and unfinished review are separate: the risk worker excludes old evidence from current risk calculations without automatically closing pending reviews. Existing legacy expired records are retained; no historical backfill was run. New reports use explicit observation timestamps. Legacy records without observedAt are not included in the new bounded current-evidence query and need assessment before any production migration.

### Organization and small analytics

- Review queue: needs admin action, new, under review, waiting for resident or all open work. Urgent requests remain visible even while waiting for clarification.
- History: completed records with outcome filters, optional last 48 hours, and server-side filtering before pagination. Exact report-ID lookup and notification links can open records outside the loaded page. This is not free-text road/person search.
- Workload summary: counts from the complete open feed, urgent requests and the oldest report still requiring admin action. Cached or unavailable data is identified; unknown workload is not presented as zero.
- Today's activity: on-demand server aggregate counts for reports submitted today and currently completed records whose latest reviewedAt is today, using the device's local calendar day. These are report counts, not incidents, rescue completions, unique residents or an audit-event total. A checked timestamp makes the snapshot explicit. Clarification replies do not count as new reports. Summary counts do not yet offer a day-specific drilldown.

### Backend and rollout requirements

No hosted deployment, APK build, installation, automatic reload or database backfill was performed in this pass. Existing hosted builds do not yet provide this full exchange.

For an isolated test rollout, deploy the updated Spark proof function modules and test-project Firestore rules/indexes, wait for indexes to become ready, then use matching admin and resident clients. Check that admin context advertises workflowVersion 2 before exercising clarification or observation-only verification. New dialogs gate these features on that version. New history filters also require their indexes.

Coordinate both clients with the backend: older dismissal clients may omit the newly required explanation and will be rejected. Older clients do not understand Waiting for resident. Do not apply these backend changes to the main project while relying on older admin/resident builds. Keep the existing test allowlist and follow-up feature flag unchanged. Follow-ups for later observations remain separately gated; this clarification feature does not enable that rollout. Automatic retention/deletion and the unresolved privacy policy decisions remain unchanged.

### Acceptance sequence still required on the hosted test environment

1. Submit a new resident report and confirm the same ID appears in the admin queue.
2. Start review; request a clear explanation without changing road status. Confirm the resident receives the private request.
3. Reply as the original resident, first with text and then in a separate request with a supporting photo/time. Confirm the original photo/time are intact, the reply is visible to admin, the badge changes and trust is unchanged.
4. Retry after an uncertain network result. Confirm one saved reply only; reject another account and reject a reply after the admin has completed that request.
5. Verify an old true observation with current-road updating off. Confirm the road is unchanged, the review/outcome appears privately, and the reward cannot be duplicated.
6. Reopen a road after a current check. Confirm other unresolved reports remain open. Exercise unable-to-verify and duplicate outcomes with private explanations and no penalty.
7. Exercise status/history paging, offline queue wording, on-demand activity counts and repeated notification opens. Confirm recipient, report ID and private photo access on both devices.

Local validation: the complete Flutter test suite passed 534 tests with one skipped; all 100 backend tests passed. Narrow-screen, light/dark and large-text/localized coverage is included. Four rendered screens (review queue light/dark, expanded workload and resident clarification) were visually checked. The render harness also passed. These checks do not replace Firestore index/rule deployment or hosted and physical-device acceptance. Logs, renders, baseline comparison and file hashes are grouped in `.usability-work-baseline/report-workflow-20261030/`.

Panel explanation: Residents submit observations with evidence and time. The barangay reviews each report, can ask its reporter for clarification, and records a reasoned outcome. The resident sees the request and outcome on the same report. Current road passability is checked and maintained separately, so confirming an old observation does not claim that the road is safe now.

Static analysis of the changed Dart files found no errors, one pre-existing unused `_LegendRow` warning and 99 informational style notices. The skipped Flutter test is the opt-in host map projection benchmark.


## Reporting UI refinement - 30 October 2026

The admin queue now groups its filter and connection state in a rounded card. Workload rows use an icon, readable label, count and chevron; activity remains on demand. History groups outcome/date controls and offers an expandable Find report action so lookup does not occupy the list by default. Lookup validates the copied reference and shows loading or failure feedback beside its field.

Each report exposes a Report reference on the resident history card, admin list card, inspector and submitted-report preview. The long reference is abbreviated for display only. Copy preserves the complete existing report ID, which can be pasted into History > Find report. This adds no new identifiers, backend lookup scheme or change to ownership checks. Clarification continues to use the original report's reference.

The clarification page now shows a private-conversation header, the barangay question, the resident reply where present, and a separate composer when the server permits a reply. Questions and replies use different icons and surfaces with one timestamp per message. Supporting images retain their own observation time. Admin questions have a matching dialog with a clear question field and Send question action. The private message history also distinguishes the speakers.

Validation for this UI refinement: 75 affected Flutter tests passed, covering reference copying, invalid lookup feedback, failed-save draft preservation, read-only answered requests, report dates/paging, localization, narrow screens and 200% text in both themes. Rendered previews use sample data and actual Flutter widgets. They can be reviewed on this computer without an Android phone. Current-pass evidence is grouped in `.usability-work-baseline/report-ui-20261030/`.

This UI pass does not deploy the backend or rules/indexes, build an APK, install a client or reload the user's Flutter terminal. Hosted clarification acceptance remains on the rollout checklist above.


## Inspector decision-context review - 30 October 2026

Useful evidence context is now visible in the main resident-evidence section: resident-selected flood level, observation/submission times (combined only when the recorded minute matches), any later edit/photo submission time, reported coordinates and available reporter/trust context. Trust is described as reporting history rather than proof of this observation. Missing or invalid metadata remains explicit. Unnamed roads also show their road reference; the report reference remains copyable. Raw IDs and correction diagnostics stay under Technical details.

The report-outcome and latest-recorded-road cards now have equal widths/heights and aligned headings/status text, using measured heading height rather than assuming one line. A divider and stronger section heading distinguish the resident submission from the road information above. The duplicate embedded Road updates panel was removed. A link opens the road and community details separately. The recorded-events section stays because it preserves the distinction between the reviewed observation and a later road update.

Additional gaps addressed in this pass: unverified road records show Unconfirmed in the comparison card; unconfirmed road-update time receives a warning; future observation time is distinguished from old evidence; missing/invalid coordinates are not shown as a valid location; and the final verification dialog displays the freshly loaded observation/submission context and a direct clarification link. Returning from clarification reloads that review context and resets its confirmation controls. No backend decision/reward/road-status logic changed in this UI pass.

Validation: 83 affected Flutter tests passed, including equal comparison-card sizing and text alignment, evidence context visibility, invalid/unknown data, future-time wording, separate historical and current states, review actions, pagination, localization and large text. Static analysis reported no errors or warnings (23 informational notices remain). The native Flutter render harness passed, with previews grouped in `.usability-work-baseline/report-inspector-20261030/`. Sample attachments and identities were used; these images are design previews rather than live reports.

The existing follow-up submission/history UI was also rendered for review. It already uses separate linked follow-up records. Its feature gate remains disabled; no flag, APK, hosted backend, index/rule deployment or user-owned Flutter terminal was changed by this pass. Clarification replies remain on the original report and do not enable follow-up submissions.


## Road-update form refinement - 30 October 2026

The current-road update dialog now uses three explicit steps: set the new road status, describe the check, and confirm the check. The status being selected is the primary visual element, with larger text, a status icon, tinted fill and a colored border. The latest recorded condition remains a smaller reference summary with road identity and available timestamp. This prevents the saved record, unsaved selection and written findings from reading as one undifferentiated block.

Field headings are outside the controls, so long floating labels no longer truncate. The minimum note length appears beside its counter, public/private visibility wording follows the note, and the current-check confirmation is on the left. The save label describes the selected task: Save road status, Verify observation, or Verify and update road. The v2 observation-only switch and the distinctions between original reports and follow-ups are preserved.

Behavioral safeguards remain: the current recorded condition is not preselected, at least ten characters of findings are required, changing condition/findings resets confirmation, a refresh resets stale condition/confirmation, uncertain saves retain the draft, and saving blocks duplicate actions/dismissal. A road-only save continues to send road_review with road IDs and current-verification confirmation, rather than a report-verification request.

Validation: 53 affected Flutter tests passed, including the road-only save payload, explicit condition choice, refreshed contexts, retries, report verification, original/follow-up safeguards, small-screen layouts, both themes and large English/Filipino text. Static analysis found no errors or warnings (7 informational notices remain). Rendered initial, filled/confirmed and dark-mode previews passed the Flutter harness and were visually checked using sample data. Source baselines, changes and evidence are grouped in `.usability-work-baseline/road-review-ui-20261030/`.

This is a local UI change. No backend/rule/index deployment, follow-up flag change, APK build, installation or automatic hot reload was performed.


## Optional report-to-road reference and full-flow check - 30 October 2026

The beneficiary's command-center monitoring and field checks are independent sources of current road information. Resident reporting assists that work where coverage is incomplete. An authorized admin can update a road directly without any resident report. SafePaths does not require access to the barangay's CCTV footage.

The implemented journey is:

1. A resident submits an observation, photo and observation time. Its submission time is recorded separately. Submission alone does not change the verified road status.
2. The admin opens the original report and can explicitly start review. If evidence needs clarification, the admin asks a private question. The original resident can reply with text and an optional supporting photo/time on that same report ID. The report returns to the review queue; original evidence and trust remain unchanged.
3. The admin records a reasoned evidence decision. Observation-only verification can confirm a truthful earlier observation without changing today's road status. A current road update requires its own explicit condition, findings and current-check confirmation.
4. When Update road status is opened from Report details, the form retains that report reference automatically. The admin does not type an ID. Saving records the reference in the private admin audit and adds a private update to that report's existing conversation/outbox. It does not verify that report, overwrite its observation, or award more points. Combined verification-and-road-update actions already retain their original reportId; the new optional sourceReportId covers a separate/later road update.
5. When the admin instead opens Roads and records a CCTV/field check, the same current-condition safeguards apply without a report reference or a fabricated resident report.

Backend safeguards bind the source reference and its road to the loaded context. Missing, changed, deleted, wrong-road, bulk and ambiguous references are rejected. Retry receipts return the original saved result without duplicate rewards/messages. The reference is not added to the broadly readable road document. Private message access remains owner/admin only; admin audit access remains admin only.

The new client checks that the backend explicitly supports retaining the reference and confirms it in the save response. An older backend blocks this linked save with an explanation instead of silently dropping the reference. A matching backend/client rollout is therefore required for online use. Direct road updates and ordinary report review do not require the optional link.

The full local journey test exposed a real clarification defect: the Firestore REST writer supported server timestamps at top level only, but clarification replies store repliedAt inside their response map. The transaction could fail before committing. The writer now emits nested Firestore server-timestamp transforms. The real-emulator journey verifies a text/photo reply, stored observation time, matching server reply timestamps, original evidence preservation, return to queue, observation-only verification, later linked road update, private history/outbox, owner/admin access and duplicate-safe retries. A separate real-emulator test verifies direct monitoring with zero resident reports. Existing checks also exercise verification with a current road update, dismissals and conflicting/stale decisions.

Validation for this pass:

- Complete Flutter suite: 548 passed, one skipped opt-in host map benchmark.
- Backend unit suites: 107 passed.
- Current Spark proof suite against local demo Firebase Auth/Firestore/Storage emulators: 75 passed. Its photo service uses a Supabase protocol fixture and push delivery uses a provider fixture; this does not prove hosted photo storage or physical-phone push delivery.
- Changed Dart files: no static-analysis errors or warnings; 27 informational style notices remain.
- Native Flutter previews: linked/direct forms and a filled dark-theme form rendered and visually checked at a 360-pixel viewport. Preview fixtures are sample data.

Evidence and baselines are grouped in `.usability-work-baseline/report-road-link-20261030/`. No main-project changes, hosted backend/rule/index deployment, APK build, installation, feature-flag change or user-terminal reload was performed.

Remaining acceptance: deploy the matching isolated test backend/client and any earlier workflow rules/indexes, then repeat resident submission, clarification text/photo, evidence decision, linked current-road update and direct CCTV/field update online. Check private recipient/report identity, current map status, duplicate-safe reconnects and actual Android notification/photo behavior. Follow-up submissions remain disabled. A locally correct workflow is not a claim that the installed APK already contains this pass.

Panel explanation: Residents provide observations with evidence and time. The barangay reviews those observations and can ask for clarification. Authorized staff maintain current road conditions using their own checks. When a report prompts a road update, SafePaths keeps the connection and informs that resident, while preserving the original report and its review outcome.


## Reporting UI entry-point audit - 30 October 2026

This is a read-only runtime-code trace of the normal app entry point (`lib/main.dart`, including the fieldtest flavor). It does not prove which revision is installed on an emulator or phone, and no UI was changed or reloaded during this audit.

| Entry point | Current UI used | Finding |
| --- | --- | --- |
| Resident Reports tab and Profile > history | ReportHistoryScreen > ReportHistoryCard | Uses the revised cards, progress/outcome, copyable reference and separate update launcher. |
| Resident history > report updates | ReportMessageThread > private updates page > AdminUpdatesContent | Uses the revised submission preview and private timeline/header. |
| Admin Reports / notification / Dashboard report tap | UserReportsScreen > UserReportCard > AdminReportInspector | Uses the revised queue/history and inspector. Dashboard cards route into that same inspector. |
| Verify observation and Update road status | showAdminReview > AdminReviewDialog | Uses the revised decision/current-condition form; inspector road updates pass the optional source report reference. Direct road updates use the same form without a reference. |
| Ask for clarification and resident question/reply | AdminClarificationDialog / ReportClarificationScreen | Uses the revised question/reply UI and current workflow service. |
| Road details > Community updates > report item | ReportDetailsBottomSheet | Older separate evidence sheet remains reachable. It retains a different information hierarchy, profile/trust presentation and technical proximity wording. Its dormant isAdmin diagnostics branch is not used by the only normal-app caller, which passes no isAdmin argument. This is not the revised admin inspector. |
| Resident report notification | ReportUpdateScreen | Older intermediary page remains reachable from UserHomeScreen. It shows title, description and review summary, then requires a second tap to reach the revised private updates page. It is not a wholly old conversation implementation, but the extra page is inconsistent with opening updates directly from history. |
| Message reporter, complete without verification and edit own report | AdminReplyDialog / AdminDismissDialog / ReportHistoryScreen edit sheet | These smaller forms use the current service/guards but remain simpler visual layouts than the redesigned inspector/current-road form. Classify as visual alignment work rather than evidence of an obsolete verification backend. |

Recommended refinement order: align the notification entry with the existing updated report-update experience while preserving live owner/account checks, error/cache handling and current-road context; align the read-only community evidence sheet using existing submission-preview components without exposing private conversations to other residents; then align the smaller action forms. Keep resident/community access and authorized-admin actions distinct. Do not indiscriminately replace the public evidence viewer with the admin inspector.

The legacyReplies parameters in the current timeline intentionally display previously saved messages inside the updated UI. They are data compatibility, not an alternate old reporting flow. `main_spark_proof.dart` is a separate diagnostic entry point; the documented live app launch uses `main.dart`.

Conclusion: the principal reporting journey uses the revised interfaces, but complete UI consistency is still open. The earlier local workflow-logic validation remains separate from this UI audit. No additional test run is claimed for this read-only route trace.


## Reporting UI consistency implementation - 30 October 2026

The remaining normal-app entry points identified in the preceding audit are now aligned locally:

- Report notifications retain the live report/owner and current-road subscriptions and open the same ReportUpdatesPage used by history directly. The separate title/description/summary landing page and second conversation tap are removed. A compact review/current-road summary remains available inside the updated page. Cached information and unavailable/unverified/changed-account cases remain explicit. The page starts listening when the report receives its first server update while it is already open, and clears its paged message state when its query identity changes.
- The community report viewer on road details now uses the shared rounded panels, action heading, theme colors, readable observation/submit times and distinct resident-evidence section. It remains a read-only community viewer without private messages, reporter-profile/trust panels or admin diagnostics/actions. Original private report evidence remains available through the owner/admin reporting paths. A retained earlier photo is labeled when the recorded times support that distinction.
- Message reporter, complete without verification and ask-for-clarification forms share ReportActionDialog and a copyable report reference. Long message presets wrap and the dismissal explanation has its own external label. Existing services, outcomes, penalties and confirmation requirements are retained. Refreshing dismissal details now clears the old context before loading so a failed refresh cannot enable a stale save.
- The resident's edit sheet uses the same heading/panel/reference language and a bounded scrollable layout with keyboard padding. It explains that corrections to this observation and a new dated observation are different tasks. Account-switch handling and late-save dismissal behavior are retained.

No backend, rule, index, reward policy, report-visibility policy, follow-up flag, APK or deployment changed in this UI pass. Older saved messages still appear through the current timeline compatibility path. The separate diagnostic main_spark_proof entry point is not the normal app launch.

Validation: the complete Flutter suite passed 554 tests with the existing optional host map benchmark skipped. Seven focused entry-point tests then passed, including one additional narrow-screen/keyboard edit test added after the full-suite run (555 distinct app tests passed across those runs). The focused tests exercise actual Firebase-facing widgets through local platform fixtures, owner transfer/account and verification changes, missing records, cached information, first live admin messages, failed-stream recovery, failed-save drafts, failed-refresh save blocking, public/private control separation, and 320-pixel/200% text layouts in English/Filipino and both themes. These fixtures do not assert hosted Firebase or physical-device delivery acceptance.

Five native previews (community light/dark, notification content, private message and completion decision) were rendered and visually checked. The render harness passed; it manually loads cached app fonts and logs Google Fonts asset-discovery notices in the test environment. Preview data are synthetic. Current-pass baselines, diff, verification logs and previews are grouped in `.usability-work-baseline/report-ui-consistency-20261030/`.

Final static analysis of the changed Dart files found no errors or warnings; 21 informational style notices remain. File hashes are recorded with the current-pass verification evidence. The user's running Flutter terminal was not reloaded; visual acceptance on that running app and the previously documented hosted/device workflow acceptance remain outstanding.


## History-control visibility correction - 30 October 2026

The shared history controls no longer advertise Page 1 before the first successful load. Pagination is hidden while a request is loading, and single-page histories hide it by default. Actual multi-page histories retain Newer/Older navigation. An initial failure shows the recorded error and an explicit Retry action. A standalone refresh remains available on resident history when no pager is needed; admin history keeps its existing header refresh. Cached-history wording remains visible and does not fabricate another page.

Validation: 59 affected Flutter tests passed, including loading/failure/retry, empty and cached single pages, older/newer navigation, admin list/date grouping, resident history, account switching and enlarged-text controls. Evidence is grouped in `.usability-work-baseline/report-history-controls-20261030/`. This corrects presentation; it does not establish the cause or resolution of the live History could not be loaded request shown in the screenshot. No backend/deployment/build/reload occurred.


## Admin Dashboard and Roads workflow refinement - 30 October 2026

Dashboard now prioritizes three actionable workloads: urgent open reports (including urgent cases waiting for a resident), reports needing admin action, and roads needing a current check. Each opens its matching queue/filter. Reports awaiting a resident have a separate shortcut. Report cards use the shared urgency/oldest-work ordering and are labeled Reports needing attention rather than Recent Reports. Find a road accurately opens road search. A map shortcut opens the existing current-condition review form after the existing admin-role check. Technical tools, reporter records, weather simulation, network rebuilding and recorded diagnostics/activity are in a secondary Advanced tools page.

Dashboard and Roads share AdminRoadAssessment and ReportWorkload. Road presentation distinguishes a recently confirmed passable record, recorded partial/not-passable restrictions, and unconfirmed passability. Recorded restrictions remain visible when old and receive a recheck warning. Unverified/unknown/future-time or due-for-recheck passable information is not presented as recently confirmed passable. Current model inputs and RiskConfig thresholds drive this read-only projection; it does not mutate road records, weather data, routing policies or report outcomes. Predicted risk is a separate label and an old prediction is identified as saved. Network summaries and filters use the same categories. Report counts include pending and under-review work and distinguish waiting-for-resident cases. Connecting/unavailable feeds with no applicable active data display an unknown count rather than zero; retained data have an explicit freshness notice.

Roads has six main filters: All roads, Needs a check, Not passable, Partially passable, Unconfirmed and Passable. A high-vulnerability Flood-prone roads only filter is secondary and does not stand for a verified closure. Search accepts a name or road reference. Status, update age, predicted risk and resident-report work have separate presentation. Selected state is exposed to accessibility services. Layout uses shared AppTopBar/ReportPanel/AppPalette components, responsive scrolling and accessible touch controls.

The duplicated outer status and note editor was removed. Select a road, inspect its record, then open one freshly loaded review form. New road status is never preselected, historical road notes are not automatically recycled into current findings, and the admin still explicitly records findings and confirms the current check. Flood-vulnerability editing remains under More road settings inside that form; leaving it unset preserves current values, and changing it resets confirmation. This also avoids applying one selected road's default vulnerability to an entire group. Existing guarded road deletion is retained in a secondary road menu.

For faster verified updates, Select multiple roads enables Select matching roads for the current result set, with the existing maximum of 20 roads. More than 20 results require narrowing the view; the app does not silently choose the first 20. Search/filter changes clear prior selection. The batch form shows the selected count and an expandable list of exact road references, then one condition, one finding and the existing current-check confirmation for the group. Clear weather, missing resident reports and selecting a group do not write passable status automatically. A report is never required for authorized CCTV/field-based road updating; current confirmation remains required. The map shortcut shares this form and does not enable unchecked map toggles or bulk all-clear from weather.

Validation so far: the full Flutter suite passed 569 tests with one existing optional host map benchmark skipped. Eleven new operations checks cover the read-only condition partition, closure retention, stale/unknown/future data, report-count deduplication and lifecycle coverage, priority navigation, unavailable counts, one-form road updates, selection clearing, bounded matching selection, six condition filters, road-setting confirmation reset and 320-pixel/200% English/Filipino layouts in both themes (including reduced keyboard space). Native Dashboard light/dark, Roads list/selection/batch and batch-review previews were rendered and visually inspected using synthetic data. Google Fonts asset-discovery notices are limited to the preview harness, which manually loads cached fonts.

This is a local client change. Existing road_review transactions, roles, bulk limits, audit/history, report rewards, notification rules and follow-up flags are unchanged. No backend/rule/index deployment, APK build/install or automatic hot reload was performed. The native Mapbox tap-to-review shortcut still needs emulator/device acceptance after reload, alongside the existing hosted/device workflow acceptance. Evidence and baselines are grouped in `.usability-work-baseline/admin-roads-dashboard-20261030/`.


Nontechnical-admin refinement: Select roads and Map now have visible, tappable text labels in addition to icons/tooltips. The batch action displays its matching-road count, and optional road settings explicitly allow keeping the existing setting. The final eleven operations tests passed again after these refinements; the preview harness also passed again. Final static analysis found no errors or warnings; 28 informational style notices remain. A beneficiary/admin unfamiliar with the app should still try finding a road due for checking, recording a checked group update and opening an urgent report without coaching. Layout and automated behavior tests do not establish that those tasks are already intuitive to an unfamiliar person.


## Dashboard and Roads redesign reverted - 30 October 2026

At the user's request, the preceding Admin Dashboard and Roads workflow redesign was reverted to the exact saved pre-redesign client files. This includes its report-queue shortcut option, map shortcut, optional road-settings/batch presentation changes and localization additions. The four new helper/catalog/test files were archived outside active source/test paths. The prior reporting UI, report-to-road linking, backend safeguards and history-pagination visibility fix remain as they were before this redesign. Existing multi-selection and the prior Dashboard/Roads appearance are restored.

The preceding implementation/previews remain historical evidence, not the current app design. Rollback copies and exact restored-file hashes are grouped in `.usability-work-baseline/admin-roads-dashboard-20261030/`. No backend, production data, rules, APK, deployment or user-owned Flutter terminal was changed by the rollback. Future UI work should preserve the user's preferred earlier design and use small, reviewable refinements.

Rollback verification: the complete Flutter suite passed 558 tests with the existing optional benchmark skipped. Restored runtime files match the saved pre-redesign baselines exactly. Hash comparisons also confirm the prior pagination widget, reporting details/timeline, report service and backend workflow are unchanged.


## Focused Roads refinements - 30 October 2026

The user's newer Roads screenshots are the reference for this Roads-only pass. The restored Dashboard is unchanged (byte-for-byte baseline hash verified). The list hides technical road references and the decorative green live-update icon. A real connecting/cache/failure notice remains when relevant. Each road emphasizes its last recorded condition, age, and confirmation/recheck warning. A recorded restriction stays restricted; imported passability is explicitly labelled as a saved condition needing confirmation. Prediction remains separate from verified road conditions.

Selected-road actions have labelled Road details and Road reports buttons, with secondary deletion under More road actions. Road reports opens the road's active review workload, with separate filters for admin work, waiting for the resident and all open reports. Cards enter the existing inspector; no new historical query or index is assumed. Completed reviews remain in the existing report history. The Map shortcut carries the selected road ID. Technical references remain available in details and optional reference expansions in the review form.

Bulk review now separates each selected road into its own bordered block. It retains the explicit 20-road limit, visible matching selection, and cleared selection after a search/filter change. One shared status and finding applies only to explicitly selected roads. The review heading icon and text are vertically aligned. Direct road-only editing offers three visible conditions and an explicit Confirm and save button; its explanation attests to a current check. It removes the repeated checkbox for that direct action only. Evidence verification, source-report references, follow-up reward safeguards and the optional current-road switch keep their prior semantics. Findings remain required, drafts survive failures, and no condition or note is silently copied from an old check.

On the full map, tapping a monitored road as an admin opens the same validated form in a bottom sheet rather than leaving the map for a full-screen list. The selected road has a blue casing beneath the original status overlays; dashed uncertainty and disconnected geometry remain intact. The camera fits selected geometry above the sheet, with bounded camera operations and failure handling. Typing expands the form into the available keyboard space; large accessibility text uses a scrolling form. Residents retain the existing road-details entry. Native Mapbox camera/overlay placement still requires manual device/emulator acceptance.

The independent road-review context no longer binds resident incident counters. The transaction reads the latest incident and preserves individual report decisions, allowing new resident activity while staff finish a separately checked current condition. Newer admin road changes, missing roads, changed source-report evidence/identity, and changed evidence-review contexts still reject stale drafts. Report verification remains bound to its report and incident snapshot. Added response metadata identifies whether the recorded road was verified. No rate-based shortcut or inference from weather/absence of reports was added.

Validation: full Flutter suite passed 571 tests with the existing optional benchmark skipped; the final affected tests plus native widget renderer passed 29 checks. Backend unit suite passed 110; the demo Firestore/Auth/Storage emulator suite passed 76, including resident activity during an independent road check and rejection of a newer admin road decision. Five widget snapshots were generated with cached app fonts and visually reviewed. The renderer does not instantiate Mapbox and uses synthetic data. Google Fonts test asset-discovery notices do not represent a live-device font result. Baselines, scoped diff, snapshots and verification logs are grouped in `.usability-work-baseline/roads-context-refinement-20261030/`.

No online backend/rules/index deployment, APK build/install, production-data change, or reload of the user's Flutter terminal was performed. The backend concurrency improvement remains local until a coordinated test deployment. UI reload and map/device acceptance remain open.

Final scoped static analysis found no errors or remaining warnings after removing one unused test import; 27 informational style/deprecation notices remain. The final standalone test-file recheck passed with one style notice.


## Road-condition meaning clarified - 30 October 2026

The earlier list still emphasized a green saved Passable value alongside an old date and a vague Needs confirmation message. The shared list/review summary now distinguishes current uncertainty from the prior check: Current condition unknown; Last confirmed passable: [age]; A new barangay check is needed. An unverified OSM default instead identifies a saved map record with no recorded barangay verification and never claims a prior confirmed Passable condition. Missing verification metadata from an older review endpoint is explicitly unavailable, rather than evidence that verification never occurred. Missing/future check times are not shown as valid inspection times. Recent verified records retain their condition and last-check age, and old restrictions remain explicitly Last recorded: Not passable/Partially passable. Resident observations requiring a check have their own reason.

These are read-only explanations of existing verification, incident and freshness rules. The Roads list and loaded road-review cards share the same summary widget; conditions, report outcomes, rerouting policy and backend writes are unchanged. Review-form source metadata is taken from the loaded context; missing vulnerability metadata uses the conservative existing high-vulnerability recheck cadence. English/Filipino copy and both themes are covered. Current status, verification and check time are never inferred from a locally cached road when fresh context omits them.

Validation: 48 affected Roads/review/accessibility tests passed, including the eleven-day-old example, unverified map defaults, retained closure warnings, new resident concerns, missing verification metadata, and existing large-text/theme/language layouts. A native widget renderer passed and generated light/dark list and single/bulk review previews; synthetic examples were visually checked. Test assets use manually loaded cached fonts, with the known Google Fonts test-discovery notices. Evidence is grouped under `.usability-work-baseline/roads-context-refinement-20261030/clarity/`. No backend deployment, APK build or user-owned terminal reload was performed.


## Road location preview and update controls - 30 October 2026

List/report-based road review now includes a read-only Mapbox SDK snapshot of the selected geometry, with the original Mapbox logo/attribution retained. A blue outline identifies the selected road; it is location context, not a passability claim. Surrounding street labels come from the basemap rather than inferred street-to-street descriptions. Enlarge map opens the same image in a read-only zoom/pan viewer and retains the in-progress form. Bulk selection draws separate segments and shows coverage when some selected roads lack geometry. Missing coordinates, unsupported platforms, render errors and timeouts have an explicit nonblocking fallback/retry. Switching selections invalidates late images and releases the previous snapshotter. Snapshot requests are stable across note/status edits and regenerate for geometry/theme/size changes. The full-map editor retains the existing highlighted map behind its sheet rather than adding a duplicate preview.

Direct status choices are three equal-sized tiles on ordinary phone layouts, with a full-width stack at enlarged text sizes. Partial is the compact label for the existing partially-passable value; saved backend values are unchanged. The findings field keeps its minimum-length guidance/counter together, with one short confirmation/visibility note below it. Optional vulnerability controls are grouped in a dedicated surface and explain that vulnerability is a road characteristic, separate from today's water level. The selected-road panel aligns its road name, icon, overflow/close controls, equal secondary actions and a separate primary update action. All controls use the existing palette and type styles.

Validation: the full Flutter regression suite passed 582 tests, with the existing optional benchmark skipped. Focused tests cover snapshot geometry preservation, invalid coordinates, image load/retry/enlargement, stale-image cancellation, partial geometry coverage, three equal status choices, existing report-review/save safeguards, optional settings, and narrow/200% English/Filipino/light/dark layouts. Native widget snapshots were rendered and visually reviewed; the host renderer exercises the missing-geometry fallback and does not prove a native Mapbox snapshot on Android. The native road highlight, street labels and attribution still require emulator/phone acceptance after the user's restart. No APK, deployment, online data write or reload of the user's Flutter terminal was performed. Evidence is grouped in `.usability-work-baseline/roads-context-refinement-20261030/map-preview/`.


## Loaded-preview blank-dialog regression - 30 October 2026

The user reported a blank Update road status dialog after the preview was added and supplied the AlertDialog/RenderIntrinsicWidth input.isFinite assertion. A regression test with a successfully loaded PNG inside a real scrollable AlertDialog reproduced the identical assertion. The loaded image had width double.infinity, causing an infinite intrinsic width; the earlier host rendering fixtures had no road geometry and the successful-image widget tests were outside AlertDialog, so they missed the container/image combination. Prior test totals did not establish acceptance of that case.

The preview root and loaded image now use the finite snapshot request width. All existing confirmation controls remain in the same validated form. Added complete-form tests exercise preview success and failure, select a condition, enter findings, perform the checked-save callback and close the dialog successfully. The initial affected run passed 42 tests. The original failure reproduction, baselines and correction logs are grouped under `.usability-work-baseline/roads-context-refinement-20261030/map-preview/blank-dialog-fix/`.

The terminal exception is a Dart layout failure, independent of backend writes. No backend, road status, report outcome, APK or deployment changed in this fix. The user's running terminal remains under their control; emulator confirmation after restart remains required, including the actual highlighted road and nearby street labels.

Final correction verification: the full Flutter suite passed 585 tests, with the existing optional benchmark skipped. Forty-two affected tests passed, including the exact loaded-image/AlertDialog sizing case and successful checked saves with preview success and failure. The native geometry/basemap acceptance check remains with the user after restart.


## Settings consistency and admin dark surfaces - 30 October 2026

Removed the disabled Guardian Mode placeholder and its unused toggle-card class. Emergency notifications, language and appearance now use a shared SettingsPreferenceCard matching the existing Settings action cards: rounded palette surface, matching icon tile, Manrope heading, Inter body copy, consistent padding and spacing. Notification readiness, permission/phone-settings actions, lifecycle refresh and delivery caveats are preserved. Only the Settings variant changes that card's framing; report-notification cards keep their existing appearance. Language/theme persistence callbacks remain intact, with expanded dropdowns for enlarged text and an explicit Appearance semantics label. The saved-information note keeps its content and receives aligned card margins/corners.

The shared admin navigation had a hard-coded translucent white background. It now uses the active surface palette across Dashboard, Roads, Alerts and Reports. The existing Dashboard layout/data logic remain in place; its dividers, overdue-road surface, check warning, action foregrounds, hover colours and badge foregrounds now use appropriate palette roles for dark-mode contrast. Roads/Alerts/Reports primary surfaces already use the palette. The app's runtime system-navigation-bar theme handling was inspected and already follows the active scheme; no global theme preference or startup behaviour changed.

Validation: 34 existing preference/accessibility, alert-composer, report-list and widget-render checks passed. Seven synthetic-data previews cover Settings light/dark, lower Settings preferences, and the four main admin tabs in dark mode, with 200% Settings layouts also checked. Firebase fixtures are local and no live service was accessed. The renderer uses cached fonts and emits known test-discovery font notices; the extra-heavy Capstone heading has no matching fixture font, so its preview is not a live-device typography result. Static analysis has no errors; the pre-existing unused _LegendRow warning and informational style notices remain. Baselines, scoped diff, logs and previews are grouped in `.usability-work-baseline/settings-theme-refinement-20261030/`.

No backend, report/routing policy, notification delivery logic, APK/deployment or user-owned terminal reload changed in this pass. User visual acceptance remains after their restart.


## Splash branding refinement - 30 October 2026

The Flutter splash now uses the existing assets/app_icon.png bridge-and-water artwork (unchanged bitmap), explicitly registered as a runtime Flutter asset. The placeholder shield/route graphic, green check badge, duplicate top SAFEPATHS label, INITIALIZING MAP DATA claim and decorative dots were removed. One main SafePaths heading and the existing localized tagline use the app theme's Manrope/Inter styles, with rounded logo corners, responsive spacing, light/dark palette surfaces and a small indeterminate loading indicator. The old timer-driven progress percentage was removed because it did not measure actual initialization. The existing session/error/account routing and timing remain; the startup timer is now cancelled when the splash is disposed.

Validation: 26 account-transition, security, preference/accessibility and widget-render checks passed; a final native widget render passed after matching the image cache key. The actual packaged PNG was decoded and visually checked in both themes, with 320-pixel/200% English/Filipino layouts checked as well. Static analysis reports no issues. Offline pub get succeeded without adding a dependency. The Android native launch screen/launcher icon was not redesigned, no APK/deployment was made, and the user's terminal was not restarted. Baselines, scoped diff, logs and previews are grouped under `.usability-work-baseline/splash-brand-refinement-20261030/`.


## November 1: local Marulas integration prepared

The separate main transport, shared backend profiles, main Firestore backup and
fenced metadata preflight are recorded in [Marulas main integration](marulas-main-integration.md).
Local app/backend checks passed with main and nearby configurations verified
separately. No main rules, endpoint, database records, schedules or installed
APKs were changed. Hosted cutover, legacy image access and main-device
acceptance remain open; follow-up evidence remains disabled.


## Admin reliability refinements - 1 November 2026

The existing Dashboard layout is retained. Dashboard condition totals and its check queue now reuse the same AdminRoadAssessment as Roads: only current verified passability is green; old, unverified or concerned passable records need checking; recorded partial/closed restrictions remain visible even when another check is due. Age is reassessed locally every minute and on resume without polling Firestore. The graph badge now describes road isolation/connectivity only, with Not confirmed for non-live or empty road data. It no longer claims that the whole system is OPERATIONAL. Unmeasured client risk-engine time is not reported as Healthy/0 ms. Narrow-screen and enlarged-text labels wrap; technical slides can scroll vertically when needed.

Admin actions now require successful local retry-marker storage before sending. Concurrent identical actions share an in-flight request. Lost responses retain their request ID and original review context across repository recreation; rejected stale context clears the attempt, and account changes block sending/accepting another account's result. Markers contain opaque tokens only, never authored findings or private coordinates. Previous test-build markers are upgraded where the prior payload matches. The server remains authoritative after a confirmed save even if local marker cleanup fails. Existing backend-scoped resident edits, clarification replies and disabled follow-up support now use the resolved main/test configuration rather than test-only defines. The client accepts the existing server maximum of 200 queued broadcast recipients (feedback remains at most one), preventing valid main publication acknowledgements from being misreported as failures.

Populated cached feedback has a visible saved-information notice until server confirmation. The feedback subscription is stable while filtering. Today's activity remains an explicitly checked snapshot: midnight clears the previous calendar day's totals, resume refreshes an expanded summary, late old-day responses are ignored, and a failed refresh never becomes a false zero. Counts are fetched on demand, not continuously polled.

Validation: 603 Flutter tests passed, with one benchmark intentionally skipped. Separate configured runs passed 45 main and 53 fieldtest checks. Added tests exercise retry storage failure, response loss/recreation, concurrent saves, changed accounts, cleanup failure, legacy retry upgrade, rejected context, backend separation, publication acknowledgement bounds, midnight/resume handling, cached nonempty feedback and Dashboard layouts in English/Filipino, both themes and 200% text. Static results and scoped source/checkpoint evidence are under `.usability-work-baseline/admin-reliability-refinement-20261101/`. Existing style notices/unused legacy legend are tracked separately from compile errors.

No cloud changes, APK build/install, feature-flag activation or user terminal reload occurred in this pass. Main hosted activation, disabled follow-up acceptance and physical-device acceptance remain separate open work. Existing successful report/push phone observations do not establish acceptance of these new source changes. Use a Flutter hot restart (capital R) for this pass because Dashboard widget state/lifecycle changed.


## Redesigned Dashboard and Insights aligned - 1 November 2026

The user's redesigned dashboard is retained, with its hero, quick actions, workload card, weekly summary, road overview and Insights cards. All sample counts, fallback percentages/review times, fixed chart values, invented street rankings and scripted recent activity are removed. Zero is displayed only for a known empty result. Workload comes from the existing live feeds, using ReportWorkload and AdminRoadAssessment; non-live feeds are labelled unconfirmed rather than assumed empty. Waiting-for-resident work is separate from admin review. Road restrictions retain their meaning and stale/unverified passability needs a check. The road illustration that looked like a condition map is replaced with actual condition counts in the same rounded-card style. Each category opens its corresponding Roads filter, and the last road-sync timestamp is shown when known. Unconfirmed is distinct from a recorded restriction needing another check. Recent submissions are identified as a checked snapshot, not a reconstructed event timeline. Its See all action opens report history with all review outcomes, not the technical system log. The original shared SafePaths Admin header (profile/settings) and Dashboard/Roads/Alerts/Reports navigation are restored, retaining the prior dark-mode fixes. The dashboard reacts to account/feed/weather changes. Unconfirmed weather is not labelled clear or assigned the default temperature. The hero weather chip is display-only and cannot open or change a simulation; a valid active drill is explicitly labelled rather than shown as current real weather. Drill controls remain separate in admin tools.

Report workload links open the appropriate existing review queue, including a waiting-resident entry point. Road-check links open the needs-check filter, active-alert links open the active list, and Send alert/Templates retain the composer. Settings remains accessible. These additions do not change report review/road write transactions, permissions or scoring.

Insights uses an on-demand, server-only query of all submissions in the selected 7 or 30 local calendar dates (through today), rather than the incomplete AppState review list. It has an explicit Checked timestamp and refresh, and a range switch clears the previous metrics while checking. Failed/cached results and account changes are rejected. There is no periodic database polling. A limit of 1000 records per period is enforced with one extra sentinel record; exceeding it fails without presenting partial totals. No new index is required beyond the existing createdAt single-field index. The query is read-only and does not depend on Firebase Cloud Functions or a billing upgrade.

Metrics describe the selected submission cohort: originals and follow-ups are distinct records; replies are not counted as submissions. Verified/resolved, needs admin review, waiting resident, dismissed and other outcomes are accounted for separately. Verification percentage uses all submitted reports as its denominator and is labelled accordingly. Review duration is submission to recorded final review, excluding negative/future clocks and without a fabricated minimum; no eligible reviews means unavailable. Zero chart bars have zero height. Thirty-day bins cover all 30 days, including the final partial period. Road rankings count road-linked submissions of every outcome and are not flood confirmations. The misleading passable-only Roads checked metric is replaced with Waiting for resident. English/Filipino strings, existing 12-hour timestamps and age formatting are used.

Validation: the full Flutter suite passed 614 tests with one intentionally skipped benchmark after the shared header/navigation, weather and history-link changes. Separate fieldtest and main-configured runs passed 62 and 26 checks. The final outcome/layout/catalog/header/route pass passed 32 checks, including the weather regression. A native widget render passed with eight light/dark Dashboard/Insights previews using synthetic records, which were visually inspected. The cached-font renderer emits known Google Fonts discovery notices; extra-heavy font weights can fall back in these previews. Static analysis found no errors or warnings; informational lint notices remain. Evidence and before-images/source are grouped in `.usability-work-baseline/dashboard-insights-alignment-20261101/`.

No cloud changes, production activation, APK build/install or user terminal restart occurred. A capital R hot restart is needed for the stateful screen/entry-point changes. Actual device/network query acceptance remains to be checked after that restart; the earlier phone evidence does not establish acceptance of this redesign.


## Dashboard priorities restored and cards refined - 1 November 2026

The original shared header/navigation and redesigned hero remain. Last 7 days and See insights now live within the same card as its checked timestamp, equal-height metric tiles and actual chart. A known empty cohort replaces the empty chart area with a compact message. Headers use natural action widths on ordinary phones and stack at enlarged text sizes. Your roads uses four readable, tinted, tappable condition tiles with distinct counts and matching existing filters. Recent submissions uses one concise period label and separate road, observation and submission-age lines; each item opens its actual report reference, while See all opens all-outcome report history. No sample values or events were reintroduced.

Needs you now starts with an urgent-open-report row when such records exist. It uses the existing isEmergency marker and reviewOpen states, including urgent records waiting for a resident reply; closed/verified urgent reports do not inflate it. Its destination is the explicit Urgent open reports filter and retains the shared urgency/age ordering. The ordinary Needs admin action filter now matches its displayed workload count and excludes waiting-resident records. General road reminders are omitted from the focused urgent view. Saved urgent information is labelled as needing confirmation when the report feed is not live.

Restricted roads requiring another check have a distinct row and matching Restricted roads to recheck view. Both use AdminRoadAssessment.needsCheck on recorded partial/not-passable roads, including stale, unverified or newly questioned records. The copy does not claim all are flooded or that water has receded. Fresh restrictions are excluded, and restrictions remain in force until an explicit verified road update. Existing selection bounds, context checks, findings/attestation and backend transactions remain unchanged.

Prediction outlook is grouped under Your roads, separately from barangay-confirmed conditions. Critical/Warning/Watch counts are shown only with loaded roads, live road/risk feeds, current weather, and a non-future risk calculation younger than five minutes. Drills and stale/cached/missing inputs do not become current model output; the real last-calculation timestamp is retained when valid. This is read-only presentation of existing model categories, not a change to rerouting, road status or risk computation.

Technical diagnostics is available through a scrollable Templates & Admin Tools sheet. It shows the latest feed states, road-sync/server-risk times, local neighbour-link counts, separately labelled local execution measurements, and up to 20 existing local system entries. Missing measurements are unavailable, not Healthy/0 ms. It does not infer overall backend health or push delivery, and local activity is clearly separate from report review history. The diagnostic view and restored summaries introduce no new database polling or writes.

Validation: 621 Flutter regression tests passed with one intentionally skipped benchmark. The final affected UI/workflow/catalog run passed 69 checks; separate fieldtest and main runs passed 44 and 24 checks. Added coverage verifies prediction freshness boundaries, urgent filtering including waiting residents and excluding closed records, exclusion of unrelated road reminders in the urgent view, restriction-recheck identity/retained status, contained weekly headers, diagnostics access, and English/Filipino layouts in both themes at 200% text. Native widget previews passed using synthetic fixtures and cached app fonts, including populated and empty cards; these were visually inspected. The renderer retains the known font-discovery notices/extra-heavy-weight fallback. Evidence, source checkpoints and final static results are grouped in `.usability-work-baseline/dashboard-priority-refinement-20261101/`.

No cloud deployment, feature-flag activation, APK build/install or user-terminal reload occurred. The user's capital R hot restart and actual device/network review remain after these local changes.

## Admin reliability and control polish - 1 November 2026

Roads search, Show roads and map/selection actions now share a raised, outlined rounded toolbar. Actions have separate brand-tinted surfaces; the toolbar adapts to narrow widths and enlarged text. Road/report filters retain their query semantics in rounded icon menus with explicit selected-row checks. Original shared headers and navigation remain.

Report History uses one loading/error/cache/empty state and retry action, without duplicate captions and error messages. Failed refreshes retain already loaded reports and explain that freshness is unconfirmed. Opening History directly from the dashboard now actually initializes its history loader. Back closes the active road/report inspection before returning to Dashboard. Inspection state in an inactive tab no longer hides navigation or intercepts Back when a notification switches tabs.

Admin Tools is grouped into Alerts and community, System checks and Advanced maintenance. Road-connection rebuilds require explicit confirmation, disable repeat requests while working, validate the returned result, and expose retryable errors. Legacy graph service errors now propagate rather than returning an empty success-shaped result. Prediction outlook is collapsed under More details. Weather drill confirmation names the configured area and matches the existing expiry behavior.

Validation: full regression suite passed 631 tests with one intentionally skipped benchmark. Separate fieldtest and production-configuration runs passed 39 and 21 tests respectively, each with the legacy-only graph test intentionally skipped. Eighteen light/dark native previews were generated; the Roads toolbar/menu, consolidated history error, grouped Tools, prediction details and graph failure were visually checked. Scoped Dart analysis completed with no errors or warnings (42 informational style notices). The Flutter analyze wrapper exited without diagnostics; direct Dart analysis supplied the static result. Final color refinements use the shared blue palette for retry/selection instead of the green theme default. Evidence and previews are grouped in `.usability-work-baseline/admin-polish-reliability-20261101/`.

No cloud deployment, feature activation, APK build/install or reload of the user's terminal occurred. Actual device/network acceptance remains separate from local regression confidence.
