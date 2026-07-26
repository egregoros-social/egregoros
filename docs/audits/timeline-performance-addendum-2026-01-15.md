# Performance Audit Addendum (2026-01-15)

This addendum supplements the main performance audit with additional observations and considerations. The original audit is solid and correctly identifies the key issues. These notes cover adjacent concerns and alternative approaches.

## General Assessment

The audit is accurate in its core findings:
- Home timeline scan amplification for sparse follow graphs is a real and well-documented issue in ActivityPub implementations
- N+1 patterns in rendering layers are correctly identified as the likely dominant latency source
- The GIN index usage concerns for hashtag/media filters are valid Postgres JSONB behavior
- The phased remediation plan is sensibly ordered (batch first, index second, materialize last)

## Additional Considerations

### 1) Connection Pool and Concurrency

The audit focuses on per-query efficiency but doesn't address aggregate load patterns:

- **Pool exhaustion**: With N+1 patterns, a spike in concurrent requests can exhaust the Ecto pool quickly. Even fast queries become slow when waiting for a connection.
- **Read replica routing**: Timeline reads are excellent candidates for replica routing since they tolerate slight staleness. This can offload the primary for writes.
- **Connection limits**: Postgres `max_connections` vs pool size vs concurrent request count. If the pool is sized for the N+1 pattern (e.g., 50 connections), fixing N+1 may allow a smaller pool.

### 2) Application-Level Caching

Before materializing timelines in the database, consider caching layers:

- **Actor/user cache**: `Users.get_by_ap_id/1` is called repeatedly; a short TTL ETS/Cachex cache can eliminate most lookups.
- **Relationship counts cache**: Like/reblog counts for popular posts change frequently but can tolerate staleness (10-60s TTL).
- **Hot post cache**: Viral posts that appear on many timelines can be cached fully rendered.

Trade-off: Caching adds invalidation complexity. The audit's batch-loading approach may be simpler and sufficient.

### 3) Pagination Edge Cases

The audit assumes keyset pagination works cleanly. Some nuances:

- **Keyset with filters**: When filtering (e.g., `only_media=true`), the cursor might point to an ID that doesn't match the filter, causing "holes" or unexpected gaps.
- **Deletion during pagination**: If posts are deleted between page loads, keyset pagination handles this gracefully (unlike offset), but the user may see fewer items than expected.
- **`max_id`/`since_id` with merged queries**: If home timeline is `UNION ALL` of multiple sources, the cursor applies to the merged result; ensure the outer query handles this consistently.

### 4) Materialized Timeline Write Amplification

Phase 4 addresses this but some specifics worth calling out:

- **Celebrity problem**: An account with 100k followers posting means 100k timeline inserts. At scale, this dominates write IO.
  - Mitigation: Only materialize for "small" accounts (< N followers); large accounts remain compute-on-read.
  - Mitigation: Hybrid approach where "recent posts from celebrities" is a separate hot cache merged at read time.
- **Backfill storms**: When a user follows a prolific account, backfilling "last N posts" can create write spikes.
  - Mitigation: Rate-limit backfill jobs; accept that old posts appear gradually.
  - Mitigation: Lazy backfill only when the user actually scrolls back.

### 5) Real-Time Streaming Interaction

If WebSocket/SSE streaming is implemented:

- **Dual path**: New posts must both fan-out to streaming subscribers AND write to materialized timelines. Ensure these are consistent.
- **Streaming can bypass N+1**: If streaming pushes fully-rendered statuses, the rendering happens once per post rather than once per viewer. This is a form of "push on write" that complements materialized timelines.

### 6) GIN Index Maintenance Costs

The audit recommends GIN indexes for several patterns. Worth noting:

- **Write overhead**: GIN indexes on JSONB are expensive to maintain on high-write tables. Each insert/update must update the index.
- **fastupdate**: Postgres GIN indexes have `fastupdate` which batches index updates, trading read latency for write throughput. May need tuning.
- **Partial indexes**: The existing `objects_status_data_path_ops_index` already uses `WHERE type IN ('Note', 'Announce')`. This is good; extend this pattern to other GIN indexes.

### 7) Table Partitioning for `objects`

If the objects table grows very large (tens of millions of rows):

- **Time-based partitioning**: Partition by `published` date (monthly or yearly). Old partitions can be on slower storage; recent partitions stay hot.
- **Query benefits**: `ORDER BY id DESC LIMIT N` queries naturally hit only recent partitions.
- **Maintenance benefits**: Dropping old partitions is instant vs. deleting rows.

