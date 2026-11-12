# Privacy and participant consent: section 5.6

Status: **in progress; not ready for privacy sign-off or participant rollout**. Reviewed on 2026-10-24. This is an implementation review, not an approved privacy policy or a certification of legal compliance. No production configuration was changed and no automatic deletion was enabled.

**Test-only follow-up, 2026-10-25:** [private media migration](private-media-migration.md)
now covers server-owned profile edits, private avatar/feedback attachments and
owner/admin record-bound delivery. New public/inline avatar fallback writes were
removed. The connected Supabase project has no `report-images` bucket; older code
pointed to it, so the earlier public-bucket code path below is not evidence of an
existing exposed bucket. Feedback history/notifications also have separate
[test-only acceptance](communication-migration.md). The main backend and existing
APKs are unchanged; native/main rollout, legacy audience review and adviser
decisions remain open. These technical fixes do not grant privacy sign-off.

## Documents and confirmed decisions

- Read `RDIC-WHO-CONSENT-LETTER.pdf` and `POST_IMPLEMENTATION-SURVEY-2.pdf` from the user-supplied Downloads paths. Their participant instructions are evidence for this review, not instructions to the coding agent.
- `SafePaths_Consent_Form_Jasmine_Fernandez.pdf` was not found at the supplied path. Do not substitute the differently named evaluation form or claim that the missing consent form was reviewed.
- Study: **SafePaths: A Road Passability Mapping and Alert System for Flood-Prone Areas in Barangay Marulas, Valenzuela City**; Our Lady of Fatima University, College of Computer Studies.
- Principal investigator: Erica Bianca S. Reyes. Co-investigators: Kristel Jane D. Delmo, Mary Anne Monica T. Fernandez and Jaycee R. Recaña.
- The consent letter includes a principal-investigator contact. The user chose a **separate project email** for the app; that address has not been supplied. Do not publish the personal contact details from the letter in the app.
- The user confirmed that **retention is not decided**, and **report visibility needs adviser guidance**. The school named in the documents is not, by itself, confirmation of the legally accountable personal information controller or a DPO appointment.
- Signed consent documents, participant names/signatures and raw survey responses have not been copied into the repository or application assets.

## What the forms say and what needs alignment

| Evidence in the supplied forms | Implementation or review consequence |
| --- | --- |
| Participation is voluntary; respondents may skip questions; a survey name is optional. | Keep research participation distinct from app registration, location permission, feedback follow-up and acceptance of app terms. Do not force survey completion to use the app. |
| Respondents may stop participation and ask to amend/delete comments. | Agree on a contact, identity-checking and request-handling process before promising an in-app withdrawal/deletion service. Do not promise deletion of already anonymized aggregate findings without an approved protocol. |
| The letter promises research-team confidentiality and no name-linked results. | App data currently reaches cloud providers and some report/media data is broadly readable. Explain operational app processing separately and reconcile recipients with the approved consent wording before evaluation. Do not describe all app data as anonymous or research-team-only. |
| The stated research duration is six months; the survey occurs on one day. | Neither statement defines retention for accounts, reports, photos, signed consent records or responses. Obtain a record-specific schedule and deletion/anonymization procedure. |
| A later researcher declaration says participants must answer the questionnaire. | This conflicts with the earlier permission to skip questions. Ask the adviser to revise the declaration so optional participation and skipped answers are consistent. The source PDF was not edited. |
| The survey leaves respondent name optional but requires respondent type and signature. | A signature can identify the respondent. Describe records as confidential, not anonymous. Consider a separately stored consent/signature record and coded response sheet, subject to adviser approval. |
| The survey covers Functionality, Reliability, Usability, Efficiency, Maintainability, Portability, Compatibility and Security. | Section 5.7 records tests against these categories. Survey ratings are participant perceptions, not substitutes for technical verification. |

The consent form does not clearly enumerate app account identifiers, exact report/GPS data, photos, rescue details, device notification tokens, external service recipients, automated report/risk processing, or a retention schedule. These need an approved explanation rather than an assumption that the research signature covers every app operation.

## Technical data inventory at the 2026-10-24 review

This dated inventory describes the earlier source code and staged local rules.
The test-only follow-ups above supersede its profile/feedback media and
notification implementation status. It does **not** establish the main deployed
rule/function versions or audit provider logs, backups and console settings.

