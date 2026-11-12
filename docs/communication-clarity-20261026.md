**Clearer resident/admin report workflow - 26 October 2026**

The user approved explicit condition choices and clearer messaging/verification after reviewing a successful report communication recording.

Resident changes: new reports begin without a selected flood severity; submission asks for the observed level before saving. Urgent-help mode neither assumes High nor overwrites the chosen level. Normal and urgent report titles are distinct, and urgent wording requests review without claiming rescue dispatch. Flood choices expose accessible selected states. English and Filipino instructions explain that an administrator will review the observation.

Admin changes: verification begins with no selected new road condition, including when a previous screen supplied a proposal. The previous proposal is displayed as context. Saving requires a loaded current context, explicit road-condition choice, source/findings note and confirmation. Changing the choice or note clears confirmation; refreshing clears the old selection/context while retaining the note. A failed save retains the chosen decision for a same-request retry. The source prompt asks who/what checked, when and what was seen, and explains that road findings are visible with the road update.

The message field is labelled Private admin update, has a visible Send update button and explains that a message does not verify a report or change road conditions. Empty messages cannot be sent; message/preset editing is disabled while saving. The existing authenticated reply command, request receipts and push sender remain unchanged. The shared report summary used by admin and resident views separates recorded review status from road condition and private message wording. A verified observation does not imply a passable road.

The new actual-form regression failed before the fix because the untouched report form did not ask for a deliberate flood level. Tests now exercise report submission validation, urgent-mode selection preservation, explicit admin choices (including supplied proposals), stale context refresh, retained retry decisions, reconfirmation after changes, and resident status explanations. Layout checks found and fixed a report label overflow and a Filipino dialog overflow at 360 x 760 with 1.8x text; the review dialog is scrollable, including its title.

Final validation records, hashes and APK inspection are under .usability-work-baseline/communication-clarity-20261026. Full suite: 371 passed, one optional benchmark skipped. Exact test-build checks: 236 passed. Static analysis has zero errors and three existing warnings. The APK signature, same test certificate, Firebase test-project/package, three ABI markers and private-credential exclusions were verified; previous installers were preserved. Native acceptance of these new controls is pending. The earlier report communication/phone notification pass remains a dated observation, not a pass for every revised form.

Use SafePaths-Test-Communication-20261026-v1.0.4.apk on both the resident phone and admin emulator to see all changes. Check: (1) no flood choice is assumed; urgent mode preserves the choice; (2) Send update leaves review/road state unchanged while the resident reads the update and receives its notification; (3) Review & Verify requires an explicit current condition and confirmation; (4) resident summary distinguishes observation review from current road condition. Recheck photo return on Android 11 as the previous native rendering acceptance is still pending.

No backend, rules, account/audience policy, road status, dependency or main-app deployment was changed. The separate Actionable-count investigation remains outside this clarification change.

## Report history and direct access refinement — 26 October 2026

The resident navigation now has Map, Planner, Alerts and Reports. Reports opens the same paged history directly, with the existing profile shortcut retained. The tab initializes history only when first opened and retains its page while switching tabs. Generic report notifications also select this tab; report-specific notification links retain their dedicated update screen. The floating alert pill remains limited to Map and Planner.

History cards show the observation and one authoritative review summary. The duplicate verification/dismissal panels, flow connector and repeated trust badge were removed. Observation time wraps on its own line; the review is labelled Reviewed rather than Resolved. The latest recorded road condition remains separate from the observation's verification, and a different condition at the time of review is still shown when needed. Full descriptions, submission time and photo evidence are available under View report details. Outdated observations retain a visible advisory.

View private admin updates now opens a separate screen instead of expanding a long thread inside the card. Messages are shown newest first, with lazy rendering and the existing 20-message pagination, live head updates, cache/error notices and retry. Earlier recorded replies are retained in this reader. Back returns to the history's existing scroll position. The existing authenticated owner/admin query and Firestore rules still control access; an account change clears the reader and requires reopening from the current account's reports. This remains an admin-update feed, not a newly introduced two-way chat.

The common summary uses actual recorded points, including follow-up correction outcomes. Removing the former dismissal banner also removes its misleading hard-coded -15 label for follow-up records. No reward calculation, report evidence, message content, backend, rules, push delivery or audience policy was changed by this UI refinement. Follow-up reporting remains disabled in the current public test configuration pending its separate coordinated rollout.

Verification: the complete enabled-fieldtest Flutter suite passed **402 tests with one optional test skipped**. The six focused layout/navigation checks also passed with the current public emulator configuration, covering verified/pending/under-review cards, the existing edit action, 320-pixel width, 200% text, English/Filipino, light/dark themes, lazy message pagination, cache wording and return navigation. Scoped analysis found no errors or warnings; informational style notices remain in existing navigation/home code. The rendered layouts were inspected using the app's Manrope and Inter fonts. Logs, previews and hashes are grouped under `.usability-work-baseline/report-history-clarity-20261026/`.

For the current running emulator preview, press capital **R** in its Flutter terminal once for a hot restart. No new APK was built or installed and no online deployment was made for this refinement. Installed release APKs still show their earlier UI until updated. Live device acceptance of the new reader and tab remains to be observed.


**Report history reference design - 27 October 2026**

The supplied mockups guide layout, spacing, rounded cards and visual hierarchy.
Their dates, trust rewards, message count and event wording are placeholders;
application content continues to come from actual records.

History cards now use a submission badge/date, a cleaned resident-facing road
name, observation text/time, optional photo thumbnail, compact status progress,
one recorded review outcome, stale-observation advice and a private-updates
button. Original technical titles and complete evidence remain available through
the expandable details. Progress distinguishes pending, reviewing, verified,
reviewed, dismissed, correction and outdated outcomes; an expired report does
not gain a completed review milestone without an actual review record. Trust
chips use the recorded points, including zero, negative and correction outcomes.
Latest recorded road condition and its age remain separate from observation
verification and any different condition recorded at the review.

The report-specific updates page now contains a compact submission preview above
its messages. It uses the stored original snapshot when one exists and keeps
follow-up evidence attached to its own record. The preview expands to full
submitted text, timestamp and photo; thumbnails open a zoomable viewer. A photo
viewer clears its old image on sign-out, verification loss or an account switch,
including legacy inline evidence. Existing protected-media retrieval is retained.
The updates reader checks the matching report/owner context and stops rendering
private content when its account changes. Admin report entry points use neutral
report-update wording rather than calling another resident's submission their own.

