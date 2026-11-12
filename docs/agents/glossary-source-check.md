# SafePaths glossary source check

Checked on 2026-11-12 against the current working-tree Dart models and related behavior. The glossary describes domain language; this document keeps implementation evidence separate. This was a source review, not a runtime acceptance or backend consistency test.

| Terms checked | Source and observed meaning |
| --- | --- |
| Resident, admin, trust score | `lib/models/user_profile.dart`: profile role and reporting reputation are distinct from report confidence. The default stored role is `user`, while the user-facing name is Resident. |
| Road, road status, vulnerability, risk score | `lib/models/road_status.dart`: passability, susceptibility, verification and predictive risk are separate properties. Unknown legacy status must not be described as passable. |
| Report, root report, follow-up, historical follow-up | `lib/models/user_report.dart`, `lib/services/report_followup_service.dart`: follow-ups link to the original report, resident and incident. A follow-up associated with an incident marked passable is historical evidence. |
| Under review, waiting resident, clarification, reply | `lib/models/user_report.dart`, `lib/services/report_clarification_service.dart`: pending/under-review reports need admin review; waiting-resident remains an open review awaiting clarification. Replies are not broadcast alerts. |
| Observation time, outdated condition | `lib/utils/report_freshness.dart`, `lib/models/road_incident.dart`: observation time differs from submission/review time; expired, old or implausibly future observations are not current. An unresolved incident can also be outdated when its observation is missing. |
| Incident, resolved incident | `lib/models/road_incident.dart`: resolved incidents are labeled Admin verified passable; admin-confirmed flooding and under-verification are distinct states. A report's status alone must not be substituted for the road's incident state. |
| Confidence, authority, severity, risk | `lib/services/risk_engine.dart`, `lib/models/user_report.dart`: reporter authority contributes to live confidence; severity and report evidence contribute separately to road risk. Scores do not prove a road is safe. |
| Planned route, route step, hazard alert, avoided hazardous road | `lib/models/planned_route.dart`: hazard alerts describe hazardous roads actually crossed; the avoided count is a comparison with a baseline alternative. |
| Blocked route, unconfirmed conditions, route score, rerouting | `lib/models/planned_route.dart`, `lib/utils/route_tracker.dart`: blocked routes cannot start navigation. Outside-area or unverified conditions produce an Unconfirmed label, rather than a verified safety score. Route tracking supplies navigation progress and rerouting context. |
| NOAH awareness | `lib/services/noah_awareness.dart`: prepared hazard context is display-only; it has no dependency on the risk engine, road status, reporting or routing. |
| Broadcast alert, active alert, saved alert | `lib/models/broadcast_alert.dart`: withdrawal and expiry determine activity. `BroadcastResult` separately tracks saving an alert and sending push notifications. Sending is not evidence of device delivery. |
| Alert template | `lib/models/alert_template.dart`: reusable title/message/severity content. |
| Feedback | `lib/models/feedback_model.dart`: ratings, comments, follow-up permission and admin review are separate from road reporting. |
| Action log | `lib/models/system_action_log.dart`: timestamp, action and details. |
| Study area, Marulas, fieldtest | `lib/config/study_area.dart`, `lib/config/app_environment.dart`, `README.md`: Marulas and nearby-test environments have distinct geographic/configuration contexts. |

## Corrections and additions

The earlier glossary broadly matched the app. This pass added unknown road status, root/historical reports, observation time, reporter trust versus report authority/confidence, route hazards versus avoided hazards, blocked/unconfirmed routes, and the remaining alert/feedback/log vocabulary. The existing distinction between NOAH awareness, live reporting and routing was retained.

No domain model was renamed and no business rule was changed. When implementation changes, recheck the affected row and update the short definition in the glossary.
