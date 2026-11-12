# Section 5.5 — usability and accessibility

## Road-details follow-up — 2026-10-26

Road details now puts recorded condition, a single admin update and separate broadcast advisories before resident observations and reports awaiting review. Report/update actions precede expandable prediction details. The duplicate Current Conditions container and calculated High/Moderate/Low Accuracy percentage were removed. Model scores are labeled out of 100 and explained as estimates rather than measured accuracy or a safe-travel guarantee. Weather labels include partly cloudy, light rain and moderate rain.

The review list includes matching-road pending/under-review observations less than 24 hours old, newest observation first. Loading, saved data and refresh failure have distinct messages; only an online result shows an authoritative count or an empty-result message. Saved reports remain readable and retries use the existing synchronization path. Reviewed or outdated reports leave this list without changing the road's official condition. Report taps still open the existing details sheet. The report-count badge uses the foreground color paired with its container.

The shared AppTheme/AppPalette styling and the existing styled resident-observation panel are retained. That panel omits its duplicate admin summary only when embedded in road details; its default presentation elsewhere is preserved. English/Filipino layouts at 360px and 1.8x text scale pass in both themes, including expanded prediction details. The complete Flutter suite passes **378 tests**, with one optional benchmark skipped. Seven focused road-details cases cover filtering, connection states, saved-report taps, verification transitions, duplicate-note removal, hierarchy and large-text layouts. Local evidence is grouped in `.usability-work-baseline/road-details-20261026/`.

The matching fieldtest flavor and public test-area configuration pass all **16 selected road-details/incident checks**. Static analysis of the changed Dart files reports no issues. Application and dependency hashes match the passing full suite; the only subsequent test change removed a redundant import and was covered by the selected fieldtest run. A preliminary check with production flavor plus fieldtest settings was correctly rejected by the existing environment guard; the final matching configuration passes.

After the user's first visual review, the admin card gained a blue accent, an admin icon, stronger heading/body text and a separate timestamp row. A 24px gap separates it from the status/advisory, and the repeated admin-source label below the street name is removed. All seven road-details checks pass again with the fieldtest settings, including both languages/themes at enlarged text. The user will reload and review this visual adjustment.

No new APK or backend/rule deployment was performed for these follow-ups. Earlier dated results below remain historical checkpoints.

---

Implemented locally on 2026-10-24. Light/dark appearance was implemented after offline feedback, notification handling, language selection and the initial accessibility checks, as requested. Device acceptance remains open. No APK was built/installed/distributed and nothing was deployed for this work.

## Implemented behavior

| Area | Behavior |
| --- | --- |
| Saved road information | Last successful online road synchronization time survives restart, scoped to the Firebase project. Cached snapshots do not advance it. The banner distinguishes missing saved roads, cached conditions and incomplete live updates, and shows the date as well as time. |
| Offline account gate | After a network failure during account checking, an existing verified, non-anonymous, unexpired session can open **View saved roads (read only)**. The viewer reads only Firestore's local road cache with a bounded wait. It offers no reporting, routing, profile or admin controls. Permission/authentication failures do not enable this path. Existing resident/admin inactivity limits remain in effect. Unknown cached roles use the shorter limit and grant no administrative access. |
| Offline meaning | The saved viewer labels status and timestamps as **last recorded**, with present conditions explicitly unconfirmed. An empty cache is explained as unavailable information. Native Firestore cache can be absent or evicted. Map tiles may be absent; no offline-region download or offline turn-by-turn navigation was added. Creating a report still requires the server. |
| Screen states | Alerts distinguish loading, failure, saved results and a confirmed online empty result. Feedback history no longer turns an error or empty cached query into “no history.” Map/history/upload retry handling from earlier sections is retained. |
| Accessibility | Shared top-bar buttons have labels and standard targets. Bottom navigation shares available width, wraps labels, supports keyboard activation and retains selected semantics. A searchable **Road list** opens road details without tapping native map lines. Observation ages and status labels have localized presentations. System text scaling is preserved. |
| Language | Settings saves English/Filipino selection; Flutter's built-in controls follow it. The catalogs contain 744 curated interface messages, including safety, cache, account, report and admin labels. Generated Dart lookup data is checked against its JSON sources. Reports, road names, official notes, saved templates and administrator-authored alerts retain their original content. |
| Notifications | Settings shows actual notification permission/channel availability and offers permission rechecking and phone settings. Checks repeat after returning from settings. Cold-start remote/local notification taps wait for a home handler instead of a fixed delay. Handler ownership prevents disposal of an old home from removing a newer handler. Sign-out clears queued contents. Foreground FCM message IDs are deduplicated with bounded memory; Firestore alert listeners no longer display a duplicate system notification. Token synchronization waits are bounded. |
| Appearance, implemented last | Settings saves Phone/Light/Dark. Screens use context-bound palettes; neutral surfaces and accent foregrounds adapt to the selected appearance. The native map uses the existing custom light style and Mapbox's dark style, with overlay invalidation/retry handling. Core body, accent and safety text pairs are tested at 4.5:1 or better in both palettes. |
| Accurate confirmation | Report confirmation says saved for review and does not promise that rescue has been dispatched. Notification permission or server acceptance is not presented as proof of device delivery. |

