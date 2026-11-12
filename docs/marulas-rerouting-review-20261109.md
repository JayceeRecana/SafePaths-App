# Marulas rerouting review - 9 November 2026

The recording begins after guidance has already paused. It shows Little Tagaytay Street as the blocking road and retains the previous route for reference. The user identified the trip as T. Serrano Street to Iglesia Ni Cristo on Tamaraw Hills Road. Travel mode, exact GPS fixes, bearing and the original provider responses were not recorded in the supplied clip.

## Evidence

A read-only road snapshot contained 149 roads, with Little Tagaytay as the only not-passable road; both MacArthur sections were passable. Public-street driving replays from three approximate points on Serrano to a point on Tamaraw Hills near the church returned MacArthur detours. The current safety evaluator accepted these without reducing its 35 m closure buffer.

A replay from eastern Serrano with a 90-degree origin bearing reproduced the failure: the detour candidates passed through the closure before reaching their diversion waypoints. Removing the forward bearing for detour requests returned a MacArthur detour avoiding the closure. This demonstrates a bug consistent with the symptom, but does not prove the phone had that exact origin/bearing.

## Change

Keep the live heading on the initial directions request. Release that heading constraint for waypoint-based detour searches so the routing provider can consider turning back under its normal road-direction and turn restrictions. Preserve the request budget, candidate cap, all-closure revalidation, blocked-route rejection, critical-risk review, GPS requirements and stale-result guards. No road status or backend records were changed.

The separate limitation that a capped search samples only a small set of diversion waypoints remains. The app does not exhaustively prove that no traversable route exists; its notice correctly refers to returned routes.

## Validation and acceptance

The same 173 regression checks passed under both the production/Marulas and fieldtest configurations across routing, navigation, closure handling, HUD, planner and route tracking. This is code/configuration parity evidence, not native-device acceptance. The captured-response regression failed before the change and passed after it. A companion test still rejects all closure-crossing results when no clean detour is returned. Fixtures contain public road geometry and provider response snapshots, not the phone location history or access tokens.

Continue local review with recorded provider responses and Marulas road snapshots first. A Marulas visit is not required for this work; pinned-origin planner checks or a controlled emulator location can be used from elsewhere. Only after the review is complete and the user requests another APK should a groupmate in Marulas repeat the controlled trip, confirm the vehicle mode and start location, observe the closure update before entering the affected road, and capture diagnostics with the route result. Native-device acceptance and the exact cause of the original recording remain to be confirmed.

Local investigation artifacts: `.usability-work-baseline/marulas-rerouting-20261109/`. The attempted replacement build was stopped at the user's request. No replacement installer was added to releases; version 1.0.6 predates this routing fix. Do not build another APK until the user asks.


## Expanded local failure reproductions

Six additional controlled cases were added in `test/rerouting_failure_reproduction_test.dart`, reusing captured public Marulas provider geometry where applicable. These do not replay the original phone's exact GPS stream.

| Scenario | Before | After |
| --- | --- | --- |
| Bearing-constrained initial request returns no routes, but unrestricted request has a clear route | Stops without checking unrestricted direction | Retries once without the bearing, under the same total computation budget |
| Initial request without a bearing returns no routes | One request | Still one request; no repeated identical request |
| One detour request fails, other returned candidates cross the closure | Returns blocked candidates as if the search completed | Signals route-service unavailability to the existing retry/backoff path |
| One detour request fails, another returns a clear MacArthur path | Clear candidate is retained | Still retains and checks the clear candidate |
| All requests complete and only closure-crossing routes are returned | Blocked | Still blocked; no safety override |
| Clear detour differs around a closure but shares the blocked route's first/middle/last points | Discarded by the sampled duplicate fingerprint | Full ordered geometry distinguishes it; identical detours still collapse |

The first, third and sixth cases failed before their fixes; the other cases are controls. Before/after logs are grouped with the investigation artifacts. The detour candidate count, closure buffer and navigation deadline were preserved. No live road records were changed and no APK was built.

