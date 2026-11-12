# Domain documentation

SafePaths uses a single context: root `GLOSSARY.md`, application code under `lib/`, Android host under `android/`, and supporting backend code. These folders do not require separate glossaries.

## Before exploring

Read `GLOSSARY.md` for domain vocabulary, then relevant existing decisions in `docs/adr/` and the dated task-specific guides linked from `README.md`. If the ADR directory or a relevant decision does not exist, proceed; create an ADR only when a decision actually needs recording. Surface conflicts with existing decisions rather than silently overriding them.

## Writing

Use the glossary's terms in issue titles, specifications, hypotheses and test names. Keep glossary definitions short and free of field names, storage details and algorithms. Put source pointers and verification details in [the glossary source check](glossary-source-check.md).

Update terms when behavior or agreed vocabulary changes. If a requested term conflicts with the glossary, clarify its meaning before changing code or the definition. Keep report status, incident state, road passability, report confidence and predictive route/road scores distinct.

Record an ADR under `docs/adr/` only for an agreed, meaningful trade-off that is hard to reverse and surprising without context. Preserve existing dated guides; this setup introduces no architectural decision.
