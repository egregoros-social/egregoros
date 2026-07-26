# Verify Pleroma bcrypt and argon2 password hashes

## Summary

`Egregoros.Password.verify/2` handles two formats: Egregoros' own
`pbkdf2_sha256$...` and Pleroma's `$pbkdf2-...`. Pleroma's `password_hash`
column can also hold bcrypt (`$2...`) or argon2 (`$argon2...`), which is common
on instances that predate its pbkdf2 default or that migrated in from
elsewhere.

Users with those hashes cannot log in after a migration; they have to reset
their password.

## Requirements

- Before implementing anything, measure: check the hash-prefix distribution in
  the actual source instance. If it is entirely pbkdf2, close this issue
  instead of adding dependencies.
- If bcrypt/argon2 hashes are present, add verification branches for them.
- Reuse the existing rehash-on-login path so verified users migrate to the
  native format on first login.

## Acceptance Criteria

- Either: a recorded measurement showing the formats are absent, and this
  issue closed as unnecessary.
- Or: known-good hashes of each supported format verify, with tests, and
  logging in rehashes to `pbkdf2_sha256$...`.

## Notes

- Deliberately measurement-first — this is the cheapest possible way to find
  out the work is unnecessary, and it adds crypto dependencies if it is not.
- Section 4.1 of `docs/pleroma-migration.md` has the background.
