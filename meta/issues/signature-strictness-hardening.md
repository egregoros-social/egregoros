# Tighten and test HTTP signature strictness

## Summary

Inbound signature verification does not require `digest` to be present and
covered by the signature, and strict mode has no direct test coverage. This
appears three times across the audits and security notes as one underlying
gap.

## Requirements

- Optionally require `digest` to be present and signed on inbox POSTs,
  balancing compatibility against security.
- Keep the compatibility-focused default and the opt-in strict mode
  (`config :egregoros, :signature_strict`).
- Add explicit tests for strict-mode header requirements, date-skew failures,
  and `@request-target` support.

## Acceptance Criteria

- Strict mode's header requirements are asserted by tests, including the
  failure cases.
- Date skew outside `:signature_skew_seconds` is rejected, with a test.
- The compatibility default still federates with servers that sign fewer
  headers, with a test.

## Notes

- Merges three previously separate entries: the open item in
  `docs/security.md` and two in
  `docs/audits/codebase-audit-2026-01-18.md`.
