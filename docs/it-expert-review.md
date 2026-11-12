# IT expert review follow-up

Source: SafePaths-Enhancements-Bugs-and-Recommendations.pdf (four pages).

**Current navigation/data follow-up, 2026-10-25:** [R-01 fix](planner-readiness-review.md)
prevents silent critical-risk adoption; current explicit review is required.
The [all-category audit](quick-destinations-audit.md) corrects supported facts and
withholds eight unresolved records and unapproved fallback recommendations.
331 full Flutter passes (one optional skip), 172 selected exact-fieldtest checks,
zero analyzer errors and four unchanged warnings. A separate test APK is authorized
for [manual phone acceptance](navigation-phone-acceptance.md); physical results,
approved entrances/designations and main integration remain open.

**Rerouting scenario follow-up, 2026-10-25:** [behavior and evidence](rerouting-scenario-acceptance.md)
implements advisory reconciliation, staging selection/revalidation, reopening
recovery and first-failure feedback. Current results: 297 full Flutter passes
(one optional benchmark skipped) and 156 complete-fieldtest checks. The twelve
suggested scenarios are conditional acceptance cases; native navigation and
workload acceptance remain open and no new APK was built.

**Planner/rerouting follow-up, 2026-10-25:** [review and evidence](planner-rerouting-reliability.md)
adds current-condition admission checks, closure-priority ranking, obsolete-work
cancellation, real/manual origin requirements and GPS/reroute recovery. The
current full suite passes 278 tests (one optional benchmark skipped), with 137
checks under the complete test configuration. Outdoor GPS, live provider,
native-map/layout and stress acceptance remain open; no APK was built.

## Changes implemented

| ID | Change | Remaining validation |
| --- | --- | --- |
| B-01 | FROM opens the map picker; selected start points recalculate routes. GPS button restores device location. Late GPS results cannot overwrite a manual choice. | Verify pin selection, GPS permissions, and navigation on Android. |
| B-02 | Dashboard has a visible search submit button, bounded network wait, failure feedback, and local study-area lookup. Planner shows local matches immediately, ignores obsolete remote results, and shows an empty-result message. | Verify actual search credentials, local road data, and place coverage on device. |
| B-03 | Planner header wraps on narrow widths; muted search text uses a darker foreground. | Reproduce the expert's exact overlapping text on their screen size and font setting. |
| B-04 | Photo picker limits dimensions, caps input size, guards repeated taps and disposed screens, bounds preview decoding, and handles preview failure. Compression runs off the UI thread and preserves aspect ratio. Upload errors preserve the form; storage operations have timeouts. Oversized embedded-photo database fallback removed. Form inputs lock during submission. | Test real camera/gallery permissions, offline uploads, storage credentials, and unusual images on Android. |
| B-05 | Watermark decoding is bounded and native image resources are disposed. Search results are capped, stale work is discarded, and image compression runs in an isolate. | OPEN: structured device/load testing must establish the original failure and confirm recovery. No claim of load-test completion. |
| E-01 | Separate show/hide buttons for password and confirmation. | Automated small-screen widget check. |
| E-02 | Registration requires 8 characters, uppercase/lowercase, number and special character; live requirement count, progress, mismatch feedback, and submit validation. Duplicate registration submissions blocked. | Client-side enforcement added. Align Firebase project's password policy separately for server enforcement. |

## Recommendations checked or deferred

- Firebase Authentication already handles account credentials; the app does not store raw passwords in user profile records. Password-reset and verification coverage still requires a separate account-flow review.
- Reports already have pending status, timestamps, a five-minute submission cooldown, and location checks in AppStateService. Pending status alone does not establish private photo moderation: photo visibility, storage access, automatic consensus approval, and admin workflow need a separate review before claiming moderation is complete.
- Photo compression existed but distorted some aspect ratios and ran on the UI thread; this pass corrects those paths. Output is JPEG. No automated offensive-content screening was added.
- Mapbox pricing/terms, billing, moderation provider selection, privacy/retention policy, bilingual UI, offline caching, and background notification reliability remain follow-up items. No paid services were enabled or backend rules deployed.

## Device acceptance checklist

1. Choose a FROM pin while GPS is still loading; it must remain selected after GPS completes. Change back to GPS and verify route recalculation.
2. Search a monitored street, catalog landmark, study-area name, unknown name, and with internet disabled. Type a second planner query before the first finishes; obsolete matches must not appear.
3. Check planner text on small screens and large system fonts with long route summaries.
4. Attach portrait, landscape, tiny, corrupt, and large photos. Cancel the picker and leave the screen during processing. Repeat attach/remove cycles while watching memory and responsiveness.
5. Disable networking during upload: the screen must recover with the form preserved, allow retry, and never falsely show success.
6. Record the original stress-test scenario, device/Android version, concurrent load, response times, memory, error logs, and recovery. Re-test all reported issues before final evaluation.

## Automated validation

- Full Flutter test suite: 130 tests passed, including 8 new regression checks.
- Targeted Flutter analysis: no compile errors; existing warnings/lints remain, plus an informational redundant typed-data import in the upload screen.
- Diff whitespace check passed for the edited tracked screens and routing service.
- No device stress test or live storage/map integration test was performed.


## Deferred reminder requested by the team

- [ ] Revisit **4.2: inappropriate photo uploads / moderation** before resident release. Deferred while implementing section 5, starting with 5.1. No timed reminder notification has been scheduled.

## Section 5.3 follow-up

See `photo-upload-5.3.md` for strict JPEG/PNG validation, processing/upload/save stages, byte-based progress, cached-photo retries, and Android smoke-check results. Live upload/permission/device acceptance and coordinated rollout remain explicit release checks.

## Section 5.2 follow-up

See `report-reliability-5.2.md` for observation/submission ages, persistent unknown-road caution, protected resident responses, admin verification, legacy migration, and rollout/device acceptance. PAGASA advisory integration remains a follow-up. No production deployment or new APK distribution was performed.

## Section 5.4 follow-up

See `performance-5.4.md` for bounded history, complete active-hazard feeds, map redraw/caching/failure handling, reproducible local workload results, and the physical Android test matrix. The retained run passed the 5/10-user bursts but failed the 20-user same-road report burst; retries preserved all reports without duplicates. Emulator variability, staging latency, physical-device profiling and reproduction of B-05 remain open. Section 5.4/B-05 is not closed by the automated test count. No APK or production deployment was performed.

## Section 5.5 follow-up

See `usability-accessibility-5.5.md` for persistent cache timestamps, restricted read-only saved roads after an offline account check, explicit feed states, English/Filipino interface selection, accessible road browsing, notification permission/tap handling and saved light/dark appearance. Themes were implemented last as requested. Device, native-map, push-delivery, translation and screen-reader acceptance remain open; automated checks do not close 5.5 by themselves. No APK or production deployment was performed.

## Sections 5.6 and 5.7 follow-up

See [privacy and consent review](privacy-consent-5.6.md) for the supplied consent/survey findings, current data inventory and unresolved project-email, controller, retention and report-visibility decisions. Limited local diagnostic/follow-up changes do not complete privacy implementation. See [evaluation readiness](evaluation-readiness-5.7.md) for expected/actual test cases mapped to the survey, automated evidence and still-open staging/device acceptance. Neither section is marked complete and no rollout is authorized.
