# Make ingestion transactional with replay-safe effect intent

## Summary

`Pipeline.ingest_with/3` persists and then immediately executes effects:
`module.ingest/2` followed by `module.side_effects/2`. Duplicate AP objects
are storage-idempotent, but notifications, PubSub broadcasts, relationship
mutations, and delivery are not uniformly idempotent, and a crash between
persist and effect leaves state that no retry reconciles.

## Requirements

- Have activity handlers return an ingestion plan: canonical mutations,
  derived-state mutations, and effect intents.
- Apply the plan with `Ecto.Multi` in one transaction.
- Persist durable effect intent in the same transaction (an outbox table, or
  uniquely identified Oban jobs where that gives equivalent durability and
  auditability).
- Identify effects by activity AP ID, effect kind, target, and payload
  version.
- Return an explicit outcome: `:inserted`, `:existing`, or `:updated`. Skip
  effect planning only when a processing-version or completion marker proves
  the projections and intents already exist; otherwise reconcile idempotently
  under unique constraints.
- Move PubSub, outbound HTTP delivery, and other non-read effects after
  commit. Keep bounded input acquisition and validation reads before commit,
  with SSRF and timeout controls.

## Acceptance Criteria

- At every injected crash point, retry produces one canonical result and one
  durable local intent per identity.
- No subscriber observes state that later rolls back.
- Dispatch is documented as at-least-once: remote servers and PubSub
  consumers may observe a repeat, and dedupe by stable AP identity.

## Notes

- Migrate one type at a time — start with Create/Note, Follow, Like,
  Announce — keeping `Pipeline.ingest/2` stable behind the change. Do not
  cut the whole pipeline over at once.
- Needs a backfill/cutover story for pre-outbox rows and already-queued jobs,
  so an existing object with missing effects is not mistaken for completed
  work.
- Blocked by [ingress-behavior-matrix](ingress-behavior-matrix.md).
- Effort is large and the risk is the highest in the backlog; it should get a
  named owner.
