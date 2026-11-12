# Quick destinations: logic and source verification

Reviewed 2026-10-25. The user requested review of all shortcuts and confirmed
there is no beneficiary-approved destination list. This desk audit distinguishes
mapped places, entrances and emergency designation; physical accuracy remains open.

## Resulting behavior

Categories use explicit local membership within the active area, without remote
fallback or implicit first-result selection. Switching category clears the old
destination/routes. A named quick place opens entrance-pin review; only the
confirmed coordinate and chosen name reach routing. Cancel, stale searches or
sessions and invalid/outside-area pins cannot start an old trip. The native pin
picker starts at the requested location without a delayed initial camera move.

Eight unresolved records now have `routingAvailable: false`. Their stored pins
remain available for audit, but catalog search, popular picks and quick categories
exclude them. School records no longer claim evacuation/high-ground status. No
approved evacuation/staging list exists, so fallback facilities are empty. The
halt dialog explains that no configured option is available. Residents can choose
a known destination with a manual pin.

Hospital quick results contain FUMC only. The other three main-area categories
explain that confirmed catalog places are unavailable. The fieldtest area has no
catalog places. Other legacy catalog entries and general provider results were
not verified by this nine-location audit. Listings do not promise nearest, open,
safe or reachable. Route admission and mandatory quick-place pin review still apply.

## Nine distinct locations checked

Coordinates are latitude, longitude. Mapped building centres are audit references,
not approved routing entrances.

| Record | Finding and action | Remaining check |
| --- | --- | --- |
| FUMC | Operator confirms 120 MacArthur Highway, Valenzuela branch. OSM hospital way 175024244 is near 14.678104, 120.980400; Waze named POI is 14.6780548, 120.9802868. Correct old pin 14.6782, 120.9785 (about 190 m west) to the corroborated POI and add street number. | Accessible gate, native pin and actual route endpoint. |
| Marulas Elementary School | Old 14.6750, 120.9822/Serrano address differs from mapped Marulas Central Elementary, way 1022946563, Pio Valenzuela St near 14.675486, 120.984940. Serrano Elementary is a separate school. Hold; remove evacuation/safe-zone claims. | Intended school, entrance and approved evacuation designation. |
| San Lorenzo Ruiz Parochial School | No sufficiently corroborated local identity/entrance for 14.6770, 120.9840 and no approved designation. Hold; remove evacuation/high-ground claims. | Local identity, entrance and approved use. |
| Marulas Barangay Hall | OSM node 255066288, Simon St, 14.6774293, 120.984476 conflicts with building way 54719504 near 14.674457, 120.988267. Neither establishes old 14.6765, 120.9845. Hold. | Current intended hall and entrance. |
| Red Cross Valenzuela | Operator blood-station directory gives Dahlia Street, Villa Teresa Subdivision, rather than MacArthur. Correct address and category to Red Cross / Blood Station. Hold old pin 14.6778, 120.9788. | Chapter entrance and services. |
| Marulas 3S Center | OSM node 8401218921/way 553290576 near 14.67399, 120.98284 are tagged recycling, not evidence for old rescue-service pin 14.6763, 120.9842. Hold. | Intended public-service building, entrance and actual functions. |
| Police Sub-Station 3 | OSM way 775162267 names Marulas Police Station / Police Community Precinct No. 3, India Maria St near 14.677619, 120.984463, versus old 14.6762, 120.9848. Hold. | Current station identity/address and entrance. |
| Marulas Fire Sub-Station | Nearby OSM station node 7231922072 is named Dona Ata, Simon St, 14.6774363, 120.9845386. Catalog MacArthur pin 14.6780, 120.9792 is uncorroborated. Hold; do not substitute a differently named station. | Intended local station and entrance. |
| Marulas Central Health Center (fallback only) | City directory does not validate this P. Sevilla listing/pin 14.6758, 120.9835 or use as a refuge. Hold; remove unapproved staging recommendation. | Identity, entrance and approved use. |

## Public sources

