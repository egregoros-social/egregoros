# Extend the moderation table to streaming, LiveView, and delivery

## Summary

`Egregoros.ModerationCases` drives four surfaces: direct fetch, public timeline,
home timeline, and notifications. Three of the surfaces the truth-table issue
listed are not yet covered:

- **`:streaming`** — the PubSub fan-out in `Egregoros.Timeline` and the
  Mastodon streaming socket.
- **`:liveview_refresh`** — timeline LiveViews re-reading after an event, which
  can apply different filtering than the initial load.
- **`:delivery`** — outbound recipient selection, which currently has no
  moderation filter at all.

Until they are in the table they can drift from the other four, which is exactly
the failure mode the table exists to prevent. Streaming and LiveView partly
inherit `Objects.visible_to?/2`, which the table does cover as
`:object_visibility`, but neither is asserted end to end.

A second axis is missing too: notifications are only covered for *mentions*. The
Follow/Like/Announce/EmojiReact/Offer notification predicates have no case,
because the table has no notification-type dimension.

## Requirements

- Add a probe per surface to the conformance test, following the existing
  `observe/3` pattern.
- Add the surfaces to `ModerationCases.surfaces/0`.
- Record whatever each surface does today as `:gaps` where it diverges, rather
  than fixing behavior in the same change.
- Extend the case list where a surface needs cases the others do not (streaming
  in particular has a subscription dimension: does a mute applied *after*
  subscribing take effect?).

## Acceptance Criteria

- All seven surfaces from the original issue are driven by the shared table.
- `ModerationCases.uncovered_surfaces/0` returns `[]`.
- Notification cases cover each notification type, not just mentions.
- Each surface's current behavior is recorded, conforming or gap.
- The "not yet covered" section of the `ModerationCases` moduledoc is empty.

## Notes

- Streaming and LiveView need heavier fixtures than the current four surfaces,
  which is why they were deferred.
- Delivery is the one where a gap is least obviously a bug: whether a block
  should suppress outbound federation to that instance is a policy question, not
  just an implementation gap. Decide it in
  [enforce-blocks-and-mutes-across-surfaces](enforce-blocks-and-mutes-across-surfaces.md).
