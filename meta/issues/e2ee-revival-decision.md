# Decide whether E2EE DMs come back

## Summary

End-to-end encrypted DMs were implemented and then removed: the browser
crypto, recovery-phrase flow, `EncryptedMessage` object type, the
`egregoros:e2ee` actor advertisement, the `/settings/e2ee*` endpoints, and the
`e2ee_*` tables are all gone. The design record is kept at
`docs/design/e2ee-direct-messages.md`.

## Requirements

- Decide whether the feature returns.
- If it does, decide on what protocol basis. The old design was
  Egregoros-specific, which is a poor fit for a server aiming at
  interoperability.
- If it does not, say so in the design doc so it stops reading as pending
  work.

## Acceptance Criteria

- A recorded decision, ideally as an ADR.
- `docs/design/e2ee-direct-messages.md` reflects that decision.

## Notes

- Reviving it means treating it as a fresh feature: new schemas and
  migrations. The drop migration is deliberately irreversible and the key
  material is gone, so the old implementation cannot be restored.
- Leftover `type = 'EncryptedMessage'` rows may still exist in `objects`;
  they are unreachable and permanently undecryptable. The purge SQL is in the
  drop migration.
