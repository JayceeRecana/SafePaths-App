# Native rerouting video review: 2026-10-26

Reviewed the resident's 4:14.76 screen recording and the relevant current Dart
paths. This is an analysis-only follow-up: no app, backend, road condition,
permission, or installer was changed. The video contains no audio stream.
Private non-app content is excluded from the written review.

## What this run establishes

| Approximate video time | Observation | Interpretation |
| --- | --- | --- |
| 00:12–00:25 | Planner offers a 2 min / 0.4 mi route; active navigation opens. | A native baseline route was planned and navigation started. This does not verify the exact intended destination entrance. |
| 00:27 onward | Turn guidance appears; distances decrease and maneuvers advance without the previous GPS-waiting screen. | Native GPS acquisition and foreground guidance work in this recorded run. GPS accuracy/age values and permission-interruption recovery are not shown. |
| By 01:42 | Summary changes to 5 min / 0.7 mi, marked Safe Detour; a red road is visible. | A replacement route has been adopted. The resident reports the real-time reroute fired. The initiating admin save and the first transition are not visible. |
| Around 02:17 | "Off route detected. Recalculating safe path..." appears and the summary becomes 6 min / 1.0 mi. | A second, explicitly off-route calculation occurs. It must be analysed separately from the first reported closure-triggered update. |
| 02:17–04:14 | Turn distance counts down toward zero and then changes to the next maneuver, while the bottom stays 6 min / 1.0 mi. | Guidance progresses. Bottom figures are the selected route's original totals, not continuously calculated remaining figures. |

The resident clarified that they followed the suggested detour and that the
opposite-direction movement was a response to the detour. Reversal itself is
not evidence of a routing defect. The video does not establish whether the
second off-route trigger was justified or a matching/handoff problem.

## Recommended refinements, in priority order

1. **Review the initial instruction after adopting a detour.**
   `RouteTracker._initCurrentStepIndex` and subsequent step selection start their
   search at index 1. This skips the initial departure step when multiple steps
   exist. Departure direction matters when a detour requires turning back.
   `_adoptNewRoute` already resets the tracker using current GPS; the gap is not
   simply a missing reset. Test initial direction, U-turn/departure handling,
   overlapping segments and out-and-back routes before changing matching logic.
   Show a clear provider-supported initial direction when a reversal is required.
   Do not assume the observed off-route event was false, or disable its gates.

2. **Calculate remaining trip figures, or label totals honestly.**
   The navigation footer reads `_currentRoute.durationMin` and
   `_currentRoute.distanceMiles` directly. They change on replacement-route
   adoption but not with ordinary progress. The video shows this clearly during
   the 6 min / 1.0 mi leg. Remaining distance should use along-route progress;
   remaining ETA needs an explicit model using route/step duration and travel
   mode. Do not present unchanged whole-route totals as a live countdown.

3. **Make the route-change handoff unmistakable.**
   Explain "Route updated to avoid [road]" and the revised estimate, then give
   the immediate next direction. Synchronize the calculating/finished messages
   with actual state: an off-route recalculation toast is still visible in a
   sampled frame that already shows the replacement totals. Clear obsolete
   progress messages on completion. The initial detour transition is covered by
   a chat overlay, so this recording cannot prove whether its alert was absent,
   late, or merely obscured. A non-blocking route-change summary helps a user
   reorient after returning to the navigation screen.

4. **Improve route direction and map hierarchy.**
   The full blue polyline remains drawn, including portions already travelled;
   the dense green road network competes with it. Distinguish travelled and
   remaining portions, add clear route-direction cues and destination identity,
   and reduce prominence of unrelated roads. A brief detour overview should
   respect manual camera gestures. The wide view shows a complex detour;
   geometry/closure replay is needed to judge whether its loops are necessary.
   A screenshot cannot certify that every closed road was avoided.

5. **Use consistent, clearly labelled measurements.**
   Maneuvers use metres, the trip panel uses miles, and the map scale uses feet.
   Use metres/kilometres consistently. Replace "In 0 meters" with "Turn now"
   while retaining the maneuver until actual progress confirms completion.
   Do not advance a turn merely to hide a zero-distance display.

6. **Keep safety scores and route labels calibrated.**
   The preview shows a bare "100%", and detours are labelled "Safe Detour...".
   `safetyScoreLabel` exposes the model score as a percentage; it is not a measured
   probability of physical safety. The planner's "Clear of known flood reports;
   conditions may change" is better calibrated. Label a score as a score and
   describe the known closure avoided, rather than implying guaranteed safety.

## Limits and next acceptance

The admin save timestamp is absent and a chat overlay covers approximately
01:15–01:41. No save-to-alert latency or voice-delivery claim can be made from
this clip. No diagnostic export is supplied, so the second trigger's GPS
accuracy, distance-to-route, matching position and request reason cannot be
fully reconstructed. No arrival, offline recovery, all-paths-blocked, or
critical-risk review acceptance is established here.

Keep the recorded GPS/guidance and route-adoption results as useful native
evidence. Next refine and replay departure/reversal/overlap handling first,
then remaining figures, then map/status presentation. Re-run with the route
screen unobscured around the admin save and preserve the existing diagnostic
log, which excludes exact GPS coordinates. Restore the selected simulated road
after each completed drill; no restoration was performed during this review.
