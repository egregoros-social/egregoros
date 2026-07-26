# Keep caching behind behaviour boundaries

## Summary

Caching should stay swappable (ETS today, something like Redis later) without
a rewrite. Today's caches are reached directly in places, and cluster-versus-
node-local semantics are not stated anywhere.

## Requirements

- Put cache access behind a behaviour so backends can be replaced.
- Document, per cache, whether guarantees are node-local or cluster-wide.
- Give lazily created facilities (for example the DNS cache) stable
  supervised ownership.
- Do not add a general-purpose cache layer before ownership, invalidation,
  and cluster semantics are defined.

## Acceptance Criteria

- Cache backends are selected through configuration, with the existing ETS
  implementation as the default.
- Tests can substitute an in-memory or mock backend.
- Each cache's scope is documented.

## Notes

- Carried over from the old `tasks.md` backlog.
- Do not rewrite already-supervised ETS facilities without a concrete issue.
- Depends on the deployment-envelope decision in
  [architecture-decision-records](architecture-decision-records.md).
