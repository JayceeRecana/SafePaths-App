# SafePaths

SafePaths describes road conditions, community flood observations and navigation in its configured study area. These terms reflect the current domain vocabulary.

## Language

**Resident**: A community member who views road information, plans trips and submits observations.

**Admin**: An authorized operator who reviews resident reports and manages road information and community alerts.

**Study area**: The geographic area for which a SafePaths environment provides its road and reporting data.

**Marulas**: The capstone study-area environment used by the main SafePaths app.

**Fieldtest**: The separate nearby test-area environment used to exercise SafePaths without mixing its records with Marulas.

**Road**: An identified road segment with geometry and condition information used in reporting and navigation.

**Road status**: The recorded passability state of a road: passable, partially passable, not passable, or unknown when reliable status information is unavailable.
_Avoid_: Risk score, flood probability.

**Report**: A resident's submitted observation about a road condition, with a description and any associated road, location and supporting evidence.
_Avoid_: Confirmed incident.

**Incident**: The current episode of reported flooding associated with a road, tracked through observation and admin review.

**Root report**: The original report to which a condition history and its follow-up reports belong.

**Follow-up report**: A later observation linked to a root report that records a condition change or additional evidence for the same resident and incident.

**Historical follow-up**: A follow-up retained as past evidence after its incident has been marked passable, rather than treated as a new live flood signal.

**Clarification**: An admin request for more information from the resident about an existing report.

**Under review**: A report state indicating that admin review has begun.

**Waiting resident**: A report state indicating that a clarification awaits the resident's reply.

**Report reply**: An admin message attached to a report conversation, distinct from a community-wide broadcast.

**Observation time**: The time the resident observed the road condition, which can differ from the time the report was submitted or reviewed.

**Resolved incident**: An incident for which an admin has verified the road as passable.

**Outdated condition**: A condition whose observation is expired, too old, missing or implausibly dated to describe the current road state reliably.
_Avoid_: Currently safe, resolved.

**Risk score**: A calculated road-risk indicator informed by road state, report evidence, weather and related conditions.
_Avoid_: Observed flood depth, guaranteed safety.

**Confidence**: An assessment of the support for reported condition information, distinct from the severity of that condition.

**Trust score**: A resident's reporting-reputation score, distinct from the confidence assigned to an individual observation.

**Authority score**: The reporter-reliability input associated with a particular report and used in assessing its confidence.

**Severity**: The stated seriousness of a reported condition or an alert, distinct from confidence and predictive risk.

**Vulnerability**: A road's underlying susceptibility to flooding, distinct from its current passability.

**NOAH awareness**: Prepared flood-hazard context shown for awareness, distinct from live observations and road passability.
_Avoid_: Live flood measurement, routing decision.

**Planned route**: A proposed path to the resident's selected destination before or during trip preparation.

**Route step**: An individual maneuver or instruction along a planned route.

**Hazard alert**: A warning about a hazardous road the planned route actually crosses.
_Avoid_: Avoided road.

**Avoided hazardous road**: A hazardous road excluded by the selected route compared with a less favorable alternative.

**Blocked route**: A route that crosses a road marked impassable and cannot be used to start navigation.

**Unconfirmed conditions**: Road conditions that the app cannot currently verify, including unverified roads or portions outside the monitored study area.
_Avoid_: Clear, guaranteed safe.

**Route score**: A summary score used to compare a route's assessed conditions; it is not a guarantee of safety and is labeled unconfirmed when conditions cannot be verified.

**Rerouting**: Reconsidering the active path when navigation conditions or the trip's progress require another path.

**Broadcast alert**: An admin message intended for a community audience rather than a private report conversation.

**Active alert**: A broadcast alert that has not been withdrawn and has not expired.

**Alert template**: Reusable title, message and severity content for composing an alert.

**Saved alert**: An alert recorded by the system, distinct from confirmation that its push notification was sent or delivered.

**Feedback**: An app-experience rating, comment or suggestion, distinct from a road-condition report.

**Action log**: A timestamped record of a system or operator action and its details.

**Private evidence**: Report media whose access is controlled rather than generally public.
