# Deduplicate the bundled front-end nginx configs

## Summary

`docker/pleroma-fe/nginx.conf` and `docker/pl-fe/nginx.conf` are effectively
the same proxy rules, so fixes have to be applied twice.

## Requirements

- Factor the shared proxy rules into one file included by both, or one
  templated config parameterized by upstream and root.
- Keep both front-ends working in the local and standalone compose stacks.

## Acceptance Criteria

- The rules exist once.
- Both front-ends still serve and proxy correctly in the compose stacks.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`.
