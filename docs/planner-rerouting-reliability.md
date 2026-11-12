# Planner and rerouting reliability review

**Scenario follow-up, 2026-10-25:** [current behavior and acceptance](rerouting-scenario-acceptance.md)
resolves advisory cleanup, staging revalidation, reopening through GPS loss and
first-failure feedback. Staging options exclude critical predictions and prefer
routes without known/unconfirmed conditions before travel time; they require
local suitability confirmation. Current verification is 297 full Flutter passes
(one optional benchmark skipped) and 156 complete-fieldtest checks. Counts below
describe the preceding checkpoint. Native/live-provider,
workload and main-integration acceptance and the APK hold remain open.

Local implementation and automated verification completed on 2026-10-25.
This review addresses the user-requested planner/rerouting gaps. It does not
close physical navigation acceptance, load testing or main-backend integration.
The existing APKs do not contain these changes; building, installing and
distributing a new APK remains on hold.

## Findings and resulting behavior

| Gap | Implemented behavior |
| --- | --- |
| Production planning substituted the map's default center when GPS was missing. | Both flavors wait for a usable device location or an explicit manual FROM point. A failed GPS lookup explains how to recover. A late lookup cannot replace a manual selection. |
| Older calculations or GPS lookups could outlive their planning session. Editing the destination could leave an old route available. | Session/calculation ownership invalidates obsolete work. Clearing/editing the destination clears its routes and loading state. Disposing an older planner cannot cancel a newer session. Identical start/destination points are rejected before requesting directions. |
| Closures could arrive while directions were pending or after routes were displayed. | Returned routes are evaluated against current road/weather state before adoption. Visible planner/preview safety refreshes with data changes. Closed routes rank after open alternatives regardless of their travel cost. |
| Planner and preview had different navigation checks. A caution dialog could become outdated. | Both use the same admission check. Reported/predicted risk, unconfirmed coverage and unavailable live data require caution. Conditions are checked again after confirmation; changed conditions require another review, and a closure prevents starting. |
| Preview selection depended on mutable list order/summary text. | Selection follows the chosen route geometry rather than a list index. Navigation receives its own destination, name and travel mode instead of reading subsequent planner choices. |
| Poor, stale or invalid GPS could become a reroute origin or trigger arrival. Voice could start before usable GPS. | Navigation validates fixes before accepting their position. Guidance pauses with a visible GPS recovery action. Reliable telemetry resumes queued hazard checks/retries. A stale retry timer cannot consume another cooldown without making a request. Turn instructions wait for a usable fix. |
| An alternative computed from an old origin could be adopted after substantial movement. | If the user moved over 90 m during a request, each returned candidate must connect within 90 m of the current fix. Disconnected alternatives are discarded. When none connect, navigation requests a fresh route after cooldown. |
| Provider outages and invalid directions could appear as an absence of routes. Cancelled work could continue launching detours. | The complete calculation has an 18-second default budget; navigation uses its existing 12/18-second budgets. Obsolete work cannot launch a later detour batch or replace newer results. Service failures remain errors; invalid alternatives/instructions are isolated. If every attempted detour request fails, the result is a service failure rather than a no-alternative verdict. |
| Safety refresh could lose exact distance/avoidance costs; unmonitored parts could appear fully confirmed. | Routes retain provider distance and requested road-avoidance metadata when refreshed. Outside-area portions display unconfirmed coverage. Predicted risks below the existing critical threshold still require caution. Obsolete comparison claims are cleared after safety changes. |

Core risk weights, official-closure policy, Mapbox request parameters, report
moderation, cloud schedules and backend permissions were not changed. Risk
scores are model outputs, not measured probabilities that travel is safe.

## Verification

- **278 Flutter tests passed**, one optional map benchmark skipped, in the
  default configuration. This is 26 more tests than the preceding maintenance
  checkpoint: 18 new planner/admission cases and eight new navigation cases.
- **137 tests passed** with the fieldtest flavor and all six migration/push
  defines enabled: environment, report/core/communication/media/maintenance
  compatibility plus planner, navigation, routing and tracking.
- Full analyzer: **zero errors, four existing warnings**, 341 findings including
  informational/style items. The analyzer exits nonzero for those findings.
- A recoverable 264-file source checkpoint was retained before this phase.
  Backend/rules/SQL/native configuration and all four existing APK hashes are
  checked against the preceding checkpoint.
- No live Mapbox request, phone operation, cloud deployment or stress run was
  performed. The preceding 60 backend-unit and 98 emulator passes remain dated
  maintenance-phase evidence; those suites were not rerun for these Dart changes.

The new tests replay destination/session races, closures during HTTP and
confirmation, open-versus-closed ranking, exact cost preservation, cancellation,
timeouts, malformed candidates/instructions, coverage warnings, poor/stale GPS,
stream interruption/retry, frozen trip settings, movement during rerouting,
arrival rejection for stale positions, and voice startup. Native maps, GPS,
provider responses and platform speech are replaced at their boundaries.

Implementation lives in the routing service, planned-route model, planner and
preview screens, navigation screen and shared navigation-admission/location
helpers. Regression cases are in `test/planner_flow_test.dart` and
`test/navigation_flow_test.dart`; detailed logs and source/installer hashes are
retained privately under `.usability-work-baseline/planner-*`.

## Remaining acceptance and limits

The accepted GPS policy is currently at most 60 m reported uncertainty, at most
30 seconds old, and no more than five seconds future-dated. These conservative
limits and the 90 m connection heuristic need walking/driving checks on the
team's phone, including stationary periods, urban GPS drift, parallel streets
and slow connectivity. They are not calibrated road-matching guarantees.

Cancellation is cooperative. Already-running HTTP calls can finish in the
background; obsolete results are ignored and later detour batches are prevented.
Detour generation remains a bounded heuristic and cannot prove that every
possible alternative was searched. Coverage detection checks route vertices
against the configured study area; it does not establish complete road/flood
monitoring inside that area. Some new copy uses English fallback pending the
existing Filipino-language review.

After a separately approved build, verify manual FROM versus delayed GPS,
rapid destination changes, preview selection after road updates, closure during
confirmation, closure during an active trip, network timeout/recovery, precise
location denial, GPS interruption/recovery, movement during a slow request,
arrival behavior, and large-font layout. Use controlled synthetic closures and
safe test routes; the tests do not establish real flood passability.

The small capstone workload/B-05 test, complete main-project Spark integration,
actual push receipt/taps, adviser privacy contact/retention/audience, deferred
section 4.2 and the historical unexplained push failure remain open. See
[evaluation readiness](evaluation-readiness-5.7.md) for the wider acceptance gates.
