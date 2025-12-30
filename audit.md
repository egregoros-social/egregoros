# Codebase Audit (2025-12-29)

This is a follow-up audit of **Egregoros** (Postgres + Elixir/OTP + Phoenix/LiveView), focused on: **security/impersonation**, **privacy leaks**, **consistency**, **performance**, and **architecture follow-ups**.

If you’re looking for the ongoing checklist of known security gaps, see `security.md`.

## Status update (2025-12-30)

Since the 2025-12-29 audit, the following items have been addressed:

- [x] Fixed IPv4-mapped IPv6 private IP detection in `Egregoros.SafeURL`.
- [x] Inbox pre-signature rate limiting no longer keys on unverified `keyId` domains.
- [x] Session hardening: renew on login/registration, drop on logout, production cookie flags reviewed.
- [x] Audience-scoped PubSub delivery to reduce DM/private blast radius.
- [x] Visibility semantics aligned across layers, including `bto`/`bcc`/`audience` handling.
- [x] “Unlisted” no longer appears on public timelines/streams.
- [x] OAuth token storage hardened and query-param bearer tokens removed (except streaming).
- [x] Attachments with unsafe media URLs are filtered from UI/Mastodon status rendering.

## Addendum (2025-12-30)

This is a short follow-up pass focused on **maintainability / DRY**, plus a quick scan for **privacy/security** regressions.

### CRITICAL (new)

- [x] **XSS via HTML entity unescaping after sanitization**: `Egregoros.HTML.sanitize/2` used to do a global `String.replace(content, "&amp;", "&")` after scrubbing.
  - This can turn *double-escaped* entities back into active entities *after* sanitization.
  - Example payload inside otherwise-valid HTML: `<a href="javascript&amp;#x3A;alert(1)">x</a>`
    - If `&amp;` is unescaped inside the `href`, the browser decodes `&#x3A;` into `:` and the `javascript:` scheme becomes active.
  - Repro (dev): `mix run -e 'IO.puts(Egregoros.HTML.to_safe_html("<a href=\"javascript&amp;#x3A;alert(1)\">x</a>", format: :html))'`
  - Code: `lib/egregoros/html.ex` (`sanitize/2`).
  - Notes / fix direction:
    - Fix by only unescaping `&amp;` in text nodes (not inside tag attributes), so we preserve the “double-escaped apostrophe” UX improvement without re-activating dangerous URLs.

### LOW (new)

- **Reply target visibility is not enforced in Mastodon create flow**: `StatusesController.resolve_in_reply_to/1` resolves `in_reply_to_id` to an `ap_id` without checking `Objects.visible_to?/2` for the posting user.
  - This is likely not exploitable for content disclosure (the client already needs the ID), but it can create “phantom” replies to objects the poster cannot view.
  - Code: `lib/egregoros_web/controllers/mastodon_api/statuses_controller.ex`.

### Maintainability / DRY opportunities (new)

- **Duplicate `truthy?/1` helpers** across LiveViews and controllers; consider centralizing a small helper (e.g. `EgregorosWeb.Param.truthy?/1`) to keep semantics consistent.
  - Code: multiple `*_live.ex` and `TimelinesController`.
- **Activity modules repeat common helpers** (`parse_datetime/1`, `maybe_put/3`, and related small normalizers) across `Egregoros.Activities.*` modules.
  - Consider a tiny shared helper module (e.g. `Egregoros.Activities.Helpers`) so each activity module stays “one file per activity type” but avoids copy/paste drift.
- **`safe_return_to/1` is duplicated** in session/registration controllers; could be shared.
  - Code: `lib/egregoros_web/controllers/session_controller.ex`, `lib/egregoros_web/controllers/registration_controller.ex`.
- **`fallback_username/1` is duplicated** across renderers/controllers; consider centralizing to avoid subtle differences in parsing.
  - Code: `StatusesController`, `StatusRenderer`, `NotificationRenderer`.
- **OAuth token fields are digests but named like raw tokens**: `oauth_tokens.token` and `oauth_tokens.refresh_token` store digests, but the field names don’t make that obvious.
  - This is correct security-wise, but it’s easy to accidentally misuse/log. Consider renaming the DB columns or clearly documenting the invariant.
  - Code: `lib/egregoros/oauth.ex`, `lib/egregoros/oauth/token.ex`.
- **Timestamp type inconsistency**: `Relationship` uses `timestamps(type: :utc_datetime)` while most other schemas use `:utc_datetime_usec`.
  - Consider standardizing for consistency and easier ordering/debugging.
  - Code: `lib/egregoros/relationship.ex`.
