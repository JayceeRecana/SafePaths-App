**SafePaths resident/admin communication test sequence - 26 October 2026**

Use the resident Android 11 phone and Pixel_9 admin emulator. Install SafePaths Test v1.0.3 on the resident phone to include the photo-overlay fix. Using the same version on the emulator is recommended; the prior migrated test admin build can exercise unchanged communication routes. Both must show TEST AREA and use the preset test cohort, not the usual main-project account. Credentials remain in the private local .usability-work-baseline/spark-proof-setup/PRIVATE-test-accounts.json; do not include them in recordings or shared results.

This sequence tests resident reports -> admin acknowledgement/private updates -> resident receipt/read; feedback and area broadcasts are separate paths. It does not assume a resident live-chat composer. All records and notices below must be clearly labelled TEST and remain in the isolated test area. Choose an existing public road segment rather than adding a synthetic fixture at a home or route origin. For the first report, use a condition that does not require a closure; keep road-changing drills separate until the base communication works.

Read the expected result before each action. Send one update at a time for ordinary delivery checks. Record an in-app save separately from a phone notification and separately from successful notification-tap routing. A five-minute observation window is useful for a delayed notification; it is a test window, not a delivery guarantee. If none arrives, record the actual wait and notification state; continue checking saved history and investigate the delivery path. Never turn Saved, Queued or provider accepted into Phone received without observing it.

Submission/edit cooldowns are intentional. Follow the displayed timer instead of repeatedly creating new records. Use the same open form/dialog for retry tests. Full unsaved-form restoration after killing the process is not promised. Feedback has a separate submission cooldown. Trust rewards/deductions are capped and can be zero; record the actual change rather than assuming a fixed award.

The test-results sheet is .usability-work-baseline/communication-phone-results-20261026.csv. It starts NOT RUN; this plan is not a claim that the phone tests passed.

**C01 - Setup and photo UI**

Resident phone: install SafePaths Test v1.0.3, confirm TEST AREA, sign in as preset resident A. Admin emulator: preset test admin, TEST AREA. Both online. Check app notification readiness and Android notification channels. Attach/cancel a non-personal image in Reporting and Edit Profile.

Expected: Correct accounts and test area; notification readiness recorded; photo screens remain visible without map covering them.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C02 - New report**

Resident A: choose an existing public test-area road. Put TEST-COMMS-A at the start of the description, attach a test image, submit once. Keep SOS off for this first case. Record report ID, road, time and trust score.

Expected: One report saved in resident history and admin feed; correct description/photo/location. New report starts received/pending.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C03 - Read-only opening and acknowledgement**

Admin: open that exact report, then select Start review. Resident: watch its status.

Expected: Opening alone leaves status unchanged. Start review changes it to under review; resident sees the acknowledgement.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C04 - Foreground private update**

Keep resident report open. Admin: send TEST-M1: Your report has been received and is being reviewed using Send message now.

Expected: Message appears once in Admin updates, on the correct report. Record any foreground notification separately.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C05 - Background push and tap**

Resident: press Home. Admin: send TEST-M2: Background notification check. Record send/receipt times, then tap the phone notification.

Expected: Phone receipt observed and timed; tap opens the correct report and current private update. Saved/queued/provider accepted alone is not a receipt pass.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C06 - Locked phone and cold opening**

Repeat with TEST-M3 while phone is locked. Then test TEST-M4 after removing the app from Recents, without Android Force stop. Tap the notification to reopen.

Expected: Observe delivery in each state; tapping routes to the correct report. Private reply/photo/details should not be exposed in generic notification text.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C07 - Resident offline and recovery**

Disconnect resident phone. Admin sends TEST-M5. Open resident history while offline, then reconnect and reopen the report.

Expected: No claim of live receipt while offline; cached state labelled appropriately. Latest message appears after reconnect and remains saved. Record delayed push separately.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C08 - Admin offline and retry**

Keep admin reply dialog/form open, type TEST-M6, disconnect emulator and try saving. Reconnect, retry the same draft/request and reopen both histories.

Expected: Failure or uncertain save is shown accurately; draft retained in the open form. Recovery leaves exactly one saved message, with no false success.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C09 - Notifications disabled and restored**

Disable SafePaths notifications or the private-update channel on phone. Admin sends TEST-M7. Check history, restore notifications, reopen app/check permissions, then send fresh TEST-M8.

Expected: No blocked-channel phone alert expected for M7; M7 still exists in history. Readiness reflects settings. Fresh M8 can be received after restoration. Old suppressed work need not re-notify.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C10 - Resident edit and stale admin review**

Wait for any displayed report-edit cooldown. Admin opens verification dialog and leaves it open. Resident A uses Update Your Report to add TEST-EDIT-A. Admin attempts to save the old loaded review, then refreshes and cancels for now.

Expected: Edit reaches admin. Old review is rejected/needs refresh, rather than overwriting newer information. Draft edits are not silently converted into another report.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C11 - Account switching and private access**

Resident phone: sign out A, sign in with preset peer resident B. Inspect own history; try an old notification only if one remains. Admin sends TEST-M9 to A. Sign back in as A, check history and send fresh TEST-M10 from admin.

Expected: B must not see A private admin thread, new protected report photo or feedback. B must not receive M9 addressed to A. A can read saved M9 after login and receive fresh M10. Public road warnings can remain visible to both.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C12 - Verify observation separately from road condition**

Admin: refresh current review, record original road condition, select an accurate simulated test condition and enter TEST: simulated review for communication testing; not a field inspection. Complete required confirmation and Save verified review.

Expected: Resident sees Verified with an accurate review outcome. Chosen road condition is shown separately. Actual trust change matches shown result, including zero/caps/cooldowns. Reopening/retrying does not award twice. Reviewed report cannot be edited.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C13 - Duplicate dismissal**

