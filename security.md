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

## High priority (privacy / visibility)
- [x] **Prevent DM/private leakage into public surfaces**: ensure public timelines, tag pages, search, profiles, and public permalinks only show statuses visible to the viewer.
- [x] **Prevent DM/private exfiltration via write endpoints**: require `Objects.visible_to?/2` for Mastodon write actions that return statuses (favourite/unfavourite, reblog/unreblog).
- [x] **Prevent DM/private probing via ancillary endpoints**: require `Objects.visible_to?/2` for `favourited_by`, `reblogged_by`, and Pleroma emoji reaction endpoints.

## Medium priority (authz)
- [x] **Enforce OAuth scopes** for Mastodon API endpoints (coarse `read`/`write`/`follow`).
- [x] **Token lifecycle**: token expiry / refresh tokens / revocation endpoint (and tests).

## Medium priority (inbox abuse controls)
- [x] **Inbox addressing checks**: optionally require incoming activities to be addressed to this instance/user (e.g. `to`/`cc` includes followers/shared inbox), to reduce DB pollution.
  - [x] Pass `inbox_user_ap_id` from controller → ingestion pipeline.
  - [x] Enforce `Follow.object == inbox_user_ap_id` for incoming remote follows.
  - [x] Enforce inbox targeting / addressing for Create/Note.
  - [x] Enforce inbox targeting / addressing for Like/Announce/EmojiReact.
  - [x] Enforce inbox targeting / addressing for Accept/Undo/Delete.
- [x] **Rate limiting / throttling**: per-IP/per-actor throttles on inbox and expensive federation fetches.
  - [x] Apply rate limiting to `POST /users/:nickname/inbox` (pre-signature-verification).
  - [x] Apply rate limiting to outgoing `SignedFetch` requests.