- **`assets/js/app.js` is becoming a “god file”** as hooks/features accumulate; consider splitting hooks into small modules under `assets/js/hooks/*` and importing them into `app.js`.
  - This keeps a single bundle while making hooks easier to test/review.

## Security / privacy (new findings)

### CRITICAL

- **SSRF bypass via IPv4-mapped IPv6**: `Egregoros.SafeURL` does not treat IPv4-mapped IPv6 addresses as private (e.g. `::ffff:127.0.0.1`), so server-side fetches can reach internal IPs.
  - Repro: `mix run -e 'IO.inspect(Egregoros.SafeURL.validate_http_url("http://[::ffff:127.0.0.1]/"))'` currently returns `:ok`.
  - Code: `lib/egregoros/safe_url.ex` (private IP detection for IPv6).
  - Impacted call sites include actor fetch / signed fetch / object fetch / webfinger / delivery URL validation:
    - `lib/egregoros/federation/actor.ex`
    - `lib/egregoros/federation/signed_fetch.ex`
    - `lib/egregoros/federation/object_fetcher.ex`
    - `lib/egregoros/federation/webfinger.ex`
    - `lib/egregoros/federation/delivery.ex`

### HIGH

- **Inbox rate limiting can be bypassed by spoofed `keyId` domains**: `RateLimitInbox` uses the unverified `Signature`/`Authorization` header `keyId` to build the rate-limit key, allowing attackers to rotate domains to avoid throttling (and potentially create many short-lived ETS entries).
  - Code: `lib/egregoros_web/plugs/rate_limit_inbox.ex`, `lib/egregoros/rate_limiter/ets.ex`
- **Session hardening gaps (fixation / cookie flags)**:
  - Login/registration do not renew the session ID (session fixation risk): `lib/egregoros_web/controllers/session_controller.ex`, `lib/egregoros_web/controllers/registration_controller.ex`
  - Logout clears session but does not drop it: `lib/egregoros_web/controllers/registration_controller.ex`
  - Session cookie options lack `secure: true` (and other prod-focused flags): `lib/egregoros_web/endpoint.ex`

### MEDIUM

- **Private media access control**: uploads are served via `Plug.Static` (because `uploads` is in `static_paths`), so DM/private attachments are world-readable if the URL leaks.
  - Code: `lib/egregoros_web.ex`, `lib/egregoros_web/endpoint.ex`
- **PubSub “blast radius” for DMs/private notes**: all Notes are broadcast on the global `"timeline"` topic and filtered later by consumers; a regression in filtering could leak private content to connected clients.
  - Code: `lib/egregoros/timeline.ex`, `lib/egregoros/activities/note.ex`
- **Visibility semantics gaps**: `Objects.visible_to?/2` considers `to`/`cc` (+ `/followers`) but ignores `bto`/`bcc`/`audience`, while inbox targeting checks do consider those fields (`InboxTargeting`).
  - Code: `lib/egregoros/objects.ex`, `lib/egregoros/inbox_targeting.ex`
- **Unlisted appears on public timelines**: “public visibility” queries treat `Public` in either `to` or `cc` as public-timeline-visible; “unlisted” posts have `Public` in `cc`.
  - Code: `lib/egregoros/objects.ex`
- **OAuth tokens stored in plaintext**: access/refresh tokens are stored as raw strings; a DB compromise trivially exposes active tokens.
  - Code: `lib/egregoros/oauth/token.ex`
- **Bearer tokens accepted via query param**: accepting `access_token` in query params increases risk of token exposure via logs/referrers.
  - Code: `lib/egregoros/auth/bearer_token.ex`

### LOW

- **Signature strictness**: inbound signature verification doesn’t require `digest` to be present/signed; this can be tightened depending on compatibility goals.
  - Code: `lib/egregoros/signature/http.ex`

## Consistency / DRY opportunities (non-security)

- **Visibility rules are duplicated across layers** (publishing, query filters, streaming filters). Consider centralizing visibility classification to avoid mismatches (e.g. “unlisted in public timeline”).
  - Code: `lib/egregoros/publish.ex`, `lib/egregoros/objects.ex`, `lib/egregoros_web/mastodon_api/streaming_socket.ex`
- **Repeated LiveView upload helpers**: `cancel_all_uploads/2` is duplicated across multiple LiveViews; consider a shared helper/module or component.
  - Code: `lib/egregoros_web/live/timeline_live.ex`, `lib/egregoros_web/live/status_live.ex`, `lib/egregoros_web/live/profile_live.ex`, `lib/egregoros_web/live/search_live.ex`, `lib/egregoros_web/live/tag_live.ex`

---

# Codebase Audit (2025-12-27)