Trade-off: Adds operational complexity. Only consider at significant scale.

### 8) Alternative to Materialized Timelines: Actor Inbox Model

An alternative architecture used by some implementations:

- Each actor has a logical "inbox" of activities addressed to them (or their followers collection)
- Home timeline = merge inboxes of (self + followed actors), sorted by timestamp
- No fan-out on write; compute on read but bounded by "N recent items per inbox"

Trade-offs:
- Simpler write path (no fan-out jobs)
- Read cost grows with number of follows (but bounded)
- Doesn't handle "addressed to followers collection of X" mentions as cleanly

### 9) Denormalization Consistency

The audit suggests several denormalizations (visibility column, in_reply_to_ap_id, replies_count, has_media flag). Each requires:

- **Migration plan**: Backfilling existing data, possibly in batches to avoid locking.
- **Write-path updates**: Every code path that creates/updates objects must maintain the denormalized fields.
- **Consistency checks**: Periodic jobs to detect and repair drift between computed and denormalized values.
- **Testing**: Property-based tests that verify denormalized values match computed values.

### 10) Observability Recommendations

To validate fixes and catch regressions:

- **Slow query logging**: Set `log_min_duration_statement` to capture queries above a threshold (e.g., 100ms).
- **Query tagging**: Use Ecto's `Repo.put_query_metadata` or similar to tag queries by endpoint/feature for APM grouping.
- **Telemetry events**: The audit mentions `bench/suite.ex`; also consider runtime telemetry (e.g., `:telemetry.span` around timeline queries) for production monitoring.
- **Baseline captures**: Before optimizing, capture `EXPLAIN ANALYZE` outputs for the key queries. Store these for comparison.

### 11) Thread Context Alternative: Conversation ID

For thread traversal, an alternative to recursive CTEs:

- Store a `conversation_id` on each object (the root object's AP ID, or a generated UUID for the thread)
- Thread query becomes: `WHERE conversation_id = ? ORDER BY published`
- Ancestors/descendants are determined by comparing `in_reply_to_ap_id` chains in application code (or store depth)

Upstream Pleroma uses a `context` field for this purpose. This can make thread queries index-friendly with a simple B-tree index on `(conversation_id, published)`.

### 12) Soft Delete Handling

If objects support soft deletion (tombstoning):

- **Index implications**: Queries need `WHERE deleted_at IS NULL` or equivalent. Indexes should be partial to exclude deleted rows.
- **Timeline cleanup**: Soft-deleted posts must be filtered from timelines. If materialized, entries need cleanup jobs.
- **Tombstone federation**: ActivityPub Delete activities should clean up materialized timeline entries the same as hard deletes.

### 13) JSONB Statistics and Query Planning

Postgres query planner statistics for JSONB columns are often poor by default:

- **Extended statistics**: Consider `CREATE STATISTICS` for frequently filtered JSONB paths.
- **Functional indexes**: A functional index on `(data->>'inReplyTo')` will collect statistics on that extracted value, improving plans.
- **`default_statistics_target`**: Increase for large tables to give the planner better cardinality estimates.

## Priority Recommendations

Based on the original audit plus these additions, a suggested priority order:

1. **Batch loading in renderers** (Phase 1) — Highest ROI, fixes the dominant latency source
2. **Add `objects.object` index** — Low effort, immediate win for notifications
3. **Rewrite hashtag filter for GIN usage** — Low effort if the fix is as simple as changing the predicate shape
4. **Application-level user cache** — Low complexity, reduces load even after batch loading
5. **Denormalize `in_reply_to_ap_id`** — Enables efficient thread queries and replies count
6. **Home timeline query restructuring** (UNION approach) — Medium effort, fixes edge cases
7. **Consider materialized timelines** — Only if the above is insufficient

## Closing Notes

The original audit is well-researched and the phased approach is sound. The key insight — that N+1 rendering likely dominates over base query inefficiency — means Phase 1 batching work should be prioritized even before diving into `EXPLAIN ANALYZE` on the timeline queries. Once rendering is batched, the actual query performance becomes measurable in isolation.

The materialized timeline (Phase 4) is a significant architectural change. The audit's framing as a "derived cache that can be rebuilt" is correct and important — it should supplement, not replace, the ability to compute timelines dynamically.
