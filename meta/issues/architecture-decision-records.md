# Start architecture decision records

## Summary

Architecture intent is currently spread across implementation, audits, task
lists, and conventions. Decisions get revisited without their original
constraints being visible, which is how hard-to-reverse choices get quietly
undone.

## Requirements

- Add a short ADR format: context, decision, alternatives, consequences,
  revisit trigger.
- Write the first ADRs for the hard-to-reverse choices already in play:
  durable effects, policy layers, canonical storage model, delivery identity,
  and the supported deployment envelope.
- Default the deployment envelope to single-node production unless a current
  operator requirement justifies paying clustering's design and test cost now.
- Add a risk-triggered PR prompt covering transaction boundary, replay
  identity, policy surface, query shape, and telemetry.

## Acceptance Criteria

- ADRs live in the repository under a stable path and are linked from
  `docs/README.md`.
- The deployment-envelope ADR states explicitly what is and is not supported.
- A costly or hard-to-reverse change can be traced to a recorded decision.

## Notes

- Deliberately lightweight: one architecture maintainer or per-milestone
  responsible individual, asynchronous review at milestone boundaries. Not an
  approval board.
- The deployment-envelope decision gates later cluster-semantics work; making
  it early avoids paying for clustering by accident.
