# Test Suite Audit Plan

This document is a working plan + checklist for reviewing Egregoros’ test suite.

Goals:
- Ensure tests verify the **behaviors we actually care about** (security/privacy invariants, federation correctness, Mastodon/Pleroma API compatibility, UI correctness).
- Reduce **brittleness** (tests that fail for incidental HTML changes, timing, global config, or process ordering).
- Reduce **uneconomical tests** (slow integration tests where a smaller unit test would suffice).
- Identify and fill **coverage gaps** in critical areas (authz, privacy/DMs, signature verification, ingestion, delivery).

Non-goals:
- Chasing arbitrary “100% coverage”.
- Rewriting tests purely for style if they’re already stable and meaningful.

## Baseline (current state)

- `mix test --cover` (2026-01-12): `1345` tests, `0` failures, **85.01%** total coverage (threshold `85%`).
- “Smell” checks:
  - No `Process.sleep/1` / `:timer.sleep/1` occurrences in `test/`.
  - No `Application.put_env/delete_env` occurrences in `test/`.
- Lowest-coverage modules worth targeting early (high ROI for coverage gate):
  - `EgregorosWeb.ErrorHTML` (50% — generated code; low ROI unless needed)
  - `Egregoros.Release` (~55%)
  - `Egregoros.Federation.ActorDiscovery` (~66%)
- Known test-suite noise:
  - Occasional `Postgrex.Protocol disconnected` log spam during suite/precommit runs (likely a process escaping the SQL sandbox owner lifetime).

## Review Criteria (per test / per file)

For each test file, answer:
1. **Intent:** What user-facing or security-critical behavior is this validating?
2. **Signal:** Does it fail for the right reasons? (Good assertions, not incidental output.)
3. **Determinism:** Does it avoid time dependence, global env changes, ordering dependence?
4. **Scope:** Is the level (unit vs integration vs LiveView) appropriate?
5. **Redundancy:** Is it duplicating coverage elsewhere? If yes, can we delete or merge?
6. **Cost:** Is it disproportionately slow? Can we use Mox / a unit boundary instead?

## Automated “Smell” Checks (always on)

These should converge to **zero occurrences**:
- `Process.sleep/1` or `:timer.sleep/1` in tests.
- Global config mutation in tests (`Application.put_env/delete_env`) where a process-local override would do.
- Tests with no meaningful assertions (`assert true`, “smoke tests” without verifying effects).
- Flaky waiting patterns (polling, sleeping) instead of deterministic synchronization.

## Workflow

1. **Inventory & metrics**
   - Count tests per file; locate the heaviest/slowest files.
   - Use `mix test --cover` to find low-coverage modules that matter.
2. **Mechanical cleanup**
   - Replace sleeps with deterministic state manipulation or process synchronization.
   - Introduce/configure a process-local runtime config override (so tests can stay async).
3. **Semantic review**
   - Go file-by-file, tagging each as:
     - ✅ keep
     - 🛠 refactor (brittle/slow)
     - 🧪 add coverage (missing cases)
     - 🗑 remove (redundant / nonsensical)
4. **Guardrails**
   - Prefer boundaries + Mox for “future” behaviors.
   - Keep commits small and semantically scoped (one refactor or one coverage area per commit).

## Checklist (test files)

