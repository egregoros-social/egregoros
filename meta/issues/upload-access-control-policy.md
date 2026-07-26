# Decide and enforce an upload access-control policy

## Summary

`EgregorosWeb.Plugs.Uploads` serves `/uploads/*` through `Plug.Static` with a
host restriction and `nosniff`, but with no per-object visibility check. Media
attached to followers-only or direct posts is therefore reachable by anyone
with the URL.

## Requirements

- Pick one policy and make the code and docs agree:
  (a) document media URLs as bearer links, which is common in the fediverse,
  or (b) gate media behind signed URLs or a token plus a controller, keeping
  `Plug.Static` only for public media.
- Whichever is chosen, state it in `docs/security.md`.

## Acceptance Criteria

- Behavior matches the documented policy, verified by tests.
- If gating is chosen, followers-only and direct media are unreachable without
  authorization, and public media still serves without a round trip through
  the app where possible.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`.
- Blocks/absorbs
  [session-cookie-scope-across-subdomains](session-cookie-scope-across-subdomains.md).
