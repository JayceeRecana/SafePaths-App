# Performance and stability: section 5.4

Scope: a capstone with a handful of simultaneous residents. Start with 5 concurrent users and use 10 and 20 as stress steps. These numbers are proposed workloads, not an established supported capacity. Work stays local; production rollout and APK distribution remain on hold.

## Changes in the app

- The live report stream selects every pending/under-review report. It is not cut off by a history limit or creation age, so an older active hazard remains visible.
- A separate live window holds the signed-in account's latest 30 reports for personal updates. Complete resident/admin history is fetched in pages of 30, ordered by submission time and document ID so equal timestamps can be paged reliably. Only one page of report records is retained by each history screen. Back-navigation cursors contain timestamp/ID values, not entire documents.
- History provides Newer, Older, refresh, loading, cache and retry feedback. Failures preserve the current page. Cached partial pages do not establish that history is exhausted. The first load no longer calls an empty cache “no reports submitted.”
- Admins can open unresolved road incidents directly even after their report records expire or leave the live report feed. Dashboard statistics distinguish current road reviews from all-time resolved counts. Citizen profiles link to complete paged history instead of implying the live cache is their complete record.
- The map subscribes to road-specific changes, weather and freshness ticks, rather than every report/profile/alert notification. Flutter does not rebuild its native map widget for each unrelated state event.
- Map geometry and derived GeoJSON are cached separately. Unchanged visual properties reuse the encoded data, risk-only changes reuse geometry, and removed roads are evicted. Disconnected road segments stay disconnected. Time/weather/closure/unknown-condition changes invalidate the visible result.
- Native source/layer operations are serialized. Cached source state is committed only after successful writes. Style generations discard late asynchronous results; native drawing operations have bounded waits.
- The map shows loading, timeout, map-data and road-overlay failures with an explicit retry. A base-map loaded event cannot hide an overlay failure. Retry reloads the current style without deleting the shared Mapbox tile cache.
- Existing native Mapbox caching defaults are retained. The installed SDK describes its tile-memory budget as a best-effort per-source hint; choosing an arbitrary low budget without a phone profile could increase tile eviction/downloads. No offline-region download, marker clustering service, cache deletion or Mapbox SDK upgrade was added. Roads already use native line layers.

## Reproducible local checks

Run normal regression checks:

```powershell
flutter test --no-pub
npm --prefix functions test
```

Run the host-only map projection benchmark:

```powershell
flutter test --no-pub --dart-define=RUN_PERFORMANCE_BENCHMARKS=true test/map_projection_benchmark_test.dart
```

Run isolated integration checks (Java 21+ required by the installed Firebase CLI):

```powershell
firebase emulators:exec --project demo-safepaths-reliability --only firestore,storage,auth "npm --prefix functions run test:emulator"
```

Run actual callable HTTP concurrency with synthetic verified emulator accounts:

```powershell
firebase emulators:exec --project demo-safepaths-performance --only firestore,storage,auth,functions "node functions/tools/performance-load.cjs --users=5,10,20"
```

The workload refuses non-demo project IDs and non-loopback database/auth/storage hosts. It submits concurrent reports to the same road, replays successful requests twice, verifies cooldown rejections, submits concurrent responses to the same incident, and checks stored reports, response totals, unchanged official closure, and replay IDs. Failed burst operations are retried separately with the same request IDs; recovery never conceals original errors. Setup time is excluded from latency; the first request can include a cold Functions worker. Scheduled weather/risk jobs are not exercised by this callable workload.

