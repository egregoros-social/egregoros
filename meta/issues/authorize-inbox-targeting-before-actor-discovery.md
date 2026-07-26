# Authorize inbox targeting before enqueueing actor discovery

## Summary

`Egregoros.Pipeline.ingest_with/3` runs `discover_actors/2` (which calls
`ActorDiscovery.enqueue/2`) *before* `module.ingest/2`. Inbox-targeting
rejection lives inside `ingest/2` — `validate_inbox_target/2` in
`activities/follow.ex`, `accept.ex`, `delete.ex`, `undo.ex`, `reject.ex`,
`move.ex`. So an activity that will be rejected as untargeted has already
enqueued actor, recipient and mention fetches by the time it is rejected.

That makes an unauthenticated inbox POST a remote-fetch amplifier: the
attacker chooses the actor URIs we go fetch, and the rejection does not
undo the queued work.

## Requirements

- Run a type-specific targeting/authorization check before
  `ActorDiscovery.enqueue/2`.
- An activity rejected as untargeted must enqueue no discovery work of any
  kind (actor, recipient, or mention fetches).
- Keep the public `Pipeline.ingest/2` contract unchanged.
- Preserve current behavior for activities that *are* targeted, including
  types with no targeting check.

## Acceptance Criteria

- A test POSTs an untargeted Follow (and Accept/Delete/Undo) to an inbox and
  asserts zero `ActorDiscovery` jobs were enqueued.
- A test asserts a targeted activity still enqueues discovery as before.
- Existing pipeline and activity tests pass unchanged.

## Notes

- This is the first concrete step of the "Now" architecture milestone: it
  pulls a policy decision out of `ingest/2` into a pre-persistence step,
  which is the shape the transactional ingestion plan needs.
- Related: [ingestion-error-taxonomy](ingestion-error-taxonomy.md),
  [transactional-ingestion-and-effect-intent](transactional-ingestion-and-effect-intent.md).