The expanded suite passed 179 checks under both production/Marulas and fieldtest configurations. Existing integration tests cover a new closure during a calculation, queued updates, unrelated/behind-route closures, unreliable GPS, request timeout/recovery, ending navigation during an in-flight request, critical-risk review, destination retention and reopening. Passing these checks is evidence for the controlled cases, not an exhaustive guarantee or a replacement for later device acceptance.


## Endpoint and wider-detour round

Four further reproductions failed before the next fixes: distant origin geometry was accepted, distant destination geometry was accepted, a malformed distant alternative was retained alongside a valid one, and the six-request search never reached the widest diversion on both sides.

- Provider geometry now must start and end within 100 m of the requested origin/destination. Invalid alternatives are filtered; if all returned alternatives are invalid the calculation is unavailable, not evidence that every road is closed. A nearby ~44 m road snap remains accepted. The 100 m bound catches gross displacement; it is an implementation limit, not a beneficiary-approved entrance tolerance or proof of access from a road to a building.
- Candidate ordering now prioritizes one waypoint on each side at the existing three offset scales before dual-waypoint corridor shapes. Navigation's candidate limit is six instead of three, shared by its injected and real routing paths. This increases the maximum provider detour request count by three, with concurrent requests and the existing total deadline retained. The initial bearing fallback may also make one extra initial request under the same deadline. No unbounded or exhaustive search is claimed.
- Existing all-blocked, stale-route pause, retry, closure-reopening and no-old-turn-instruction checks continue to pass. The new endpoint/wider tests use controlled geometry; they do not prove those faults caused the original phone recording.

The expanded suite passed 183 checks under both production/Marulas and fieldtest configurations. Scoped analysis reported no errors or warnings (44 informational style lints). Logs are in `endpoint-width-fieldtest-after.log` and `endpoint-width-analysis.log` within the local artifact folder. No APK build or live backend changes were performed for this round. Device acceptance remains open; the installed 1.0.6 APK does not contain these local changes.


## Marulas multi-area virtual checks - 11 November 2026

Read-only Mapbox Directions requests were passed through the current `RoutingService.computeRoutes` and closure-admission checks. Road geometry came from the saved 149-road public snapshot of 9 November. All roads were locally assigned fresh, verified passable conditions except the specified simulated closure, with clear simulated weather. These are controlled inputs, not current barangay records; no live database writes, emulator GPS changes, application changes or APK builds were made.

Six public-point trips covered eastern Serrano to the approximate INC/Tamaraw destination, northern Fatima to BBB and the reverse, Bitik to northern MacArthur, Constantino to northern Fatima, and Old Tamaraw to BBB. Endpoints are road geometry samples/public approximate locations, not verified facility entrances or the original phone GPS stream. Requests followed the app's driving/walking profile, 90-degree initial heading, silent waypoint and six-candidate navigation limit. Directions responses were captured without tokens.

Results:
- 18/18 all-passable baseline calculations found a clear returned route (six trips x Sedan/Motorcycle/Walking).
- With Little Tagaytay simulated closed, 17/18 calculations found a clear returned route. All six car and six motorcycle cases found one. The walking Bitik-to-northern-MacArthur case did not.
- 12 further Sedan calculations closed either MacArthur section: eight found alternatives, while four returned no clear route where the chosen origin or destination lies on the closed section. No returned route crossing a simulated closure was admitted.
- The Serrano-to-INC Sedan closure case returned accepted detours using MacArthur Highway, confirmed by the provider's full step street names, not just the summary. This contradicts a general MacArthur exclusion in these controlled inputs.
- A separate two-waypoint northern walking probe (approximately 3.20 km, via the General T. de Leon/MacArthur corridor) passed the same closure evaluator for the missed Bitik case. This establishes a remaining candidate-discovery limitation: six single diversion samples can miss a usable two-waypoint corridor. It is not evidence that a safety override is needed. Preserve closure rejection, request/deadline limits and original destination when addressing it.
- 21 diagnostic/regression checks passed: one independently captured walking-corridor evaluation plus 20 existing Marulas rerouting failure/closure regressions. The 48 scenario checks passing only asserts their specified baseline/safety conditions; it does not mean all 48 found a route.

