# Re-routing verification — 19 October 2026

## Verified locally

76 tests passed across the four files below. The 12 navigation-screen tests run
the actual NavigationScreen with simulated GPS, route responses, and a substitute
map widget. Road changes use AppStateService's local mock update path. Speech
requests are captured through a mock platform channel. No production road records
are changed by these tests.

Static analysis found no issues in the navigation screen, routing service,
route tracker, and new test files. The map file still reports three warnings/info
items in unchanged code: experimental Android hosting mode, deprecated
`onTapListener`, and deprecated `cameraOptions`. No map analyzer errors were reported.

Run from the project directory, from any location:

```powershell
flutter test --no-pub test/route_tracker_test.dart test/routing_service_test.dart test/navigation_closure_test.dart test/navigation_flow_test.dart
```

| Screen simulation | Expected and verified |
| --- | --- |
| Sudden closure, Walking mode | Warning text, speech request, recalculation request, new route passed to map |
| Sudden closure, Sedan mode at walking speed | Same response; no minimum driving speed required |
| Closure before first GPS fix | No request without a position; closure handled after first fix |
| Second flood during cooldown | Queued request starts after cooldown without another GPS update; both closures included |
| Short sidewalk deviation followed by sustained deviation | Short deviation ignored; sustained qualifying deviation triggers a request |
| All returned paths blocked | No blocked result adopted; no-clear-route dialog displayed |
| Failed request | Retry waits for failure backoff and adopts the recovered route |
| Queued road reopens | Queued reroute dropped and warning cleared |
| New closure on detour while request is running | Outdated result rejected; fresh search includes both closures |
| GPS accuracy 80 metres | No false off-route trigger |
| Request never completes | Times out, leaves loading state, then retries successfully |
| Screen closed while request runs | Late result does not update the disposed screen |

Geometry tests also cover crossings between sparse route vertices, a closure
within the first 50 metres, and choosing a third candidate that avoids two closures.

## Fixes made during this review

- Retry scheduling now occurs after the failure cooldown has been recorded.
- A new closure that invalidates an in-flight result triggers another search.
- A queued road reopening clears its stale warning.
- A late request result cannot resume navigation after arrival.
- A duplicate trigger cannot release another request's lock.
- Initial turn speech respects an active hazard/recalculation.
- The map records a route as drawn only after the map source update succeeds,
  allowing a later redraw to retry a failed update.

## Current behavior to use as acceptance criteria

- A confirmed closure must have road geometry that intersects the remaining route.
  Changing a road elsewhere should not reroute this trip.
- Closure checks wait approximately one second after notification. They require
  an actual GPS fix; pinning a planner origin does not replace navigation GPS.
- Normal cooldown is eight seconds after completion. Failure backoff is
  16, 32, then 60 seconds, with at most four automatic failure retries.
- Off-route detection still requires three acceptable fixes over six seconds.
  The distance threshold is `clamp(35 + accuracy * 1.2, 35, 90)` metres.
  Accuracy worse than 60 metres is ignored. A few steps into a street will normally
  not trigger it. Updates are movement-filtered, so standing still does not
  guarantee further fixes.
- A newly drawn route in under two seconds is not implemented or guaranteed.
- Navigation tries three detour waypoint candidates. Failure to find a clear
  candidate does not prove that no real-world alternative exists.
- Confirmed closures are checked again before adopting the returned route.
  If none is usable, the app displays a halt warning; the old route line may remain.
- Hazards are rendered as road segments; two dedicated red circles are not implemented.

## Still requires device / service verification

These tests do not establish live Firebase synchronization, road-dataset accuracy,
Mapbox's available routes, native map rendering, audible TTS, or phone GPS quality.
They also do not build or install an APK. Install a fresh build before any retest.

For a controlled test, record the app build, road ID/name, selected travel mode,
GPS location/accuracy, status-change time, warning time, recalculation time, and
route-result time. Use approved test data when changing road statuses.

1. Verify the admin status save succeeds and the navigation device receives the
   changed road. A map road-color update is a useful visible check of reception.
2. Change a road ahead on the planned route, away from the start and destination.
   Expect the red banner, speech, and recalculation indicator, followed by either
   a clear alternative or an explicit no-clear-route outcome.