After the submission cooldown, resident creates TEST-COMMS-DUP. Admin dismisses as Duplicate / already handled with a factual test note.

Expected: Resident sees dismissal and reason. Duplicate dismissal does not deduct trust; reopening/retry does not duplicate the decision.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C14 - False/spam confirmation**

Use a separate deliberately synthetic TEST-COMMS-FALSE report. Admin chooses Confirmed false / spam, tests the required evidence acknowledgement, and saves with an accurate test note.

Expected: Required acknowledgement enforced; actual bounded trust deduction is shown accurately and applied once. Earlier floodwater receding alone is not treated as a false report.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C15 - SOS communication safeguards**

Use only TEST AREA and an explicitly labelled TEST SOS - no real emergency report. Confirm its priority in admin review. Exercise dismissal with required extra SOS acknowledgement and an accurate test note.

Expected: SOS priority and confirmations work. Messages/status must not claim that rescue has been dispatched or completed simply because a report was saved/reviewed/dismissed.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C16 - Feedback with follow-up enabled**

Resident: Feedback & Suggestions, complete category/rating/comment TEST-F1, enable Allow Follow-up, submit once. Admin: Review / reply, Mark under review, then Save a reply with TEST-F1 reply. Check Queue a generic update notification. Background resident app and send.

Expected: Feedback saved in owner history/admin feed. Reply stays in private history without automatically closing feedback. Observe notification and verify its tap opens the correct feedback.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C17 - Feedback closure and reopen**

Admin: choose Close feedback, select Recorded; no fix claimed, enter a truthful test note and check the confirmation. Resident checks outcome. Admin then chooses Reopen for review.

Expected: Explicit closure outcome/note preserved without claiming a fix. Reopening changes status while retaining the existing message history.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C18 - Feedback with follow-up disabled**

After displayed feedback cooldown, submit TEST-F2 with Allow Follow-up OFF. Admin replies and checks available notification controls.

Expected: Owner can read the saved response in feedback history. Optional notification is disabled/suppressed when consent is absent. Peer B cannot read F1/F2 private threads.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C19 - Scoped broadcast**

Admin: Broadcast Alert, title TEST-BC1 - communication drill, message Test only; no real flood advisory, severity Advisory, validity 15 minutes, test-area audience. Record any linked road original official fields, publish once while resident app is backgrounded.

Expected: Resident Alerts displays correct content and audience. Observe phone notification/tap. Publication does not change official road status, verification time or notes. Saved publication alone is not proof of phone receipt.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C20 - Withdraw broadcast**

Admin retracts/withdraws BC1 with TEST: communication drill completed. If its old notification remains, resident taps it.

Expected: BC1 is removed from active alerts or shown withdrawn/inactive. Old tap opens current withdrawn state. Already handed-off notifications are not assumed recallable.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C21 - Broadcast expiry**

Publish separate TEST-BC2 with 15-minute validity. While it ages, finish remaining cases. Open it again after expiry.

Expected: Expired alert is not presented as an active warning. History/old tap clearly identifies inactivity. No manual clock change or expiry-field manipulation.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C22 - Feedback and publication retry**

Repeat a feedback submission/reply and a broadcast publication with a short connection interruption, retrying each same open form/request. Use fresh TEST labels. Withdraw the extra broadcast afterward.

Expected: No false success, lost open-form draft, duplicate feedback/reply/publication or silently extended broadcast expiry from retry. Keep draft-restoration-after-kill outside this check.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C23 - Restart, force stop and rapid updates**

Restart/reopen both apps and check saved histories. For Android Force stop, reopen manually, check history/readiness and send a fresh update on a still-active report or reopened feedback. Send several labelled updates in succession as a separate case.

Expected: Saved messages/outcomes survive restart. Force stop may stop push until reopen; fresh receipt checked afterward. Every saved message remains in-thread, even when Android combines/replaces tray notifications.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**C24 - Cleanup and outcome record**

Restore any intentionally changed test-road condition through admin review with a truthful cleanup note. Withdraw remaining test broadcasts, resolve active TEST SOS/report items appropriately, restore phone connectivity and notification settings, sign back in as resident A.

Expected: Test state identified/cleaned without wiping records or resetting accounts. Record each case as PASS, FAIL, BLOCKED or NOT RUN; native acceptance remains open for any unobserved requirement.

Record: PASS / FAIL / BLOCKED / NOT RUN; actual result; save time; phone receipt time; tap destination; error text.

**Verification-condition note**

C12 is a simulated communication review. Keeping the road original condition avoids accidentally blocking the route baseline. To additionally demonstrate that verifying a report does not automatically reopen a flooded road, use an agreed isolated public test segment, deliberately select Not passable during its simulated review, confirm Verified report plus Not passable road, and restore through a new accurate admin review after the drill. Do not backdate timestamps or claim a real field inspection.

**Completion and limits**

A case passes only when its expected result is actually observed. If upload UI is covered, stop C01 and record the display defect before testing submission. If a save succeeds but no notification arrives, record save PASS and receipt FAIL/PENDING separately, then keep the exact resource label/time for diagnosis. Stop and record failures that expose another account private content, silently change the wrong road, duplicate saved decisions, lose a retained draft on ordinary retry or claim rescue dispatch without a real recorded action.

One physical resident phone plus an admin emulator can establish these workflows for that setup. It cannot establish simultaneous two-physical-resident fan-out, other Android versions/devices, all OEM background restrictions, stress capacity or every server concurrency/authorization case. Account-role removal, worker failure injection and multi-admin contention retain their automated/backend checks; do not claim they were physically exercised by this checklist. Project privacy/retention decisions and main-project rollout remain separate.
