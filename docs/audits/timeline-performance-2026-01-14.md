# Timeline Performance Audit (2026-01-14)

This is a **read-path performance review** of the “timeline-ish” parts of the app: home/public/local/tag/profile feeds, Mastodon API timelines, notifications, and status context (thread ancestors/descendants). It’s based on **static code reading** (not `EXPLAIN ANALYZE`), so treat it as a list of **potential risks** and **candidate improvements** to validate with real data.

## TL;DR (biggest risks)

1. **Home timeline worst-case scans**: `Objects.list_home_statuses/2` can devolve into scanning a large portion of `objects` when the viewer follows nobody (common for “new user on an existing instance”) or when the viewer follows only very inactive accounts (“nothing since 2 years ago”). In these cases it may do a lot of work to return *few or zero* rows.
2. **Replies count is computed by scanning notes**: Mastodon status rendering calls `Objects.count_note_replies_by_parent_ap_ids/1`, which likely becomes a “scan lots of notes” query on large DBs without a supporting index/denormalization.
3. **LiveView feed rendering is very query-heavy**: `EgregorosWeb.ViewModels.Status` + `EgregorosWeb.ViewModels.Actor` perform many per-item DB calls (N+1 patterns), which can dominate timeline latency even if the base timeline query is fast.
4. **Notifications API is multiplicatively expensive**: `Notifications.list_for_user/2` is a complex predicate, then `NotificationRenderer` loads related accounts/statuses per-item and calls `StatusRenderer.render_status/2` per item (each call builds its own query context).
5. **Hashtag + media-only filters likely bypass indexes**: hashtag filtering uses expression fragments that probably don’t use the existing `GIN (data jsonb_path_ops)` index; media-only filtering uses `jsonb_array_length` checks (not index-friendly).

## Scope inventory (where timeline queries happen)

### “Timeline list” queries (Objects)

- `lib/egregoros/objects.ex`
  - `list_home_statuses/2` (home feed) and `list_home_notes/2` (note-only variant)
  - `list_public_statuses/1` (public/local timeline API)
  - `list_public_statuses_by_hashtag/2` and `list_notes_by_hashtag/2` (tag feeds)
  - `list_visible_statuses_by_actor/3` (profile feed)
  - `thread_ancestors/2`, `thread_descendants/2`, `list_replies_to/2` (status context)
  - `count_note_replies_by_parent_ap_ids/1` (used for Mastodon `replies_count`)

### Notifications

- `lib/egregoros/notifications.ex`
  - `list_for_user/2` (notifications “timeline” query)

### Rendering & view-model layering (can dominate DB time)

- Mastodon API rendering
  - `lib/egregoros_web/mastodon_api/status_renderer.ex` (batch-ish, but calls replies count)
  - `lib/egregoros_web/mastodon_api/notification_renderer.ex` (per-item DB loads + per-item status rendering)
- LiveView rendering (timeline, profile, tag, bookmarks)
  - `lib/egregoros_web/view_models/status.ex` (many per-item queries)
  - `lib/egregoros_web/view_models/actor.ex` (per-item user lookup)

## What the DB has today (relevant to timelines)

The two main “feed read” tables are:

- `objects`: stores **both** content objects (e.g. `Note`) and activity-like objects (`Announce`, `Like`, `Follow`, etc.)
  - B-tree indexes: `actor`, `type`, `published`, `local`, plus composites: `(type, id)`, `(actor, type, id)`
  - GIN indexes:
    - `objects_status_data_path_ops_index` on `data jsonb_path_ops` for `type IN ('Note', 'Announce')`
    - Trigram GIN indexes for searching `Note` `content` / `summary`
- `relationships`: stores derived edges (`Follow`, `Like`, `Announce`, `Bookmark`, `EmojiReact:*`, …)
  - Unique index on `(type, actor, object)` plus indexes on `actor`, `object`, and `(object, type)`

Notably, there is **no index on `objects.object`**, which matters because multiple “timeline-ish” queries filter on that column (e.g. follow/like notifications, “what did this user like”, etc.).

## Detailed findings by feature

### 1) Home timeline (`Objects.list_home_statuses/2`)