- [FUMC operator contact information](https://www.fumc.com.ph/contact-information/)
  and [mapped Valenzuela POI](https://www.waze.com/live-map/directions/ph/ncr/valenzuela/fatima-university-medical-center-valenzuela?to=place.ChIJG9ckXxm0lzMR-n65nYBGGew).
- [Philippine Red Cross blood-station directory](https://redcross.org.ph/give-blood/).
- City [barangay/3S directory](https://valenzuela.gov.ph/3s-centers-barangays/),
  [health stations](https://valenzuela.gov.ph/hospitals-health-stations/) and
  [emergency directory](https://valenzuela.gov.ph/emergency-hotlines-numbers/).
- Primary OpenStreetMap records: [hospital](https://www.openstreetmap.org/way/175024244),
  [school](https://www.openstreetmap.org/way/1022946563),
  [hall node](https://www.openstreetmap.org/node/255066288),
  [hall building](https://www.openstreetmap.org/way/54719504),
  [3S](https://www.openstreetmap.org/way/553290576),
  [police](https://www.openstreetmap.org/way/775162267),
  [fire](https://www.openstreetmap.org/node/7231922072).
- [DSWD July 2025 Marulas report](https://www.dswd.gov.ph/dswd-chief-brings-cheer-to-valenzuela-city-evacuees/)
  establishes evacuation activity, not current designation of these schools.

Public Overpass timed out; bounded read-only OSM map/node/way requests and the
FUMC POI lookup succeeded. OSM is contributed map data. No tagged boundary
entrances were found for matched facilities. Public response summaries are in
`.usability-work-baseline/destination-map-research.json` and related sources.
No contacts were messaged/called; no authenticated Mapbox query was made.

To release a held record, obtain the exact official name/address, accessible
entrance coordinates/map link, approver/date, current services and relevant
current evacuation designation/opening. Then verify native pin alignment and
routed endpoint. See [phone acceptance](navigation-phone-acceptance.md).

## 2026-11-08 search review and LGU list

Keep `lib/data/marulas_landmarks.dart`: the active area uses it for planner,
home-map and pin-picker search. `routingAvailable` means a catalog pin may be
reviewed, not that the entrance, opening, or route is approved.

Search now requires all meaningful query words, preserves words such as
Citymall, filters invalid pins, and keeps duplicate street segments distinct
by road ID. Typed catalog landmarks use the same entrance review as quick
shortcuts. The home map presents ambiguous local matches for explicit selection.
The public Nominatim autocomplete fallback was removed: its usage policy
forbids client autocomplete. Local data and the configured Mapbox provider remain.

The project team supplied an LGU image and linked its source:
https://www.facebook.com/photo?fbid=468942608601563&set=pcb.468955825266908
Automated retrieval could not verify the post date. The 11 names were transcribed
from the supplied image in `lib/data/marulas_evacuation_sites.dart`. They appear
under Marulas Evac Centers with a non-routable entrance-confirmation label.
Neither the image nor this change establishes current opening, capacity, exact
entrance coordinates, or road reachability. No coordinates were invented and no
existing withheld pin was enabled. Test-area catalogs remain separate.

Names: 3S Center; Barangay Hall; Do?a Ata Covered Court; Elysian Covered Court;
Constantino Elementary School; San Miguel Heights Elementary School; Serrano
Elementary School; Valenzuela National High School; Marulas Central Elementary
School; Bitik Elementary School; Do?a Ata Elementary School.

## Live mapped-location lookup and removed site (2026-11-08)

The team clarified that a building/compound location is sufficient for a reviewed
navigation destination; an independently surveyed entrance is not a prerequisite.
The planner now says to review the mapped location and check access/opening locally.
The team confirmed Do?a Ata Covered Court is no longer present and requested its
removal. It is absent from the 10 current LGU-name options and excluded from
provider search results. The old source image still contains 11 historical names.

The existing Mapbox token returned named POIs through Search Box `/forward` during
read-only checks. Eight of the ten remaining names had matching candidates;
Marulas Barangay Hall and Elysian Covered Court did not return a matching place.
Marulas Central School is an accepted name alias for the listed Marulas Central
Elementary School; unrelated school results are rejected. These checks establish
provider search availability, not open evacuation operations or an approved gate.

The app resolves listed names at runtime and keeps provider positions only in
active search/navigation memory. No Mapbox coordinates were copied into the
bundled catalog or either database. This follows Search Box's temporary-use terms:
https://docs.mapbox.com/api/search/search-box/

Planner, home search and the pin picker share `MapboxPlaceSearch`. Listed-site
lookups require an in-area named POI matching the requested name/alias. Generic
school/court results cannot substitute for a missing match. Failure leaves retry
and manual map selection available. Stale results cannot replace a newer planner
choice. This does not change road verification or route safety admission.

Two old general-search pins (Marulas Central School and Constantino Elementary
School) conflict with the live mapped locations and are now withheld. Typing
an LGU-listed name uses live lookup too, so typed search cannot bypass the newer
resolution and silently reuse those old coordinates.
