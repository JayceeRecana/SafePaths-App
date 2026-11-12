# Local issue tracker

The user selected local Markdown for SafePaths issues, tasks and specifications. The GitHub remote remains a source repository; setup does not publish issues, labels or PRs there.

## Files

- One feature or effort per directory: `.scratch/<feature-slug>/`.
- Specification: `.scratch/<feature-slug>/spec.md`, starting from [the spec template](templates/spec.md).
- Tickets: `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, starting from [the issue template](templates/issue.md). Number from `01`; keep one file per ticket, including completed tickets.
- Use a feature-qualified ID, such as `report-retry/01`, when a bare number could be ambiguous.
- Comments and decisions append under `## Comments`; preserve earlier entries.

The tracker is ignored by Git and remains on this computer. The configuration and reusable templates under `docs/agents/` can be versioned. No sample task represents an actual app requirement.

## Ticket operations

- **Publish**: create a spec or ticket at the paths above. Publishing locally needs no external service.
- **Fetch**: read the referenced ticket and its linked spec, blockers and comments.
- **Triage**: set the `Status:` line using [the label mapping](triage-labels.md).
- **Start**: set `State: in-progress` and record the owner. Work starts when its blocking tickets are done.
- **Complete**: record acceptance results and validation evidence, then set `State: done`.
- **Block**: keep unresolved dependencies in `Blocked by:` using ticket IDs; `none` means no dependencies. A lack of information is `Status: needs-info`, with a concrete question in the comments.

`Status` is triage readiness; `State` is progress (`open`, `in-progress`, `done`). They are separate so completion never invents a sixth triage label. `ready-for-agent` means the brief is sufficiently specified; it does not grant deployment or external-write permission.

## Wayfinding operations

For `/wayfinder`, keep `.scratch/<effort>/map.md` with Notes, Decisions-so-far and Fog sections, plus one numbered child file per question. The Wayfinder child format is distinct from implementation tickets: `Type:` is `research`, `prototype`, `grilling` or `task`; its `Status:` lifecycle is `open`, `claimed`, `resolved`.

Read blockers before claiming a child. A child is unblocked when every listed blocker is resolved; the first numbered open, unclaimed child is the frontier. Save `Status: claimed` before work. On resolution, append `## Answer`, set `Status: resolved`, and add a gist plus link to Decisions-so-far in the map. These lifecycle words are not triage labels.

## Connected skills

`to-spec` writes the spec, `to-tickets` creates numbered implementation tickets, `triage` records readiness, `implement`/`implement-spec` read briefs and acceptance criteria, and `wayfinder` uses the map convention above. Use the project's glossary vocabulary in all of them. External issue/PR writes require an explicit task requesting them.