Actual messages use a neutral connected timeline layout, retaining newest-first
order and bounded 20-message pagination. No extra acknowledgement, verification
event, delivery promise, author identity, reward or count is inferred from message
text. Feedback readers retain their existing presentation. Loading/error/cache
states remain explicit, and a report preview stays available while message loading
fails without claiming that no messages exist. Authenticated queries, rules,
report submission/review writes, reward calculations and feature flags are unchanged.

Five additional checks cover original/follow-up evidence separation, a lazy timeline
with report context at 200% Filipino text, honest pending/expired progress, loading
and error wording, and clearing an open photo across account changes. The complete
fieldtest suite passed **469 app tests and one font-loaded rendering check**, with
one optional benchmark skipped. Light/dark history and updates previews, including
enlarged Filipino text, were visually inspected. Artifacts are grouped under
`.usability-work-baseline/report-history-design-20261027/`.

For the running emulator, hot restart with capital **R**, then open Reports and
See updates on your report. Native photo display and live account/message behavior
still require the team's manual review. No APK, installation, backend/rules
change, billing change or emulator reload was performed by this UI pass.


**Report-history refinement - 27 October 2026**

Removed the repeated, unlabelled submission date at the history card's top right.
Observation, review and road-update age remain distinct. When an explicitly
stored observation time and submission time share the displayed minute, the
submission preview labels that single timestamp Observed and submitted and
omits its repeated expanded date. Distinct times remain separately labelled.
Only the thumbnail renders inline; tapping it opens the existing full photo
viewer. Both expanded report views no longer repeat the same image.

The report message section now has a dedicated Barangay updates header with
a blue icon/title, a smaller privacy/order subtitle, and primary-blue timeline
dots with a lighter blue connector. Feedback readers keep their existing layout.
English/Filipino and both themes are supported. No message content, data write,
review status, reward or photo-access rule changed.

Verification: 38 targeted report-layout, privacy/media and accessibility checks
plus one font-loaded rendering check passed. Light/dark and expanded-submission
previews were inspected. Detailed records are under
`.usability-work-baseline/report-history-design-20261027/refinement-1/`.
The full suite was not repeated for this presentation-only refinement. The user
can hot restart the running app with capital R for native visual review.


**Reporting reliability audit - 28 October 2026**

Reviewed submission/photo retry handling, resident edits, admin review and trust
outcomes, paginated history, private messages, account changes and the revised
report cards. Seven confirmed gaps were corrected in local source:

- History previously combined the current description/time with the sealed
  original photo and expanded details. It now renders the current report revision
  consistently. The updates-page submission preview still preserves the original
  snapshot; after a resident edit it is labelled Original submission. Retained
  photos with an earlier recorded submission time are identified, and photo
  submission time is available in expanded details. Photo time is not asserted
  to be the capture time.
- A late active-report snapshot could overwrite a newer paginated review and
  reward result. Feed merging now compares recorded mutation times, including
  review-start and admin-reply timestamps. These survive model serialization.
  The same choice protects the combined active/recent feed. Legacy ties preserve
  live-feed precedence; records without revision times cannot establish a strict
  server order. The history page retains its paging/order and owner filtering.
- An update arriving during the first older-message request could displace a
  message from the live head before it had been retained. Displaced records are
  now retained while that request is in flight, with ID deduplication. Before
  pagination starts the live window remains bounded.
- History's stale-observation warning now refreshes each minute without needing
  another backend update. Timers stop when cards are disposed; existing photo
  widgets remain in place during age refreshes.
- History binds itself to its initial verified, nonanonymous account. Direct
  account switches, sign-out or verification loss clear old history and close
  the edit sheet. Disposed pending page results cannot restore it. The user must
  reopen history for the new account. Repeated auth events do not pop extra routes.
- Dismissing an edit sheet while saving no longer allows a late error to call
  setState on the disposed sheet. Late responses also cannot show success to a
  different account. The text field owns its controller lifecycle.
- Resident edits now validate durable retry-marker persistence before sending,
  reuse the request ID/observation time after an uncertain response, and scope
  receipts to the account and backend. Local cleanup failure after a confirmed
  backend response no longer turns the successful edit into a failed-save message.

No server contract, review/reward formula, privacy rules or feature flags were
changed. The stored original evidence remains unchanged. Follow-ups remain gated
and disabled in the current public test configuration; this audit does not enable
their coordinated rollout. Existing broad report-read rules and retention/media
visibility decisions still require the previously requested adviser guidance.
No automatic deletion, main-project deployment, APK build, installation or emulator
reload was performed.

Manual acceptance still needed on the updated phone build: submit a photo report;
verify it on the admin emulator; check the resident's matching photo, actual review
outcome/points and private update; retry once after a controlled network failure;
and switch accounts to check private history and photos disappear. A quick resident
observation remains distinct from a full report and does not earn report points.
Local automated results and source diffs are grouped under
`.usability-work-baseline/reporting-audit-20261028/`.

Automated verification: the complete fieldtest app suite passed 483 tests, with
one optional benchmark skipped, including 13 new reporting audit regressions.
All 94 local backend unit checks passed. These are local tests, not a new hosted
end-to-end or phone acceptance run. The initial focused run exposed two incomplete
fix paths; both were corrected before the passing full-suite run.

Whole-workspace static analysis found zero errors, two warnings outside these
reporting changes (unused _LegendRow in admin_panel_screen.dart and unused
accuracyRate in consensus_audit_screen.dart), and 372 informational lints. The
analysis command therefore returned 1; no reporting-file warning was reported.
These unrelated admin files were left unchanged. For source review on the running
emulator, the user can hot restart with capital R. The phone must receive a newly
built test APK later to exercise these source changes.


**Admin report inspector redesign - 28 October 2026**

Replaced the dense floating inspector with an independent, testable inspector
widget. A pending report opens as Review report; completed records open as Report
details. The readable road name comes first, followed by separate This report
(or This follow-up) and Latest road update summaries. Stale observation advice
stays with the submitted evidence, while unconfirmed/stale road updates have their
own notices. A later road snapshot differing from the condition recorded at
review is described as a difference between known records, not as a complete
reconstructed road history. Long road notes expand on request.

