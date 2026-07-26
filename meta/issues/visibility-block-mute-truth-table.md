# Build one cross-surface visibility/block/mute truth table

## Summary

ActivityPub audience visibility is centralized, but blocks, mutes,
notification eligibility, stream eligibility, and federation moderation do
not share one contract. Each surface (timeline, direct fetch, notification,
LiveView refresh, streaming, delivery) can drift independently, which is how
privacy leaks appear.

## Requirements

- Express visibility, block (both directions), and mute semantics as a single
  truth table of cases.
- Drive every surface's tests from that table: timelines, direct object
  fetch, notifications, LiveView refresh, streaming, and outbound delivery.
- Where SQL and in-memory implementations both exist, test both adapters
  against the same table rather than forcing one implementation.

## Acceptance Criteria

- One shared set of cases is consumed by all listed surfaces' test suites.
- Adding a moderation case requires editing the table, not rediscovering
  every surface.
- Any surface that cannot yet satisfy a case is explicitly marked, not
  silently omitted.

## Notes

- Replaces the old open task "continuous audit for privacy leaks (public
  timelines, streaming, media access, DM visibility)", which was too vague to
  act on.
- Precursor to the explicit access/subscription policy layers.

## Progress

The table exists as `Egregoros.ModerationCases`, driven by
`test/egregoros/moderation_conformance_test.exs`. It covers four of the seven
surfaces this issue listed: object visibility (`visible_to?/2`), public timeline,
home timeline, and notifications. `ModerationCases.uncovered_surfaces/0` names
the rest in code, not just prose.

Remaining before this can close:

- streaming, LiveView refresh, and delivery — see
  [extend-moderation-table-to-remaining-surfaces](extend-moderation-table-to-remaining-surfaces.md)

What the table already surfaced is filed as
[enforce-blocks-and-mutes-across-surfaces](enforce-blocks-and-mutes-across-surfaces.md):
blocks and mutes are enforced in only three home-ish queries, direct fetch and
notifications ignore them entirely, and the incoming direction of a block is
ignored everywhere.
