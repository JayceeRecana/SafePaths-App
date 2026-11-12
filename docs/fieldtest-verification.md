# SafePaths Test verification — 2026-10-19

Automated checks completed:

- Existing 76 routing tests plus the first 7 configuration tests: **83 passed**, production flavor.
- Final full suite including the missing-GPS regression: **84 passed**, fieldtest flavor.
- Final configuration/GPS/import/geometry/log suite: **8 passed**, production flavor.
- Full static analysis: **no errors**, 86 warnings/informational findings remain across the repository.
- Test Firestore rules and indexes successfully deployed with explicit target `safepaths-test`.
- Clear override created in `safepaths-test/system/weather`; no production weather write was performed.
- Fieldtest APK manifest: `com.safepaths.safepaths_app.test`, label **SafePaths Test**.
- Fieldtest APK native Firebase resources identify **safepaths-test**.
- APK asset inspection: fieldtest contains `.env.fieldtest` only, with the expected project and no Supabase/FCM/private-key environment entries.
- Both final release APKs built successfully, including the missing-GPS safeguard.
- Production APK inspection confirms its original `com.safepaths.safepaths_app` ID, **SafePaths** label, `safepaths-92c3d` Firebase resources, and production-only `.env` asset.

Final test APK SHA-256:

```text
9BAD03ACC36200BEE56236DCFCABF652E1E9DB17106E3FFD1F6D15D12AF1376A
```

The tests exercise closure warnings/recalculation while walking in both Walking and Sedan modes, closure arrival before GPS, a second closure during cooldown, sustained off-route detection, ignored short deviations/poor GPS, blocked-route rejection, reopening, failure backoff/recovery, request timeout, and screen disposal during a request.

No Android device was connected. The user will install manually. Accounts/admin assignment, road-network import and preview, selection of three locally accessible paths, phone GPS/speech, live cross-phone updates, and outdoor scenarios remain unverified. Automated tests use controlled positions and routing responses; they do not prove live Mapbox availability or a particular local detour.

Follow [the setup and two-phone script](fieldtest-setup.md). Retain the diagnostic session logs and visible observations before declaring the field test accepted. Marulas still needs its own final network check.
