# Check in operational and query baselines

## Summary

Static reading identifies expensive query shapes but cannot rank real
bottlenecks. Without a baseline, a latency regression cannot be attributed to
query shape versus fanout, render, queue, or remote-network behavior.

## Requirements

- Extend the existing query budgets (`perf/`) to status lists, notifications,
  threads, conversations, and streams.
- Measure and record: pipeline duration, duplicate rate, effects and jobs per
  activity, resolved inboxes per federating activity, worker retries, socket
  recipients, render time, and socket mailbox growth.
- Keep a representative benchmark dataset: local and remote actors, replies,
  interactions, deletes, private addressing, and high-fanout authors.
- Check the baseline into the repository so regressions are diffable.

## Acceptance Criteria

- A committed baseline plus a small production-like dashboard can distinguish
  a query regression from a fanout, render, queue, or network problem.
- The benchmark dataset is reproducible from a seed task.

## Notes

- Can run in parallel with the behavior-matrix work; nothing depends on it
  first.
- This gates any decision about materialized timelines or new projections:
  measure before projecting.
