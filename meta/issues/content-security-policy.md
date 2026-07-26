# Add a Content-Security-Policy

## Summary

There is no explicit `Content-Security-Policy` header. Given the app renders
sanitized remote HTML and serves user uploads, CSP is the natural
defense-in-depth layer behind `Egregoros.HTML`.

## Requirements

- Add a CSP for app responses, tight enough to be meaningful with LiveView
  (which needs its own script/websocket allowances).
- Serve uploads with their own restrictive policy.
- Make the policy configurable for operators running extra front-ends on
  subdomains.

## Acceptance Criteria

- App and uploads responses carry a CSP, asserted by tests.
- LiveView, the emoji picker, media playback, and image cropping still work
  under the policy.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`.