Open: add a captured-response failing regression for the missed walking corridor, then consider a bounded fallback that tests corridor pairs only when the normal candidates produce no usable route. This must retain all-closure revalidation and distinguish an incomplete search/service failure from confirmed closure. Do not increase API requests or relax the closure buffer without measuring the tradeoff. Current cases do not establish the cause of the original physical-phone failure, real-time subscription delivery, GPS reliability, turn legality in the field, or complete route coverage outside the study area. Native controlled acceptance remains required.

Artifacts: `.usability-work-baseline/marulas-virtual-tests-20261111/` contains the harness, request captures, outcomes, independent probe, and logs. Existing installed 1.0.9 is unchanged.


## Missed walking-corridor fix - 11 November 2026

The captured Bitik regression failed before the change: none of the six single-point responses passed closure admission, while an endpoint-spanning pair at the middle offset returned a 3,542.038 m walking route that passed the identical checks. The fix replaces the two middle-scale single-point candidates with two-point corridors spanning the original trip, one on each side. Near and widest single-point candidates remain on both sides. This is a general geometry strategy, without road-name or Marulas-coordinate exceptions.

The navigation cap stays at six detour requests, sent concurrently, under the existing 18-second total budget. Original endpoints, endpoint-snap rejection, initial-heading behavior, unheaded detour requests, cancellation checks, incomplete-search failure handling, route ranking and full closure/risk admission remain unchanged. No additional fallback round or live backend mutation was introduced. The alternate shapes trade some single-point coverage for corridor coverage; this remains a bounded search, not a guarantee of discovering every usable road path or the shortest detour.

`test/marulas_bitik_walking_detour_test.dart` replays captured public provider responses from `test/fixtures/marulas-bitik-walking-detour.json`. It checks the previously missed route, unchanged destination, mode, released detour heading and six-request limit. A second control substitutes closure-crossing corridor responses and checks that they remain blocked and cannot be automatically adopted.

Repeating all 48 read-only virtual scenarios after the fix found clear routes in all 36 baseline/Little Tagaytay combinations (previously 35), including the 3.54 km walking detour. The 12 MacArthur-section closure cases retained the same eight clear/four blocked outcomes; those four have an origin or destination on the simulated closed section. These are controlled modeled road conditions, not current barangay verification. Captures and before/after logs remain grouped in the 11 November virtual-test artifact folder. The earlier candidate-discovery issue is fixed for this captured case; physical-phone acceptance and the original recording's exact cause remain open. No APK has been built for this change; installed 1.0.9 predates it.


Post-fix verification: 209 selected routing, safety, tracking, navigation/HUD and planner regressions passed under production/Marulas and the same 209 passed with the matching fieldtest flavor/configuration. An initial fieldtest invocation accidentally kept the production flavor and was rejected by the existing environment guard; the corrected invocation passed without application changes. Regression logs are retained with the virtual-test artifacts.

Scoped static analysis reported no errors or warnings (23 informational style lints).


## User-drawn trip clarification - 11 November 2026

The user supplied a diagram showing the approximate start near Serrano Elementary School, an eastbound approach on T. Serrano toward Little Tagaytay, and an expected westward return via T. Serrano -> MacArthur -> Tamaraw Hills to the approximate destination west of the closure. This clarifies intent, not the original device GPS or selected travel mode.

Eight additional read-only route calculations used four approximate public geometry positions, each in Sedan and Walking modes, with the current source and locally simulated Little Tagaytay closure. Both modes found closure-clear alternatives at the green-start approximation and at the Serrano point before the turn. The Sedan pre-turn case includes a 1,016.651 m accepted route whose full provider steps are T. Serrano Street, MacArthur Highway and Tamaraw Hills Road, matching the drawn corridor. The app need not choose the exact illustrated route if another admissible route ranks better.

