# Current one-phone navigation acceptance

2026-10-25. **User confirms installation, launch, TEST AREA, resident sign-in,
map loading and an apparently correct location marker.** The user checked Android
settings and confirms location is allowed while using the app, with precise
location ON. Measured GPS accuracy, area scope and navigation results remain
pending; phone model and Android version are not yet supplied.
There is no approved destination/evacuation list.
Automated success and a successful build do not count as navigation acceptance.
Current observations: `.usability-work-baseline/navigation-phone-acceptance.json`.

**GPS blocker, 2026-10-26:** the outdoor resident phone entered active navigation
but stayed on Waiting for a reliable GPS location after retry. The video confirms
the visible failure, without accuracy/age values. The
[GPS acquisition follow-up](gps-recovery-followup.md) fixes discarded retry results
and inconsistent shared stream settings while retaining the quality gates.
The updated test APK needs a fresh phone recovery test before closure/rerouting
can be accepted. The earlier installation and permission observations remain valid.

**Baseline fixture blocker found:** the user's two screenshots show the legacy
`spark-normal-form-road` simulated closure crossing their starting location,
with status Not Passable and risk 80/Critical. The attempted route was blocked.
This was contaminated test setup, not a passing planner/rerouting result.
**Server reset verified:** the synthetic road is removed, its incident and one
retained report are resolved, dangling neighbor references are absent, and the
successful worker's current topology cache excludes it. The other 735 roads'
official fields are unchanged. The retired seed command now refuses recreation
before credentials/cloud access. Evidence is in
`.usability-work-baseline/home-fixture-reset/result.json`; private backups remain
local. App Dart/APK and prior main/proof installer hashes are unchanged. Await a
fresh online phone view before retrying the baseline. Do not bypass normal
closure admission checks to make it pass. Future drills need an agreed public
road segment and a recorded reset/restoration step.

## Installer and account boundary

Use `.usability-work-baseline/review-candidate/SafePaths-Test-GPS-20261026.apk`
after `review-candidate/gps-apk-inspection-20261026.json` exists. Expected name
**SafePaths Test**, version **1.0.1-fieldtest**, package
`com.safepaths.safepaths_app.test`, version code `20261026`, Firebase
`safepaths-test`, five migration flags enabled. This is the normal full app
(`lib/main.dart`), not the old standalone report-proof screen. It currently uses
the repository's debug signing configuration for this isolated test installer.
Its app ID is separate from the main SafePaths installation.

Only the three existing synthetic accounts are accepted by the test backend.
Read login details privately in
`.usability-work-baseline/spark-proof-setup/PRIVATE-test-accounts.json`.
Do not send passwords, tokens or service-account files in chat. New registration
does not enroll an account into this proof cohort.

## First run

1. Transfer the inspected APK to the phone and install it manually. Open
   **SafePaths Test**, confirm the TEST AREA banner and normal resident dashboard.
   Record phone model, Android version and installation/launch outcome.
2. Sign in with the synthetic resident account. Allow precise location while
   using the app and the notification permission if requested. Record GPS
   availability, map loading and any displayed error. Never test while driving.
3. Check the current test area before choosing a destination: its centre is
   14.676139, 121.009417 and bounds are 14.667156–14.685122 latitude,
   121.000131–121.018703 longitude. Navigation requires actual usable GPS in scope.
   If outside, report that limitation; do not spoof a successful native test.
4. Browse all four quick categories. This area's catalog is deliberately empty;
   each should explain that no confirmed locations are configured and keep the
   destination empty. This does not validate the Marulas catalog data.
5. Choose a known, accessible nearby destination using a manual map pin. Check
   pin alignment, adjustment, cancel and re-open; confirm the intended entrance,
   origin, route endpoint and vehicle. Start a short route while stationary or
   safely walking with a companion. Record actual speech and map behaviour.

## Controlled rerouting with one resident phone

**Admin emulator, 2026-10-26:** Pixel_9 now has the inspected GPS test APK,
version `20261026` / `1.0.1-fieldtest`. Normal installation failed for insufficient
storage, so the older APK was backed up and replaced using the same certificate
and Android's keep-data option. The app ID and data-directory inode are preserved;
no emulator wipe or main-app uninstall was performed. Evidence:
`.usability-work-baseline/emulator-admin-install-20261026/result.json`.