The report photo, description and explicit observation time stay together.
Missing times are identified as unrecorded. Retained earlier photos are labelled;
photo zoom uses the existing account-guarded viewer. Trust scores, coordinates,
technical IDs, community observations and correction tools are under More details.
Urgent-assistance requests remain prominent without claiming rescue dispatch.

Recorded updates use chronological timestamps and labelled/icon-coded colours:
blue submissions/edits, amber review starts/corrections, green verified outcomes
and confirmed passable road snapshots, red confirmed closures/false-report outcomes,
and neutral other completed outcomes. No synthetic Now/waiting event or inferred
intermediate road transition is inserted. A road snapshot identical to the same
review timestamp/status is not repeated. Stored reviewStartedAt now survives
model decoding/serialization/copying; no server data/schema changes are required.

The fixed footer opens the existing guarded report review/dismissal dialogs for
pending records. Completed records offer Back to list and the existing current-road
review dialog for the matching road. No status, note or confirmation is silently
preselected. Private updates use the existing reply dialog, keeping per-report
drafts on cancellation and clearing them only after a confirmed save. Previous
private messages remain available through the protected updates reader.

Follow-ups have their own observation, photo and review outcome. A matching original
can be expanded when loaded; the existing protected condition-history link handles
retrieval otherwise. Root identity, owner and incident are checked before inline
original evidence is displayed. Corrections and recorded points remain separate
from the original award. Existing follow-up flags and coordinated rollout remain
unchanged and disabled in the public test configuration.

English/Filipino, light/dark, narrow displays and enlarged text are supported;
large-text summaries/buttons stack and the main content scrolls independently
of the footer. The popup is bounded by its actual available parent area.
No APK, installation, reload, backend/rules deployment or scoring changes were made.
Verification artifacts and synthetic, font-loaded previews are grouped under
`.usability-work-baseline/admin-inspector-design-20261028/`.

Verification: 492 regular app tests passed, with one optional benchmark skipped.
Nine new inspector checks cover actual event provenance/order, review timestamps,
corrections, action callbacks/busy states, separate follow-up evidence, retained
private-message drafts and 16 combinations of language/theme/report state at
200% text. After final presentation refinements, all nine checks plus one
font-loaded rendering check passed again. Six synthetic previews were inspected.
Scoped source analysis found zero errors/warnings and 19 informational lints.
The offline preview harness manually loads fonts and emits google_fonts notices
about disabled automatic fetching; these do not represent application test failures.
No physical-device or hosted backend acceptance was claimed. The user can hot
restart the running emulator with capital R to review real test-project records.


**Admin report inbox aligned with the inspector - 30 October 2026**

The shared admin report card now takes the actual report record and uses the same
short outcome labels as the inspector. Cards show a readable road name, two-line
observation preview, an actual photo thumbnail when present, explicitly labelled
observation/submission ages, and one entry action: Review report or View details.
Missing observation times are labelled Submitted, never inferred as an observation.
Same-minute observation/submission times are not repeated. Retained older photos
are identified when their recorded submission time establishes that difference.
Reporter names are secondary; trust scores, confidence calculations, category
badges and full evidence remain outside the compact list. Urgent-assistance
requests remain explicit only when the report's stored emergency flag is set.

A quiet Private updates indicator replaces Reply sent and also covers saved
review notifications and legacy messages without implying manual authorship,
confirmed push delivery or unread counts. Follow-ups have their own status,
observation and photo; original outcomes are not inherited. Follow-up feature flags
remain unchanged. A reviewed report whose matching active road incident requires
attention keeps its actual review outcome and adds Road condition needs review.

Filters are Needs attention, Last 48 hours and All reports. They wrap on narrow
screens rather than hiding All reports beyond a horizontal scroller. Selected
foreground colours use the theme's onPrimary colour for dark-theme contrast.
The attention count comes from the current report feed, so paging through history
does not change it to a count of the loaded page; zero counts are omitted. Road
conditions needing checks retain their own list/count. The recent-view exclusion
of dismissed records is preserved and explained with a short caption directing
the admin to All reports. The 48-hour cutoff uses the exact duration and excludes
future timestamps rather than including the remainder of the 49th hour.

The dashboard's shared report summaries use the same design and open the matching
report inspector through an initial report ID. Main-list selection, guarded review
and dismissal dialogs, pagination, risk ranking and emergency ordering remain in
place. Unused dashboard callback methods formerly passed to an inert card API
were removed; review actions remain available in the inspector. No backend/rules,
scoring policy, APK build/install, project setting or emulator reload changed.
Artifacts are grouped under `.usability-work-baseline/admin-report-list-20261030/`.

Verification: the final full app suite passed 502 tests, with one optional benchmark
skipped. The final report-list/accessibility run plus a font-loaded actual-screen
render passed 27 checks. Ten new report-list checks cover status/evidence accuracy,
missing/distinct times, callbacks/busy state, follow-ups, urgent flags, narrow
English/Filipino and both-theme layouts, matching inspector selection, filter
visibility/contrast and stable counts while paging. Four synthetic previews were
inspected. Scoped analysis found zero errors, one existing unused _LegendRow
warning in the dashboard, and 17 informational lints. That existing warning was
left in place and causes analysis exit 1. A minor test-import cleanup followed the
passing test runs; final analysis confirms the re-exported model types resolve.
The offline preview harness manually loads fonts; automatic-fetch notices in its
log are not app test failures. Native phone/backend acceptance was not claimed.
For visual review in the running Flutter session, the user can hot restart with
capital R. No automatic reload or APK build was performed.


**Report submission-date organization - 30 October 2026**

All reports and Last 48 hours now show newest-first submission-date groups:
Today, Yesterday, then localized dates (including the year for older-year records).
Calendar dates use device-local time, including UTC timestamp conversion and
month/year boundaries; elapsed 24-hour periods are not used to infer yesterday.
Submission order is stable for timestamp ties and does not change when a report
is reviewed, edited or supplied with a later observation. Needs attention retains
its existing emergency-first review/risk ordering without misleading date groups.
A follow-up keeps its own submission record/date.

Within dated views, cards show labelled 12-hour submission times and keep differing
observation ages separate. Explicit observation and submission times sharing the
same minute use a single Observed and submitted label. The attention queue and
dashboard retain relative age labels. Missing/invalid submission dates are shown
as unrecorded instead of January 1970; future-day dates require confirmation.
Missing review/photo timestamps are not formatted as recorded dates. Pagination
remains bounded; a day can continue on another page, and no daily totals are
inferred from one page.

