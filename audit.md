# Codebase Audit (2025-12-29)

This is a follow-up audit of **Egregoros** (Postgres + Elixir/OTP + Phoenix/LiveView), focused on: **security/impersonation**, **privacy leaks**, **consistency**, **performance**, and **architecture follow-ups**.

If you’re looking for the ongoing checklist of known security gaps, see `security.md`.

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
