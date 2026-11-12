# Local skill pack installation

Installed from the five ZIP archives in `C:\Users\cecil\Downloads` on 2026-11-12, exclusively for SafePaths. Archives were extracted with PowerShell under `_temp_skills`; originals are retained. Sources and file hashes are recorded in `.agents/local-packs-snapshot.json`. The seven previously installed skills remain intact.

## Compatibility and selected content

| Pack | Installed | Compatibility and requirements |
| --- | --- | --- |
| `skills-main.zip` (Matt Pocock) | 25 promoted engineering/productivity skills | General reasoning, review, diagnosis, domain modeling, planning, TDD and documentation workflows fit Dart/Kotlin/backend work. Local Markdown tracker configured; external CLIs are needed only if a future task selects their service. |
| `ponytail-main.zip` | `ponytail`, `ponytail-audit`, `ponytail-debt`, `ponytail-gain`, `ponytail-help`, `ponytail-review` | Language-independent Markdown workflows. The Claude-specific band, hooks, board, global defaults and Pi extension were not installed. No Node dependency is needed for the copied skill instructions. |
| `impeccable-main.zip` | Codex-generated `impeccable` skill, references and scripts | Includes native Android design guidance. Windows engine downloaded and checksum-verified by its launcher, cached under `.skill-tools/impeccable`. Native Flutter source requires manual interpretation: context detection did not recognize `lib/theme/app_theme.dart` as visual implementation. Web DOM/live tooling does not inspect Flutter widgets. No Rust/Bun build is needed to use the downloaded engine. |
| `diagram-design-main.zip` | `diagram-design`, templates, references, scripts and assets | Suitable for architecture and flow documentation without app dependencies. The local style guide was adapted to SafePaths colors and Manrope/Inter. HTML/SVG authoring works independently; PNG/render validation may additionally need Playwright/Chromium and Python libraries used by the chosen export script. Those optional render dependencies were not installed. |
| `graphify-8.zip` | Codex `graphify` skill and references; runtime version 0.9.107 | Python 3.14.3 satisfies the bundled requirement (>=3.10,<3.15). Runtime installed into `.skill-tools/graphify/venv` from retained local source. Dependencies include NetworkX, NumPy, RapidFuzz, PyYAML, tree-sitter and language grammars; optional SQL parser added for Supabase files. No system Python package installation or global agent registration was performed. |

Total: 34 additional skills; 41 including the original seven. Copied skill directories retain their supporting files, and upstream license/notices plus contributor instructions are retained under `.agents/pack-sources/` for provenance. Those contributor instructions govern upstream repositories, not this application.

## Explicit exclusions and adaptations

- `wizard` generates Bash-specific human provisioning flows and was excluded from this PowerShell-focused setup.
- `prototype` assumes HTML/web routes and was excluded as an app implementation workflow. It remains in the original ZIP if a standalone web demonstration is later wanted.
- Experimental/in-progress, misc and deprecated skills were not installed.
- Root `AGENTS.md` was extended, preserving all prior guidance. Upstream skill development, release, gallery and contributor rules were not pasted over SafePaths build rules.
- Planning skills use local `.scratch/<feature>/` tickets with canonical triage statuses. This is an initial local-only default, not a change to any external tracker. Domain docs use the root `GLOSSARY.md`; architecture decisions are created only when warranted.
- `DESIGN.md` is extracted from current Flutter source. No creative interview, redesign, UI implementation or device visual audit was performed. It preserves the incumbent identity requested by this setup task.
- Impeccable initialization reported missing product context and optional hook wiring. No global config or hooks were enabled. A PRODUCT.md interview and web-oriented automatic hooks are separate from documenting this existing Flutter UI.

## Graphify usage and limits

From the project root:

```powershell
& .\scripts\update-code-map.ps1
& .\.skill-tools\graphify\venv\Scripts\python.exe -m graphify query 'How are road risk and navigation connected?'
```

The rebuild script uses code-only extraction and `cluster-only --no-label`, with the LLM backend disabled. Initial clustering tried its default Claude labeling fallback; the CLI was not logged in, so it generated no model labels. Subsequent builds explicitly disable this fallback. Generic community names are expected.

Outputs: `graphify-out/graph.json`, `graphify-out/GRAPH_REPORT.md`, and `graphify-out/graph.html`. The HTML aggregates communities when the graph exceeds 5,000 nodes; full node-level detail remains in JSON. `.graphifyignore` excludes downloaded packs, runtime tools, generated caches, credentials/configuration with secrets, assets, and the non-Android platform hosts. These tools do not modify application dependencies or deploy services.

The bundled Dart extractor is regex-based. Kotlin/Java extraction uses tree-sitter, but the three Gradle Kotlin scripts yielded no symbols. Android XML manifests/resources are unsupported by this build and were reviewed directly during setup. Some SQL policy/bucket scripts likewise yield no symbols. A code map is an orientation aid, not proof of build correctness, complete dependency coverage, security, or runtime behavior.

## Local files and verification

- `DESIGN.md`: source-derived theme and component conventions.
- `GLOSSARY.md`: existing road/report/incident/navigation vocabulary.
- `docs/agents/domain.md`, `issue-tracker.md`, `triage-labels.md`: engineering workflow configuration.
- `.agents/local-packs-snapshot.json`: archive hashes, selected skill paths and installed file hashes, including the customized diagram style guide.
- `.skill-tools/graphify/requirements-lock.txt`: captured local Python package versions for this Windows/Python environment.
- `.gitignore`: ignores `_temp_skills/`, `.skill-tools/`, `graphify-out/`, and `.scratch/`.

Installation validation checks skill metadata, referenced supporting files, preservation of existing skill hashes, code-map outputs and a real graph query. App tests/builds are not required for a skill/documentation-only installation; no Flutter, Gradle, Kotlin or Java application source was changed.

Final code-map extraction covered 439 code files and produced 5,681 nodes and 9,476 edges in 234 communities. All 41 skill entrypoints parsed successfully; entrypoint supporting links resolved (the example `[title](link)` in Wayfinder is a placeholder, not a missing file). The original seven skills matched every hash in their prior snapshot.