Open views update calendar labels within a minute after midnight and immediately
on app resume. The rolling 48-hour window is re-evaluated while open without a
background query every minute. Filters stay visible; explanatory text and paging
controls scroll with the report content to fit enlarged text. The paging controls
support an explicit outer inset and long Older labels wrap while retaining their
tap targets. Changing filters returns the list to the top.

The next recommended report-management work is making old observations awaiting
review and long-waiting reviews easier to identify, followed by grouping related
road reports/follow-ups. These are recommendations, not features enabled by this
pass. Daily totals require actual scoped backend counts; a loaded page is not a
daily total. Existing review/dismissal guards, reward calculations, privacy rules,
feature flags and backend deployments were unchanged. No APK/install or automatic
reload was performed. Artifacts are grouped under
`.usability-work-baseline/report-timekeeping-20261030/`.

A final queue-order review found that routine road-condition reminders were placed
before all report cards. Those reminders now follow the report cards in Needs
attention, keeping urgent report requests visible ahead of routine road checks.
A dedicated screen regression verifies this placement. This changes presentation
order only; incident/review eligibility, existing report priority sorting and
road-review actions are unchanged.

Verification: the full app suite passed 513 tests with one optional benchmark
skipped before the final reminder-placement adjustment. After that adjustment,
32 focused checks passed, including the font-loaded rendering check (12 timekeeping/queue tests, 10 report-list tests, 9 inspector tests and one
render check). Scoped final analysis found zero errors/warnings and eight existing
informational lints. Four synthetic light/dark/Filipino/older-date previews were
inspected. The offline preview harness manually loads fonts and emits notices
about disabled automatic font fetching; those notices are not test failures.
A newly added placement regression brings total distinct regular app coverage to
514 across the broad and final focused runs. No hosted or physical-phone acceptance
was claimed. The user can hot restart the running app with capital R for review.


**Compact admin report controls - 30 October 2026**

Admin filters now share one segmented surface. Full Needs attention, Last 48 hours
and All reports labels remain accurate; there is no invented all-time total.
Normal text uses one row, while enlarged text stacks the same controls within the
surface. Only the selected segment receives the filled surface. Theme foregrounds
preserve contrast. The existing Needs attention count still refers to the current
report feed and does not change with history pagination.

Admin history uses compact, shadow-free paging controls only when a page boundary
or unconfirmed/cache state makes them useful. A single confirmed first page with
no next cursor hides the redundant paging strip. Refresh is available in the
header while browsing history, is disabled during loading, and remains accessible
when the strip is hidden. Multi-page Newer/Older and page-number controls remain.
Cache/error/loading notices are retained. Other screens using the shared controls
retain their default presentation. The date explanation follows paging, avoiding
an unnecessary gap between the filter bar and navigation.

The existing actual-screen test now checks the hidden single-page strip and visible
header refresh. Its tap uses the visible View details action after layout settles,
so the test does not tap the center of a partially off-screen lazy card. Existing
paging, date, inspector, language and accessibility checks were rerun. No analytics
counts or backend changes were introduced. The recommended next step is a compact
dashboard report overview using complete counts for Submitted today, Awaiting
review, Reviewed today and Old observations needing a fresh check. The dashboard
already has an active Reports count; its meaning should be labelled clearly.
Daily totals must not be derived from the loaded history page, and review-speed
metrics require suitable recorded event timestamps.
Artifacts are grouped under `.usability-work-baseline/report-controls-20261030/`.

Verification: 60 focused report-list/date/paging/history/accessibility/render checks
passed. The final styling rerun passed ten list tests and the render check; a
separate actual-screen rendering pass also verified a 35-report multi-page case.
Five synthetic light/dark/enlarged/older-date/paged previews were inspected. Scoped
analysis found zero errors/warnings and eight existing informational lints. Offline
preview fonts are loaded manually; automatic-fetch notices remain in render logs
without failing the checks. No new full-suite or hosted/device acceptance run was
claimed for this presentation-only pass. The user can hot restart with capital R.


**Compact admin report cards - 30 October 2026**

The User Reports cards now follow the approved reference density: smaller photo
previews, shorter summaries, a compact status badge, top-right submission time and
a quieter reporter footer. Private updates use a labelled tooltip icon without
an invented unread count. Review report / View details remain visible actions,
and the entire card still opens the existing protected inspector. Enlarged text
stacks the header and footer to preserve readability.

Observation time remains separately visible when it differs from submission time.
Older-photo warnings, urgent assistance and road-review reminders are retained
when supported by the stored record. Review eligibility, date grouping, paging,
rewards and backend rules are unchanged. Analytics remains deferred.

Verification: 59 existing focused list/date/inspector/history/accessibility checks
and one rendering check passed. Five synthetic light, dark, enlarged Filipino,
older-date and paged previews were inspected. Final scoped analysis found no
issues after a braces-only lint cleanup. The offline font loader emits expected
automatic-fetch notices; synthetic photo URLs show the unavailable-photo fallback.
Artifacts are grouped in `.usability-work-baseline/report-list-density-20261030/`.
No build, install, deployment or automatic reload was performed. The user can
hot restart the running app with capital R.


**Admin report spacing revision - 30 October 2026**

Following emulator review, the compact card density was relaxed. Cards now use
16px padding, larger titles/descriptions/status labels, 60px thumbnails and more
space between sections. Submission/observation time is left-aligned below the
description rather than competing with the status in the upper-right corner.
The footer has a subtle divider. Timestamp meanings and missing-time safeguards
are unchanged.

The nested filter pills were replaced by plain text tabs with a blue selected
underline, minimum 52px targets and selected-state semantics. Long/enlarged labels
retain the stacked fallback. The existing accessibility/contrast regression now
checks those tab semantics and theme foreground contrast. Review actions, queue
logic, pagination, rewards and backend behavior are unchanged. No reload or APK
operation was performed. Artifacts are grouped under
`.usability-work-baseline/report-list-spacing-20261030/`.

Verification: 59 focused checks and one rendering check passed. Five light/dark,
enlarged Filipino, paging and scrolled previews were inspected. Scoped analysis
found zero errors/warnings and eight existing informational lints. The synthetic
preview font-loading notices did not fail rendering.


