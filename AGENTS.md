# SafePaths project guidance

## Project context

- Read `README.md` for current setup and the task-specific guide it links. Check dates before treating an older document as current behavior.
- Preserve the existing Flutter architecture, theme, localization conventions, and resident/admin workflows. Make focused changes and retain unrelated work already in the workspace.
- Keep production/Marulas and fieldtest configuration separate. Use `config/build/marulas.json` with `--flavor production`, and `config/build/fieldtest.json` with `--flavor fieldtest`.
- Keep local environment files, credentials, private backups, and retained testing evidence out of commits and shared artifacts.

## Installed skills

Load the relevant `SKILL.md` from `.agents/skills/` when the task matches:

| Task | Skill |
| --- | --- |
| Widget behavior and interactions | `flutter-add-widget-test` |
| Overflow and constraint failures | `flutter-fix-layout-issues` |
| Device integration tests | `flutter-add-integration-test` |
| Map widgets, annotations, camera and location | `mapbox-flutter-patterns` |
| Firestore access rules | `firestore-rules-creation` |
| SQL, schemas, indexes, migrations and RLS | `supabase-postgres-best-practices` |
| Dart business logic regressions | `dart-add-unit-test` |

Apply these project-specific adjustments to generic skill examples:

- Preserve the installed package versions and environment/token setup; examples are not instructions to downgrade dependencies or replace build configuration.
- Prefer the existing `flutter_test` imports and test helpers. Add dependencies only when a task actually requires them.
- Use modern `integration_test` bindings for new integration tests. If Flutter Driver extensions are needed for a particular tool, isolate them in a dedicated test entry point; keep them out of production startup.
- MCP tool names in skills are conditional on tools actually being available. Use Flutter CLI tests and logs as a fallback, and report runtime/UI checks that could not be performed.
- Use bounded pumping for persistent animations, maps, and asynchronous streams rather than assuming `pumpAndSettle` always terminates.
- Preserve documented resident/admin authorization requirements. Verify Firestore rules with emulator tests, including denied operations and the queries the app uses; mental review alone is not test evidence.

## Verification

- Local Windows SDK commands: `C:\flutter\bin\flutter.bat` and `C:\flutter\bin\dart.bat`.
- For Dart changes, check formatting on changed files and run Flutter analysis and relevant tests. Start with targeted regression tests and broaden when shared behavior changes.
- Commands from the project root: `& 'C:\flutter\bin\dart.bat' format --output=none --set-exit-if-changed <changed-files>`, `& 'C:\flutter\bin\flutter.bat' analyze --no-pub`, and `& 'C:\flutter\bin\flutter.bat' test --no-pub <test-path>`.
- Backend tests: `npm.cmd --prefix functions test`. Rules/emulator checks use `npm.cmd --prefix functions run test:emulator` with the configured local emulators running; inspect the relevant test prerequisites first.
- Run one Flutter debug session at a time. Preserve flavor and dart-define arguments from `README.md` for device runs and builds.
- Report what changed, checks actually run, and any remaining limitations. Installing skills alone does not validate app behavior or authorize backend deployment.

## Additional local skill packs

- These packs apply only to this repository. Existing guidance above remains in force; upstream pack contributor/release instructions do not become SafePaths build rules.
- Use Ponytail's smallest complete change: reuse existing helpers, inspect affected callers, and retain validation, error handling, security and accessibility. Concision must not remove required behavior or checks.
- Read `DESIGN.md` before UI changes. The UI is Flutter Material 3 in `lib/`; `android/app/src/main/kotlin/.../MainActivity.kt` is a Flutter host, not a Compose app. Keep the current visual identity unless redesign is explicitly requested.
- Impeccable's design references apply to Flutter UI by analogy. Its web DOM/live tools and automatic platform detection do not validate a Flutter surface. Use Flutter tests and actual Android captures for verification. Its engine cache is project-local: set `IMPECCABLE_HOME` to `.skill-tools/impeccable` before invoking its Windows launcher.
- Diagram Design uses the SafePaths-customized local style guide under `.agents/skills/diagram-design/references/style-guide.md`. Keep profile changes local; do not initialize a global profile library for this project.
- Read `GLOSSARY.md` for domain vocabulary and `docs/agents/domain.md` for documentation conventions. Follow language-independent engineering skills without introducing TypeScript, web routes or Bash tooling into the app.
- Planning/ticket skills use local Markdown under `.scratch/<feature>/` as the initial tracker for this local-only setup. See `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`. External issue/PR writes require an explicit task requesting them.
- The Graphify interpreter is `.skill-tools/graphify/venv/Scripts/python.exe`. Use `scripts/update-code-map.ps1` to rebuild the local code-only map and query it with that interpreter's `-m graphify query` command. Keep `.graphifyignore` exclusions in effect. Do not invoke skill examples that install a global runtime.
- Treat the graph as a navigation aid, verify claims against source, and refresh it after structural changes. Dart extraction in this bundled version is regex-based; do not assume compiler-level call-graph precision. A missing/stale graph must not block direct source inspection.
- Installation scope, skipped tools, dependencies and checks are recorded in `docs/agents/skill-packs.md` and `.agents/local-packs-snapshot.json`.

## Agent skills

### Issue tracker

Issues, tasks and specs use local Markdown in `.scratch/<feature>/`, with one file per ticket. Read `docs/agents/issue-tracker.md` before creating, triaging or implementing tickets.

### Triage labels

Keep the five canonical labels confirmed by the user: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. Read `docs/agents/triage-labels.md` when assigning status.

### Domain docs

Use a single root `GLOSSARY.md` and `docs/adr/` for decisions created when needed. Before exploring a domain area, read the glossary and relevant existing decisions according to `docs/agents/domain.md`.
