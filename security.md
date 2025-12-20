# Security Notes / TODOs

This file tracks known security gaps and their remediation status.

## High priority (impersonation / integrity)
- [x] **Bind HTTP signature `keyId` to ActivityPub `actor`**: reject inbox requests where the verified signing actor does not match the activity `"actor"` (or inline `"actor": {"id": ...}`).
- [x] **Bind `Create.actor` to embedded object author**: reject `Create` activities where the embedded object’s author (`attributedTo`/`actor`) does not match the `Create.actor`.
- [x] **Authorize `Undo`**: only apply `Undo` side-effects when `Undo.actor` matches the target activity’s `actor` (prevents undoing other people’s follows/likes/etc).

## High priority (SSRF / DoS)
- [ ] **Harden remote actor fetches** (used in signature verification and discovery):
  - Reject non-HTTP(S) schemes and missing hosts.
  - Block loopback / private IP literals (and eventually DNS rebinding).
  - Disable redirects or re-validate redirect targets.
  - Apply response size/time limits.

## Medium priority (authz)
- [ ] **Enforce OAuth scopes** for Mastodon API endpoints (read vs write, per-endpoint scopes).
- [ ] **Token lifecycle**: token expiry / refresh tokens / revocation endpoint (and tests).

## Medium priority (inbox abuse controls)
- [ ] **Inbox addressing checks**: optionally require incoming activities to be addressed to this instance/user (e.g. `to`/`cc` includes followers/shared inbox), to reduce DB pollution.
- [ ] **Rate limiting / throttling**: per-IP/per-actor throttles on inbox and expensive federation fetches.
