# Make ingress behavior executable as a parity matrix

## Summary

The unified pipeline is easy to trace, but source and activity-type behavior
is not captured in one suite. Duplicate and partial-failure semantics are
especially under-specified: they exist as prose and as scattered tests, not
as an executable matrix.

## Requirements

- Start with high-risk families: Create/Note, Follow/Accept/Undo, and
  interactions (Like/Announce/EmojiReact). Expand incrementally rather than
  covering everything at once.
- For each family, cover the sources: local authoring, inbox delivery,
  on-demand fetch, retry, and the explicit offline bulk-import exception.
- Assert normalization, validation, targeting, persistence, relationship
  changes, notification, streaming eligibility, and federation eligibility.
- Add failure injection at the current seams: after object insert, after
  relationship mutation, after PubSub broadcast, and after Oban insertion.
- Add duplicate-ingestion tests per effect-producing family, then factor the
  duplicate contract so remaining types can reuse it.

## Acceptance Criteria

- Covered families have explicit, asserted persistence, failure, and effect
  outcomes in one place.
- The duplicate-ingestion contract is reusable by a type not yet covered.
- Failure injection points exist and are exercised.

## Notes

- This is the prerequisite for
  [transactional-ingestion-and-effect-intent](transactional-ingestion-and-effect-intent.md):
  that issue's success signal is these tests passing. Do not start the
  transactional rewrite before this exists.
