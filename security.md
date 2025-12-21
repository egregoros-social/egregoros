# Security Notes / TODOs

This file tracks known security gaps and their remediation status.

## High priority (impersonation / integrity)
- [x] **Bind HTTP signature `keyId` to ActivityPub `actor` / `attributedTo`**: reject inbox requests where the verified signing actor does not match the activity `"actor"` (or `"attributedTo"` for object posts), and reject messages with no attributable actor.
- [x] **Bind `Create.actor` to embedded object author**: reject `Create` activities where the embedded object’s author (`attributedTo`/`actor`) does not match the `Create.actor`.
- [x] **Authorize `Undo`**: only apply `Undo` side-effects when `Undo.actor` matches the target activity’s `actor` (prevents undoing other people’s follows/likes/etc).
- [x] **Prevent local-namespace hijack**: reject remote activities whose `"id"` is on this instance’s host (prevents remote content being stored under local URLs).
- [x] **Only serve local objects at `/objects/:uuid`**: return 404 when a stored object is not `local: true` (defense-in-depth against poisoned `ap_id`s).
- [x] **Actor fetch integrity**: require fetched actor JSON `"id"` to match the requested actor URL (prevents actor poisoning).

## Medium priority (web UI hardening)
- [x] **CSRF-safe logout**: use POST logout behind CSRF protection (prevents third-party logout CSRF).
- [x] **Avoid unsafe share links**: do not render share/copy links for remote objects with non-HTTP(S) IDs (prevents `javascript:`/`data:` link injection).

## High priority (SSRF / DoS)
- [x] **Harden remote actor fetches** (used in signature verification and discovery):
  - [x] Reject non-HTTP(S) schemes and missing hosts.
  - [x] Block loopback / private IP literals.
  - [x] Block private IPs via DNS resolution (basic DNS rebinding mitigation).
  - [x] Disable redirects (temporary; re-validate redirect targets if re-enabled).
  - [x] Apply request receive timeout.
  - [x] Apply response size limits.
- [x] **Validate WebFinger / delivery URLs via `SafeURL`**:
  - [x] Reject unsafe WebFinger targets before fetching (`lookup/1`).
  - [x] Reject unsafe actor `inbox`/`outbox` before storing.
  - [x] Reject unsafe inbox URLs before enqueueing/sending deliveries.
- [x] **Avoid signature verification crashes**: reject invalid stored public keys (bad PEM) without raising (prevents trivial DoS).

## Medium priority (authz)
- [x] **Enforce OAuth scopes** for Mastodon API endpoints (coarse `read`/`write`/`follow`).
- [ ] **Token lifecycle**: token expiry / refresh tokens / revocation endpoint (and tests).

## Medium priority (inbox abuse controls)
- [ ] **Inbox addressing checks**: optionally require incoming activities to be addressed to this instance/user (e.g. `to`/`cc` includes followers/shared inbox), to reduce DB pollution.
- [ ] **Rate limiting / throttling**: per-IP/per-actor throttles on inbox and expensive federation fetches.