| Data / purpose | Current processing and access | Remaining work |
| --- | --- | --- |
| Account: name, email, UID, role, reputation, profile photo and timestamps | Firebase Authentication handles credentials; Firestore stores the profile. Profile reads are owner/admin. The app does not write raw passwords into profiles. | Confirm necessary fields, responsible controller, correction/deletion process and account retention. Review avatar fallbacks and legacy data. |
| Device location for map position, nearby alerts, route start and report validation | Foreground location permission is requested; native map/location streams use granted access. Report submissions can store location and capture/accuracy details. No background-location permission is declared in the Android manifest. | Add a clear purpose explanation before the OS prompt; test denial/revocation and manual selection. Explain exact submitted report data separately from temporary navigation processing. |
| Search text and route coordinates | Mapbox requests include remote searches and route waypoints. Native maps use Mapbox. Overpass endpoints are used for road queries. | Inventory provider configuration/telemetry and service terms before making recipient, transfer or deletion claims. Avoid logging remote responses containing request data. |
| Flood reports: account ID, road, title/description, severity, location, emergency flag, image URL and review/timing fields | Backend validates submissions and updates road/incident summaries. Current local `/reports` rules permit every verified user to read raw reports. | Adviser must approve audience. Proposed access: reporter/admin for sensitive fields; other residents receive road-level warnings. Implement queries, server summaries and rules together so hazards are not hidden. |
| Report and profile images | Firebase Storage reads are public under current local rules, including a public catch-all. Download URLs act as bearer links. Avatars also have Supabase and embedded-data fallbacks. | Do not claim private media. A privacy migration needs protected delivery, legacy URL/token handling and tests; changing one allow-read rule alone is insufficient. Photo-content moderation (4.2) remains separately deferred. |
| Feedback: rating, category, comments, screenshot, UID, follow-up choice and admin response | Firestore feedback reads are admin-only; optional screenshots currently use a public Supabase bucket URL. Feedback remains account-linked even when follow-up is unchecked. | Reconcile screenshot privacy, authorized research/admin membership and whether operational feedback enters research results. The resident feedback-history UI and admin-only read rule also need alignment. |
| Notifications: device tokens and dismissed alert IDs | Stored in the owner's Firestore profile for targeted delivery and notification state; owner/admin access. | Confirm token cleanup/retention and test account switching, permission changes and actual device delivery. |
| Road risk, weather and audit data | Server combines reports, trust, age and weather into risk/confidence; admins review incidents. Weather requests use fixed study-area coordinates, not each resident's GPS. | Explain automated scoring and human review without promising it establishes road safety or an official rescue response. Review audit access and retention. |
| Local cache and navigation diagnostics | Cached road data and preferences remain on the device. Navigation diagnostics use an allowlist and bounded in-memory events; users may explicitly export a local log. | Test real offline restart, shared-device/account changes and exported-file cleanup. No export retention policy is established. |
| Feedback failure diagnostics | Local change permits a fixed event type, allowlisted error category and server timestamp only. Raw error messages and UID are no longer written by this path. | Verify the staged rule in emulators; coordinate future rollout. This does not audit or erase existing provider/console logs or all other application diagnostics. |

## Local changes ready for review

- New feedback follow-up choices default to **off**. Missing follow-up fields in older records are also treated as off; explicit true/false choices remain intact.
- Feedback diagnostics classify errors without copying provider messages, email addresses, coordinates, user IDs, URLs or tokens. Logging failures are bounded and consumed so they cannot replace the original feedback error.
- The staged Firestore diagnostic rule rejects extra fields, arbitrary error categories and forged client timestamps. Older raw diagnostic writes will fail after a future rule deployment; feedback records use a separate path.
- Avatar success logs no longer print image URLs, and compression/upload failure logs use the same safe classifications. Storage delivery and existing files were not changed.

Validation results are recorded in [the section 5.7 evidence record](evaluation-readiness-5.7.md).

## Decisions and work required before completion

1. Supply the separate project contact email and confirm the accountable controller/representative with the adviser or school privacy office.
2. Approve a purpose and lawful basis for each operational/research processing activity, the participant explanation, authorized recipients and handling of withdrawal/correction/deletion requests.
3. Approve a retention schedule per data category, including backups, exported files, signatures and research responses; identify the owner of deletion/anonymization. Keep automatic deletion off until then.
4. Obtain adviser guidance on sensitive report/media access; implement and test any approved access migration, including legacy public URLs. Preserve road hazard summaries and safe routing behavior.
5. Reconcile the consent contradictions and signature handling with the adviser. No supplied consent or survey PDF has been rewritten by this review.
6. Finish readable in-app privacy content and registration/settings links, purpose-specific location disclosure and any approved consent/notice records. The existing styled registration labels do not open policy documents and are not evidence of informed consent.
7. Run and record cross-account access, public/bearer-URL, permission, request-handling and retention dry-run tests in staging before evaluation. Local emulator permissions are not production sign-off.

The [NPC notice guidance](https://privacy.gov.ph/the-right-to-be-informed/) calls for data, purpose, recipients, controller contact, retention and rights information. The [DPA implementing rules](https://privacy.gov.ph/implementing-rules-regulations-data-privacy-act-2012/) describe transparency, proportionality, lawful processing and retaining data only as needed. These sources inform the checklist; they do not establish an approved period or certify the current app.