**Code:** `lib/egregoros/objects.ex` (`list_home_statuses/2`)

**Query shape (simplified):**

- `FROM objects o`
- `WHERE o.type IN ('Note','Announce')`
- Exclude blocks/mutes: `o.actor NOT IN (subquery relationships where type IN ('Block','Mute'))`
- Include if:
  - `o.actor = viewer` **OR**
  - `o.actor IN (subquery relationships where type='Follow' and actor=viewer)` **OR**
  - object addressed to viewer via JSONB `@>` checks (`to`/`cc`/`bto`/`bcc`/`audience`)
- Extra visibility predicate: allows public, direct-to-viewer, and “followers” addressing using `jsonb_exists((data->'to'/'cc'), (o.actor || '/followers'))`

**Why this can be slow in edge cases:**

- The query is **ordered by newest `id` with a small `LIMIT`**, but the filter can be extremely selective depending on the viewer:
  - If the viewer follows nobody and has no mentions, there may be **0 matches**, forcing the DB to keep scanning down the index until it can conclude “no rows”.
  - If the viewer follows only dormant actors, the DB may need to scan back to **very old IDs** to find enough matches (or any), doing lots of work even though the result set is empty/small.
- The “followers visibility” check uses a **row-dependent value** (`o.actor || '/followers'`). This is not a constant RHS and is generally **hard for a GIN index to accelerate**, so it tends to be CPU-heavy evaluation per candidate row.

**Suggested improvements (validate with EXPLAIN first):**

- **Short-circuit for empty follow graph**: if the viewer follows nobody, use a much cheaper query (e.g. “my own posts + direct-to-me mentions”) instead of scanning the entire status space.
  - This directly targets the “new user on an established instance” case.
- **Split home feed into separate sources and merge**:
  - Source A: statuses by `viewer` + followed actors (actor-driven, index-friendly)
  - Source B: direct mentions to viewer (recipient-driven, GIN-friendly)
  - Merge in-memory (or with `UNION ALL` + outer `ORDER BY/LIMIT`).
  - This reduces “scan the world until you find a match” behavior.
- **Materialize home timelines (bigger change)**:
  - Fan-out on write to a `timeline_entries(user_ap_id, object_id)` table (or similar) so reads are `WHERE user_ap_id = ? ORDER BY object_id DESC LIMIT ?`.
  - This is the canonical fix for “sparse follow graph” scan amplification.
- **Normalize / denormalize visibility**:
  - Consider storing a computed `visibility` column (`public|unlisted|followers|direct`) so visibility predicates avoid multiple JSONB checks.
  - For replies/mentions, consider a recipients join table if you want fast “addressed to X” queries at scale.

**Reference (upstream Pleroma):**

- Upstream builds home timeline based on an explicit list of followed actor IDs (`[user.ap_id | User.following(user)]`) and passes it into a bounded query (`ActivityPub.fetch_activities/2`). This is more “actor-driven” than “scan recent statuses and filter” and tends to behave better for sparse timelines.

### 2) Public/local timelines (`Objects.list_public_statuses/1`)

**Code:** `lib/egregoros/objects.ex` (`list_public_statuses/1`)

**What’s good:**

- `type IN ('Note','Announce')` + `ORDER BY id DESC LIMIT` is a good fit for `(type, id)` and the primary key.
- `where_publicly_listed` uses JSONB `@>` checks that should benefit from `objects_status_data_path_ops_index`.

**Potential hotspots:**

- **`only_media` filter** uses `jsonb_array_length`/`jsonb_typeof` checks on `attachment` for both notes and reblogs.
  - These are typically **not index-friendly**, so the DB may have to evaluate JSON functions across many candidate rows.

**Suggested improvements:**

- Denormalize “has media” onto the row (boolean or integer attachment count) and index it.
  - Or add a functional index if you’re confident in the JSON shape, but maintaining a column tends to be simpler and cheaper.
- Consider a separate “attachments” table if media is a major feature and needs more querying.

### 3) Tag timelines (`Objects.list_public_statuses_by_hashtag/2`, `Objects.list_notes_by_hashtag/2`)

