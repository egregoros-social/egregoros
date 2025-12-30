# Security Notes / TODOs

This file tracks known security gaps and their remediation status.

## High priority (impersonation / integrity)
- [x] **Bind HTTP signature `keyId` to ActivityPub `actor` / `attributedTo`**: reject inbox requests where the verified signing actor does not match the activity `"actor"` (or `"attributedTo"` for object posts), and reject messages with no attributable actor.
- [x] **Bind `Create.actor` to embedded object author**: reject `Create` activities where the embedded object’s author (`attributedTo`/`actor`) does not match the `Create.actor`.
- [x] **Authorize `Undo`**: only apply `Undo` side-effects when `Undo.actor` matches the target activity’s `actor` (prevents undoing other people’s follows/likes/etc).
- [x] **Prevent local-namespace hijack**: reject remote activities whose `"id"` is on this instance’s host (prevents remote content being stored under local URLs).
- [x] **Only serve local objects at `/objects/:uuid`**: return 404 when a stored object is not `local: true` (defense-in-depth against poisoned `ap_id`s).
- [x] **Actor fetch integrity**: require fetched actor JSON `"id"` to match the requested actor URL (prevents actor poisoning).

## High priority (XSS / content rendering)
- [ ] **XSS via HTML entity unescaping after sanitization**: `Egregoros.HTML.sanitize/2` does a global `&amp;` → `&` rewrite after scrubbing, which can re-activate double-escaped entities inside otherwise-valid HTML (e.g. `<p>&amp;#x3C;script...`). This can turn into an actual `<script>` when rendered with `Phoenix.HTML.raw/1`. Fix by removing the global rewrite and adding regression tests for `&amp;#x3C;` / `&amp;#60;` payloads.

## Medium priority (web UI hardening)
- [x] **CSRF-safe logout**: use POST logout behind CSRF protection (prevents third-party logout CSRF).
- [x] **Avoid unsafe share links**: do not render share/copy links for remote objects with non-HTTP(S) IDs (prevents `javascript:`/`data:` link injection).
- [x] **Filter unsafe media URLs before rendering**: drop attachments with unsafe `href` URLs (e.g. private IPs, `javascript:`/`data:`), both in the LiveView UI and in Mastodon API status rendering.

## High priority (SSRF / DoS)
- [x] **Harden remote actor fetches** (used in signature verification and discovery):
  - [x] Reject non-HTTP(S) schemes and missing hosts.
  - [x] Block loopback / private IP literals.
  - [x] Block IPv4-mapped IPv6 private IPs (e.g. `http://[::ffff:127.0.0.1]/`) and treat them as IPv4 for private-range checks.
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
- [x] **Unlisted semantics**: ensure “unlisted” statuses do **not** appear on public timelines/streams (they should still be publicly fetchable by ID).
- [x] **Recipient field completeness**: ensure visibility checks consider `bto`/`bcc`/`audience` where relevant (and stay consistent with inbox targeting rules).
- [x] **Private upload access control**: avoid serving DM/private attachments from `Plug.Static` without authorization checks (URLs should not be world-readable if leaked).

## Medium priority (authz)
- [x] **Enforce OAuth scopes** for Mastodon API endpoints (coarse `read`/`write`/`follow`).
- [x] **Token lifecycle**: token expiry / refresh tokens / revocation endpoint (and tests).
- [x] **Token storage hardening**: avoid storing OAuth access/refresh tokens in plaintext in the DB (hash tokens and/or store only a digest).
- [x] **Avoid access tokens in query params**: prefer header-only bearer tokens (query params leak into logs/referrers). (Exception: streaming uses its own access_token handling.)

## Medium priority (inbox abuse controls)
- [x] **Inbox addressing checks**: optionally require incoming activities to be addressed to this instance/user (e.g. `to`/`cc` includes followers/shared inbox), to reduce DB pollution.
  - [x] Pass `inbox_user_ap_id` from controller → ingestion pipeline.
  - [x] Enforce `Follow.object == inbox_user_ap_id` for incoming remote follows.
  - [x] Enforce inbox targeting / addressing for Create/Note.
  - [x] Enforce inbox targeting / addressing for Like/Announce/EmojiReact.
  - [x] Enforce inbox targeting / addressing for Accept/Undo/Delete.
- [x] **Rate limiting / throttling**: per-IP/per-actor throttles on inbox and expensive federation fetches.
  - [x] Apply rate limiting to `POST /users/:nickname/inbox` (pre-signature-verification).
  - [x] Ensure pre-signature inbox throttling keys on IP (not unverified `keyId` domains) to prevent bypass and ETS key explosion.
  - [x] Apply rate limiting to outgoing `SignedFetch` requests.

## Medium priority (web session hardening)
- [x] **Session fixation resistance**: renew session on login/registration.
- [x] **Logout should drop the session** (not just clear values).
- [x] **Secure cookie flags**: ensure session cookie is `secure` in production (and review other cookie flags).

## Low priority (signature strictness / compatibility)
- [ ] **Stricter signature requirements**: optionally require `digest` to be present and covered by the signature on inbox POSTs (balance compatibility vs security).
