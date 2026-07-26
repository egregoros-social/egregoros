# Remove the N+1 actor lookup in the messages view

## Summary

`EgregorosWeb.MessagesLive` builds conversation cards by calling
`Actor.card/1` once per peer, so opening `/messages` issues one query per
conversation in the list.

## Requirements

- Batch the lookups with `Actor.cards_by_ap_id/1` (or equivalent) instead of
  per-peer calls.
- Cover the conversation list, the selected thread, and the paths that
  refresh the list after sending or receiving a DM.

## Acceptance Criteria

- Rendering the conversation list issues a bounded number of queries,
  independent of the number of conversations, asserted by a query-count test.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`.
- Fits the broader "prepared render contexts perform no hidden queries"
  direction, so it is worth doing in that style.
