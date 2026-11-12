# Rerouting behavior and scenario acceptance

**Current follow-up:** the [critical-risk fix and data review](planner-readiness-review.md)
supersede the earlier build hold below. The separate full-app test APK is built
and inspected for [one-phone acceptance](navigation-phone-acceptance.md).
Main rollout remains on hold. Physical scenarios are pending user observations;
unapproved evacuation/staging records are withheld.

Updated 2026-10-25 after the team clarified that its twelve scenarios are
suggestions. This follow-up implements consistent failure/recovery behavior;
the app is not tuned to produce a particular screenshot or a fixed number of
reroutes. Existing APKs remain unchanged and a new build is still on hold.

## Implemented policy

An affected trip responds to current official road conditions. Known closures
remain barriers, returned alternatives are checked again, and one calculation
runs at a time. A later hazard can require a later calculation. GPS interruption
pauses guidance and preserves pending reopening work. A reopened road causes a
new check; it does not establish that every other road is passable.

Unconfirmed-road advisories are reconciled against current road records and
effective status. The card clears when its condition is actually resolved;
refreshing a timestamp alone cannot resolve a community incident. Periodic
advisory checks use the same effective-status rule as routing, including its
strict age threshold and weather/vulnerability conditions.

When no returned route avoids the known closures, the app can offer an optional
listed staging location. It excludes blocked/invalid routes and critical
predicted routes. Among eligible candidates it prefers a route without reported,
predicted or unconfirmed conditions, then shorter estimated travel time. This
is a bounded search of configured locations and provider alternatives, not a
proof of the nearest geographically safe or open facility. The method's existing
name is retained for caller compatibility.

Every staging-button press evaluates current road/weather state and live-data
health. Starting requires usable GPS and a path within 90 metres of the current
fix. Risk or unconfirmed data requires an inline caution review and a second
confirmation; changed conditions require another review. A new closure or
critical prediction prevents adoption. Movement away from the suggested path
requires refreshing options from the current position. The private trip
destination changes only when the selected staging route is adopted, and later
off-route calculations retain that destination.

Staging requests have bounded waits and generation checks. Dismissing a dialog,
reopening a road or ending navigation invalidates old results. The dialog can
refresh options after failure and scrolls on smaller screens. It explicitly
states that a listed location's operating status and suitability require local
confirmation. No facilities were invented for the test area; its configuration
still contains no staging locations.

The first failed reroute displays persistent feedback and a manual retry action.
It describes the previous route as un-rechecked/reference information. A known
hazard remains visible. Failure is not automatically labelled an internet outage.
Automatic retries remain capped at four after the initial failure, with failure
backoff of 16, 32 and then 60 seconds, and require usable GPS. Reconnection is
handled by those retries or the user's retry action, without an instant-recovery
promise. Arrival copy reports reaching the planned route/destination rather
than certifying safe arrival.

## Acceptance matrix

These are expected behaviors and controlled test procedures. Physical execution
is still pending; the final column describes existing automated evidence.

| Scenario | Acceptance criterion | Automated evidence / physical remainder |
| --- | --- | --- |
| 1. Closure ahead | After receipt, warn and search from usable GPS; adopt a current closure-free candidate or show a failure/halt outcome. A 400 m setup is not a trigger radius or latency guarantee. | Existing real-screen replay in walking/sedan modes and closure-before-GPS cases; live synchronization, voice and map rendering pending. |
| 2. Wrong turn | Three acceptable off-route fixes over at least six seconds, beyond the accuracy-scaled 35–90 m threshold, can request a reroute. One request at a time; further attempts may be necessary. | Tracker/deviation/cooldown and screen replay; physical GPS calibration pending. |
| 3. Unrelated closure | Keep this trip's route if its remaining path is unaffected. The road overlay can update independently. | Added screen replay verifies no request and unchanged trip geometry. |
| 4. Two phones | Each phone evaluates its own remaining route. | Per-trip logic covered; actual simultaneous two-phone acceptance remains open. |
| 5. Rapid changes | Coalesce updates within the existing one-second window, serialize requests, and process newer hazards after cooldown. Do not require exactly one reroute. | Existing queued-second-closure and in-flight-result revalidation replays. |
| 6. Closure on detour | Check against all current closures, including changes during the request. Reject invalidated results and search again or halt. | Existing screen and closure-geometry regressions. |
| 7. Closed road in planner | Open candidates precede blocked candidates regardless of travel cost. If no open candidate is found, prevent starting a blocked route. Comparison text and extra minutes depend on the actual alternatives. | Existing planner, cost-ranking and confirmation-race regressions. |
| 8. Different vehicles | Partial-flood classification/notice may differ; a different polyline is not required. Official closure barriers apply to both, and high predicted risk can override the partial classification. | Existing sedan/SUV safety tests. No measured flood-depth or vehicle-clearance guarantee. |
| 9. Old status in heavy rain | A passable high-vulnerability road must be older than 30 minutes; allow the periodic check interval when it ages during a trip. Warn without treating mere age as an official closure. Clear resolved cards while retaining unresolved incidents. | Existing risk/model tests plus new resolved/unresolved advisory screen cases; native dashed-line rendering pending. |
| 10. No returned clear route | Show a halt warning. Offer a current eligible configured staging option if found; the user selects it. Check hazards/GPS again on each confirmation. Show explicit recovery when options cannot be confirmed. | Added pending-result closure, critical-risk exclusion, risk-before-ETA, confirmation race, GPS loss/movement, destination retention, timeout and late-result cases. Real facilities/service acceptance pending. |
| 11. Road reopens | Preserve the new-check intent during GPS loss. Keep the halt context until a fresh check can start; re-evaluate every remaining closure. | Added real-screen reopening/GPS recovery and late-staging-result rejection. Physical reconnect/reopen timing pending. |
| 12. Reroute outage | Retain reference geometry, show first-failure feedback, preserve known-hazard warnings and allow bounded automatic/manual retries with usable GPS. Do not claim the old route is checked or that every error means offline. | Added first-failure closure and off-route service-error replays; existing timeout/recovery cases. Real airplane-mode lifecycle pending. |

## Verification and limits

The full default Flutter suite passed **297 tests**, with one optional benchmark
skipped. **156 tests** passed with the fieldtest flavor, all five migration flags
and push enabled. Nineteen new regressions were added in this follow-up: 14 screen cases
and five staging-policy/provider cases. The pre-existing ETA test now compares
two equally monitored destinations; separate tests establish the risk priority.

Final analysis has zero errors and the same four existing warnings, with 341
findings including informational/style items. The analyzer's nonzero exit
reflects those findings. A successful later reroute closes obsolete halt UI and
invalidates its outstanding staging work.

GPS, HTTP, map rendering and speech boundaries are mocked. These results do not
prove physical flood passability, location suitability, map-provider coverage,
audible alerts, real-time synchronization latency or capacity. Risk weights and
official-closure policy were not changed. Small-capstone workload/B-05, physical
acceptance, main Spark integration, adviser privacy decisions, deferred section
4.2 and the historical unexplained push failure remain open.

No backend/rules/native configuration deployment, paid-service enablement,
device inventory, APK build, installation or distribution was performed. A
credential-free 268-file source checkpoint and unchanged installer hashes are
retained under ignored `.usability-work-baseline/rerouting-followup-*` files.
The prior backend/emulator evidence remains dated evidence and was not rerun
for this local Dart follow-up.

See the [preceding planner review](planner-rerouting-reliability.md) and
[evaluation-readiness record](evaluation-readiness-5.7.md) for the wider gates.
