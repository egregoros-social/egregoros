# Remove end-to-end encrypted DMs

## Summary

Excise the end-to-end encrypted DM feature. Egregoros is moving toward
Pleroma compatibility and then a cutover; a large experimental feature with
its own crypto, key storage, actor advertisement and object type does not fit
that path. Plaintext direct messages must keep working.

## Requirements

- Remove the browser crypto, the recovery-phrase settings flow, and the
  LiveView hooks.
- Remove the `EncryptedMessage` object type and the `:e2ee_dm` publish option.
- Remove the `/settings/e2ee*` endpoints and the settings UI section.
- Stop advertising `egregoros:e2ee` in the actor document.
- Remove the E2EE key storage modules and drop the `e2ee_*` tables.
- Keep the design doc as a parked record in case the feature is revived.

## Acceptance Criteria

- No E2EE code remains in `lib`, `assets`, `config`, or `priv` outside the
  historical migrations.
- Plaintext DMs still work, with tests.
- Guard tests cover: the composer has no encryption controls,
  `EncryptedMessage` is an unknown activity type and is not ingested, the
  `/settings/e2ee*` routes 404, the actor document advertises no E2EE keys,
  and the `e2ee_*` tables are absent.
- Full suite passes and coverage stays at or above the 85% gate.

## Notes

- Completed across eight commits; see the `remove-e2ee` branch and its pull
  request.
- Design record kept at `docs/design/e2ee-direct-messages.md`, marked parked.
- Two consequences were accepted rather than fixed: leftover
  `type = 'EncryptedMessage'` rows stay in `objects` (unreachable and
  permanently undecryptable; purge SQL is in the drop migration), and peers
  still running E2EE have their encrypted DMs discarded on ingest as an
  unknown type.
- Whether the feature returns is tracked in
  [e2ee-revival-decision](e2ee-revival-decision.md).