**Code:** `lib/egregoros/objects.ex` (`list_public_statuses_by_hashtag/2`, `list_notes_by_hashtag/2`, helpers `where_hashtag_tag*`)

**Potential issue: hashtag predicate shape likely prevents index usage**

The current hashtag filter uses:

- `coalesce(data->'tag', '[]'::jsonb) @> [%{"type"=>"Hashtag","name"=>"#tag"}]`

Because this is an expression over `data->'tag'` rather than a containment test on `data` itself, Postgres may **not** use `objects_status_data_path_ops_index` (which indexes `data`).

**Suggested improvements:**

- Prefer rewriting to a form that can use the existing GIN index, e.g.:
  - `data @> %{"tag" => [%{"type" => "Hashtag", "name" => "#tag"}]}`
- If you keep the `data->'tag'` expression, consider a dedicated functional GIN index on that expression (with a partial `WHERE type IN (...)`), but validate bloat/benefit.
- For high-scale hashtag discovery, consider a normalized hashtag join table (object_ap_id ↔ hashtag).

### 4) Profile timeline (`Objects.list_visible_statuses_by_actor/3`)

**Code:** `lib/egregoros/objects.ex` (`list_visible_statuses_by_actor/3`)

**What’s good:**

- Primary filter is `actor = ?` with `type IN (...)` and `ORDER BY id DESC LIMIT`, which should fit `(actor, type, id)` well.

**Potential hotspot:**

- Viewer visibility is decided via a runtime `Relationships.get_by_type_actor_object("Follow", viewer, actor)` check, then adds JSONB predicates for public/followers collection.
  - This is only 1 extra query per request and is likely fine.

### 5) Replies count (`Objects.count_note_replies_by_parent_ap_ids/1`)

**Code:** `lib/egregoros/objects.ex` (`count_note_replies_by_parent_ap_ids/1`)

**Why this is likely expensive:**

- It groups by `coalesce(data->>'inReplyTo', data->'inReplyTo'->>'id')` and filters by `... IN ^parent_ap_ids`.
- Without a functional index on that expression (or a normalized column), this can easily become:
  - “scan a large fraction of notes and compute an expression for each row”

This function is used by `StatusRenderer` to provide Mastodon’s `replies_count`, so it can run on every timeline page load for API clients.

**Suggested improvements (in increasing scope):**

- Add a **dedicated column** for the parent AP id (e.g. `in_reply_to_ap_id`) and index it; write-time parse fills it.
- Or add a **functional index** matching the current `coalesce(...)` expression.
- Or denormalize **reply counts** onto the parent object.

**Reference (upstream Pleroma):**

- Upstream stores `repliesCount` on the object and increments/decrements it on create/delete side effects. This avoids “count replies on read” entirely.

### 6) Status context (thread ancestors/descendants)

**Code:** `lib/egregoros/objects.ex` (`thread_ancestors/2`, `thread_descendants/2`, `list_replies_to/2`)

**Why it can be slow:**

- `thread_ancestors/2` calls `get_by_ap_id/1` repeatedly (up to `limit`, default 50): **N queries** in the worst case.
- `thread_descendants/2` recursively calls `list_replies_to/2` for each visited node: can become **O(nodes)** queries.
- `list_replies_to/2` filters by `fragment("?->>'inReplyTo' = ?", data, ^ap_id)` which likely has **no supporting index**.

**Suggested improvements:**

- Use a **recursive CTE** to fetch ancestors/descendants in a single DB query.
- Store a normalized `in_reply_to_ap_id` column + index and use that in thread traversal queries.
- If threads are a primary UX surface, consider a materialized thread index / closure table.

### 7) Notifications feed (`Notifications.list_for_user/2`) + rendering

**Query code:** `lib/egregoros/notifications.ex` (`list_for_user/2`)

**Rendering code:** `lib/egregoros_web/mastodon_api/notification_renderer.ex`

**Potential query issues:**

- The predicate is a large OR across:
  - follows to the user (`type='Follow' and object=user_ap_id`)
  - interactions on any of the user’s notes (`object IN subquery(note_ap_ids)`)
  - mentions (`Note` with `to`/`cc` containing user ap id)
