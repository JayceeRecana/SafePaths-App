# Current SafePaths installers

| APK | Use |
| --- | --- |
| [SafePaths Test 1.0.5](SafePaths-Test-20261103-v1.0.5.apk) | Nearby test area, test accounts/backend. Follow-up evidence reports remain disabled. |
| [SafePaths Marulas 1.0.9](SafePaths-Marulas-20261110-v1.0.9.apk) | Groupmates testing actual Marulas roads and the main backend. Follow-ups are enabled for controlled acceptance. |

Both are universal Android APKs for a phone or emulator. Install the correct version and use that environment's accounts. Complete email verification if prompted. Native device acceptance is still in progress.

The Marulas APK was rebuilt on November 10, 2026 with the consolidated reporting refinements: Android-safe header placement, evidence hierarchy and reporter avatar, environment-specific protected photos/avatars, explanatory reply/notification states, and clearer road-check reminders. It uses version code 9 and the same signing certificate as the earlier Marulas APKs. Install over an existing SafePaths installation; no uninstall is required when sufficient storage is available. The nearby test APK remains the November 3 build. SHA256 values are in [manifest.json](manifest.json); older files remain on disk.

Marulas build command: `flutter build apk --release --no-pub --flavor production --dart-define-from-file=config/build/marulas.json --build-name=1.0.9 --build-number=9`.

Validation: the consolidated 184-case Marulas reporting regression suite, 42 selected test-build compatibility checks, and 48 local backend workflow/media checks passed. Subsequent road-reminder and reporter-avatar changes passed their focused regression suites and light/dark preview checks. APK version/package, signature, archive integrity, universal ABIs, production-only environment asset, bundled NOAH GeoJSON and changed compiled code versus 1.0.8 were verified. Installed and launched Marulas 1.0.9 successfully on emulator-5554; Android displayed its permission prompt. Real-device reporting/photo/map and notification acceptance remain open.

Share only the intended APK. Keep local credentials, private backups and test-account files private. Use a new dated filename and an appropriate version code for future builds.
