# Thread Fetching (Plan)

Right now Egregoros only stores objects/activities that arrive via:

- direct federation delivery (inbox),
- local authoring (Publish),
- explicit user interactions (follow/like/etc).

That means reply chains are often incomplete: we can render a reply we received, but we may not
have its ancestors (or the rest of the conversation). This document proposes a **best-effort,
safe, bounded** system to **fill in missing thread context** over federation.

## Goals

- When a reply arrives (or a local user replies to a remote post), automatically fetch enough
  context to read the thread (at minimum: ancestors via `inReplyTo`).
- Never block inbox ingestion; everything runs async via Oban.
- Respect security/safety constraints:
  - prevent SSRF via `Egregoros.SafeURL.validate_http_url/1`
  - don’t bypass visibility rules when rendering (still rely on `Objects.visible_to?/2`)
  - handle signed-fetch-only servers (use `Egregoros.Federation.SignedFetch`)
- Stay compatible with “single `objects` table” storage.

## Non-goals (for now)

- Guarantee fetching *all* descendants/replies in a conversation (not always possible with AP).
- Implement per-domain crawling, relays, or discovery-based thread expansion beyond direct links.
- Replace existing thread rendering; this is about *adding missing data*.

## What we already have

- Thread rendering from local DB:
  - `Objects.thread_ancestors/2` follows `data["inReplyTo"]` **only if the parent exists locally**
  - `Objects.thread_descendants/2` finds replies by querying `data["inReplyTo"]` in stored notes
- A safe signed fetch primitive:
  - `Egregoros.Federation.SignedFetch.get/2`
- An ingestion pipeline that can ingest Note/Create/etc from a JSON map:
  - `Pipeline.ingest(map, local: false)`
- Actor discovery during ingestion (already done):
  - `Egregoros.Federation.ActorDiscovery.enqueue/2`

## Design overview

### 1) Fetch missing ancestors (core win)

When we ingest a `Note` (or a `Create` embedding a `Note`) and it has an `inReplyTo` URL we don’t
have locally, enqueue a bounded thread fetch job that:

1. Fetches the `inReplyTo` object (best-effort: signed fetch; handle 401/403 gracefully).
2. Ingests it with `Pipeline.ingest(..., local: false)` so it becomes a first-class `objects` row.
3. Repeats (walking the chain) until:
   - we reach a root (no `inReplyTo`), or
   - we hit a configured max depth, or
   - we hit a failure (non-2xx, invalid JSON, tombstone, safety rejection).

This alone turns “small glimpse” replies into readable threads for most real-world posts.

### 2) Fetch descendants (optional / phased)

Fetching all replies is not reliably possible, but we can do **best-effort** expansion when a
remote object exposes an ActivityPub `replies` collection:

- If `Note.data["replies"]` is a collection URL:
  - fetch `replies` (and optionally `first`) pages with a strict item/page limit
  - ingest any `Note` objects found in `orderedItems/items`
  - for items that are just IDs/links, enqueue per-object fetches

This should likely be **on-demand** (UI “Load more replies”) or limited to a small “nearby”
window to avoid accidental crawling.

### 3) UI refresh (how users see completion)

Thread fetch runs in the background. The UI needs a way to update without requiring manual
refresh:

Options (in order of preference):

1. **Targeted PubSub**: broadcast `{:object_upserted, ap_id}` on a topic like `"object:" <> ap_id`
   (or `"thread:" <> root_ap_id`) whenever a `Note` is ingested. `StatusLive` subscribes and calls
   `refresh_thread/1`.
2. **Light polling**: when a thread is incomplete, `StatusLive` schedules a short periodic
   refresh (e.g. every 1–2s for a few attempts) until ancestors appear.
3. **Manual UX**: show “More context is loading…” + a “Refresh” button.

We should start with (1) if feasible; it’s the best UX and keeps DB reads bounded.

## Proposed modules / workers

### `Egregoros.Federation.ObjectFetcher` (new)

Responsibility: **fetch a single ActivityPub object** (URL → JSON map), validate, ingest.

Key behaviors:

- Always validate URL safety (`SafeURL.validate_http_url/1`).
- Prefer signed fetch to support signed-fetch-only servers.
- Validate that fetched JSON is a map and that `"id"` matches the URL when present (reject mismatches).
- Ingest via `Pipeline.ingest(map, local: false)`.
- Return `{:ok, object}` or `{:error, reason}` with reasons suitable for Oban retries.

