# Narrow session cookie scope across subdomains

## Summary

The "uploads on a separate origin" setup documents
`EGREGOROS_SESSION_COOKIE_DOMAIN=example.com` so the session cookie reaches
`i.example.com` for followers-only/direct media checks. That also sends the
session cookie to every other subdomain, including the bundled front-ends at
`fe.*` and `pl-fe.*`.

## Requirements

- Stop requiring a domain-wide session cookie for media visibility checks.
- Prefer a scoped credential for the uploads host (short-lived signed URL or
  a separate token) over widening the session cookie.
- Update `docs/deployment.md` so the documented setup is the safe one.

## Acceptance Criteria

- Followers-only and direct media remain access-controlled without a
  domain-wide session cookie.
- A test covers that the media path authorizes without the shared cookie.
- The deployment guide no longer recommends a domain-wide cookie.

## Notes

- From `docs/audits/codebase-audit-2026-01-18.md`.
- Overlaps [upload-access-control-policy](upload-access-control-policy.md);
  solving that one may subsume this.