- There is no index on `objects.object`, so both follow and interaction branches may be forced into less efficient plans as data grows.

**Rendering issues (likely larger than the base query):**

- `NotificationRenderer` does per-notification:
  - `Users.get_by_ap_id(activity.actor)` (per-row)
  - For Like/Announce: `Objects.get_by_ap_id(activity.object)` (per-row)
  - Then calls `StatusRenderer.render_status(status, current_user)` per notification.
    - `StatusRenderer.render_status/2` builds a full rendering context each time, which triggers multiple DB queries.

**Suggested improvements:**

- Add an index on `objects.object` (and potentially `(type, object, id)`) to support notifications patterns.
- Batch render notifications:
  - Fetch all needed accounts in one `Users.list_by_ap_ids/1`
  - Fetch all needed statuses in one `Objects.list_by_ap_ids/1`
  - Call `StatusRenderer.render_statuses/2` once for the batch.

### 8) LiveView timelines are currently N+1 heavy

**Code:** `lib/egregoros_web/view_models/status.ex`, `lib/egregoros_web/view_models/actor.ex`

`StatusVM.decorate_many/2` is used in multiple LiveViews (timeline, profile, tag, bookmarks, …). It currently does per-object queries:

- counts: `Relationships.count_by_type_object/2` twice per status (likes + announces)
- viewer flags: `Relationships.get_by_type_actor_object/3` up to 3 times per status (like/reblog/bookmark)
- emoji: `Relationships.emoji_reaction_counts/1` per status, plus relationship lookups per emoji to compute `reacted?`
- actors: `Actor.card/1` calls `Users.get_by_ap_id/1` per actor
- reblogs: can call `Objects.get_by_ap_id/1` (though `decorate_many/2` does batch for reblogs)

Even with a small page size, this can easily mean **dozens to hundreds of DB round trips** per page load.

**Suggested improvements:**

- Create a batch “status rendering context” for LiveView similar to `MastodonAPI.StatusRenderer.rendering_context/2`:
  - bulk fetch actors (users)
  - bulk fetch relationship counts
  - bulk fetch viewer relationships
  - bulk fetch emoji counts + viewer emoji reactions
  - then map over the objects with the precomputed context

There are already helper functions that make this easier (e.g. `Relationships.count_by_types_objects/2`, `Relationships.list_by_types_actor_objects/3`, `Relationships.emoji_reaction_counts_for_objects/1`, `Relationships.emoji_reactions_by_actor_for_objects/2`, `Users.list_by_ap_ids/1`).

## Related list endpoints (not strictly “timelines”, but similar scaling risks)

- `lib/egregoros_web/controllers/mastodon_api/accounts_controller.ex` (`followers/2`, `following/2`)
  - Builds a (potentially large) list of follow relationships, then calls `Users.get_by_ap_id/1` per row (classic N+1).
  - Likely fine for small accounts, but will degrade quickly for accounts with large follower/following counts.
- `lib/egregoros_web/controllers/mastodon_api/statuses_controller.ex` (`favourited_by/2`, `reblogged_by/2`)
  - Loads relationships, then renders actor accounts per row (often implies per-row user lookup).
  - Should be batchable with `Users.list_by_ap_ids/1`.

## Edge-case scenarios called out in the request

### A) “New user who doesn’t follow anyone”

There are two materially different cases:

1. **New user on a new/empty DB**: most queries are fast because there are few rows to scan.
2. **New user on an existing DB**: this is the risky one.

In case (2), `list_home_statuses/2` can be forced into scanning many status rows to discover there are no matches (no follows, no mentions). This is a classic “sparse home feed” performance trap.

### B) “User who only follows people who haven’t posted for 2 years”

If followed accounts are inactive, the newest matching status might be very old (or none exist). A “newest-first with limit” query can end up scanning back a long way to find the first match. Without a precomputed timeline table or a more actor-driven approach, this can become expensive at scale.

## Concrete next steps to validate/measure (no code changes)

