# Road import and deletion reliability

Implemented for the isolated `safepaths-test` project and its existing Supabase
proof function. This closes the test implementation of the two maintenance gaps
found in the integration audit. Main-project integration, APK building and phone
acceptance remain separate. No main Firebase changes or APK distribution occur
as part of this phase.

## What changed

Imports now use a protected, create-only server transaction. Every selected OSM
ID is checked against current server data. An existing road is skipped instead
of merging an old import snapshot over its status, notes, verification or
geometry. Simultaneous imports create an ID once. A new road's neighbor links
are calculated in the same transaction, so the migrated importer no longer runs
a separate client graph rebuild after saving. The result reports actual created
and skipped counts, including receipt replays after a lost response.

Deletion first loads a current, account-bound confirmation. The server rejects
a stale confirmation, a changed admin role, pending/under-review reports, an
unresolved incident, and a road whose current status is not passable. A newly
imported, unverified road can still be removed when it has no active conditions.
Officially closed/partially passable roads require a current review before
network removal; deleting a record cannot substitute for resolving a hazard.

An accepted deletion atomically removes the selected road and every bounded
incoming neighbor reference, advances the topology revision, and records an
audit and retry receipt. Reports, resolved incidents, messages and photos are
retained. Neighbor edits change only links and risk-input stamps, preserving
official status, notes and verification timestamps. Retrying an old deletion
after the same OSM ID is reimported confirms the old action; it does not delete
the newer road generation.

The risk worker stores the topology revision alongside its cached graph. A
revision change forces a full scoped scan on its next run, instead of waiting
for the hourly scan. Existing transaction fences reject inputs changed during
calculation and prevent a false success heartbeat. An empty network is valid:
deleting the last road clears the cache and records a zero-road success instead
of leaving the worker in a failure loop.

Graph repair also runs through the server. It checks real geometry segments
separately, including T-junctions within the existing 25-meter tolerance;
disconnected pieces never become an invented connecting segment. Geometry,
comparison and write bounds fail before committing a partial maintenance change.
Oversized operations return a recoverable error so an admin can choose a smaller
operation or review the network.

## Scope, controls and limits

The native paths use the existing `SPARK_PROOF_CORE_ENABLED` fieldtest option.
The managed backend requires `PROOF_ROADS_ENABLED=true` and the core migration.
`system/road_maintenance.enabled=true` protects all direct road writes, including
legacy client-admin writes. The topology marker is also protected. Maintenance
requests are server-only; audits are readable by current admins. The existing
Firebase verification, current account/role checks and three synthetic-account
allowlist remain in force. No client has a private server credential.

`RoadMaintenanceService` uses durable, account/environment-scoped request IDs.
It retains only opaque retry/context data locally, and checks the confirmed
operation, created/skipped counts and result structure. Failed imports preserve
the selection; the screen blocks back navigation while importing. Deletion asks
for explicit confirmation of the loaded current road; a stale response asks the
admin to refresh. These host checks do not prove actual Android lifecycle,
permission, connectivity or background behavior.

Protocol limits are explicit: 10 candidate roads per import command, 1024 points
per road/2048 per command, 1000 scoped roads, 40,000 graph points and one million
estimated pair comparisons. A maintenance transaction changes at most 400 road
documents. Deletion prunes at most 200 incoming road records and refuses a scan
that exceeds the proof's 100 active-report bound. No new Firestore composite
index is required; the existing 14 indexes remain in use. These are proof bounds,
not established production capacity or a substitute for the small stress test.

The production compatibility import/deletion branches remain part of the older
architecture. A main APK must inherit the protected paths through the separate
main integration; this test acceptance does not certify that legacy branch.
The earlier [integration audit](full-app-integration-audit.md) still describes
the main release blocker and other unresolved gates.

## Deployment and recovery

`prepare-road-maintenance.cjs` rejects main-project credentials and defaults to a
read-only check. `--apply` privately snapshots the test control, marker/cache,
worker state, synthetic profiles and current roads before preparing a disabled
control. After staged test rules/function checks, `--apply --activate` enables
the control and bumps the topology revision once. The managed roads flag then
enables the new commands. No bucket, index or scheduler is created or replaced.
Existing four-minute core and five-minute push schedules stay in place.

