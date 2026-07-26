# Bound actor discovery fan-out per activity

## Summary

`Egregoros.Federation.ActorDiscovery.enqueue/2` collects every actor id it can
find in an inbound activity — `actor`, `attributedTo`, `issuer`, all of
`to`/`cc`/`bto`/`bcc`/`audience`, and every `Mention` tag — and enqueues a
`FetchActor` job per unknown id, with no cap.

Moving authorization ahead of discovery closed the case where a *rejected*
activity still triggered fetches. It does not bound the accepted case:

- Public activities are delivered without an `inbox_user_ap_id`
  (`inbox_controller.ex` and `instance_inbox_controller.ex` both omit it when
  `public_activity?/1`), and `InboxTargeting.validate/2` is permissive when it
  is absent. So a signed peer can POST one `to: [...#Public]` activity carrying
  hundreds of attacker-chosen `cc` entries or `Mention` tags to the shared
  inbox and get one remote fetch per entry.
- The same holds for an activity genuinely addressed to one local user:
  authorization passes on that recipient, then every other id in the envelope
  is fetched.

## Requirements

- Cap the number of actor fetches enqueued per activity, with the cap
  configurable and a safe default.
- Prefer the ids that matter (`actor`/`attributedTo`) over bulk recipients and
  mentions when the cap bites.
- Log or emit telemetry when the cap truncates, rather than silently dropping.
- Consider deferring recipient and mention discovery until after the activity
  is persisted, so only content we actually kept drives fetches.
- Consider a per-peer rate limit on discovery work, separate from the existing
  inbox rate limit.

## Acceptance Criteria

- An activity carrying many unknown recipient ids enqueues no more than the
  cap, asserted by a test.
- Truncation is observable.
- Normal federation is unaffected: an ordinary activity with a handful of
  participants still resolves all of them, with a test.

## Notes

- Inbox POSTs are signature-verified and the signer must match the activity's
  `actor`, so this requires a federated peer rather than an anonymous client.
  It is amplification and resource abuse, not an open relay.
- Found while reviewing
  [authorize-inbox-targeting-before-actor-discovery](authorize-inbox-targeting-before-actor-discovery.md);
  that issue's fix is a prerequisite and is already done.
- Fits the "measure before projecting" posture — the discovery-jobs-per-activity
  metric in
  [operational-and-query-baselines](operational-and-query-baselines.md) would
  tell us what a sane default cap is.