At the closed road's northern geometry endpoint and just inside that section, both modes returned no clear route. These four cases reproduce the paused/no-clear result for on-closure origins: full-route closure intersection rejects routes that start on the closed geometry, even when a route could head back away from it. This does not prove the original phone was at those points. Do not reinterpret it as proof all alternative roads are closed, relax the closure buffer, or automatically guide a resident along a confirmed closed road. Start-at/near-closure explanation and recovery require a separate explicit decision; GPS uncertainty and possible real flood exposure make automatic egress safety-sensitive. Exact original timing, mode, installed APK and GPS fixes remain unconfirmed.

Artifacts are `drawn-trip-results.json`, `drawn-trip-capture-*.json`, `drawn_trip_test.dart` and `drawn-trip.log` in the existing virtual-test folder. These are provider/calculation checks, not a replay of Firestore subscription timing or the phone GPS stream. No new source change, APK, or backend write occurred during this clarification.


## Multi-area moving navigation replay - 11 November 2026

Expanded the fixed-position checks into captured-route navigation replays. Eighteen additional read-only provider calculations start at approximately 15% progress along six Marulas trips in Sedan, Motorcycle and Walking modes. A full named road crossed ahead is locally closed where its geometry is at least 90 m from the progressed origin and destination; where no full road qualifies (the short Serrano/INC trip), the fixture explicitly uses a short synthetic route segment. All other road inputs are locally fresh/passable. These are simulated conditions, not changes to official records.

Seventeen of the eighteen progressed-origin calculations found clear returned routes. Constantino -> northern Fatima in Walking mode, with the entire T. Serrano Street geometry closed, returned none. Two independent corridor probes also intersected the same closure under the existing safety evaluator. No independently validated clear alternative has been established for this case, so it remains a reviewed no-clear outcome rather than a demonstrated candidate-search defect or proof that all possible paths are closed. The road-intersection buffer and full-road geometry can affect adjoining junctions; do not silently weaken those rules.

Added `test/marulas_navigation_replay_test.dart` and `test/fixtures/marulas-moving-closures.json`. The fixture captures public geometry/provider responses, omits maneuver steps and contains no personal location history. Twenty-six movement sequences feed the real NavigationScreen: 18 area/mode combinations plus eight timing variants of the user's drawn Serrano/Little Tagaytay trip. The latter find alternatives when the closure arrives at the green-start approximation or before the turn, and remain paused when it arrives at the closed section's endpoint or just inside it. Captured candidates are evaluated with the actual RoutingService; mocked GPS, native map, speech and in-memory AppState updates isolate transport/device dependencies. No initialized Firebase application is used and no live record is written.

The 62 new widget checks comprise 26 moving-closure cases and six each for unrelated closures, unusable GPS followed by recovery, failed requests followed by recovery at the configured backoff, behind-progress closures, a second closure during an in-flight calculation, and sustained wrong turns. They check destination/mode/request-cap retention, current request origin, eligible route adoption, no blocked-detour adoption and appropriate pause states. The first test harness incorrectly expected failure recovery before the configured 16-second first-failure backoff; it was corrected to keep GPS fresh through the real delay without changing application code.

All 62 new widget cases passed under production and matching fieldtest configurations. The selected existing 209 route/safety/tracking/navigation/planner checks also passed under both configurations (the intermediate combined run had 263 checks before the final eight drawn-trip cases were added). The independent two-corridor diagnostic passed after correcting a nullable diagnostic label in the temporary probe. Its passing assertion means the responses were evaluated successfully, not that a clear Constantino route exists.

Outstanding: start-at/inside-closure recovery and wording still require a deliberate safety-preserving design; the original phone failure's precise GPS/timing/mode remains unconfirmed. These replays do not exercise hosted subscription delivery, real location accuracy, native Mapbox rendering, actual road access or turn-by-turn speech. Preserve the distinction between a route calculation result and a proved absence of alternatives. No application behavior was changed by this replay expansion, and no new APK was built. Installed 1.0.9 still predates the corridor-search fix.