Mark each file after review:
- [x] test/egregoros/activities/accept_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/announce_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/builders_test.exs (✅ keep)
- [x] test/egregoros/activities/create_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/delete_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/delete_side_effects_test.exs (✅ keep)
- [x] test/egregoros/activities/emoji_react_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/follow_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/helpers_test.exs (✅ keep)
- [x] test/egregoros/activities/like_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/move_ingest_test.exs (✅ keep)
- [x] test/egregoros/activities/note_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/undo_authorization_test.exs (✅ keep)
- [x] test/egregoros/activities/undo_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/update_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/activities/update_ingest_test.exs (✅ keep)
- [x] test/egregoros/activities/update_note_ingest_test.exs (✅ keep)
- [x] test/egregoros/activities/update_side_effects_test.exs (✅ keep)
- [x] test/egregoros/activity_pub/object_validators/types_test.exs (✅ keep; good type contract coverage)
- [x] test/egregoros/auth/bearer_token_test.exs (✅ keep; ensures bearer auth correctness)
- [x] test/egregoros/auth/default_test.exs (✅ keep; stubbed local auth contract)
- [x] test/egregoros/authz/oauth_scopes_test.exs (✅ keep; scope enforcement)
- [x] test/egregoros/avatar_storage/local_test.exs (✅ keep)
- [x] test/egregoros/banner_storage/local_test.exs (✅ keep)
- [x] test/egregoros/bench/runner_test.exs (✅ keep)
- [x] test/egregoros/bench/seed_test.exs (✅ keep; guards Postgres param chunking)
- [x] test/egregoros/bench/stats_test.exs (✅ keep)
- [x] test/egregoros/bench/suite_test.exs (✅ keep)
- [x] test/egregoros/cbor_test.exs (✅ keep; codec invariants + failure cases)
- [x] test/egregoros/compat/upstream_fixtures_test.exs (✅ keep; real-world fixture ingestion)
- [x] test/egregoros/custom_emojis_test.exs (✅ keep; SSRF/XSS hardening)
- [x] test/egregoros/deployment_test.exs (✅ keep; env-driven admin bootstrap)
- [x] test/egregoros/direct_messages_test.exs (✅ keep; privacy-critical DM scoping)
- [x] test/egregoros/discovery/implementations_test.exs (✅ keep)
- [x] test/egregoros/discovery_test.exs (✅ keep; delegates via Mox)
- [x] test/egregoros/dns/cached_test.exs (✅ keep; cache TTL behavior)
- [x] test/egregoros/dns/inet_test.exs (✅ keep)
- [x] test/egregoros/federation/actor_discovery_test.exs (✅ keep)
- [x] test/egregoros/federation/actor_test.exs (✅ keep; strong SSRF/signed-fetch edge coverage)
- [x] test/egregoros/federation/announce_object_fetch_test.exs (✅ keep)
- [x] test/egregoros/federation/delivery_test.exs (✅ keep)
- [x] test/egregoros/federation/fetch_thread_ancestors_test.exs (✅ keep)
- [x] test/egregoros/federation/follow_flow_test.exs (✅ keep)
- [x] test/egregoros/federation/follow_remote_async_test.exs (✅ keep)
- [x] test/egregoros/federation/incoming_follow_accept_test.exs (✅ keep; includes locked account flow)
- [x] test/egregoros/federation/incoming_follow_reject_test.exs (✅ keep)
- [x] test/egregoros/federation/incoming_undo_follow_test.exs (✅ keep)
- [x] test/egregoros/federation/like_object_fetch_test.exs (✅ keep)
- [x] test/egregoros/federation/outgoing_delivery_test.exs (✅ keep; broad outgoing activity coverage)
- [x] test/egregoros/federation/signed_fetch_test.exs (✅ keep)
- [x] test/egregoros/federation/thread_fetch_test.exs (✅ keep)
- [x] test/egregoros/federation/thread_replies_fetch_test.exs (✅ keep)
- [x] test/egregoros/federation/webfinger_test.exs (✅ keep)
- [x] test/egregoros/follow_requests_test.exs (✅ keep; locked + remote follow request semantics)
- [x] test/egregoros/html_test.exs (🛠 keep; some markup/class assertions may be over-specific)
- [x] test/egregoros/http/req_test.exs (🛠 keep; consider `async: false` if Req stub is global)
- [x] test/egregoros/http/stub_test.exs (✅ keep)
- [x] test/egregoros/http_date_test.exs (✅ keep)
- [x] test/egregoros/http_test.exs (✅ keep; delegates via Mox)
- [x] test/egregoros/instance_settings_test.exs (🧪 add coverage; invalid inputs + initial insert branches)
- [x] test/egregoros/interactions_test.exs (✅ keep; authorization guard)
- [x] test/egregoros/keys_test.exs (✅ keep)
- [x] test/egregoros/maintenance/refetch_remote_actors_test.exs (✅ keep; operational tooling correctness)
- [x] test/egregoros/media_storage/local_test.exs (✅ keep; ensures thumbnails generated)
- [x] test/egregoros/mentions_test.exs (✅ keep; mention parsing edge cases)
- [x] test/egregoros/notifications_pubsub_test.exs (✅ keep; pubsub delivery)
- [x] test/egregoros/notifications_test.exs (✅ keep; types + pagination)
- [x] test/egregoros/oauth/scopes_authorization_test.exs (✅ keep)
- [x] test/egregoros/oauth/token_schema_test.exs (✅ keep)
- [x] test/egregoros/oauth_test.exs (✅ keep; broad OAuth grant coverage)
- [x] test/egregoros/objects_test.exs (✅ keep; core DB/query invariants incl. privacy)
- [x] test/egregoros/passkeys/webauthn_test.exs (✅ keep; WebAuthn parsing/verification)
- [x] test/egregoros/performance_regressions_test.exs (🛠 keep; performance guardrails are intentionally strict)
- [x] test/egregoros/pipeline_cast_and_validate_test.exs (✅ keep)
- [x] test/egregoros/pipeline_test.exs (✅ keep; ingestion rules incl. relay edge cases)
- [x] test/egregoros/publish_test.exs (✅ keep; publish rules + mention delivery)
- [x] test/egregoros/rate_limiter/ets_test.exs
- [x] test/egregoros/relationship_schema_test.exs (✅ keep)
- [x] test/egregoros/relationships_test.exs (✅ keep; relationship uniqueness/state semantics)
- [x] test/egregoros/relays_test.exs (✅ keep; covers relay subscribe/unsubscribe paths)
- [x] test/egregoros/release_healthcheck_test.exs (✅ keep; deployment healthcheck behavior)
- [x] test/egregoros/runtime_config_test.exs
- [x] test/egregoros/safe_url_test.exs
- [x] test/egregoros/security/html_scrubber_security_test.exs (✅ keep; UI redress/XSS hardening)
- [x] test/egregoros/security/safe_url_no_dns_security_test.exs
- [x] test/egregoros/security/uploads_security_headers_test.exs (✅ keep; uploads headers)
- [x] test/egregoros/signature/http_actor_fetch_test.exs (✅ keep; actor fetch for signature verification)
- [x] test/egregoros/signature/http_test.exs (✅ keep; signature parsing + verification)
- [x] test/egregoros/timeline_pubsub_scoping_test.exs (✅ keep; privacy-scoped timeline topics)
- [x] test/egregoros/timeline_pubsub_test.exs (✅ keep; announce broadcast rules)
- [x] test/egregoros/timeline_test.exs (✅ keep)
- [x] test/egregoros/uploads_config_test.exs (✅ keep; prevents destructive test uploads)
- [x] test/egregoros/users_race_test.exs (✅ keep; concurrency safety)
- [x] test/egregoros/users_test.exs (✅ keep; user lifecycle + search behavior)
- [x] test/egregoros/workers/deliver_activity_test.exs (✅ keep)
- [x] test/egregoros/workers/deliver_to_actor_test.exs (✅ keep)
- [x] test/egregoros/workers/fetch_actor_test.exs (✅ keep)
- [x] test/egregoros/workers/follow_remote_test.exs
- [x] test/egregoros/workers/ingest_activity_test.exs (✅ keep)
- [x] test/egregoros/workers/resolve_mentions_test.exs
- [x] test/egregoros_web/body_reader_test.exs (✅ keep)
- [x] test/egregoros_web/components/app_shell_test.exs (✅ keep)
- [x] test/egregoros_web/components/core_components_test.exs (🛠 keep; consider reducing coupling to exact Tailwind classes)
- [x] test/egregoros_web/components/layouts_test.exs (✅ keep)
- [x] test/egregoros_web/components/media_viewer_test.exs (✅ keep; prevents z-index/CORS regressions)
- [x] test/egregoros_web/components/status_card_test.exs (🛠 keep; some styling assertions may be brittle)
- [x] test/egregoros_web/controllers/actor_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/admin/live_dashboard_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/admin_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/e2ee_routes_removed_test.exs (✅ keep; guards that the E2EE endpoints stay gone)
- [x] test/egregoros_web/controllers/error_html_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/error_json_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/follow_collection_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/health_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/inbox_controller_test.exs (🛠 keep; consider table-driven refactor for repeated not_targeted cases)
- [x] test/egregoros_web/controllers/mastodon_api/accounts_controller_test.exs (✅ keep; broad API compatibility incl. follow request semantics + privacy)
- [x] test/egregoros_web/controllers/mastodon_api/announcements_controller_test.exs (✅ keep; placeholder endpoints required by clients)
- [x] test/egregoros_web/controllers/mastodon_api/apps_controller_test.exs (✅ keep; OAuth app registration)
- [x] test/egregoros_web/controllers/mastodon_api/blocks_mutes_controller_test.exs (✅ keep; relationship list endpoints)
- [x] test/egregoros_web/controllers/mastodon_api/conversations_controller_test.exs (✅ keep; placeholder (returns []) expected by clients)
- [x] test/egregoros_web/controllers/mastodon_api/custom_emojis_controller_test.exs (✅ keep; ensures endpoint exists and returns a list)
- [x] test/egregoros_web/controllers/mastodon_api/empty_list_endpoints_test.exs (✅ keep; compatibility endpoints return [])
- [x] test/egregoros_web/controllers/mastodon_api/favourites_and_bookmarks_controller_test.exs (✅ keep; list endpoints backed by relationships)
- [x] test/egregoros_web/controllers/mastodon_api/follow_requests_controller_test.exs (✅ keep; locked account follow-request flows)
- [x] test/egregoros_web/controllers/mastodon_api/follows_controller_test.exs (✅ keep; remote follow via WebFinger + delivery job)
- [x] test/egregoros_web/controllers/mastodon_api/instance_controller_test.exs (✅ keep; v1/v2 payload shapes + registrations toggle)
- [x] test/egregoros_web/controllers/mastodon_api/markers_controller_test.exs (✅ keep; markers get/set contract)
- [x] test/egregoros_web/controllers/mastodon_api/media_controller_test.exs (✅ keep; upload contract incl meta/blurhash)
- [x] test/egregoros_web/controllers/mastodon_api/notifications_controller_test.exs (✅ keep; types, include_types, pleroma-fe `is_seen` compat)
- [x] test/egregoros_web/controllers/mastodon_api/preferences_controller_test.exs (✅ keep; endpoint shape)
- [x] test/egregoros_web/controllers/mastodon_api/push_subscription_controller_test.exs (✅ keep; explicit unsupported behavior)
- [x] test/egregoros_web/controllers/mastodon_api/search_controller_test.exs (✅ keep; account/status search incl. privacy)
- [x] test/egregoros_web/controllers/mastodon_api/statuses_controller_test.exs (✅ keep; core Mastodon Status API; heavy but security/compat critical)
- [x] test/egregoros_web/controllers/mastodon_api/streaming_controller_test.exs (✅ keep; websocket upgrade + token auth)
- [x] test/egregoros_web/controllers/mastodon_api/tags_controller_test.exs (✅ keep; tag entity + history shapes)
- [x] test/egregoros_web/controllers/mastodon_api/timelines_controller_test.exs (✅ keep; public/home timeline semantics incl. privacy)
- [x] test/egregoros_web/controllers/mastodon_api/trends_controller_test.exs (✅ keep; trends endpoints + HTML-entity hashtag regression)
- [x] test/egregoros_web/controllers/nodeinfo_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/oauth_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/oban_dashboard_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/object_controller_test.exs (✅ keep; ActivityPub objects endpoint + privacy)
- [x] test/egregoros_web/controllers/outbox_controller_test.exs (✅ keep; ActivityPub outbox collection + privacy)
- [x] test/egregoros_web/controllers/page_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/passkeys_controller_test.exs (✅ keep; end-to-end passkey flow)
- [x] test/egregoros_web/controllers/pleroma_api/compat_endpoints_test.exs (✅ keep; pleroma-fe compatibility stubs)
- [x] test/egregoros_web/controllers/pleroma_api/emoji_reaction_controller_test.exs (✅ keep; emoji reactions + privacy/idempotence)
- [x] test/egregoros_web/controllers/poco_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/registration_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/session_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/settings_controller_test.exs (✅ keep)
- [x] test/egregoros_web/controllers/webfinger_controller_test.exs (✅ keep)
- [x] test/egregoros_web/cors_test.exs (✅ keep; cross-origin headers for API/nodeinfo/uploads)
- [x] test/egregoros_web/live/bookmarks_live_test.exs (✅ keep; validates reply modal UX + errors)
- [x] test/egregoros_web/live/favourites_live_test.exs (✅ keep; favourites list + unliking)
- [x] test/egregoros_web/live/messages_live_test.exs (✅ keep; validates compose + load-more + reply modal)
- [x] test/egregoros_web/live/notifications_live_test.exs (✅ keep; streaming, filters, follow requests, link targets)
- [x] test/egregoros_web/live/privacy_live_test.exs (✅ keep; block/mute management UI)
- [x] test/egregoros_web/live/profile_live_test.exs (✅ keep; profile UI incl. follow-request updates + remote counts)
- [x] test/egregoros_web/live/relationships_live_test.exs (✅ keep; followers/following lists + load-more + follow actions)
- [x] test/egregoros_web/live/search_live_test.exs (✅ keep; search UX incl remote follow, reply modal, attachments)
- [x] test/egregoros_web/live/status_live_test.exs (✅ keep; thread view + reply modal + fetch job UX)
- [x] test/egregoros_web/live/tag_live_test.exs (✅ keep; tag timeline UI and interactions)
- [x] test/egregoros_web/live/timeline_live_test.exs (✅ keep; core timeline + composer + privacy; heavy but high-value)
- [x] test/egregoros_web/mastodon_api/account_renderer_test.exs (✅ keep; renderer correctness + XSS hardening)
- [x] test/egregoros_web/mastodon_api/notification_renderer_test.exs (✅ keep; notification type mapping + fallbacks)
- [x] test/egregoros_web/mastodon_api/status_renderer_test.exs (✅ keep; status rendering + sanitization + media/mentions/tags)
- [x] test/egregoros_web/mastodon_api/streaming_socket_test.exs (✅ keep; streaming socket filtering + privacy rules)
- [x] test/egregoros_web/plugs/force_ssl_test.exs (✅ keep; proxy-aware SSL enforcement)
- [x] test/egregoros_web/plugs/rate_limit_inbox_test.exs (✅ keep; IP-based rate limiting even with Signature keyId)
- [x] test/egregoros_web/plugs/require_scopes_test.exs (✅ keep; authz boundary via Mox)
- [x] test/egregoros_web/plugs/session_cookie_domain_test.exs (✅ keep; runtime-configurable cookie domain)
- [x] test/egregoros_web/plugs/static_assets_test.exs (🛠 keep; temp filesystem setup + cleanup; ok but avoid cross-test collisions)
- [x] test/egregoros_web/plugs/uploads_access_test.exs (✅ keep; unguessable uploads serve without auth)
- [x] test/egregoros_web/plugs/uploads_dynamic_root_test.exs (✅ keep; runtime-configurable uploads dir)
- [x] test/egregoros_web/plugs/uploads_host_restriction_test.exs (✅ keep; uploads served only on uploads host)
- [x] test/egregoros_web/plugs/verify_signature_test.exs (🛠 keep; one test description contradicts expectation (rename for clarity))
- [x] test/egregoros_web/profile_paths_test.exs (✅ keep; canonical profile path derivation)
- [x] test/egregoros_web/safe_media_url_test.exs (✅ keep; SSRF prevention)
- [x] test/egregoros_web/time_test.exs (✅ keep; relative time formatting)
- [x] test/egregoros_web/url_uploads_base_url_test.exs (✅ keep; URL.absolute uses uploads base url)
- [x] test/egregoros_web/view_models/actor_test.exs (✅ keep; actor card normalization)
- [x] test/egregoros_web/view_models/status_test.exs (✅ keep; view-model decoration + safe attachments)
- [x] test/mix/tasks/egregoros_tasks_test.exs (✅ keep; mix tasks smoke coverage)
- [x] test/egregoros/user_events_test.exs (✅ keep; user event broadcasts)
- [x] test/egregoros/relationship_events_test.exs (✅ keep; relationship event broadcasts)
- [x] test/egregoros/timeline_functions_test.exs (✅ keep; timeline helper/broadcast coverage)
- [x] test/egregoros/workers/refresh_remote_user_counts_test.exs (✅ keep; worker contract coverage)
- [x] test/egregoros_web/error_html_render_test.exs (✅ keep; ErrorHTML rendering coverage)
- [x] test/egregoros_web/live/uploads_test.exs (✅ keep; uploads LiveView coverage)
- [x] test/egregoros_web/mastodon_api/fallback_test.exs (✅ keep; fallback username parsing coverage)
- [x] test/egregoros_web/param_test.exs (✅ keep; param parsing coverage)
- [x] test/egregoros_web/websock_adapter_test.exs (✅ keep; WebSock adapter coverage)
