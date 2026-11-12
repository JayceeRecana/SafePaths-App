# GPS acquisition and retry follow-up

2026-10-26. The resident reported being outdoors, with precise location enabled,
while navigation remained on "Waiting for a reliable GPS location" after Retry
GPS. Their 51-second recording shows the planner, active navigation, a disabled
then re-enabled retry button, and an updating Mapbox location marker. The
recording does not show measured GPS accuracy or fix age.

## Confirmed implementation gaps

1. Retry requested a validated coordinate, discarded it, restarted its stream
   subscription and waited for another event. A successful one-shot acquisition
   could therefore leave navigation waiting. A regression reproduced a queued
   closure receiving zero reroute requests after retry, instead of one.
2. UserHome started a Geolocator stream with a 100-metre movement filter before
   navigation requested a one-metre filter. The installed geolocator_android
   5.0.3 caches its first stream across subscribers without changing settings.
   The home feature could therefore impose sparse updates on navigation. Mapbox's
   separate location marker can continue moving during this condition.

## Resulting behavior

- Home and navigation use the same high-accuracy, zero-distance-filter stream.
  The installed Android provider defaults to a five-second interval. The home
  feature still throttles its own proximity work to 100 metres and skips that
  work while navigation is active.
- Navigation obtains an initial one-shot fix and applies retry results through
  the same handler as streamed fixes. `LocationService.getCurrentFix` preserves
  timestamp and accuracy; the planner's coordinate-only wrapper retains its
  existing quality checks.
- The native one-shot request has a 15-second time limit, which the installed
  plugin cancels on timeout. Navigation bounds the whole acquisition at 20 seconds.
  The retry button shows progress and prevents simultaneous repeated requests.
- A failed or older one-shot cannot replace a newer accepted position. An older
  result also cannot recover guidance after a stream error. Disposed navigation
  ignores pending results. Pending closure work resumes after a valid fix.
- Rejected fixes explain accuracy, age or an ahead-of-clock timestamp. Test
  diagnostics include accuracy, age, source and GPS outcome without adding exact
  coordinates or credentials.

The quality gates remain **accuracy at most 60 metres**, **age at most 30 seconds**,
and **future timestamp at most five seconds**. No timestamp is fabricated and no
closure/risk admission rule is weakened. The installed GPS library and lockfile
are retained; no dependency upgrade is part of this fix.

## Verification and device acceptance

Sixteen new regressions cover metadata preservation, native request limits,
poor/stale/future fixes, initial acquisition, retry without movement/events,
progress/timeout, older/error races, stationary fresh updates, permission denial,
shared stream settings and disposal. **347 full Flutter tests passed**, with one
optional benchmark skipped; **188 selected exact-fieldtest checks passed**.
Analysis has **zero errors and four unchanged warnings**, with 348 total findings
including informational/style items. Final checks and APK inspection are recorded under
`.usability-work-baseline/gps-retry-20261026/verification.json` after packaging.
The original video and previous inspected phone/emulator APK remain unchanged.

Install **SafePaths-Test-GPS-20261026.apk**, version **1.0.1-fieldtest** / code
**20261026**, as an update to SafePaths Test, then test navigation
outdoors while safely stopped. Confirm the GPS banner clears or record its new
explanation and the diagnostics `accuracyMeters`, `fixAgeSeconds`, `gpsOutcome`
and `fixSource`. A precise permission grant alone does not prove GPS quality.
After usable GPS and a normal route are observed, perform the controlled admin
closure-ahead test and restore the chosen public test road afterward.

**Physical GPS recovery and end-to-end rerouting remain pending.** Source fixes
and automated replays cannot establish the phone's actual GPS quality or native
receipt/adoption of a road update. See [phone acceptance](navigation-phone-acceptance.md).