**Admin broadcast alert redesign - 30 October 2026**

The alert screen now separates Write alert and Active alerts. Composition follows
severity, message, location/duration, then resident preview. Templates and the
existing manager remain, with three stored templates offered as quick choices.
Inputs follow the app theme, have persistent labels and validate the existing
120-character title / 2000-character message limits (minimums 2 and 10). The
current Spark duration choices remain 15 minutes, 1 hour, 3 hours and 24 hours.
Legacy builds retain their existing 24-hour validity instead of promising a
custom expiry unsupported by that path. Expiry previews use 12-hour local time
and explain that the actual lifetime starts at publication.

The area name replaces City-wide. A road selects the alert location; it does not
change area-based recipient eligibility. Push choice is guarded by the existing
build flag. Copy distinguishes publishing, notification queueing and unconfirmed
phone receipt. An alert still does not change a road's verified condition.

Review alert validates and presents an immutable draft; Keep editing/cancel sends
nothing. Only Publish alert invokes the existing service. The sending state
blocks repeated taps and screen controls; failures retain the visible draft and
existing repository retry identity. Confirmed success clears the form and opens
Active alerts. The active count and expiry state refresh on a 30-second timer
and app resume. Expired/withdrawn alerts remain under Show past alerts; View
alert reveals the complete message. Withdraw alert uses the existing protected
withdrawal dialog. No rules, backend commands or feature flags were changed.

Verification: six composer workflow/layout checks, eight existing communication
checks and one native-font rendering check passed (15 distinct checks). Coverage
includes cancel, failed/repeated sends, late completion after disposal, road
selection/duration/push settings without road-status changes, expiry without a
backend update, and narrow-screen English/Filipino layouts at 200% text. Checks
caught and resolved hidden ink surfaces, long template-name overflow and large
review-dialog overflow. Final scoped analysis found no issues. Eight synthetic
light/dark/composition/review/active previews were inspected; the preview harness
loads fonts locally and automatic-fetch notices did not fail rendering.

Artifacts are grouped in `.usability-work-baseline/admin-alert-redesign-20261030/`.
No hosted publication, phone delivery test, APK build/install, deployment or
automatic reload occurred. The user can hot restart the running app with capital R.


**Admin alert guidance emphasis - 30 October 2026**

Templates now have a labelled optional area above the title/message fields, with
a short instruction, stored quick choices and a separate Browse templates action.
Field labels have stronger weight and contrast. The location picker hint is more
prominent, and the road-verification clarification uses an information callout.
Duration labels, an expiry clock row, notification guidance and an audience icon
row are larger and easier to scan; character counters retain secondary emphasis.
The theme palette supplies both light and dark variants. Three new interface
phrases also have Filipino catalog entries.

This pass changes presentation only. Publication validation, templates, duration
values, recipient eligibility, retry identity, review confirmation and withdrawal
behavior remain unchanged. Six existing composer checks and the native-layout
render check passed. Light/dark composition and location previews were inspected.
Artifacts are grouped in `.usability-work-baseline/admin-alert-emphasis-20261030/`.
No automatic reload, APK build/install or backend deployment was performed.

Final scoped analysis found no issues. The user can hot restart with capital R.


**Simplified alert template library - 30 October 2026**

Alert Template Studio has been replaced by Alert templates, opening on Saved
templates rather than a technical creation form. Cards show the saved name,
severity, title and a short message, with View message, Use template and a
confirmed Delete action. Using a stored template only copies its contents into
the existing alert draft. The parent confirmation flow remains required before
publishing. The creation tab separates Template name (an organizing name, not
included in a published alert) from Message for residents. Plain field labels
replace chip/headline/body terminology. Examples and the message preview are
optional expandable sections. The original example content was retained with an
explicit instruction to verify details; it is not presented as confirmed news.

Save template and Save and use explain the two existing outcomes. The form and
actions scroll together, including with the keyboard open and enlarged text.
Buttons and guidance follow the theme; modal close/delete icons explicitly use
theme foregrounds. New copy has Filipino catalog entries. Creation validates a
1?60 character name and the existing broadcast title/message limits, preventing
new templates whose content cannot be published.

The old save path did not await storage and silently added failed writes to the
local library. Save and delete now await the existing Firestore API and propagate
failures to the form, preserving the existing storage collection and live feed.
A 20-second confirmation timeout leaves the draft intact; a retry uses the same
template ID and cannot add duplicates. Late success does not auto-apply a draft.
Deletion failure does not pretend the record was removed. Mock storage also
upserts by ID. No backend command, rule, feature flag or deployment was changed.

Verification: seven template tests, seven alert composer tests (including the
actual Browse ? Use template interaction), eight existing communication checks
and one native-font render check passed: 23 distinct checks. Coverage includes
failed/late/timed-out saves, cancelled/failed deletion, save-only versus use,
retry identity and narrow English/Filipino layouts in both themes at 200% text
with and without keyboard insets. Six synthetic library/form/bottom-action/dark/
Filipino previews were inspected. Broad scoped analysis found no errors/warnings
and thirteen existing informational lints in app_state_service.dart. The final
UI-only analysis is recorded separately. Local preview fonts emit disabled-fetch
notices without failing rendering. No hosted save/deletion acceptance, automatic
reload, APK build/install, main-project deployment or full-suite rerun was claimed.
Artifacts are grouped in `.usability-work-baseline/alert-template-library-20261030/`.
The user can hot restart the running app with capital R.

## Resident report list and detail tabs — November 8, 2026

The resident list is now headed “Your reports.” Compact cards show the road,
observation excerpt, submission time, explicit report outcome and next action.
An outstanding clarification has an amber badge and a primary “Reply to
barangay” action. Opening a card starts on Report; the reply action and existing
message/notification entry points start on Messages. Admin presentation is
retained.

The detail header uses the live road title, submission time and report badge.
Report contains the submitted evidence, copyable real reference, progress,
review/reward and existing condition-history access. The latest recorded road
condition appears separately and uses the existing road assessment so an old or
unverified passable default is not presented as a fresh confirmation. No report
is claimed to have caused a later road update. Waiting for a resident counts as
an active review step, not a completed decision.

Messages are chronological, with the latest brought into view when opening or
receiving a new message near the bottom. Older-page loading and authenticated
live subscriptions remain in the parent. The primary reply action exists only
for an active clarification. After a reply, residents see the waiting-for-review
state and can revisit the question and answer. No unread count, new chat
capability, fabricated reference, reward or notification delivery claim was
introduced. Account-switch, cache/error and original evidence protections remain.