The user's screenshot shows an admin screen but failed review-context loading;
they confirmed using their usual admin account. Protected test operations accept
the preset cohort. A read-only check with the preset test admin successfully
loaded `osm_way_552835264` (HTTP 200); no road/role changes were made. Native
sign-in with that account and successful review loading remain pending. Use the
private account entry marked `role: admin`, refresh the review, and confirm the
checkbox becomes enabled before any coordinated closure test. Evidence:
`.usability-work-baseline/admin-road-context-20261026.json`.

The computer can supply the synthetic admin action while the phone remains in
navigation. Do not begin a cloud drill until the resident confirms they are
ready and identifies the test road/route. Use only `safepaths-test` / the pinned
test backend, snapshot affected test roads/weather first, and restore them after
each run, including interruption. Record fixture IDs and restoration evidence.
No emergency notifications, real rescue request or main-project writes.

| Case | Action and acceptance |
| --- | --- |
| Closure ahead | Close one test road crossing the remaining route. Observe received update, warning/speech, request and replacement. Any adopted route must avoid every confirmed closure. |
| Unrelated closure | Close a test road away from the remaining route. No unnecessary reroute. Restore it. |
| Second detour closure | Close a road crossing the adopted detour. A later check must include both closures, including queued cooldown handling. |
| Wrong turn / GPS | Safely walk off-route. Threshold depends on accuracy; requires three qualifying fixes over six seconds. Disable precise/location service, then restore: no fabricated movement, arrival or repeated route storm. |
| Critical-only prediction | With a documented isolated fixture that yields a critical predicted-risk alternative and no navigable noncritical result, confirm paused guidance and explicit review. Cancel must stay paused. Acceptance must recheck current GPS and conditions. Do not pretend the case ran if Mapbox/fixture does not produce it. |
| Changed review | While review is open, change the candidate's closure/risk. Old confirmation must not adopt it. A fresh review/retry is required. |
| No route / reopening | When no usable result is returned, show an honest halt/recovery state. No configured staging locations means no invented safe-zone button. Reopen a blocking road and verify recovery attempt. |
| Network recovery | Let the phone receive a closure, then disconnect during the request. Observe clear failure/timeout, paused/hazard state and applicable retry after reconnection. A phone offline before an update cannot receive it until connected. |

Diagnostics (bug icon during test navigation) record `roads_checked`, request
events, `risk_review_required`, `risk_review_finished` and `route_adopted`.
They exclude exact GPS coordinates and credentials. Save/copy the session log
and record the local filename, phone/Android, test case, fixture IDs, visible
message, speech, route adoption and restoration. Check the actual GPS accuracy
and event timestamps rather than assuming a fixed reroute time.

## Acceptance record

| Gate | Current evidence |
| --- | --- |
| Automated logic | Full 331 passed / one optional skip; selected exact fieldtest configuration 172 passed; analyzer zero errors / four existing warnings. |
| Installer identity/assets/signature | See `review-candidate/navigation-apk-inspection.json` after build. |
| Installation, launch, TEST AREA banner | Passed by user report: "Installed; I see TEST AREA". |
| Resident sign-in, native map, location marker | Passed by user report; marker looks correct, not measured accuracy. |
| Foreground / precise location permission | Passed by user settings report: allowed while using; precise ON. |
| GPS accuracy, freshness and test-area scope | Native navigation blocked waiting for GPS in the outdoor recording. GPS follow-up build/retest pending; no GPS or reroute pass claimed. |
| Pin, endpoint, speech | Pending user observations. |
| Initial baseline route attempt | Blocked by legacy synthetic reporting fixture at the origin. Server reset verified; phone refresh and repeat route test pending. |
| Hosted road changes and phone receipt/reroute | Pending coordinated one-phone run and restoration log. |
| Critical-risk native review | Pending documented fixture and phone result; automated cases already pass. |
| Actual Marulas destinations/entrances | Pending approved data and physical/provider check in the main area; this test catalog is empty. |

Two independent resident routes still require two phones or a later separate
session. Push receipt/taps, small-capstone workload/B-05 and full main Spark
integration remain separate gates. Do not mark a case passed without its result.
