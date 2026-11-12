# SafePaths Test: setup and two-phone checks

**November 1:** [Marulas integration](marulas-main-integration.md) now has a
separate reviewed configuration. The historical production build command below
does not include it and must not be used for the main candidate.

**Current test-only authorization, 2026-10-25:** the user requested the navigation
fixes followed by controlled phone tests and can install the test APK manually.
Use the [current one-phone installer/protocol](navigation-phone-acceptance.md).
The historical baseline build commands below omit newer migration flags; use
`functions/tools/prepare-review-defines.cjs` and the public define file with all
five flags for the current full-app candidate. Build flavor must be `fieldtest`.
Only three synthetic accounts are accepted; new registrations are not enrolled.
Main build/rollout and billing changes remain outside this authorization.

The [integration audit](full-app-integration-audit.md) recorded road-maintenance
gaps, now covered by [test-only maintenance acceptance](road-maintenance.md).
The existing core native flag routes maintenance to the new protected server
commands; no sixth native flag is needed. A local candidate defines file can be
prepared with `node functions/tools/prepare-review-defines.cjs`; this does not
build or deploy. The explicit preparation script's `-DeployRules` option now
uses `firebase.spark-proof.json` and pins the existing `safepaths-test` project,
so it includes all 14 required indexes. That deployment option was not run in
the audit phase.

SafePaths Test uses the existing navigation screens and rerouting engine. Its Android ID is `com.safepaths.safepaths_app.test`, so it installs beside SafePaths. Look for the orange icon badge and persistent TEST AREA banner.

The test area is centered at **14.676139, 121.009417**. Bounds: west 121.000131, south 14.667156, east 121.018703, north 14.685122. The map center is only a camera position; route planning requires real device GPS. No evacuation facilities are designated here.

## Firebase checklist

Completed in this workspace on 2026-10-19:

- Separate Firebase project: `safepaths-test`.
- Downloaded Android configuration matches `com.safepaths.safepaths_app.test`.
- User confirmed Email/Password authentication and Firestore are enabled.
- Firestore rules and index configuration deployed explicitly to `safepaths-test`.
- Clear simulated weather initialized in the test project's `system/weather` document.

For a new setup:

1. Open [Firebase Console](https://console.firebase.google.com/), create **SafePaths Test**, then register an Android app with package `com.safepaths.safepaths_app.test`.
2. Save its downloaded `google-services.json` to `android/app/src/fieldtest/google-services.json`. Leave `android/app/google-services.json` intact.
3. Enable **Authentication → Sign-in method → Email/Password**.
4. Create **Firestore Database → (default)**. Deploy this repository's rules using the explicit test project command below.
5. Run the preparation script. It checks the project and app IDs, then creates `.env.fieldtest` containing only the test project ID and public Mapbox token. Neither `.env.fieldtest` nor the downloaded test JSON is committed.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-fieldtest.ps1
firebase.cmd login
firebase.cmd deploy --only firestore --project safepaths-test --config firebase.fieldtest.json
node scripts/seed-fieldtest-weather.cjs
```

The weather helper uses the existing Windows Firebase CLI login in memory, creates only a missing test `system/weather` document, and preserves existing weather. It was checked against Firebase CLI 15.28.2. Alternatively, create `system/weather` in the **test** console with `currentState` string `clear`, `isOverrideMode` boolean `true`, `precipitationIntensity` number `0`, and `windSpeed` number `0`. Do not add an expiry field. Test weather never polls production or live weather services; reset returns it to clear.

## Build and install

From the repository root with Flutter and Android SDK installed:

```powershell
flutter pub get
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-fieldtest.ps1
flutter build apk --flavor fieldtest --release
flutter build apk --flavor production --release
```

Outputs:

- Test: `build/app/outputs/flutter-apk/app-fieldtest-release.apk`
- Production: `build/app/outputs/flutter-apk/app-production-release.apk`

The current Android release build uses the repository's existing debug signing configuration; this APK is for direct testing. Transfer the **fieldtest** APK to both phones, open it, and allow installation by the selected file manager if prompted. Do not uninstall the Marulas app. Allow precise location and turn up media volume for spoken guidance.

For USB installation instead:

```powershell
adb devices -l
adb -s PHONE_SERIAL install -r build/app/outputs/flutter-apk/app-fieldtest-release.apk
```

Run the installation command separately for each phone serial. Missing or inconsistent Firebase/environment configuration displays a startup error instead of opening production services. Photo reports, avatar uploads, feedback image attachments, and broadcast push sends are unavailable in this build. Local navigation banners and speech remain enabled.

## Accounts and road import

1. Register one navigation account and one administrator account through **SafePaths Test**. Use passwords privately on the phones.
2. In the **safepaths-test** Firestore console, open `users/{admin UID}` and change its `role` string from `user` to `admin`. Sign out and sign in again on the admin phone. Keep the navigation user's role as `user`.
3. On the admin phone, open **Import Roads**, fetch the area network, and preview candidate segments using their map buttons. The query includes public roads, walking paths, and unnamed connectors. Labels include OSM IDs so matching street names remain distinguishable.
4. Import the selected connected network. The importer retains one document per OSM way (`osm_way_ID`) and separate geometry segments. It does not apply Marulas-specific splitting. Existing IDs are skipped; imports are committed in batches.
5. Confirm roads appear in **safepaths-test → roads** and on the navigation phone. Do not move or copy Marulas records.
6. Preview routes before choosing a short ordinary path A, an accessible detour B, and a second alternative C. Keep closures ahead of the GPS position and leave the starting position and destination reachable. No specific local paths have been field-verified yet.

## Two-phone test script

Use legal pedestrian access. Walking mode is the primary sidewalk test. A Sedan-mode test while walking can verify closure handling, but it does not reproduce vehicle GPS behavior or pedestrian routing permissions.

Before each scenario, confirm TEST AREA on both phones, clear weather, good GPS accuracy, and matching road IDs. Start navigation on phone 1 and open the bug icon for diagnostics. Phone 2 changes the selected road's actual status to **Not Passable** and saves it. A pending user report is a different workflow.

| Scenario | Action | Expected observation |
| --- | --- | --- |
| Sudden closure | While navigating A, close a segment ahead that intersects the remaining blue route. | Red warning and spoken alert; a recalculation attempt; safe replacement if one is returned. A closure received before the first GPS fix is checked when GPS arrives. |
| Sustained wrong turn | Walk away along an accessible side street; stay beyond the off-route threshold for multiple good fixes. | Recalculating appears, then a route from the current position or an explicit failure. A few steps into an entrance are normally ignored. |
| Two closures | Keep A closed; after taking B, close B ahead too. | A second attempt, including after a queued cooldown. An adopted C must avoid both confirmed closures. If none is available, the app must say so rather than adopt a blocked route. |
| Reopening | Reopen the blocked segment. | A pending obsolete closure is cleared. If halted because of that closure, the app attempts recovery. A normal detour need not immediately switch back to the original road. |
| Network recovery | First let phone 1 receive a closure, then interrupt its internet during recalculation; restore it. | Explicit failure/timeout and applicable retry. A phone offline before an update cannot receive that update until reconnecting. |

Current wrong-turn gates are unchanged: distance threshold `clamp(35 + 1.2 × GPS accuracy, 35, 90)` metres, at least 3 qualifying fixes spanning at least 6 seconds. Fixes with accuracy worse than 60 metres are ignored. For example, 10 m accuracy requires over 47 m from the route. There is a 1-second road-update debounce and existing cooldown/backoff behavior. An individual reroute request can time out after 18 seconds. A new route within 2 seconds is not guaranteed.

The diagnostics panel records GPS accuracy, distance to route, app road-update callbacks, trigger reason, request start/finish, route count, outcome, cooldown at events, and error types. Its road-update callback can also be invoked by other app-state changes: check `roads_checked` and its IDs to identify the closure. Timestamps use UTC; cooldown is a snapshot, not a live countdown. Copy the log to a local notes/file app or use **Save local file** (the dialog shows its app-private path). Logs contain no credentials or exact GPS coordinates and retain at most 2,000 events per navigation session.

Record this for each run:

```text
Phone/model and mode:
Start/destination and closed OSM road IDs:
Admin save time:
GPS accuracy and route distance:
Road callback / roads_checked time:
Request start / finish, outcome, cooldown:
Banner / speech heard / route changed:
Did the adopted route avoid every confirmed closure?
Session log filename:
```

Acceptance requires a received closure intersecting the remaining route to warn and attempt recalculation, adopted routes to avoid confirmed closures, and failures to show an explicit outcome with applicable retry. Also verify that registered users, imported roads, closures and weather writes appear in **safepaths-test**, and that the production app still opens the Marulas area. Device installation, speech, GPS, live synchronization, actual test-path selection and these field scenarios remain to be checked on the two phones. A final Marulas network check remains necessary.

## Repeat automated verification

```powershell
flutter test --flavor production test/route_tracker_test.dart test/routing_service_test.dart test/navigation_closure_test.dart test/navigation_flow_test.dart test/fieldtest_configuration_test.dart
flutter test --flavor fieldtest test/fieldtest_configuration_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

The production-flavor run covers the existing 76 routing tests plus 8 configuration/GPS/import/segmented-geometry/log tests. The configuration tests also run with the fieldtest flavor. Use `--flavor`; do not manually define Flutter's reserved `FLUTTER_APP_FLAVOR` variable.

References: [Flutter Android flavors](https://docs.flutter.dev/deployment/flavors), [Firebase Android setup](https://firebase.google.com/docs/android/setup), [Email/Password authentication](https://firebase.google.com/docs/auth/flutter/password-auth).
