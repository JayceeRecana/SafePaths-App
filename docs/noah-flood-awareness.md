# NOAH flood awareness — implementation and boundaries

The optional NOAH overlay is a static awareness view. It is independent of
SafePaths' resident reports, barangay verification, road passability, trust
rewards, weather/risk model, planner and rerouting decisions. Turning layers
on/off changes rendered map visibility only. It cannot write road statuses or
approve a report.

## Resident and admin experience

- Resident home: SafePaths/NOAH choices replace the former Road conditions
  button. SafePaths is on initially; NOAH is off. Both can be on together.
- The information icon retains the existing road-condition legend and road list.
- NOAH's Legend and coverage panel explains the 5-year rainfall scenario,
  low/medium/high classes, limitations, source and ODbL attribution. It offers
  View Marulas coverage, which pans the existing map without changing GPS,
  starting navigation or changing the app environment.
- The full-screen map used by admin Roads exposes the same controls. Existing
  road selection, confirmation and checked save flows remain separate.
- Road details (available to both roles) keeps current road information and
  barangay updates above a separate collapsed NOAH flood awareness section.
  Expanding it assesses every segment of the road geometry, not its midpoint.
  Multiple intersected classes are shown; none is promoted to a road closure.
  View NOAH on map opens the existing full-screen map with awareness enabled.
- Outside the prepared rectangle, road information is unavailable. Partial
  roads explicitly identify the unassessed remainder. No intersection is
  described only as no mapped hazard in this prepared dataset, never safe.
  The map notes when its centre is outside the prepared area.

## Source and preparation

Source package: BetterGov.PH mirror of Project NOAH,
`Flood/5yr/MetroManila.zip`, revision
`3820095a7e40b6bc852390d43a8c6d368d6fe081`. All four supplied shapefile
components matched that public ZIP byte for byte. The mirror documents the
package as a 5-year rainfall return-period scenario. Its shared flood-metadata
text describes 100-year data generically; it is not used as this package's
scenario identifier. The original model date remains unestablished.

`scripts/noah/prepare_marulas.py` verifies component hashes, preserves polygon
shell/hole grouping, repairs invalid candidate polygons and clips the three
hazard classes to `[120.963,14.661,121.0045,14.6905]`: Marulas' configured
bounding box plus an approximately 500 m surrounding buffer. The preparation
report records 42/13/3 invalid candidate polygons repaired for classes 1/2/3.
There were no unresolved ring-grouping errors; final cropped geometries are
valid. Repairs are an explicit preprocessing adaptation, not new hazard
modeling or field verification. No class reassignment or simplification occurs.

The static GeoJSON is 1,747,504 bytes (approximately 591 KB gzip in the
preparation check). The app bundles it for both flavours; it does not load the
33 MB regional shapefile or earlier nationwide PMTiles archive. No new Flutter
dependency, database or hosted service is required. Asset size is not a phone
rendering benchmark.

The source has no explicit study/no-data coverage mask. The prepared rectangle
is a clipping limit, not proof that all unshaded space was studied or is safe.
The layer is labeled modeled hazard, not live flooding. Classification considers
depth and flow and is not a current depth reading. Source notices and the
adapted open database are included under `assets/noah/` with the ODbL reference.

## Isolation and lifecycle

`services/noah_awareness.dart` imports only Dart/Flutter support. It has no
dependency on app state, Firebase/Supabase, reporting, risk or routing services.
It loads/parses the bundled asset once on demand, off the UI isolate. Road
assessment also runs off the UI isolate. Bounding boxes prune unrelated
polygons; segment/polygon intersections include holes, multipart roads and
boundary touches. Malformed or missing geometry yields unavailable information.

Each map owns a nonpersistent `NoahMapController`; disposed or late loads cannot
re-enable a layer. The normal map draw does not await the optional NOAH writer.
The fill is positioned beneath road-status/selection lines and route guidance.
Style epoch/identity guards and a separate writer queue discard obsolete writes
and reapply the layer after style changes. NOAH-specific source/native errors
are contained in the NOAH status and retry action rather than the global map
error or navigation state. There are no NOAH requests in the GPS/reroute loop.

## Validation and review

