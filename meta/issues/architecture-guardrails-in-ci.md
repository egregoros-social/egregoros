# Add architecture guardrails to CI

## Summary

Core-to-web dependencies and direct side effects from activity modules are
already normal patterns. Nothing stops new ones from landing. A concrete
current example: `Egregoros.Pipeline` aliases `EgregorosWeb.Endpoint` and
calls `Endpoint.url()` in `local_ap_id?/1`, so a core protocol module depends
on web presentation.

## Requirements

- Add an architecture test that reports core modules depending on
  `EgregorosWeb`.
- Seed a short allowlist of existing violations and require it to shrink;
  fail on additions.
- Reject new direct PubSub broadcasts, direct outbound HTTP delivery, or
  uncoordinated Oban insertion from activity modules unless it is part of the
  agreed effect mechanism.
- Document the bulk importer as the one offline exception: it shares canonical
  mapping rules, suppresses live effects, and has reconciliation tests.

## Acceptance Criteria

- CI fails when a new core-to-web dependency or direct effect path is added.
- The allowlist is committed, visible, and only shrinks.
- The importer exception is documented where the rule is defined.

## Notes

- Not blocked. An earlier note here claimed `mix precommit` was failing on
  `main`; that was a local toolchain mismatch, not a repository problem — see
  [fix-precommit-toolchain-gate](fix-precommit-toolchain-gate.md). CI is green and
  runs the full precommit, so a new rule has a trustworthy gate to land on.
- The `Endpoint.url()` dependency is also the first target of the eventual
  boundary repair work.