Verification: 36 focused reporting checks passed under each of the Marulas and
field-test configurations. Two additional isolated render checks passed for
Marulas (38 checks including rendering). Coverage includes actual notification
entry, live questions/replies, draft protection, ownership changes, chronological
messages, separate road/review outcomes, cache failures, history controls and
320-pixel layouts at 200% text in English/Filipino and both themes. Scoped
analysis found no errors or warnings; informational style lints remain.
Light/dark previews with sample data are grouped in
`.usability-work-baseline/ui-previews-20261108/` as `report-redesign-*` and
`report-history-observation-*`. No live records, backend settings or APKs were
changed by this UI work. Device acceptance remains necessary.

### Reference-layout refinement

Following the owner's feedback, resident messages now use compact bubbles with
small sender/avatar labels and external 12-hour timestamps grouped by day,
instead of the large conversation panels. Routine messages are neutral; an
active question is amber; resident replies and the matching verified-review
event use green. Event identification uses the existing stored request/review
timestamps and resident sender marker, never a keyword scan of message text.
An answered question is no longer styled as an active request. Reply-sent
badges, status text and the review progress also use meaningful colors.

The resident Report tab now has a “What you sent” card showing observation,
location, observation time and real copyable reference directly. Open reviews
show a larger photo preview, with the existing account-protected photo viewer;
completed reviews use a compact photo. The final review summary precedes this
card, with a simple progress card below. Latest road information remains
separate. Original submission evidence and the condition-history link remain
available. Admin widgets, backend commands, privacy guards, notification
behavior and follow-up eligibility were not redesigned.

An additional event-color regression brings the focused suite to 37 checks.
The existing sample previews were regenerated for both themes; their photo
placeholder deliberately contains no resident evidence.

## Admin report workspace — November 8, 2026

The live admin Reports selection now opens a dedicated Report/Messages workspace
matching the resident design. The report tab prioritizes submitted evidence,
observation time, copyable real reference, and the latest recorded road condition
with its date and barangay note. Additional reporter context and earlier
submission comparison remain under More details; follow-up history and correction
actions remain available. The list retains its filters and scroll state, while
its semantics are excluded when the selected report covers it. The admin's main
navigation styling is unchanged.

Messages use the same compact bubble presentation with admin/resident alignment,
chronological order, real day/time labels, explicit received-reply state and
semantic colors. The existing authenticated, paginated report-message reader is
embedded rather than replaced by an unprotected query. No unread number is
invented. A second clarification cannot be requested while the first is awaiting
the resident. Question presets are editable and confirm replacement of a manual
draft; asking and sending updates use bounded bottom sheets.

Make a decision opens a fresh-context sheet requiring an explicit outcome.
Verification retains the existing explanation and evidence/time confirmation,
self-review restriction and original-before-follow-up checks. It sends an
observation-only command. Current road changes are a separate guarded review,
with a new context required on return. Not verified leads to an explicit reason
step; no reason is preselected in the new sheet. The existing no-penalty,
confirmed-false, follow-up and SOS safeguards remain. Busy nested actions are
serialized. Failed saves preserve drafts and do not claim success.

Verification: 88 focused functional checks passed in each build configuration;
the Marulas render check also passed (89 total including rendering). Tests cover
list selection, notification entry and per-report drafts, embedded-message
account changes, fresh decision tokens, no road mutation during observation
verification, explicit non-verification reasons, protected manual question text,
and narrow English/Filipino layouts at 200% text with keyboard insets. The older
road-review form was included in regressions after repairing a local edit
boundary. Scoped analysis found no errors or warnings; informational lints
remain. Light/dark actual-widget previews are grouped under
`.usability-work-baseline/ui-previews-20261108/admin-workspace-*`.

This work changes app presentation and action launchers. It does not deploy
backend changes, alter the databases, enable feature flags, or build/install an
APK. Native phone/emulator acceptance remains the next check.

Decision-sheet polish: the explanation input, character guidance and evidence
confirmation are grouped in one card. The recorded road condition now has an
icon, bold status badge, matching border, real update timestamp (or an honest
missing-time label) and an outlined Change action. The road/report separation
note stays below a divider. Both themes were rendered and inspected. The 24
decision/road-review/render checks passed, followed by the final eight workspace
checks and refreshed render check after compacting the explanation card. Save
requirements and command payloads were retained.


### Admin reporting polish - 8 November 2026

Refined admin report cards, workspace status/actions, question presets, and private update editors using shared compact report-context and editor cards. Active questions retain amber emphasis; received replies retain green emphasis. Real report references, protected photos, drafts, account guards, and the separation between observation verification and road updates are preserved. No backend configuration or APK changes.

Validation: production reporting suite passed 88 functional checks plus actual-widget light/dark rendering. Focused fieldtest checks passed 34 functional checks plus rendering, including the update composer at 320px width, enlarged English/Filipino text, and keyboard insets. Scoped analysis reported no errors or warnings (11 informational style lints). Sample-data previews are grouped under `.usability-work-baseline/ui-previews-20261108/`. Physical-device acceptance remains outstanding.


### Follow-up and condition-history alignment - 10 November 2026

The road-details reporter prompt now uses the same rounded, tinted action-card treatment as reporting. Condition history has a compact original-report summary, semantic review badge and expandable original evidence/photo/reference. Observation/submission times share a line only when both were recorded in the same displayed minute; missing observation time is no longer inferred from submission time. Duplicate photo submission timestamps are omitted when already represented by the submission minute.

The follow-up form uses separate cards for the condition change/description, observation time, optional current photo, and urgent-review option. Manrope/Inter, AppPalette colours and ReportPanel are shared with the newer reporting screens. Existing payload fields, original evidence preservation, optional-photo confirmation, original-reporter ownership, context refresh/token, draft-leave protection, uncertain-send retry and reward rules remain. English/Filipino and light/dark layouts were checked at 320 px with 200% text and keyboard insets. Test navigation now scrolls controls into the actual viewport before tapping, accounting for the separately styled cards.

SafeImage also now routes both safepaths-main and safepaths-report-proof private report/media paths through their existing authenticated readers. Previously the main paths fell through to Image.network. Host/project/reference and account checks still run in those readers; no public bucket or auth bypass was added. Protected-path classification and existing private-media/upload checks passed. Actual hosted-image rendering on a device still needs confirmation.

