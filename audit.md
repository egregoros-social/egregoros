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