1. Use `EXPLAIN (ANALYZE, BUFFERS)` on the SQL generated for:
   - home timeline for (a) no follows, (b) dormant follows
   - hashtag timeline with a rarely-used tag
   - public timeline with `only_media=true`
   - `count_note_replies_by_parent_ap_ids/1` with ~20 parent IDs on a large notes table
2. Extend `lib/egregoros/bench/suite.ex` with benchmark cases that simulate the edge cases above (especially “no follows on big DB”), so regressions are visible.

## Remediation plan (phased)

This is a suggested **implementation order** that tends to produce the biggest wins earliest while keeping risk manageable. The key idea is: **measure first**, then reduce query count, then make the remaining heavy queries index-friendly, and only then consider materializing.

### Phase 0 — Measure + define budgets

- Define target budgets per endpoint/surface (e.g. p95 DB time, max Ecto query count per request/page, max rows scanned).
- Capture baseline `EXPLAIN (ANALYZE, BUFFERS)` for the edge cases called out in the request:
  - Home timeline: (a) no follows on a large DB, (b) only dormant follows
  - Hashtag timeline with a rare tag
  - Public timeline with `only_media=true`
  - `count_note_replies_by_parent_ap_ids/1` on a page-sized set of parent IDs
- Add micro-bench cases in `lib/egregoros/bench/suite.ex` for these scenarios so improvements are measurable and regressions visible.

### Phase 1 — Remove N+1 / per-item DB work (high ROI, low risk)

Most “timeline latency” issues become irrelevant once you stop doing dozens/hundreds of DB round trips per page.

- **LiveView feeds:** refactor `EgregorosWeb.ViewModels.Status.decorate_many/2` to compute a single batch “context”:
  - bulk users by actor ap_id (`Users.list_by_ap_ids/1`)
  - bulk counts (likes/reblogs) using `Relationships.count_by_types_objects/2`
  - bulk viewer relationships (like/reblog/bookmark) using `Relationships.list_by_types_actor_objects/3`
  - bulk emoji counts using `Relationships.emoji_reaction_counts_for_objects/1`
  - bulk viewer emoji reactions using `Relationships.emoji_reactions_by_actor_for_objects/2`
  - then map objects → view-model using the context (no per-item DB calls)
- **Notifications API:** change rendering to batch-load actors + target statuses for the page, then call `StatusRenderer.render_statuses/2` once for the batch (avoid per-notification `render_status/2`).
- **List endpoints (followers/following/favourited_by/reblogged_by):** batch `Users.list_by_ap_ids/1` instead of per-row `Users.get_by_ap_id/1`.

Success criteria:
- “Page load DB query count” becomes ~O(1) relative to page size.
- Overall response time becomes dominated by a small number of meaningful queries.

### Phase 2 — Make timeline queries index-friendly

- **Add missing index support for `objects.object`:**
  - Add an index on `objects.object` and likely a composite like `(type, object, id)` to match notifications + “activity references object” patterns.
- **Rewrite hashtag filter to use the existing `data` GIN index:**
  - Prefer `data @> %{"tag" => [...]} ` over `coalesce(data->'tag', ...) @> ...` so `objects_status_data_path_ops_index` can be used.
- **Home timeline query: split the “big OR” into separate branches and merge:**
  - Branch A: actor-driven feed (self + followed actors) using `(actor,type,id)`
  - Branch B: “addressed to me” feed using JSONB `@>` (GIN-friendly)
  - Merge with `UNION ALL` + outer `ORDER BY id DESC LIMIT ?`.
  - **Short-circuit:** if the viewer follows nobody, skip Branch A entirely (directly fixes “new user on existing DB” worst case).

Success criteria:
- “No follows” and “dormant follows” stop scanning large ID ranges to return empty/small results.
- Hashtag timelines stop devolving into expression scans.

### Phase 3 — Stop “counting/graph-walking on read”

- **Replies count (`replies_count`)**
  - Best: store `replies_count` on the parent object and update it on create/delete side-effects (upstream Pleroma does this via `repliesCount`).
  - Next best: store `in_reply_to_ap_id` as a column + index it; count/group on the column (avoid `coalesce(...)` expression scans).