Pause commands through the backend roads flag while retaining protection of
direct writes. Keep dependent core/roads flags coordinated. Do not reopen broad
client writes or restore a whole backup over later official decisions. Preserve
newer roads, resolved history, receipts and audit records during recovery.
Retention, audience and automatic deletion decisions remain unchanged.

## Verification

Local checks passed: 252 Flutter tests (one optional benchmark skipped), 49 tests
with the complete candidate configuration, 60 backend unit tests and 98 emulator
integration tests. The actual Deno Edge entry point checked successfully. Full
analysis has zero errors and the same four existing warnings; its 315 total
findings include informational/style items.

The emulator cases exercise simultaneous imports, a concurrent official review,
response-loss replay, stale/other-admin confirmation, derived-risk-only changes,
active hazards, neighbor pruning, retained history, rollback, deletion followed
by reimport, empty networks, topology changes during risk calculation and denial
of legacy direct writes.

Thirteen hosted checks passed using two new isolated synthetic OSM-like road IDs.
They verified the actual protected endpoints, stale import/closure preservation,
direct-delete denial, an actual pending report/incident blocking deletion, its
explicit resolution, retained history and the next hosted worker's cache
refresh. Both synthetic roads were removed through the protected API. The helper
checked that every original road's official data remained unchanged; it never
deleted an existing road or targeted a phone. Synthetic report/incident history,
receipts and audits remain as evidence.

Seven checks through the actual Dart client also passed against the hosted
endpoint. They recovered the import, repair and deletion receipts, confirmed
that old receipts did not recreate removed roads, loaded current protected
context and rejected a resident's administrative request. The existing eight
normal report/photo, 18 communication and nine push regressions passed after
the maintenance rollout, including confirmed synthetic-device cleanup.

Final read-only checks confirm the maintenance/media/communication controls,
all 14 indexes READY, no active phone registration, matching worker/marker
topology revisions and a successful risk heartbeat. Existing core and push
schedules still complete actual HTTP 200 runs; client database roles cannot
execute their private signers. These results do not explain or erase the earlier
unreproduced push-test failure documented in the integration audit.

Detailed results, private setup state and source/installer hashes are retained
under ignored `.usability-work-baseline/roads-*` and `spark-proof-setup` files.
Private backups/credentials are not distribution artifacts. Native acceptance,
small-workload stress/B-05, main integration, adviser privacy decisions and
deferred section 4.2 remain open.

### Marulas MacArthur section correction — November 8, 2026

At the project owner's request, the main database now contains two MacArthur
Highway sections: Fatima / OLFU and BBB. The former Marulas Public Market
geometry was merged into the existing BBB ID. Fatima / OLFU was clipped to the
existing Marulas study polygon near J.P. Rizal/Fausto, compared against the
owner's supplied boundary screenshot; the northern extension toward SM
Valenzuela/Karuhatan was removed. This is a study-area correction, not a new
survey or a claim that the app polygon is a cadastral boundary.

The migration preserved individual geometry parts without drawing artificial
links between them. It backed up the road records, checked that the source
sections had no reports, alerts or incident records, and committed the merge,
affected neighbor lists and topology revision atomically with concurrency
checks. Existing conditions, verification authors, notes and inspection dates
were preserved. The former Public Market ID was removed; five road records
were updated in total. Main road count changed from 152 to 151.

Read-back checks confirmed exact prepared geometry, symmetric links, no dangling
references, unchanged component count, and preserved verification fields. The
existing risk worker completed successfully with topology revision 1 and a
151-road cache excluding the removed ID. The audit is
`road_maintenance_audits/macarthur-two-sections-20261108`. Private backup and
review artifacts are grouped under the ignored
`.usability-work-baseline/macarthur-review-20261108/` directory. No APK or test
database changes were needed; visual confirmation in the Marulas app remains
the next device check.

The owner subsequently identified the northern Inocencio Street and F. Lazaro
Street records as Karuhatan roads and requested their removal from the Marulas
monitored network. Both were backed up and removed in one guarded transaction
after confirming there were no linked reports, alerts or incidents. Incoming
links were pruned from Fausto Street, Felomina Street and Legion of Mary Street.
Road count is now 149; topology revision is 2. The existing worker refreshed
successfully. These changes remove SafePaths monitoring overlays, not the
underlying Mapbox street labels. Audit:
`road_maintenance_audits/remove-karuhatan-northern-roads-20261108`; private backup
and verification artifacts:
`.usability-work-baseline/northern-roads-20261108/`.
