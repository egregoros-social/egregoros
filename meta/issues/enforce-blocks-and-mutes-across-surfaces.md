# Enforce blocks and mutes across every surface

## Summary

Blocks and mutes are stored as `Relationship` rows and rendered in the API and
profile UI, but they are only *enforced* in three queries:
`Objects.list_home_notes/1`, `list_home_statuses/2`, and
`list_for_you_statuses/2`. Everywhere else they are ignored, and even where they
are enforced only the outgoing direction counts.

Confirmed by the conformance table in `Egregoros.ModerationCases` — each of
these is a recorded `:known_gap`, reproducible by removing the marker:

- **`Objects.visible_to?/2` ignores blocks entirely.** This is the widest gap:
  it is the shared visibility predicate with ~45 call sites, including the
  Mastodon status controllers, the streaming socket, and the timeline/status
  LiveViews. Anything that asks "may this viewer see this object?" ignores
  blocks. (It is *not* what serves `GET /objects/:uuid` — that uses
  `publicly_visible?/1`, which has no viewer and so no moderation dimension.)
- **The public timeline ignores blocks and mutes.** `list_public_statuses/1` has
  no moderation filter, so a blocked author appears in the public feed. Same for
  `list_public_statuses_by_hashtag/2`.
- **Notifications ignore blocks and mutes completely.**
  `Notifications.list_for_user/2` applies no moderation filter, so a blocked
  actor can still notify you by mentioning, liking, boosting, following, or
  reacting. Only the mention path is covered by the conformance table; the rest
  is established by inspection (there is no filter at all) rather than by test.
- **The incoming direction is never considered.** Every filter matches rows
  where the viewer is the blocking actor, so "the author blocks the viewer" has
  no effect on any surface. Home *appears* to handle it, but only because
  blocking severs the follow in both directions — there is no filter behind that,
  so it leaks the moment follow-severing changes.
- **`status_renderer` hardcodes `"muted" => false`**, so clients cannot show
  mute state even where it exists.

## Requirements

- Decide the semantics first and write them down, because they are not obvious:
  - Does a block hide content in both directions, as Mastodon does?
  - Does a blocked viewer get 404 or 403 on a direct fetch?
  - Does a mute hide from feeds and notifications while leaving direct fetch
    working? (The table currently assumes yes.)
- Apply the decided semantics uniformly rather than query by query. A shared
  predicate or policy function is preferable to repeating a subquery.
- Note that `Objects.list_public_statuses/1` takes no viewer at all, so making
  the public timeline viewer-aware means changing its signature and every
  caller — more than adding a filter.
- Remove each surface from the `:gaps` list in `Egregoros.ModerationCases` as it
  starts conforming.
- Make `status_renderer` report real mute state.

## Acceptance Criteria

- No `:gaps` entries remain for the four surfaces the table drives.
- The semantics are recorded (ideally an ADR) rather than only implied by code.
- Adding a surface does not require rediscovering the rules.

## Notes

- Found by [visibility-block-mute-truth-table](visibility-block-mute-truth-table.md);
  that table is the regression net for this work, so do it after the table
  covers the remaining surfaces if you want full coverage first.
- This is a moderation correctness issue with a privacy dimension: users
  reasonably assume a block stops the blocked account from reaching them, and
  today it does not stop notifications.