Evidence is grouped in
`.usability-work-baseline/noah-awareness-implementation-20261101/`.
Tests cover source scenario/provenance, bounded size, geometry holes/multipart
segments, outside/partial/malformed/unshaded roads, immutable inputs, independent
toggles, late-load/disposal, failures/retry, English/Filipino and enlarged text.
The existing reporting and navigation suites are run as regression checks.
Light/dark native widget previews cover the controls and expanded road section.

Final local results: 644 regression tests passed with one intentionally skipped
benchmark; separate fieldtest and Marulas configuration runs passed 41 and 18
checks. Scoped Dart analysis reported no errors or warnings (36 informational
style/deprecation notices). Eight native component previews rendered, with the
controls, error/outside state and expanded road card visually inspected in both
themes. The final source asset reproduced byte for byte from the pinned input.
The large-text test found and fixed a legend-row overflow before the final run.

Actual Android map rendering, source alignment, pan/zoom smoothness and native
style reload behavior still require a phone/emulator acceptance check. Widget
previews are not evidence of GPU map performance. Do not mark that acceptance
complete from local Flutter tests alone.

Because a new asset is declared, stop/start the existing Flutter run once to
pick up the complete bundle. In the fieldtest build, enable NOAH, open Legend
and coverage and choose View Marulas coverage. Test roads remain in the nearby
test area and keep their TEST AREA label; no Marulas road data is silently
inserted into the test backend. Use the main Marulas map for actual combined
NOAH/Marulas road-line acceptance.

No APK was built, no cloud state was changed and no running user session was
reloaded during implementation.

## Controls and missing-asset follow-up — 1 November 2026

The user reported a large/plain layer panel, an unstyled explanation sheet and
NOAH unavailable after hot reload/restart. Read-only ADB inspection confirmed
the installed test APK had no `assets/noah` data (its AssetManifest was 213
bytes). This identifies a packaging gap in that installed build; a full Flutter
stop/start is required before judging native overlay rendering. The agent did
not stop/reload the user's run or install another APK.

The map now uses a compact rounded floating selector with independent blue
SafePaths/NOAH buttons and the existing road-legend information action. A small
information pill beneath it shows loading, outside-prepared-area, unavailable
or modeled-hazard context, with a separate retry icon for failures. It opens
the NOAH sheet without the previous full-width paragraph panel.

The explanation sheet groups scenario, hazard legend and coverage/authority
into themed cards. Attribution remains available in a collapsed Source and
licence section. Its fixed coverage action explicitly uses the SafePaths blue
palette in both themes; it no longer inherits the green tonal-button default.

Loading now distinguishes missing bundled data, data decoding and native map
render failures. Missing-asset debug help explains the required full restart;
SafePaths road conditions/reporting remain available. Native failures log a
bounded operation/type diagnostic rather than silently losing the failure
category. No raw resident data or credentials are logged by these additions.

Evidence is grouped in `.usability-work-baseline/noah-controls-fix-20261101/`.
Targeted tests passed 54 checks, including missing-vs-malformed bundles, retry,
blue coverage styling, compact controls and enlarged Filipino text. Light/dark
previews of the controls, explanation and missing-data state were rendered for
visual inspection. The installed app still needs the user's full restart and
actual native map acceptance check.

The follow-up full suite passed 646 tests with one intentionally skipped
benchmark. Final scoped static analysis had no errors or warnings (21
informational notices). Final light/dark previews also verify the inset close
button remains visible in dark mode.

## Road-awareness presentation — 2 November 2026

The existing collapsed road-details section now expands into a grouped
source-based summary: Mapped hazard along this road, one colored row per
intersected NOAH class, a modeled-vs-current-condition reminder, View NOAH on
map, and a collapsed Source and limitations section. Multiple classes remain
separate. Loading, unavailable, unshaded and partial-coverage states never
default to a low class or a safe road. Unknown model date and mirror attribution
remain explicit. No depth guarantee, flood probability, barangay percentage,
road coverage percentage or other statistics were added. Class labels come
from the bundled NOAH polygons; SafePaths performs the road intersection.

FutureBuilder can retain an old future's data while a new future is pending.
The card now gates displayed results on completion, preventing the previous
road's classes from appearing briefly after a selection/geometry change.
Tests explicitly cover that pending-road transition, source-only class rows,
absence of invented statistics, and both themes/languages at enlarged text.

