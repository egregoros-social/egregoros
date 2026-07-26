# Rehearse the Pleroma migration end to end

## Summary

The migration plan, the importer, and the compatibility shims
(`/media/*` serving, `/activities/:uuid`, pbkdf2 verification, flake IDs) have
never been exercised together against a real Pleroma dump. Section 7 of
`docs/pleroma-migration.md` lists risks that can only be settled by running it.

Most of the harness already exists: `docker/federation/` runs Egregoros,
Pleroma and Mastodon with a test runner.

## Requirements

- Restore a small real Pleroma dump into the Pleroma container.
- Scan the source read-only first: count rows by `activities.data->>'type'`
  and `objects.data->>'type'`, and list unhandled types. This replaces the
  "prototype a DB scanner" step and tells us what the importer is silently
  skipping.
- Run the importer against it into a fresh Egregoros database.
- Run the existing fedbox smoke tests against the imported instance: follow,
  receive a post, reply, like, boost, delete.
- Verify by hand: login for a migrated user, actor and object URLs resolve,
  `/media/...` resolves for a historical attachment, and timeline ordering
  looks right.
- Record what broke and what the import silently dropped.

## Acceptance Criteria

- A documented rehearsal run: what was imported, what was skipped, what
  failed.
- The unhandled-type list exists and each entry is either handled or
  consciously accepted.
- Findings become their own issues rather than staying in a report.

## Notes

- This is what turns section 7's "risks / unknowns" into either checkmarks or
  bugs, and it is where the unpredicted schema mismatches will surface.
- Blocked in practice by
  [pleroma-import-follow-graph](pleroma-import-follow-graph.md): rehearsing an
  import that cannot carry follows would not tell us much.
- The importer does not copy Pleroma's local media uploads or rewrite historic
  attachment URLs; `/media/*` serving expects `:pleroma_media_dir` to point at
  the existing uploads directory. Confirm that during the rehearsal.
