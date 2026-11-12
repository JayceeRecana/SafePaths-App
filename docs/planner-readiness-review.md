# Planner and rerouting confidence review

**2026-10-26 device follow-up:** [GPS acquisition/retry fixes](gps-recovery-followup.md)
address a native acceptance blocker reported outdoors. Navigation discarded retry
positions and could inherit the home feature's 100-metre stream filter. These
findings prevent closing phone rerouting acceptance. Prior automated counts below
remain dated evidence; the GPS follow-up records its own final checks and APK.

2026-10-25. The user authorized fixing critical-risk automatic adoption,
checking destination data and preparing a separate test APK for manual phone
acceptance. Main-project rollout and billing remain unchanged.

## R-01: critical predicted-risk automatic adoption

**Implementation fixed; physical acceptance pending.** The prior real-screen
replay showed that a closure could trigger automatic adoption of an alternative
with predicted risk 85. The old private probe intentionally reproduces the
original defect; it is not a passing regression for the fix.

Automatic rerouting now requires a navigable, noncritical alternative, even if
a critical candidate has a lower route cost. Official closures remain hard
blocks. Prediction weights are unchanged.

If only critical alternatives are returned, guidance and arrival detection
pause. The previous route remains visible with a paused warning. The resident
can retry or preview and review an alternative. Cancel restores the previous
map and keeps guidance paused. Only explicit confirmation of the current
alternative permits adoption. Acknowledgement does not certify passability.

Confirmation rechecks current closure/risk admission, fresh usable GPS and
connection within the existing 90-metre route threshold. Changed conditions
invalidate acknowledgement. A later noncritical alternative can resume guidance;
a new critical escalation requires review again. Shared planner/preview admission
passes the review key for an initially acknowledged critical route. Disposed or
obsolete modals cannot adopt a preview.

Twelve added real-screen regressions cover critical-only and mixed alternatives,
cancel/confirm, closure and prediction changes during review, GPS loss, movement,
recovery, initial acknowledgement, disposal and narrow-screen/large-text actions.
Fieldtest diagnostics record review/adoption outcomes without adding credentials
or exact coordinates. The tests replace GPS/provider/native-map/speech boundaries.

## Data and local verification

The [destination audit](quick-destinations-audit.md) records supported corrections
and unresolved records. Eight entries are withheld from catalog routing; no
school is currently certified as an evacuation site. Staging lists are empty
pending beneficiary-approved locations and entrances; the halt dialog supports
this explicitly. FUMC's mapped POI was corrected; entrance accuracy remains open.

- Full Flutter: **331 passed**, one optional benchmark skipped.
- Final analyzer: **zero errors, four unchanged warnings**, 347 total findings
  including informational/style items. Its nonzero exit reflects those findings.
- The complete fieldtest candidate run and APK inspection are recorded in
  `.usability-work-baseline/critical-adoption-verification.json` after packaging.
- No backend, rules, SQL, native configuration or main installer was changed.

## Remaining acceptance

Obtain approved facility identities, accessible entrance pins, current services
and evacuation designation/opening before releasing held records. Perform native
GPS, pin alignment, provider snapping, speech, closure/reopening, risk review and
network recovery checks using the [one-phone protocol](navigation-phone-acceptance.md).
Physical acceptance remains pending until actual observations are recorded.

## Expanded planner preview — 27 October 2026

The user approved the second image as a design reference and explicitly identified its contents as placeholders. The expanded preview now separates a compact route header, horizontally selectable route cards, selected-route conditions and a persistent navigation action. Times, distances, option counts, warnings and condition entries come from the route models. Unconfirmed-road counts are not inferred from the explanation-list length, because explanations can also include avoided roads. The design does not introduce a “No flooded roads reported” claim for uncertain or flagged routes.

Each candidate is refreshed against current road/weather data. The preview retains the chosen geometry when the provider reorders candidates or road status changes; route selection is matched by geometry identity rather than a potentially stale index. If the chosen route becomes closed, navigation is disabled. Reopening is re-evaluated. Critical predictions remain distinct from physical closures and continue through the existing explicit caution/admission flow. The shared `startRouteNavigation` function is retained, including its second check when conditions change while confirmation is open. An unavailable selection no longer claims that every possible path is closed.

Live road/weather availability also affects the visible caution state. Condition explanations are lazy-rendered within the panel's scrolling body; the navigation action remains outside that body. The handle alone resizes the panel, while scrolling conditions does not resize it. Native camera fits are deferred until resize ends, and safety evaluation is cached between layout-only updates. The selected Mapbox route is fitted into the map viewport above the options panel; Mapbox styling, geometry, native hosting and backend requests are retained. The planner's collapsed result card keeps its existing flow into this expanded view.

Safety refresh applies to the displayed candidate geometries. This presentation change does not add an automatic provider search for new detours while a user is still previewing; the planner's existing calculation flow remains available for requesting new candidates. The native map framing and live two-client update flow still require emulator/phone acceptance after restarting the preview. No APK, backend/rules deployment or main-project migration is part of this UI pass.

Evidence and labelled sample-data renders are grouped in `.usability-work-baseline/planner-preview-design-20261027/`. The rendering harness omits Mapbox and uses synthetic route models; its values are not production data.

Final validation: **439 regular Flutter tests and one rendering check passed** (**440 total**), with **one optional test skipped**. Nine new preview checks cover actual metrics/counts, route-choice/map synchronization during provider reordering, long lazy condition lists with the action pinned, critical/uncertain mixtures, blocked navigation, missing live data, enlarged English/Filipino layouts, short landscape, live closure/reopening and closure during confirmation. Final scoped analysis found **zero errors and zero warnings**, with three existing informational notices in the collapsed planner screen. No routing model or shared navigation-admission implementation was changed.

For native review, press capital **R** in the running Flutter terminal, open Planner and Tap to expand, switch alternatives and verify map framing. Then change a road using the admin client while the preview remains open: confirm that the selected geometry stays selected, badges/conditions refresh, a newly blocked route cannot start, and reopening is re-evaluated. Native camera framing and backend delivery timing remain pending until observed on the emulator/phone.

Small-capstone workload/B-05, main Spark integration, adviser policy, deferred
section 4.2 and the original unexplained push cause remain separate open gates.
Bounded route searches cannot prove that no real-world route exists, and model
scores cannot certify physical flood safety.