Artifacts remain grouped in `.usability-work-baseline/marulas-virtual-tests-20261111/`: moving capture harness, unabridged provider captures, replay logs for both configurations and independent Constantino probes. No new user-facing workflow or dashboard was introduced.

Final expanded replay runs passed 63 checks in each flavor (62 navigation cases plus one independent route-evaluation diagnostic). Scoped analysis of the new replay test reported no errors or warnings, with three informational style lints.


## Reference-only route presentation and closure-origin recovery - 11 November 2026

Implemented a navigation-only `AppMap.routeReferenceOnly` flag, default false for other screens. Paused/off-route/recalculating navigation keeps the same route geometry and destination but renders the remaining line gray/dashed and hides direction arrows. The existing map/style lifecycle is retained; no 3D puck, additional source, or native model is introduced. Paint updates are cached so ordinary position changes do not resend unchanged paint properties. A checked adopted route restores the standard blue solid line and arrows. Native map paint still requires device visual acceptance.

The guidance card now explicitly describes the gray dashed line as the previous route and says guidance is paused. A risk alternative preview is labeled as a preview rather than incorrectly calling it the previous route. Turn instructions/voice and arrival estimates retain their existing pause guards. Near-closure notices and the scrollable halt dialog say GPS places the user on or near a road marked not passable, rather than implying no alternative road can exist or claiming a confirmed flood at the exact GPS point. Existing Retry/End Route/options remain available. English and Filipino copy was added.

`ClosureExitRecovery` arms when a closure-paused calculation starts/halts near a confirmed closed road. Near means within the existing crossing buffer plus the current usable fix's reported accuracy, checked against every closed geometry with segments preserved. It requests another route only after three distinct reliable fixes remain clear of all such closures over at least six seconds, with no gap over ten seconds. Unusable GPS, a new near-closure fix or a pending calculation interrupts the clear streak. The gate is one-shot per near-closure episode and respects the existing reroute cooldown, pending/in-flight guards, cancellation, current destination and full closed-road avoid set. It does not approve movement out of a closed road or provide an egress maneuver. All returned routes still pass normal closure/risk admission, and successful adoption resets the recovery state.

New pure recovery tests cover timestamps, interruptions, near-road recurrence, in-flight calculations, long GPS gaps, one-shot behavior and unarmed pauses. Navigation integration verifies no premature recheck when GPS uncertainty still overlaps the closure; once sustained clear fixes arrive, the request uses current position, preserves the original destination/closure exclusions, adopts only a checked route and removes the reference-only warning. The warning/dialog also fits 320x800 with 200% text scale without layout exceptions.

Constantino diagnosis: both independently probed walking routes explicitly traverse T. Serrano according to provider step names and trigger geometry intersection even with a 1 m threshold. Their rejection is not explained merely by the 35 m buffer. No independently validated closure-clear alternative has been established; do not change road status/geometry or weaken closure protection to accept them. Finite search coverage and real-device acceptance remain limitations.

Validation artifacts are the `closure-recovery-*` logs in the existing virtual-test folder. The broad Marulas run passed 291 checks including the independent diagnostic, with one optional benchmark skipped. The fieldtest run passed 291 checks including the subsequently added narrow-screen case (without the temporary diagnostic), with the same optional benchmark skipped. A final Marulas recovery/navigation run verifies that narrow-screen case as well. No backend records were changed and no APK was built; installed 1.0.9 still does not contain these local changes.

Final dialog refinement: opening View options and receiving subsequent GPS fixes both use the current near-closure calculation. The dialog no longer retains a captured location label after the user is clear. All 77 navigation-flow checks passed in each flavor after this refinement; the final Marulas recovery/UI run also passed 85 checks (77 navigation + eight pure recovery cases).

Final scoped static analysis reported no errors or warnings (30 informational style/deprecation notices). Native gray/dashed paint and arrow visibility remain for the next APK device visual check.