The normal online account gate still refreshes credentials and validates the server profile before opening the operational app. The saved viewer is a separate presentation of information already on the phone. It does not extend sessions, change backend rules, or allow cached roles to authorize writes.

## Validation

- Full Flutter regression suite on re-check: **197 passed**, with the opt-in map CPU benchmark skipped. See `recheck-2026-10-24.md` for the notification verification fix, its two additional checks, and the passing backend/emulator results.
- Fifteen section 5.5 checks cover language/appearance persistence, catalog parity, preserved authored text, offline-empty semantics, small-screen 200% text, navigation target size, core contrast pairs, preserved form text on theme changes, relative ages, notification tap queuing/clearing, cached-reader eligibility, and saved-reader data/empty/error states.
- Full `flutter analyze lib test`: no compile errors. Existing informational lints and warnings remain; this is not a clean-lint claim.
- Focused analysis of the new usability code and tests: **no issues**. The final app-entry-point check also passed, with two existing informational notices.
- No live push-delivery test, physical Android cache/restart test, screen-reader walkthrough, or comprehensive screen-by-screen accessibility certification was performed. Native map style switching still needs phone verification.

## Device acceptance before closing 5.5

Use the team's available Android phones; record model, Android version, app revision and result. A small capstone team can run this matrix without buying a device lab.

| Scenario | Expected result | Status |
| --- | --- | --- |
| Load roads online, disable internet while using the app | Saved data is visibly distinguished from live data; closures remain visible. New route/report failures have recovery feedback. | Pending |
| Close/reopen offline during a valid session | Account check fails visibly; read-only saved roads can open. No route/report/admin actions are offered. | Pending |
| First install/no road cache, expired session, unverified account | No fabricated road status; no offline bypass of verification/session rules. | Pending |
| Reconnect and retry | Current data replaces cached data; synchronization timestamp advances only on online confirmation. | Pending |
| English ↔ Filipino; restart | Choice persists. Critical warnings remain clear. Review wording with a Filipino-speaking team member. | Pending |
| 200% text, narrow screen, TalkBack | Read login, settings, alerts, road list/details, report form, history and route warnings; reach controls and read errors without clipping or relying on color. | Pending |
| Light ↔ Dark ↔ Phone; restart; change OS theme | Selection persists, drafts remain, dialogs are legible, map style changes, and road/route overlays reappear correctly. | Pending |
| Push in foreground/background/locked screen and ordinary terminated state | One visible notification where permitted; tap opens the appropriate home/history after account access is established. Compare stored alert with receipt. | Pending |
| Deny app permission or disable alert channel; return from settings | Settings accurately describes the blocked state. Received/stored alerts remain readable in the app. | Pending |
| Force-stop in Android Settings, then send push | Treat missing delivery as an OS limitation; reopen the app and inspect its stored alerts. Do not claim guaranteed emergency delivery. | Pending |
| Change account while a notification tap/startup check is pending | No old-account report details or handler are surfaced to the next account. | Pending |

Some dynamic service errors, route narratives and provider-generated directions can still fall back to English. The static-copy inventory is not proof that every runtime sentence is translated. The bilingual walkthrough must cover these paths and add reviewed messages as needed. Likewise, core-palette contrast checks do not establish that every custom chart, gradient, photo overlay or native-map label meets WCAG.

## Translation maintenance

Catalog sources live in `lib/l10n/*_fil.json` and `lib/l10n/filipino.json`; `lib/l10n/app_strings.dart` is generated. Interface calls use `tr(context, message)` so locale changes rebuild the appropriate widgets. Do not pass authored report or broadcast content through interface translation.

From the workspace root, using the existing Dart SDK:

```powershell
Push-Location scripts/localization
try { dart pub get --offline } finally { Pop-Location }
dart --packages=scripts/localization/.dart_tool/package_config.json scripts/localization/apply.dart
dart format lib/l10n/app_strings.dart
flutter test test/usability_accessibility_test.dart
```

The isolated analyzer tool does not add analyzer dependencies to the application. Catalog tests reject duplicate or empty translations and stale generated data.

The photo-moderation follow-up in **4.2** and the staging/device performance work in **5.4** remain open independently of this section.
