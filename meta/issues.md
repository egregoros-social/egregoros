# Open issues

Grouped by theme; roughly highest-leverage first within each group. Completed
issues move to [`issues_archive.md`](issues_archive.md).

## Now: characterize and contain

Make current behavior and failure semantics executable and reviewable, before
changing the execution model.

- [ ] [Make ingress behavior executable as a parity matrix](issues/ingress-behavior-matrix.md)
- [ ] [Build one cross-surface visibility/block/mute truth table](issues/visibility-block-mute-truth-table.md)
- [ ] [Extend the moderation table to streaming, LiveView, and delivery](issues/extend-moderation-table-to-remaining-surfaces.md)
- [ ] [Check in operational and query baselines](issues/operational-and-query-baselines.md)
- [ ] [Add architecture guardrails to CI](issues/architecture-guardrails-in-ci.md)
- [ ] [Start architecture decision records](issues/architecture-decision-records.md)

## Next: durable core

Changes execution semantics behind the tests written above. Do not start before
the behavior matrix exists.

- [ ] [Make ingestion transactional with replay-safe effect intent](issues/transactional-ingestion-and-effect-intent.md)

## Security and privacy

- [ ] [Bound actor discovery fan-out per activity](issues/bound-actor-discovery-fanout.md)
- [ ] [Enforce blocks and mutes across every surface](issues/enforce-blocks-and-mutes-across-surfaces.md)
- [ ] [Decide and enforce an upload access-control policy](issues/upload-access-control-policy.md)
- [ ] [Narrow session cookie scope across subdomains](issues/session-cookie-scope-across-subdomains.md)
- [ ] [Bound image processing against decompression bombs](issues/image-processing-limits.md)
- [ ] [Tighten and test HTTP signature strictness](issues/signature-strictness-hardening.md)
- [ ] [Add a Content-Security-Policy](issues/content-security-policy.md)
- [ ] [Test the uploads plug host restriction and headers](issues/uploads-plug-host-restriction-tests.md)

## Performance

- [ ] [Follow up on timeline read-path performance](issues/timeline-read-path-performance.md)
- [ ] [Remove the N+1 actor lookup in the messages view](issues/actor-card-n-plus-1-in-messages.md)
- [ ] [Fix quadratic HTTP response body accumulation](issues/http-response-body-accumulation.md)

## Maintainability

- [ ] [Keep caching behind behaviour boundaries](issues/cache-behaviour-boundaries.md)
- [ ] [Deduplicate uploads root and file persistence logic](issues/deduplicate-uploads-storage-logic.md)
- [ ] [Deduplicate the bundled front-end nginx configs](issues/deduplicate-frontend-nginx-configs.md)

## Web UI

- [ ] [Work through the frontend parity checklist](issues/frontend-parity-checklist.md)
- [ ] [Polish the composer](issues/composer-polish.md)
- [ ] [Polish the thread and status view](issues/thread-view-polish.md)
- [ ] [Finish messages UI parity](issues/messages-ui-parity.md)

## Compatibility (later)

Not current-milestone work. These gate a Pleroma cutover, not the architecture
milestone above, and the posture is to keep compatibility work narrow and
evidence-driven until the reliability work lands. See
[`../docs/pleroma-migration.md`](../docs/pleroma-migration.md).

- [ ] [Import the follow graph from Pleroma](issues/pleroma-import-follow-graph.md)
- [ ] [Rehearse the Pleroma migration end to end](issues/pleroma-migration-rehearsal.md)
- [ ] [Verify Pleroma bcrypt and argon2 password hashes](issues/pleroma-password-hash-compatibility.md)

## Decisions pending

- [ ] [Decide whether E2EE DMs come back](issues/e2ee-revival-decision.md)
