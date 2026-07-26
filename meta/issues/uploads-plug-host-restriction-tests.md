# Test the uploads plug host restriction and headers

## Summary

`EgregorosWeb.Plugs.Uploads` enforces a host restriction (so uploads are not
served from the main app origin when `EGREGOROS_UPLOADS_BASE_URL` is set) and
sets `nosniff`. Neither is covered by a direct test, so a refactor could
silently drop them.

## Requirements

- Test that the allowed uploads host serves `/uploads/*`.
- Test that a disallowed host does not.
- Test the security headers the plug is responsible for, including `nosniff`.

## Acceptance Criteria

- Host allow and deny paths are both asserted.
- Header assertions fail if the headers are removed.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`.
