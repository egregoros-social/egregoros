# Codebase Audit (2025-12-27)

This is a point-in-time audit of **Egregoros** (Postgres + Elixir/OTP + Phoenix/LiveView), focused on: **security/impersonation**, **privacy leaks**, **consistency**, **performance**, and **architecture follow-ups**.

If you’re looking for the ongoing checklist of known security gaps, see `security.md`.

## Security

### High priority (new)

No new “drop everything” issues found beyond the items already tracked in `security.md`.

### Medium priority (new)

- **Inbox addressing / target verification is missing** (abuse/DB pollution risk).
  - `lib/egregoros_web/controllers/inbox_controller.ex` only checks the local nickname exists; it doesn’t pass “which local inbox user was targeted” into ingestion (`Egregoros.Workers.IngestActivity` only receives `%{"activity" => activity}`).
  - As a result, a malicious sender can POST validly signed activities that are *not* actually addressed to that local user, and we may still store them (including relationships).
  - Suggested approach: include `inbox_user_ap_id` (and/or nickname) in the Oban job args and pass it through pipeline opts, then enforce:
    - Follow: `Follow.object == inbox_user_ap_id`
    - Like/Announce/EmojiReact: addressed to inbox user or followers/shared inbox rules
    - Create/Note: addressed to inbox user or followers/shared inbox rules

- **Defense-in-depth: LiveView “refresh” helpers don’t re-check visibility**.
  - Several LiveViews call `Objects.get(id)` and update streams without a `Objects.visible_to?/2` guard (see `refresh_post/2` helpers in `lib/egregoros_web/live/*.ex`).
  - This probably doesn’t create an exploit by itself (call sites typically already require auth/visibility), but it’s a cheap hardening win and prevents regressions from turning into leaks.

- **Client-side “SSRF-ish” via remote emoji/icon URLs** (privacy/internal network probing).
  - Custom emoji tags (`Egregoros.CustomEmojis`) and some remote profile fields can embed arbitrary `http(s)` URLs which the browser will fetch.
  - This is not server-side SSRF, but it can still be abused for tracking or for probing a user’s local network via image loads.
  - Mitigation options: stricter URL allowlist (reject private IPs), proxy images/media, or only allow remote emoji/icon URLs that pass `Egregoros.SafeURL.validate_http_url/1` at ingest time.

### Low priority (new)

- **Potential DoS if HTML sanitization ever raises**.
  - `Egregoros.HTML.sanitize/1` currently pattern-matches on `{:ok, content}` from `FastSanitize.Sanitizer.scrub/2`.
  - If scrub ever returns `{:error, _}` (or raises), it would crash the request render path. Consider wrapping in a safe fallback.

## Consistency / correctness gaps (non-security)

- **Mastodon v1 instance streaming URL**:
  - `lib/egregoros_web/controllers/mastodon_api/instance_controller.ex` returns `urls.streaming_api` as a bare `ws(s)://…` base; some clients expect the full streaming path (commonly `/api/v1/streaming`).

- **Account statuses visibility is conservative**:
  - `lib/egregoros_web/controllers/mastodon_api/accounts_controller.ex` uses `Objects.list_public_statuses_by_actor/2` for `/api/v1/accounts/:id/statuses` even when authenticated.
  - This avoids leaks but may diverge from user expectations (followers-only/profile-visible posts won’t show via API even when the viewer is allowed).

- **Minor config mismatch**:
  - `nodeinfo` sets `openRegistrations: false` while Mastodon instance endpoints report registrations enabled. Decide which policy is intended and keep consistent.

- **Stray CRLF artifact**:
  - `lib/egregoros_web/controllers/e2ee_controller.ex` contains a literal `\r` character on one line (harmless but noisy).

## Performance / scalability

- **Search and hashtag scan are unindexed**:
  - `Objects.search_notes/2` and `Objects.list_notes_by_hashtag/2` use `ILIKE` on `data->>'content'`/`summary`. This will degrade to sequential scans at scale.
  - Options: trigram index on extracted text, full-text search via `tsvector`, or precomputed searchable columns.

- **Visibility filtering relies on JSONB containment** (`@>` / `jsonb_exists`) without GIN support.
  - Home timeline and visibility checks do JSONB ops over `data.to`/`data.cc`.
  - Consider GIN indexes on `data` (or specific json paths), or a normalized “recipient” table/materialized columns.

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

