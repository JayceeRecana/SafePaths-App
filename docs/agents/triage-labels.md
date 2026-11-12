# Local triage vocabulary

The user confirmed the defaults during setup. Use the same string for each canonical role in a local ticket's `Status:` line; no remote labels were created.

| Canonical role | Local status | Meaning |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | Needs evaluation. |
| `needs-info` | `needs-info` | Needs more information before a useful brief can be completed. |
| `ready-for-agent` | `ready-for-agent` | Specified and ready for agent implementation. |
| `ready-for-human` | `ready-for-human` | Requires human implementation or action. |
| `wontfix` | `wontfix` | Intentionally will not be actioned. |

Ticket progress uses a separate `State:` line, as defined in `issue-tracker.md`. Wayfinder children have their own lifecycle and do not redefine these triage roles.
