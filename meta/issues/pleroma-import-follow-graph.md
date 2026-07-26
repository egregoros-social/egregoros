# Import the follow graph from Pleroma

## Summary

`Egregoros.PleromaMigration` exposes `import_users/1` and `import_statuses/1`
only. Nothing imports follows: there is no reference to `relationships`,
`following_relationships`, or Follow activities anywhere in the importer, its
source module, or the `egregoros.import_pleroma` mix task.

`docs/pleroma-migration.md` section 3.1 lists preserving the follow graph as a
minimum-viable goal. Without it, a cutover lands every migrated user on an
instance where they follow nobody and nobody follows them, which is the most
visible possible regression.

## Requirements

- Read the follow graph from Pleroma. Prefer `following_relationships` (which
  carries accepted/pending state) over reconstructing from Follow activities.
- Insert into `relationships` with `type` `"Follow"` for accepted and
  `"FollowRequest"` for pending, `actor` = follower AP ID, `object` =
  followed AP ID, and a non-null `activity_ap_id`.
- Import the remote users the graph references, so edges do not dangle.
- Preserve source timestamps, following the pattern `import_statuses/1`
  already uses (`inserted_at`/`updated_at` threaded per row, coerced to
  `utc_datetime_usec`).
- Suppress live effects: no Follow/Accept delivery, no notifications. This is
  the offline import path.
- Be idempotent and resumable, like the existing importers.

## Acceptance Criteria

- Importing a fixture graph produces the expected `relationships` rows,
  including the pending/accepted distinction.
- Re-running the import produces no duplicates and no errors.
- No federation delivery or notification side effects fire during import,
  asserted by a test.
- Follower and following counts on a migrated user match the source.

## Notes

- Testable against fixtures without a live Pleroma database: the source query
  and the insert can be covered separately.
- Explicitly out of scope, and fine to defer past a first cutover: likes,
  boosts, emoji reactions, bookmarks, markers, and scheduled posts (section
  5.2 of the migration doc). Users notice a missing follow graph immediately
  and a missing bookmark eventually.
- Related: [pleroma-migration-rehearsal](pleroma-migration-rehearsal.md).