- **Thread context (ancestors/descendants)**
  - With `in_reply_to_ap_id`, fetch via a recursive CTE in one query rather than N queries.

Success criteria:
- `replies_count` and status context become stable-cost as the DB grows.

### Phase 4 — Materialized home timeline (derived cache)

Only consider this if Phase 1–3 still leaves home timeline too slow at your expected scale. Treat it as a **derived cache that can be rebuilt**, not the only source of truth.

#### 4.1 Core requirements

- **Blocks/mutes** must remove content from the viewer’s feed promptly.
- **Follows** must cause older posts to appear (at least within some bounded window).
- **Deletes/visibility changes** must be reflected (no “ghost” posts).
- Avoid “O(followers)” synchronous fan-out in the request path: use Oban jobs and backpressure.

#### 4.2 Data model (suggestion)

Create a `timeline_entries` table for local viewers:

- Columns (illustrative):
  - `user_id` (viewer; FK users)
  - `object_id` (status/announce object; FK objects; ideally `ON DELETE CASCADE`)
  - `entry_actor_ap_id` (the actor who created the timeline entry; for an Announce, this is the booster)
  - `subject_actor_ap_id` (the “content author”; for Announce, the original object’s actor; for Note, same as entry_actor)
  - `sources` (bitmask/array of reasons, e.g. `follow`, `mention`, `self`), enabling selective removal
- Constraints/indexes:
  - `UNIQUE(user_id, object_id)` so multiple sources merge
  - `(user_id, object_id DESC)` for reads
  - `(user_id, entry_actor_ap_id)` and `(user_id, subject_actor_ap_id)` for block/unfollow cleanup

The explicit `sources` field is what makes “unfollow removes only follow-sourced entries” and “mentions remain” feasible without full rebuild.

#### 4.3 Write/update rules (how to handle follow/block/delete concerns)

- **On new Note/Announce**
  - Determine candidate recipients (followers of the author, explicit recipients, self).
  - Exclude recipients who block/mute the author (and optionally exclude if recipient is blocked by author depending on desired semantics).
  - Upsert into `timeline_entries` with the right `sources`.
- **On follow(viewer → actor)**
  - Schedule an Oban backfill job that inserts *older* statuses from the followed actor into the viewer’s `timeline_entries`.
  - Bound it (e.g. “last N statuses” or “last X days”), and optionally extend on-demand when the viewer scrolls further back (lazy backfill).
- **On unfollow(viewer → actor)**
  - Remove the `follow` source for entries whose `subject_actor_ap_id == actor` (and/or `entry_actor_ap_id == actor` depending on your semantics).
  - Delete rows whose `sources` becomes empty.
- **On block/mute(viewer ↔ actor)**
  - Delete entries where `entry_actor_ap_id == actor` (so you stop seeing their own posts and boosts).
  - Decide semantics for “someone I follow boosted a blocked user”:
    - If you want to hide it (typical), also delete rows where `subject_actor_ap_id == actor`.
  - Ensure future fan-out excludes blocked actors (but keep a read-time safety net).
- **On delete(object)**
  - If objects are hard-deleted: `ON DELETE CASCADE` handles removal of timeline entries.
  - If tombstoned: run a cleanup job keyed by `object_id`.
- **On visibility/recipient change**
  - Recompute membership for that `object_id`: delete its existing entries and repopulate (jobbed).

#### 4.4 Read strategy (cache + correctness)

- Read from `timeline_entries` for the primary “home” path.
- If `timeline_entries` cannot fill a page (e.g. initial backfill still running), fall back to the dynamic query (Phase 2 shape) and optionally “warm” the cache with returned results.
- Keep a read-time safety filter for blocks/mutes to avoid privacy bugs if the cache lags (defense-in-depth).

#### 4.5 Rollout and validation

- Gate behind a feature flag and dual-run in staging: compare “materialized result IDs” vs “dynamic result IDs” for sampled users.
- Add targeted tests for:
  - follow triggers backfill (older posts appear)
  - unfollow removes follow-sourced posts but keeps mentions
  - block removes posts/boosts per chosen semantics
  - delete removes entries
  - visibility change reconciles membership
