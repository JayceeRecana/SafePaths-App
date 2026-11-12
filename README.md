# SafePaths

Flutter capstone app for road conditions, flood reporting and navigation. Both versions share the application source and use separate Firebase projects, road data and private backend records.

## Current APKs

Open [releases/](releases/README.md) for the two current installers:

| Version | Installer | Public build settings |
| --- | --- | --- |
| Nearby test area - SafePaths Test | [Test APK 1.0.5](releases/SafePaths-Test-20261103-v1.0.5.apk) | [config/build/fieldtest.json](config/build/fieldtest.json) |
| Marulas capstone - SafePaths | [Marulas APK 1.0.9](releases/SafePaths-Marulas-20261110-v1.0.9.apk) | [config/build/marulas.json](config/build/marulas.json) |

The Marulas candidate backend was activated on November 2, 2026. Follow-up evidence reports are enabled in that candidate; they remain disabled in the nearby test configuration. Email verification may be required when signing in. Real-device acceptance, approved destination pins and the existing privacy/retention decisions remain open. See the [Marulas rollout record](docs/marulas-main-integration.md).

The Marulas APK was rebuilt on November 10 with the current reporting interface and interaction corrections. The nearby test installer remains the November 3 build and predates those later changes. See the [interaction review and resolution](docs/user-admin-interaction-review-20261104.md).

Older installer files are retained. [Installer hashes](releases/manifest.json) identify the current files.

## Project layout

| Folder | Purpose |
| --- | --- |
| `lib/` | Flutter app screens, widgets, behavior, models and translations |
| `assets/` | App logo, fonts and bundled map/awareness assets |
| `config/build/` | Public main/test build settings; no server credentials |
| `test/` | Flutter automated checks and their fixtures |
| `supabase/`, `functions/` | Backend source, rules integration, server tests and maintenance tools |
| `scripts/` | Development, localization and data-preparation tools |
| `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/` | Platform projects |
| `docs/` | Technical notes, design decisions and manual testing guides |
| `releases/` | The two current phone/emulator installers |
| `.usability-work-baseline/` | Retained local evidence, checkpoints, older APKs, tool dependencies and private setup/backups |

Keep the root Flutter/Firebase configuration, dependency lockfile, indexes and security rules in place. JSON files under the app, backend and test folders are functional project files.

The design reference is [app_theme.dart](lib/theme/app_theme.dart), [app_palette.dart](lib/theme/app_palette.dart) and [app_colors.dart](lib/theme/app_colors.dart): Manrope headings, Inter body text, blue actions, rounded cards and theme-aware status colors.

## Run from your IDE or PowerShell

Run one debug session at a time, from the project folder. Replace `emulator-5554` if `flutter devices` shows a different device ID.

Nearby test area:

```powershell
& 'C:\flutter\bin\flutter.bat' run --no-pub -d emulator-5554 --flavor fieldtest --dart-define-from-file=config/build/fieldtest.json
```

Marulas:

```powershell
& 'C:\flutter\bin\flutter.bat' run --no-pub -d emulator-5554 --flavor production --dart-define-from-file=config/build/marulas.json
```

VS Code has matching **SafePaths Test - Live UI** and **SafePaths Marulas - Live UI** launch choices. Press `r` for hot reload in a Flutter terminal or capital `R` for a hot restart. See [live UI preview](docs/live-ui-preview.md) for switching between release APKs and debug previews.

Generated build caches were cleared on November 4, 2026. Dependencies were restored so the run commands can still use `--no-pub`; the first rebuild will take longer.

## Local files and history

Old root-level analysis, test, emulator and build logs are grouped under `.usability-work-baseline/workspace-cleanup-20261104/archived-root-logs/`. The accompanying cleanup manifest records their original locations. Existing evidence/tool paths inside the baseline were retained.

`.env`, `.env.fieldtest`, server backups and private setup/account files stay local and ignored by Git. Share only the intended APK, not the entire workspace or testing archive. Generated caches, dependencies and retained local evidence are hidden from VS Code Explorer/search; [settings](.vscode/settings.json) controls those filters.

## Guides

| Task | Guide |
| --- | --- |
| Marulas configuration and acceptance | [Main rollout](docs/marulas-main-integration.md) |
| Reporting and private messages | [Admin/resident workflow](docs/admin-resident-workflow.md) |
| Notification behavior | [Admin report notifications](docs/admin-report-notifications.md) |
| Resident/admin device test | [Manual communication sequence](docs/communication-phone-test-sequence.md) |
| Follow-up reports and rewards | [Reporting reliability](docs/report-reliability-5.2.md) |
| Navigation and rerouting | [Refinements](docs/navigation-refinements-20261026.md), [scenario checklist](docs/rerouting-scenario-acceptance.md) |
| NOAH awareness data | [NOAH integration](docs/noah-flood-awareness.md) |
| Privacy decisions | [Privacy and consent](docs/privacy-consent-5.6.md) |
| Original expert-review tracking | [Expert review](docs/it-expert-review.md) |

Technical documents include dated checkpoints. Read their date and scope before using an older test count, feature flag or APK name as current status.
