# Section 5.1: security and account management

## Implemented locally

| Recommendation | Result |
| --- | --- |
| Email or phone verification | Email verification is required before account access. Registration can send the first link; the verification screen supports resend with a persisted 60-second cooldown, manual checking and checking after returning to the app. Successful verification reloads the Firebase user and refreshes the token. Login and restored sessions share the same account gate. Backend callables and protected database/storage actions also require verified identity. |
| Forgot password/reset | Existing Firebase reset flow now validates addresses, disables repeated submissions, bounds the network wait and uses the same generic success message for known and unknown addresses. The password is changed using Firebase's hosted reset flow. |
| Login attempt limits | The app persists a one-minute device cooldown after five failed credential attempts and honors Firebase's `too-many-requests` response. Successful sign-in clears the local counter. Firebase remains responsible for server-side sign-in abuse protection: this local counter can be bypassed by a modified client or cleared app data and is not a custom global account/IP limiter. |
| Password storage and HTTPS | Credentials remain in Firebase Authentication; the app does not implement or store password hashes. Passwords and raw auth/refresh tokens are not stored in SharedPreferences. Custom backend requests use HTTPS, remote image readers reject plaintext HTTP, Supabase setup requires HTTPS, and Android explicitly rejects cleartext traffic. |
| Session timeout/token handling | Admin sessions expire after 15 minutes of inactivity and resident sessions after 30. Active resident navigation counts as activity so guidance is not interrupted. Expiry is checked after app resume and on restored sessions, including time spent in the background. Firebase handles auth-token storage/refresh; user-state checks detect disabled/deleted/revoked sessions. Protected callables compare the signed authentication time against Firebase's revocation timestamp. Sign-out removes this device's FCM token where possible, invalidates its local registration, cancels data listeners and clears account state. |

Timeouts are application session policy, not a claim that an already issued Firebase token is instantly revoked everywhere. Rules validate the supplied signed token; backend calls additionally check the current Auth user record. Runtime Auth lookups fail closed if user identity cannot be confirmed.

The account gate requires a live profile/role lookup before entering the admin UI. An account whose registration succeeded but profile write failed can finish profile creation after verification. Former anonymous or invented offline IDs are no longer treated as signed-in identities. Existing sessions without the new activity record will require a fresh sign-in after upgrading.

## Required before release

1. Deploy the coordinated backend, rules, indexes and updated app described in `reliability-rollout.md`. Do not publish the verification-dependent rules without the matching verification UI. Existing administrators also need verified email addresses.
2. In Firebase Authentication, confirm Email/Password sign-in is enabled; configure and test verification/reset templates, sender identity and authorized domains with real inboxes. No SMS provider or phone verification flow was added.
3. Align Firebase's server password policy with the app's existing registration requirements. Review server sign-in abuse controls and email-enumeration protection. No live Firebase console settings were changed here.
4. Verify the deployed function runtime can read Auth user records as well as the existing Firestore, Storage and FCM resources using appropriate scoped permissions. No new service-account key should be bundled in the app.
5. Re-test real email links, resend cooldown, unknown-address reset feedback, disabled/revoked users, app restart/background expiry, shared-device sign-out and an uninterrupted resident trip. Verify native SDK token storage on the release devices; no custom credential store was introduced.

Local UI cooldowns, resume/idle behavior and backend authorization are covered by automated tests. Real email delivery, provider anti-abuse behavior, native token storage and end-to-end device behavior still require release verification.

## Deferred reminder

- [ ] Revisit **section 4.2: photo moderation** before resident release. The team explicitly deferred it while focusing on section 5.1. This checklist is a recorded reminder; no timed reminder notification is scheduled.

References: [Flutter password authentication](https://firebase.google.com/docs/auth/flutter/password-auth), [Firebase session management](https://firebase.google.com/docs/auth/admin/manage-sessions), [Firebase authentication limits](https://firebase.google.com/docs/auth/limits).

Verification results: **148 Flutter tests and 13 Firebase Auth/Firestore/Storage emulator integration tests passed**. Analysis reported no compile errors; lint warnings remain. The emulator tests use a demo project and do not send real email or change production users.