3. Close a road on the detour while keeping the first closure. Expect avoidance
   of both, or an explicit halt; never accept a new route through either closure.
4. Replay a GPS trace well outside the blue route for the required number of fixes
   and duration. Do not use just a few steps at a street entrance as the pass/fail
   test. GPS simulation can be used to exercise this before travelling.
5. Record any failure with its stage: update not received, warning absent,
   request stalled, no alternative returned, or new line not drawn. This separates
   service/device problems from the locally verified trigger logic.


## Navigation UI and rerouting integration audit: 27 October 2026

This audit reviews the redesigned navigation screen against the reroute engine.
Five focused screen replays first failed on the old code: a dropped GPS-interrupted
detour, false arrival during calculation and after failure, a critical prediction
behind progress, and an open Trip details sheet that did not receive road updates.
Additional replays confirmed the missing stale-weather advisory on an otherwise
unflagged route and a late failure announcement after ending the trip. These are local reproductions, not claims about a physical trip.

| Finding | Correction |
| --- | --- |
| Requested detour lost after GPS interruption; retries could lose requested avoid IDs | Retain the request reason and explicit exclusions, queue the interrupted check, resume through the existing GPS/cooldown gate, and preserve exclusions in automatic/manual retries. Pending work has a visible status. |
| Old route endpoint could replace an unresolved closure with arrival | Complete arrival only when guidance is not interrupted by rerouting, active hazard, failed check, pending refresh, critical review or no-clear-route state. Normal arrival remains covered separately. |
| Full travelled geometry could turn a newly predicted risk behind the user into a pause | Refresh active-trip safety against the remaining geometry while retaining the original route points, steps and destination. Alternative adoption and critical review still re-evaluate the full proposed route. |
| Open Trip details could retain old conditions and controls | Refresh the sheet from navigation changes, display its current notice, preserve the route-change reason and invalidate refresh callbacks on dismissal/disposal. |
| Missing/stale weather data could be omitted from the main navigation UI | Use the same existing live-data health signals as planning; add a caution or combine it with current uncertainty/success feedback. Listen for weather changes and detect freshness expiry without treating it as a physical closure. |
| A late failed request could announce a hazard after the user ended the trip | Invalidate failure/timeout handling when the screen is disposed, the trip has arrived or the request generation is obsolete. A screen replay first reproduced the late voice message after disposal. |

New checks also cover a valid normal arrival announced once, critical prediction
still ahead, manual detour retry exclusions, and a safety boundary proving that
remaining-path presentation cannot bypass full-route admission. Invalid evaluation
geometry remains blocked. Existing closure geometry, rapid-update serialization,
GPS freshness, critical review, staging, retry, tracker and responsive HUD checks
are retained. Movement-based hiding, road-risk thresholds and failure backoff
limits are unchanged. No new backend or paid service is introduced.

Audit artifacts, baseline snapshots and replay logs are grouped under
`.usability-work-baseline/rerouting-ui-audit-20261027/`.

Device acceptance remains open: replay closure ahead, a second closure on the
detour, GPS interruption/recovery and an actual connection failure on the test
phone while the admin emulator controls simulated conditions. Verify the new HUD,
voice, map line and destination together. Route-overview camera framing still
needs visual review on the device, especially with enlarged text. Dataset and
beneficiary-approved staging/destination accuracy are separate open dependencies.
The historical cause of the earlier off-route/push observations is not established
by these new tests. No APK build, install, emulator reload, backend deployment or
main-project change was performed by this audit.


Verification for this audit: the full suite passed **463 tests**, with one
optional benchmark skipped. A subsequently added shutdown replay reproduced
late failure speech; after its lifecycle guard was applied, **all 92 final
navigation, closure and HUD checks passed**. This covers 464 distinct regular
checks across these runs; it is not a claim that a second complete 464-test
suite was run after the small lifecycle guard. Ten screen replays and one
admission-boundary check were added. Final source hashes and separate run logs
are retained in the audit verification record.

Final scoped analysis completed with zero errors and zero warnings. Informational
style notices remain; the detailed analyzer output is in the audit folder.