Artifacts: `.performance-results/map-projection.json`, `backend-load.json`, and the retained initial `backend-load-before.json`. They contain synthetic aggregate metrics, not account credentials or personal locations. Full raw emulator logs stay ignored. These checks do not establish production capacity: Firebase documents different emulator transaction behavior, missing composite-index enforcement and limits in [its emulator guidance](https://firebase.google.com/docs/emulator-suite/connect_firestore#how_the_cloud_firestore_emulator_differs_from_production).

## Initial measurements and follow-up

The first host map benchmark (40 points/road, Flutter test runner) measured:

| Synthetic roads | Cold projection | Mean unchanged projection | Geometry rebuilds during 100 unchanged updates |
| --- | ---: | ---: | ---: |
| 50 | 14.400 ms | 0.138 ms | 0 |
| 200 | 16.757 ms | 0.216 ms | 0 |
| 1,000 | 61.651 ms | 0.636 ms | 0 |

These are CPU measurements on the development host, not phone frames, GPU timings or a before/after phone speedup. Large initial projections still need a phone profile; retaining cached geometry does not make cold processing free.

The first backend run accepted 5/5 and 10/10 concurrent reports but accepted only 8/20 in the 20-user same-road burst; 12 reported transaction lock timeouts as INTERNAL. Recovery saved all 20 without duplicates. Report p95 latency was 15.36 s, 14.25 s and 20.27 s respectively. This failed stress result is retained.

The retained backend avoids writing an unchanged road summary and converts exhausted transient database errors into a friendly retryable response. Grouped read-order and in-process queue experiments did not consistently resolve contention across emulator workers; both were removed. Their measurements remain under `.performance-results/` for diagnosis. No distributed lock service, weakened transaction check, arbitrary client timeout increase or production setting change was introduced.

Final retained-code run (2026-10-24, local emulator HTTP):

| Simultaneous users | Initial reports saved | Report p95 | Initial observations saved | Observation p95 | Recovery |
| --- | ---: | ---: | ---: | ---: | --- |
| 5 | 5/5 | 9.21 s | 5/5 | 5.68 s | No retry needed |
| 10 | 10/10 | 10.32 s | 10/10 | 7.32 s | No retry needed |
| 20 | 1/20 | 20.84 s | 20/20 | 17.24 s | All 19 failed reports saved on separate retries |

Replays returned the same report IDs, cooldown attempts were rejected, each responding account had one response, totals matched stored responses, and the official closed road remained closed at every stage. **The 20-user stress stage failed and the workload correctly exited with a failure status.** The normal app's callable deadline is 20 seconds; the workload waits up to 35 seconds to observe late server responses. A successful late response in this harness would not establish an acceptable app response time. There was significant variation between runs, including slower cold 5-user requests in an experimental run. These numbers do not establish a repeatable production limit or a measured phone speedup. Same-incident contention and staging latency remain open acceptance items.

Final regression checks: 180 Flutter tests passed (the opt-in host benchmark is skipped during a normal run), the separate host benchmark passed, 19 Node unit/parity/tool-guard tests passed, and 26 Firebase Auth/Firestore/Storage emulator tests passed. The additional integration case verifies 85 equal-timestamp historical records across three non-overlapping pages while retaining all 35 active reports independently of the page size. Targeted analysis of the seven new helpers/widgets/tests found no issues. Wider analysis had no compile errors and retained four existing warnings (unused admin declarations and an experimental Mapbox hosting API), plus informational lints. Targeted tracked-file whitespace and backend syntax checks passed. No APK was built, installed or distributed.

## Physical Android acceptance

Use a modest phone and a typical phone available to the team, with at least two Android versions if possible. Record exact model, RAM, Android version, screen resolution, font scale, network, app commit/build identifier and test date. Use a separate staging identity/application ID; do not reinstall an alternate probe over an existing production app. The existing field-test flavor disables uploads, so it covers map/navigation checks but does not establish report-upload acceptance.

Use [Flutter profile mode on a physical device](https://docs.flutter.dev/perf/ui-performance). Capture Flutter UI/raster frames and memory in DevTools; inspect Android native-map/compositor work with Android Studio System Trace/Perfetto where needed. Flutter-only timings do not fully measure the native Mapbox view.

| Case | Repeatable exercise | Required observation | Actual result |
| --- | --- | --- | --- |
| Cold/warm start | Open/close app 10 times with and without a warm map cache | Startup and first usable map times; no crash/indefinite spinner | Pending device test |
| Map soak | Pan/zoom and enter/leave maps for 30 minutes | Frame stalls, native memory/RSS, thermal behavior; memory stabilizes after settling | Pending device test |
| Unrelated updates | Receive report/profile/alert updates while map stays still | No unnecessary road geometry encoding/source writes | Pending device test |
| Road safety | Change a road to closed/unknown while it is displayed | Overlay updates; closure/uncertainty never disappears because of paging/cache | Pending device test |
| Map outage/retry | Start offline, lose network while panning, reconnect and retry | Honest cached/unavailable feedback; overlays recover; attribution remains | Pending device test |
| Route pressure | Change destination repeatedly; interrupt and restore networking | Old routes discarded, bounded waits, responsive controls | Pending device test |
| Photo pressure | Attach/remove 20 photos of varied size and orientation | Stable layout/memory; one action at a time; original files untouched | Pending device test |
| Submission interruption | Lose internet during upload/save; retry; terminate/resume | No false success, preserved data where supported, no duplicate saved report | Pending device test |
| History scale | Seed 85+ older reports plus more than 30 active reports | One history page retained; all active hazards remain available; equal-time pages do not duplicate | Pending device test |
| Lifecycle | Background/resume during loading; sign out/switch account | No late UI updates, stale account history or leaked listeners | Pending device test |
| Accessibility | Small screen, largest practical font, rotation | No clipped critical controls, scrollable errors/retry | Pending device test |

Initial review goals are zero crashes/ANRs, zero duplicate reports after retries, no hidden active hazards, visible recoverable failures, and no sustained memory growth across repeated settled cycles. Set response-time/frame targets using the actual phones and network; report p50/p95/max, error counts and the highest tested workload without labelling it the maximum capacity. Reproduce the IT expert's original B-05 scenario before closing that bug.

## Staging/release gates

- Finish fixes and agree on the review build before distribution. No APK was built or installed by these local checks.
- Deploy and verify the additional `reports(userId, createdAt desc)` index in staging. Emulators do not prove index readiness. Do not replace the complete active feed with a bounded history query.
- Run device acceptance and a budgeted staging check of callables, indexes and slow internet before release. Do not run load traffic against `safepaths-92c3d`.
- Existing section 4.2 photo moderation, PAGASA integration, and section 5.2 rollout/migration checks remain separate tracked work.