The NOAH GeoJSON and assessment service are unchanged in this presentation
revision, verified by SHA256 checks. Reporting, persisted road conditions,
trust and routing decisions are unchanged. Evidence and ten native component
previews (high, mixed, unshaded, unavailable and partial states in both themes)
are grouped in `.usability-work-baseline/noah-road-card-20261102/`.

Validation for this revision: 55 targeted workflow/UI checks and 650 full-suite
tests passed (one optional benchmark skipped). Scoped static analysis had no
errors or warnings, with three informational notices. Ten component previews
rendered successfully; mapped-high, mixed, unshaded and partial examples were
visually inspected. No new APK, cloud write or user-session reload occurred.

## Road-length percentages — 2 November 2026

The road-details section now includes a percentage bar and labeled shares of
the **whole unique mapped road centreline**: high, medium and low NOAH hazard,
no mapped hazard intersection within the prepared rectangle, and outside
prepared data. These are SafePaths calculations using NOAH polygons and the
selected road geometry, not percentages published directly by NOAH, a flood
probability, observed water depth, a barangay-area statistic or passability.

The explanation is expandable within the chart. It makes the denominator,
unknown study coverage, outside-crop category and rounding explicit. Existing
modeled-vs-current-condition and barangay-verification reminders remain.
Outside-only valid roads show 100.0% outside prepared data; missing, malformed,
zero-length and unsupported dateline geometry have no fabricated breakdown.
Point-only boundary contacts can retain the existing awareness class but have
zero measured length. A tiny positive intersection can round to 0.0%.

### Calculation method

The read-only NOAH service removes repeated/reversed and overlapping collinear
road pieces before measuring. Disjoint components remain disjoint. It splits
each road segment at every candidate polygon boundary/hole and at the prepared
rectangle. Each resulting interval is assigned once, using its midpoint: highest
mapped class wins overlapping polygons, otherwise no mapped intersection inside
the crop, or outside prepared data. This priority is a stated display-aggregation
rule; it changes no NOAH source class or verified road condition. Polygon holes
are retained and closed polygon edges are considered boundaries of the polygon.

Segment length uses a spherical great-circle estimate (radius 6,371,008.8 m)
between mapped vertices. Each straight GeoJSON segment's length is allocated by
its intersection parameter fractions. These are approximate centreline lengths,
not a road survey or surface area. The five meter totals form the denominator.
Largest-remainder rounding to one decimal place makes displayed shares total
100.0%, without double-counting overlaps. Labels retain very short/point-contact
classes at 0.0% when appropriate, with an explanation of rounding and contacts.

### Validation and isolation

Unit examples verify known meter distances and shares, feature-order invariance,
same-class union, highest-class overlaps, holes, collinear boundaries, isolated
touches, crop crossings, outside-only roads, disjoint components, duplicate and
reversed lines, densification, tiny intersections and invalid/zero geometry.
Three independent GIS references use the actual unchanged bundled NOAH polygons:
Shapely difference/intersection and straight east-west test lines through
Marulas. `scripts/noah/verify_length_reference.py` reproduces
`test/fixtures/noah_length_reference.json`; the Dart results match the reference
fractions within 0.000001. Reference cases are test geometries, not statistics
for the whole barangay or production fixtures.

Calculations still run off the UI isolate only for road details, outside GPS,
weather, reporting and routing paths. The NOAH source asset/notice, report
verification, trust rewards, stored road status and rerouting logic are
unchanged. Evidence and native light/dark component previews are in
`.usability-work-baseline/noah-road-percentages-20261102/`. No APK, cloud write
or user-session reload is performed by this change.

Final checks for the percentage addition: 661 full regression tests passed
(one optional benchmark skipped); the fieldtest configuration passed all 30
NOAH calculation/UI checks. The earlier targeted run passed 44 checks including
road-details regressions. Static analysis reported no errors or warnings and
18 informational notices. Ten native component previews rendered successfully;
the mapped and partial-coverage percentage layouts were visually inspected in
light/dark themes. The bundled NOAH GeoJSON hash is unchanged. Physical-device
map/GPU acceptance remains separate from these component/math checks.