Validation: 87 functional checks across the focused and reporting-regression suites plus two actual-widget preview runs passed. Scoped analysis reported no errors or warnings (26 informational style lints). Preview images and logs are grouped in `.usability-work-baseline/followup-ui-20261110/`; their data is clearly labelled sample data and is not seeded online. No backend deployment or APK build/install occurred. The installed version 1.0.7 predates this UI/photo-routing pass.


### Report flood-level selector - 10 November 2026

Replaced the submission screen's private flood-level tile with `ReportFloodLevelSelector`. Selected Low/Medium/High use a subtle theme-aware accent blend, an accent border, readable icon/label and a separate selection check. High no longer fills from the theme's tertiaryFixed token, which could blend into its icon. The three choices have consistent height and stack at narrow widths or enlarged text. Existing semantic keys, selected state, index-to-severity mapping and deliberate-choice validation are retained; urgent rescue selection remains separate from flood level.

Validation: 17 selector, report-clarity and reporting-reliability checks passed, plus actual-widget light/dark preview rendering. Tests cover all three selections, icon/fill contrast and enlarged English/Filipino labels. Images and logs are alongside the follow-up previews in `.usability-work-baseline/followup-ui-20261110/`. No backend or APK changes were made.


### Full-width report photo attachment - 10 November 2026

Replaced the small Add Photo pill beside Location with `ReportPhotoAttachmentCard`: a full-width 148 px minimum picker area, clearly labelled camera/gallery entry, processing feedback, and a 220 px preview that contains the whole photo rather than cropping its evidence. Change and Remove actions sit below the preview. The old attached-photo verified icon is removed; the card claims only that a photo is attached. Location remains accessible through a separate Review report location button with the same picker result/generation handling.

The screen retains the existing image-picker, validation, watermarking, temporary-file handling, upload/retry coordinator and photo-removal invalidation. Replacement/removal/location actions are disabled during preparation or upload. The attachment widget owns presentation and callbacks only. English/Filipino labels and light/dark states match the reporting cards.

Validation: 29 functional attachment, upload, report-clarity and reporting-reliability checks passed plus actual-widget rendering; a final focused rerun also passed after ensuring the card shrink-wraps its content. Coverage includes empty-area hit size, change/remove callbacks, uncropped preview, processing lock and 200% text in both languages/themes. Previews use the user-provided BBB photo locally and are not uploaded as reports. Logs and PNGs are grouped with the follow-up previews. No APK was rebuilt or installed.


### 2026-11-10 ? Admin submission evidence visibility

- Replaced the admin workspace's resident-summary preview with `AdminReportEvidenceCard`: expandable protected photo, full resident description, selected flood level, coordinates, recorded location source, observation time, and submission time. Uses original-submission snapshot when available; follow-up evidence remains its own dated record.
- Added copy coordinates (full stored precision) and a read-only map action. The map snapshot shows an orange reported point and blue selected road geometry, preserving disjoint road segments. Point-only records remain viewable; missing/invalid coordinates never create a map point. No photo EXIF, source, capture time, accuracy, or verification is inferred.
- Reused the existing native Mapbox snapshot renderer rather than adding an interactive platform view. Coordinates remain readable when the snapshot fails. Map dialogs and enlarged previews use the same account-change guard as private photo viewing.
- Latest barangay road condition remains a separate card. Reporter context, full report reference, and extra evidence metadata remain under More details. No review, road-update, notification, follow-up, or reward backend behavior changed.
- Added Filipino strings and focused evidence tests. Previews use explicitly marked sample data and a locally supplied demonstration photo; nothing was submitted to either backend.
- Source changes only: no APK built or installed for this pass. Native map rendering and private hosted-photo display still require device acceptance.

Validation: 76 focused and reporting regression tests passed; actual-widget preview renderer passed. Checked light/dark previews, narrow 320px layouts at 200% text in English/Filipino, coordinate validation/copy precision, original evidence preservation, map failure recovery, private-media/account switching, and existing admin interaction workflows. Scoped analyzer reported no errors or warnings (style information only). Preview files are grouped in `.usability-work-baseline/admin-evidence-20261110/`.


### 2026-11-10 ? Reporting edge-case review, resident and admin

Scope: report submission, follow-up history, private clarification, admin review/road-update separation, and notification handling. This is local regression evidence, not full application or on-device acceptance.

Confirmed and fixed:

1. **Resident account switch during condition history:** the old screen could load again after switching accounts or signing back in. Reproduced with controlled account events. The screen now latches the account change, clears draft/evidence/expanded history, cancels its uploader, blocks refresh, and ignores late load/picker/time/upload/save results. A fresh report screen is required.
2. **Uncertain follow-up save followed by context refresh:** including the refreshed context token in the retry identity created a new request instead of replaying the original uncertain save. Reproduced with a lost-response/restarted-repository test. Follow-up retry identity now binds the unchanged intent independently of context refresh and durably preserves only the opaque request ID and original context token. Explicit failed-precondition rejection releases the pending receipt so refreshed context can be used. Same-context receipts from the previous implementation migrate without reissuing their ID. Ordinary report submissions retain their prior retry format.
3. **Resident compact-card age warning:** the newer compact history branch omitted the existing stale-observation warning. Restored the warning using the existing freshness rule and minute timer. It is descriptive, not an automatic road-status change.
4. **Retained photo clarity:** resident and admin evidence cards now identify an attachment submitted before the recorded observation time. This uses recorded timestamps only; it makes no photo capture-time/EXIF claim.

Other guards verified:

| Situation | Verified behavior |
| --- | --- |
| Duplicate taps / response loss | Shared in-flight operation and durable retry identity; original evidence/observation time retained |
| Two admins reviewing the same report | Stale context prevents a second conflicting decision or duplicate reward |
| Question replaced while resident is writing | Old draft is retained and cannot be sent as the new answer |
| Report deleted / account switched / private viewer open | Selected evidence becomes unavailable; late results cannot restore it |
| Pending report vs current road status | Verifying an observation remains distinct from an independent barangay road update |
| False/unclear follow-up evidence | Original reward preserved; correction and confirmed-false penalties remain explicit and separate |
| Notification retries / wrong account | Backend queuing/replay and account scoping checked; real delivery still needs device verification |
| Missing coordinates / map load failure | No invented point; recorded coordinates and close/retry actions remain accessible |

