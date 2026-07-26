# Define an ingestion error taxonomy with explicit Oban outcomes

## Summary

Ingestion errors are returned as bare atoms with no documented contract for
how `Egregoros.Workers.IngestActivity` should treat them. Whether a given
failure discards, retries, or counts as success is currently implicit.

## Requirements

- Define three classes: permanent rejection, transient retryable failure,
  and duplicate/no-op.
- Map every error currently returned from the pipeline and activity modules
  into one of those classes.
- Assert how `IngestActivity` maps each class to discard, retry, or success.
- Make the mapping total: an unrecognized error must have a defined default
  (prefer discard with a logged reason over infinite retry).

## Acceptance Criteria

- A test asserts the worker outcome for at least one error of each class.
- No pipeline error path reaches the worker without a defined outcome.
- Telemetry or logs distinguish reject, retry, and terminal failure.

## Notes

- Pairs with
  [authorize-inbox-targeting-before-actor-discovery](authorize-inbox-targeting-before-actor-discovery.md).

- **Correction, found while implementing.** This issue asserted that
  `:not_targeted` "is the clearest example of a permanent rejection that should
  never retry". That is true for `Follow` (a pure comparison) but wrong for
  `Undo`: its authorization depends on us already holding the activity being
  undone, and `federation_incoming` runs at concurrency 10, so an Undo can be
  processed before the Like it undoes. Discarding it left the Like applied
  forever. `Undo` now returns a distinct `:target_unknown`, classified transient.
  Same reasoning applies to `:question_not_found`.
