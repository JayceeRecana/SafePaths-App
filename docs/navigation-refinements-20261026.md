# Navigation refinements: 26 October 2026

The resident video demonstrates GPS guidance and replacement-route adoption. The resident followed the detour; opposite-direction travel is expected when directed. The recording alone cannot establish whether the later off-route recalculation was necessary. Private non-app video content is excluded.

## Implemented behavior

- Preserve the provider departure instruction for the first leg, except when a turn is immediately ahead. Announce the adopted route's immediate direction; include distance when a later maneuver is still ahead. Never synthesize a U-turn from uncertain stationary headings.
- Match distance and progress together within a plausible forward corridor. Ordered step anchors disambiguate repeated locations; proximity to a loop endpoint cannot cause immediate arrival. Actual off-route detection still requires three qualifying fixes and six seconds with the original accuracy-dependent threshold. GPS quality/freshness gates and closure/critical-review admission remain intact.
- Show GPS-derived remaining metres/kilometres and an estimated remaining time. Use provider step durations where available, otherwise scale the original route time by remaining distance. This is not live traffic or waiting-time prediction. Poor GPS/off-route estimates freeze and are labelled; recalculating or hazard-interrupted guidance identifies the previous-route estimate.
- After successful adoption, persist the route-change reason and clear obsolete calculating snackbars. A new calculation clears the previous success notice; failed calculations never produce a fresh success message. Trip details expose the destination, travel mode, update time, conditions and estimate basis without a permanent large overlay.
- Draw remaining route blue and travelled route grey, with direction cues and destination marker. Dim only background passable roads without risk glow. Preserve closed, partial and unconfirmed road prominence. Map gestures stop camera following; overview and recenter are explicit actions.
- Use metric units in navigation/planner/preview and native map scales. Show Turn now at an imminent turn without prematurely advancing its maneuver. Present route scores as model ratings out of 100; displayed detour labels avoid a safety guarantee.

## Verification and limits

Before the fix, regression tests reproduced jumping to a future parallel leg and false arrival near the start of a loop. The updated tests also cover completing a loop, out-and-back step order, departure/immediate-turn priority, exact timing metadata, progress estimates, poor GPS, successful detour messages and 360-pixel navigation with enlarged text. Final full-suite result: 361 passed, one optional benchmark skipped. Candidate configuration: 193 selected checks passed. Static analysis: zero errors and four existing warnings; detailed records and logs are in .usability-work-baseline/navigation-refinements-20261026 and adjacent navigation-refinements logs.

The new native map cues and voice handoff require resident-phone confirmation. This does not close controlled arrival/offline/all-paths-blocked/critical-risk acceptance, unresolved destination approval, or the original unexplained off-route cause. No backend, road status, rules, production configuration or billing change was made.

## Phone replay

Install the new v1.0.2 SafePaths Test APK over the existing test app. Verify TEST AREA, destination identity and selected travel mode. With the route visible, have the test admin close an actual upcoming test-area road; record the update reason, immediate direction and revised remaining estimate. Follow the detour only where actual road conditions permit. Check progress through a turn and compare remaining distance/time. Review the blue direction cues, grey travelled segment, destination marker, overview and recenter controls. If off-route fires unexpectedly while following the displayed detour, preserve the app diagnostics and unobscured video. Restore simulated road conditions after the drill. The APK does not change the main app or test backend.


## Navigation layout and state presentation: 27 October 2026

The scenario mockups guide the visual layout only. Navigation uses actual route,
GPS, advisory and calculation state; mock road names, counts and timing values
are not application defaults. Movement-based hiding is deliberately omitted at
the user's request. Details, retry and review controls remain accessible, with
a reminder to review detailed information when safely stopped.

The screen now has one direction/status-of-guidance card, at most one primary
notice, map controls in layout space above the footer, and a persistent trip
panel. Normal map space passes pointer gestures to the existing native map.
On short screens or enlarged text, the upper information scrolls independently;
footer metrics have their own bounded scroll space while Trip details and End
Route remain accessible. Both themes use the existing AppPalette and fonts.

| Navigation condition | Direction card | Primary notice / outcome |
| --- | --- | --- |
| Normal, usable GPS | Actual provider maneuver and distance, or explicit unavailable-instructions message | No routine notice unless actual conditions require one |
| Unconfirmed route | Existing valid maneuver | One advisory with actual route count when available; details expose current road advisories and the existing detour operation |
| Confirmed flood/closure ahead | Guidance paused; old maneuver removed | Current affected road, severity and calculation/GPS/failure state in one notice |
| Off route | Position check or recalculation | No duplicate recalculation banner |
| Detour request or reopening check | Updating directions, or retained pause from the interrupted route | Current calculation reason; repeated calculation actions remain gated |
| Successful adoption | New route guidance | Route updated for five seconds, then the current conditions notice; reason and 12-hour update time remain in Trip details |
| Unchanged requested detour | Existing guidance only when otherwise usable | No different detour found; unresolved conditions remain explicit |
| Failed calculation | Guidance paused; no stale turn voice prompts | Retry and previous-route/reference information; an existing confirmed hazard remains prominent |
| Unusable GPS | Guidance paused with GPS reason and retry | No duplicate GPS-only card; an independent closure, risk-review or failure notice remains |
| Critical alternative | Guidance paused | Existing explicit review and current-condition admission checks, never automatic success |
| No returned closure-free option | Guidance paused, including after dialog dismissal | Persistent warning, retry and a way to reopen the existing staging/options dialog |
| Arrival | Planned-destination arrival | Done action and completed trip presentation |

Routine calculation snackbars were removed. The five-second acknowledgement is
presentation only: it never delays a route request or adoption, and GPS loss or
a newer hazard takes priority. Success notices retain unresolved cautions rather
than certifying safety. Raw OSM identifiers are removed from short resident-facing
navigation labels without changing stored road identity or the routing inputs.

Active trip estimates include a labelled 12-hour estimated arrival time based
on the existing remaining duration, with no live-traffic claim. Interrupted
states suppress that arrival time and label existing metrics as previous-route
estimates or paused estimates. Existing route-provider requests, closure filters,
GPS acceptance limits, cooldown/backoff, critical-risk admission and staging
selection remain in place. No APK or backend deployment is part of this UI pass.

Verification artifacts are grouped under
`.usability-work-baseline/navigation-ui-20261027/`. Automated replays cover the
combined closure/GPS case, failure with suppressed old turns, fast-success timing,
reopening the blocked-route options and existing routing admission cases. HUD
layout tests cover narrow portrait and short landscape at 200% text in English
and Filipino, both themes, reachable controls and unobstructed map gestures.
Native map placement, speech timing and the new layout still require manual
emulator/phone review after a hot restart.

Final verification for this UI pass: **453 regular Flutter tests and one
font-loaded rendering check passed**, with one optional benchmark skipped.
Scoped analysis completed with zero errors and zero warnings; 21 informational
brace-style notices remain. Sample-data light/dark and enlarged-Filipino
captures were inspected. Native map and phone acceptance remain pending.