### `Egregoros.Workers.FetchObject` (new)

Responsibility: Oban wrapper around `ObjectFetcher`.

- Args: `%{"ap_id" => "https://remote/.../objects/..."}` (and maybe `"expected_type"` later).
- Unique on `ap_id` for a window to dedupe bursts (Oban uniqueness).
- Fast path: if `Objects.get_by_ap_id(ap_id)` exists, do nothing.

### `Egregoros.Workers.FetchThreadAncestors` (new)

Responsibility: bounded “walk `inReplyTo` chain” job.

- Args: `%{"start_ap_id" => note_ap_id, "max_depth" => 20}`
- Steps:
  1. Load `start_ap_id` from DB (if missing, try fetching it once via `FetchObject`)
  2. Extract `inReplyTo` from stored object data
  3. While parent is missing and depth remains:
     - fetch + ingest parent (inline inside the job *or* enqueue `FetchObject` and snooze)
     - continue with new parent’s `inReplyTo`
- Stop conditions: missing/unsafe URLs, authorization failures, depth limit, cycles (visited set).

Implementation choice:

- **Inline fetch** inside the thread job is simplest and completes threads faster, but must be
  strongly bounded (max N fetches per job).
- **Enqueue + snooze** splits work into smaller pieces (better backoff/dedup), but takes longer.

Start with inline fetch bounded to ~10–20 objects per job.

### `Egregoros.Federation.ThreadDiscovery` (new)

Responsibility: extract “thread-related URLs” from ingested activities/objects and enqueue thread
work.

Input: a validated activity map + opts (`local: true/false`).

Rules (initial):

- For `Note` maps: if it has `inReplyTo` and parent isn’t stored, enqueue `FetchThreadAncestors`.
- For `Create` maps: if it embeds a `Note` object with `inReplyTo`, enqueue based on the embedded note id.
- For local replies to remote posts: also enqueue, so local users see context.

Hook point:

- `Pipeline.ingest_with/3` already has a discovery call for actors; we can add thread discovery
  there as well (or expand the existing discovery phase into multiple calls).

## Safety and performance constraints

Minimum constraints we should enforce from day 1:

- SSRF protection: only http/https, no private IPs/localhost (already covered by `SafeURL`).
- Per-job maximum fetch count / depth.
- Oban uniqueness (dedupe) and small retry budget for thread fetch jobs.
- Prefer not to crawl:
  - only follow explicit `inReplyTo` links
  - no “search the remote outbox for context” (too expensive and privacy-sensitive)

Later (if needed):

- Per-domain concurrency limits / circuit breaking (avoid hammering a remote instance).
- Cache fetch failures (e.g., “403 for this object”) to avoid repeated attempts on every reply.

## TDD plan (incremental)

### Milestone A — ancestor completion

1. Add a failing test: ingest a reply note with `inReplyTo` pointing to a missing object, then
   running the thread job causes the parent to be stored and appear in `Objects.thread_ancestors/1`.
2. Implement `ObjectFetcher` + `FetchObject` with Mox’d HTTP responses (fixtures in `test/fixtures`).
3. Implement `FetchThreadAncestors` bounded loop.
4. Wire `ThreadDiscovery` into ingestion (ensure this doesn’t block inbox requests).

### Milestone B — UX updates

1. Add a failing LiveView test: mount `StatusLive` for a reply; after the thread job runs and the
   parent is ingested, the view updates and shows the ancestor.
2. Implement PubSub-based refresh or minimal polling.

### Milestone C — descendants (optional)

1. Add tests for parsing `replies` collections (single page first).
2. Add an on-demand endpoint/UI action to expand replies.
3. Add strict limits (pages/items) and dedupe.

## Open questions / decisions

- Should we always signed-fetch, or try unsigned first?
  - Always signed-fetch is simpler and avoids signed-fetch-only failures, but adds signatures to
    every request (small overhead).
- Should we store denormalized `in_reply_to` column for indexing?
  - Not required for correctness, but may matter for large instances; revisit after baseline works.
- How do we handle tombstones / deleted objects?
  - Store the activity we have, but thread fetch should stop walking when encountering tombstones.

