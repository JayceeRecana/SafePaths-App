# SafePaths agent skills

Seven upstream skills were installed at project scope on 2026-11-12 using the built-in skill installer's GitHub download/Git workflows. The skill directories retain upstream content; SafePaths-specific adjustments live in the root `AGENTS.md`.

| Repository | Selected paths (requested ref: main) |
| --- | --- |
| https://github.com/flutter/agent-plugins | `skills/flutter-add-widget-test`, `skills/flutter-fix-layout-issues`, `skills/flutter-add-integration-test` |
| https://github.com/mapbox/mapbox-agent-skills | `skills/mapbox-flutter-patterns` |
| https://github.com/firebase/agent-skills | `skills/firestore-rules-creation` |
| https://github.com/supabase/agent-skills | `skills/supabase-postgres-best-practices` |
| https://github.com/dart-lang/skills | `skills/dart-add-unit-test` |

`skills-snapshot.json` records SHA-256 hashes of the installed files for local integrity checking. This is a content snapshot, not an upstream commit pin. Review upstream changes before updating; preserve the project adjustments in `AGENTS.md`.

Skills will be available for discovery on the next turn. They provide workflow instructions, not MCP servers, SDK installations, credentials, or backend deployments. Runtime tooling must be connected separately when required by a task.

## Additional ZIP packs

The five local ZIP packs added 34 skills on 2026-11-12, for 41 total. See `../docs/agents/skill-packs.md` for compatibility, exclusions and runtime setup, and `local-packs-snapshot.json` for archive and installed-file hashes. The original seven-skill snapshot above is retained unchanged.
