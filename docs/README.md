# Egregoros documentation

## Working on Egregoros

- [`development.md`](development.md) — setup, tests, precommit, benchmarks
- [`architecture.md`](architecture.md) — moving parts and data flow
- [`extending-activity-types.md`](extending-activity-types.md) — adding a new
  ActivityPub type end to end (ingestion + display)
- [`security.md`](security.md) — security and privacy checklist
- [`benchmarks.md`](benchmarks.md) — benchmark harness

Current work is tracked as repository-local issues in
[`../meta/issues.md`](../meta/issues.md).

## Running Egregoros

- [`deployment.md`](deployment.md) — Docker Compose, standalone Caddy, Coolify,
  systemd, uploads subdomain, signature strictness, troubleshooting

## Compatibility

- [`pleroma-migration.md`](pleroma-migration.md) — importing an existing Pleroma
  instance, plus the operator runbook
- [`frontend-checklist.md`](frontend-checklist.md) — web UI parity checklist
  against Mastodon/Pleroma clients

## Design notes

Proposals and plans. Some are implemented, some are historical, some are
parked — each states its own status.

- [`design/liveview-ui.md`](design/liveview-ui.md) — LiveView + Tailwind UI plan
- [`design/thread-fetching.md`](design/thread-fetching.md) — thread completion
  design
- [`design/e2ee-direct-messages.md`](design/e2ee-direct-messages.md) — **parked**;
  E2EE DMs were implemented and then removed
- [`design/initial-plan.md`](design/initial-plan.md) — the original staged build
  plan, kept for context

## Audits

Point-in-time reviews. They are **historical**: findings that are still open
live in [`../meta/issues.md`](../meta/issues.md), so unchecked boxes here are not
a second backlog.

- [`audits/codebase-audit-2026-01-18.md`](audits/codebase-audit-2026-01-18.md)
- [`audits/timeline-performance-2026-01-14.md`](audits/timeline-performance-2026-01-14.md)
- [`audits/timeline-performance-addendum-2026-01-15.md`](audits/timeline-performance-addendum-2026-01-15.md)
- [`audits/test-suite-audit.md`](audits/test-suite-audit.md)
- [`audits/poll-publish-refactor.md`](audits/poll-publish-refactor.md)

## Mockups

[`mockups/`](mockups) holds standalone HTML UI explorations. They are sketches,
not a component library.
