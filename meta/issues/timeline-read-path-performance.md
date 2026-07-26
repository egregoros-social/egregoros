# Follow up on timeline read-path performance

## Summary

The timeline performance audits list candidate improvements for the read path
(home/public/local/tag/profile feeds, API timelines, notifications, thread
context). They were derived from static reading, not measurement, so they are
candidates rather than a ranked plan.

## Requirements

- Validate the audit's candidates against real data before implementing them.
- Define p95 budgets/SLOs for the identified cases. CI enforcement may be
  flaky, so consider "watch" thresholds in `perf/` rather than hard failures.
- Only add typed columns, partial indexes, or recipient projections for
  predicates shown to be hot.
- Require any derived table to be rebuildable from canonical state, with a
  named owner and a removal criterion.

## Acceptance Criteria

- Each implemented change cites a measurement, not a hypothesis.
- p95 budgets exist for the audited cases.
- Any projection added has a documented rebuild path.

## Notes

- Sources: `docs/audits/timeline-performance-2026-01-14.md` and
  `docs/audits/timeline-performance-addendum-2026-01-15.md`.
- Explicitly out of scope for now: materializing home timelines. Do not do
  that before dynamic-query targets are known.
- Depends on
  [operational-and-query-baselines](operational-and-query-baselines.md).