This is a point-in-time audit of **Egregoros** (Postgres + Elixir/OTP + Phoenix/LiveView), focused on: **security/impersonation**, **privacy leaks**, **consistency**, **performance**, and **architecture follow-ups**.

If you’re looking for the ongoing checklist of known security gaps, see `security.md`.

## Security

### High priority (new)

No new “drop everything” issues found beyond the items already tracked in `security.md`.

### Medium priority (new)

- [x] **Inbox addressing / target verification** (abuse/DB pollution risk).
  - Addressing context is now propagated from inbox controller into ingestion (`inbox_user_ap_id`) and enforced for common activity types (see `Egregoros.InboxTargeting`).

- [x] **Defense-in-depth: LiveView “refresh” helpers re-check visibility**.
  - `refresh_post/2` helpers now guard via `Objects.visible_to?/2`, removing items from streams when they become invisible to the viewer.

- **Client-side “SSRF-ish” via remote emoji/icon URLs** (privacy/internal network probing).
  - Custom emoji tags (`Egregoros.CustomEmojis`) and some remote profile fields can embed arbitrary `http(s)` URLs which the browser will fetch.
  - This is not server-side SSRF, but it can still be abused for tracking or for probing a user’s local network via image loads.
  - Mitigation options: stricter URL allowlist (reject private IPs), proxy images/media, or only allow remote emoji/icon URLs that pass `Egregoros.SafeURL.validate_http_url/1` at ingest time.

### Low priority (new)

- [x] **Potential DoS if HTML sanitization ever raises**.
  - `Egregoros.HTML.sanitize/1` now wraps scrubbing in a safe fallback and escapes on failure.

## Consistency / correctness gaps (non-security)

- **Mastodon v1 instance streaming URL**:
  - `lib/egregoros_web/controllers/mastodon_api/instance_controller.ex` returns `urls.streaming_api` as a bare `ws(s)://…` base; some clients expect the full streaming path (commonly `/api/v1/streaming`).

- **Account statuses visibility is conservative**:
  - `lib/egregoros_web/controllers/mastodon_api/accounts_controller.ex` uses `Objects.list_public_statuses_by_actor/2` for `/api/v1/accounts/:id/statuses` even when authenticated.
  - This avoids leaks but may diverge from user expectations (followers-only/profile-visible posts won’t show via API even when the viewer is allowed).

- [x] **Registration flags are consistent**:
  - `nodeinfo` now reports `openRegistrations: true` when registrations are enabled (aligned with Mastodon instance endpoints).

## Performance / scalability

- [x] **Search and hashtag scan are indexed**:
  - Trigram indexes were added for note `content`/`summary` and a GIN `jsonb_path_ops` index for status `data` to support common `@>` visibility queries.

- **Visibility filtering relies on JSONB containment** (`@>` / `jsonb_exists`) and can still be improved.
  - A GIN `jsonb_path_ops` index on status `data` helps the common `@>` predicates, but some `jsonb_exists` patterns may still be slow at scale.
  - Consider further indexes (path-specific), or a normalized “recipient” table/materialized columns.

- **DNS lookups are synchronous and uncached**:
  - `Egregoros.SafeURL` calls `Egregoros.DNS.Inet.lookup_ips/1` on every validation. This is correct for SSRF protection but can become a throughput limiter.
  - Consider putting caching behind the `Egregoros.DNS` behaviour (ETS + TTL), so it remains swappable.

- **Synchronous remote resolution during posting**:
  - `Egregoros.Publish.post_note/3` resolves remote mentions via WebFinger + actor fetch inline. This makes posting latency depend on remote servers.
  - Consider a two-phase approach (post immediately; enqueue resolution + delivery retries) while keeping addressing correctness.

## Architectural follow-ups

- **Inbox context propagation** (also a security hardening enabler):
  - Pass `inbox_user_ap_id` through `IngestActivity` → `Pipeline.ingest/2` so validators/activities can make policy decisions without relying on global heuristics.

- **Object “upsert” semantics**:
  - `Objects.upsert_object/1` is effectively “insert or return existing” and does not merge/replace data when a conflict occurs.
  - This is fine for idempotency, but will matter once we add Update-like flows, partial fetches, or want to enrich objects after initial ingestion.

## Suggested next steps (ordered)

1. Add inbox context + optional addressing enforcement (start with Follow object target match).
2. Add visibility guards to LiveView refresh/update helpers (defense-in-depth).
3. Make `HTML.sanitize/1` resilient to scrub failures (safe fallback).
4. Pick an indexing strategy for search + JSONB recipient visibility queries.
5. Decide on (and align) registration flags across Nodeinfo and Mastodon instance endpoints.