Validation: 119 Marulas Flutter checks passed; two in-place-edit tests correctly do not apply with follow-ups enabled. All 22 selected test-build checks passed, including those two legacy edit tests. 48 local backend workflow/notification checks passed. Scoped analyzer: no errors or warnings; informational style lints remain. Older audit assertions were updated to the actual evidence view and supported archived-card branch. No live records, deployments, APK builds or installs were performed.

Logs and controlled reproductions: `.usability-work-baseline/reporting-edge-cases-20261110/`.

Remaining acceptance: installed builds must still confirm private hosted-photo display, native reported-location map rendering, offline/reconnect behavior, foreground/background notification delivery, and report-opening from a notification. Local checks do not prove Android delivery or every timing/device condition.


### 2026-11-10 ? Recorded admin report refinements and Marulas photo fix

- Restored top SafeArea protection for the full-screen admin report workspace. A dedicated Android-inset test verifies the back button/header stay below the system UI.
- Reordered evidence as photo/description, reported location with filled map and outlined copy actions, resident-selected flood level, then Report information. Observation/submission times, copyable report reference, reporter context and optional trust score are visible together. Removed the More details wrapper; a follow-up's original-report preview remains separately available.
- Renamed the road card to Road condition now, explains that it is the latest barangay record separate from resident evidence, and uses the assessment's actual history label for the timestamp. Unknown/stale conditions remain unknown/stale; no changes to road authority or routing.
- Reproduced the protected photo defect: client signed-URL validation hardcoded the test bucket `report-photos-proof`, while the main backend returns `report-photos-marulas`. The client now chooses its configured environment bucket and binds the signed URL to the exact requested owner/digest file. Wrong environment, host, protocol, photo, missing signature token, and fragments are rejected. This is a client fix; no bucket privacy change or backend deployment.
- Added descriptive protected-photo error/retry UI and network-image loading feedback. Signed URLs and photo bytes are not logged.
- Validation: 105 functional checks plus the actual-widget preview renderer passed; includes 16 main/test protected-photo URL cases, safe-area positioning, evidence order, visible metadata, narrow/large-text layouts, admin interaction, resident messages, and existing workflow guards. Scoped analyzer: no errors/warnings; style information remains.
- Light/dark sample previews and logs: `.usability-work-baseline/admin-evidence-refinement-20261110/`.
- These changes are local source only, after Marulas 1.0.8 was built/installed. A new APK is needed to verify the real hosted photo and system-inset fix on the emulator/phone. No report, road, account or backend data was modified in this refinement task.


### 2026-11-10 ? Consolidated reporting pass before another APK

User requested holding APK builds while reviewing the connected resident/admin flow. No APK or deployment was performed.

Additional reproduced gaps and fixes:

- `UserAvatar` selected the authenticated private-media reader only for the test endpoint. Marulas avatar references fell through to an unauthenticated network image. It now shares the environment-aware `protectedImageKind` classification used by SafeImage, preserving backend resource/account checks. Test confirmed both endpoint branches.
- Short resident clarification replies disabled Send without explaining the 10-character minimum. A shared validation function now supplies the visible reason and the save guard. It also explains missing/invalid/future attachment observation time and missing photo confirmation; server validation remains authoritative.
- A closed, unanswered question with no draft could show only the question and no explanation. It now shows an explicit closed-question notice and a return action. Admin read-only views do not receive the resident-only warning. Saved-response and changed-question draft behavior remain intact.
- Opening a notification with an empty cache was presented as an unavailable report before any server-confirmed result. It now shows Report not loaded yet with connection guidance. A later live report opens normally; a server-confirmed deletion still closes the report view. Ownership checks and private message gating are unchanged.

Usability refinements: resident optional-photo selection reuses the full-width reporting attachment card, with an accurate gallery-only label and unchanged picker/preparation/upload rules. Photo time selection and completed upload references ignore stale generation/account results. Admin clarification reading labels the question from the admin perspective.

Validation: 184 Marulas Flutter checks passed; the two inactive legacy-edit cases are not applicable there. All 42 selected fieldtest checks passed, including retained legacy edit behavior. All 48 selected local backend report/notification/media checks passed. Actual-widget light/dark reply/closed-state render test passed, and previews were visually inspected. Scoped analyzer found no errors or warnings (informational style lints remain).

Previews and logs: `.usability-work-baseline/reporting-consolidation-20261110/`. This batch includes the preceding top-inset, evidence hierarchy and Marulas photo-bucket fixes in local source. Installed Marulas 1.0.8 remains unchanged. Native hosted-photo/avatar display, map preview and end-to-end notification/device timing still require the next installed candidate rehearsal; these checks are not evidence of full real-world acceptance.


### 2026-11-10 ? Explain current-road reminders in the admin report queue

Replaced the plain Road conditions to check list with a shared ReportPanel headed Check current road conditions. It explains the CCTV/field-check workflow, gives each road a reason derived only from its existing communityCondition (reported flooding, under verification, or outdated observations), and explicitly labels Open road details. A short footer distinguishes road updates from report decisions. Existing selection, authenticated road-details navigation, road status, and report-review behavior remain unchanged.

Validation: all 25 selected queue/timekeeping/admin-interaction checks passed, including urgent reports staying ahead of routine reminders and the urgent-only view excluding road reminders. The light/dark actual-widget renderer passed and both previews were inspected. Preview/log folder: `.usability-work-baseline/road-check-clarity-20261110/`. No APK built or installed.


### 2026-11-10 ? Small reporter avatar in admin evidence

Added an optional 36px UserAvatar beside Reported by/name in the current admin evidence card. Uses the existing protected image reader and person-icon fallback. Other ReportEvidenceContext callers retain their existing presentation by default; public resident report views are unchanged. Trust context remains a separate row and does not affect the avatar style. The admin workspace binds reporter name/photo/trust only when the profile ID matches the selected report owner.

Validation: 33 functional evidence/workspace/media checks plus the light/dark renderer passed, including a mismatched cached-profile guard and existing narrow/large-text layouts. Scoped analyzer: no errors/warnings; informational style lints only. Updated previews remain in `.usability-work-baseline/admin-evidence-refinement-20261110/`. No APK build, installation, or backend changes.
