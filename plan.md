# Pleroma‑Redux Plan (TDD‑first)

This plan assumes a green‑field codebase living in this repo and a staged migration of ideas (not code) from Pleroma. Each milestone ends with a runnable, tested vertical slice. **Target stack: Elixir + Phoenix + PostgreSQL.**

## Guiding principles
- **TDD is non‑negotiable**: write failing tests first; implement the minimum to pass; refactor before moving on.
- **Opinionated core**: reduce configuration surfaces, remove feature flags, prefer simple defaults.
- **Single source of truth**: one `objects` table, all activities are objects.
- **Unified ingestion**: same pipeline for local and remote activities (validation, normalization, storage, side‑effects).
- **One activity type = one file**: every activity type defined in a single module that declares schema, validation, ingestion hooks, and rendering/API projection.
- **Normalization lives in validators**: fold “Transmogrifier” logic into per‑activity validators; no separate normalization layer.

## Milestones

### M0 — Repo bootstrap + test harness (1–2 days)
Goal: minimal, testable skeleton.
- Create a new Mix/OTP app with ExUnit.
- Establish test patterns (factories, fixtures, property tests if desired).
- Decide on runtime boundaries (core, web, federation, storage).
- CI‑friendly defaults (single database config for test).

**Deliverables**
- `mix test` runs green with at least one failing‑then‑passing “hello” unit test.
- TDD conventions documented (naming, factories, test helpers).

---

### M0.5 — Local post + live update slice (1–2 days)
Goal: prove TDD + UX loop with the smallest possible vertical slice.
- In‑memory or temporary store for a “post” object.
- LiveView (or minimal streaming transport) updates a simple timeline view.
- Replace the temporary store in M1 without changing the UI contract.

**Deliverables**
- Test proves a new local post appears without refresh.
- Thin UI that exercises the stream end‑to‑end.

---

### M1 — Storage model (objects table) + activity pipeline (2–4 days)
Goal: define the foundation for everything else.
- Postgres schema:
  - `objects` table with `id`, `ap_id`, `type`, `actor`, `object`, `data` (jsonb), `published`, `local`, `inserted_at`, `updated_at`.
  - Unique constraints for `ap_id` and maybe `object` depending on your AP style.
  - Indexes for `ap_id`, `actor`, `type`, `published`, `local` (and any timeline query keys).
- Ingestion pipeline skeleton:
  - `normalize+validate (per‑activity) → store → side_effects`.
  - Same pipeline for local and remote.
  - Idempotency / dedupe on `ap_id` with safe retries.
- Define “activity module” interface:
  - `schema/0`, `normalize/1`, `validate/1`, `ingest/1`, `side_effects/1`, `render/1` (and/or `project/1`).
 - Standard error shape for validation failures.

**Deliverables**
- Tests for storing and retrieving objects as jsonb.
- Tests for ingestion with a stub “Note” activity (one file).
- Tests ensuring local and remote flows call the same pipeline.

---

### M1.5 — Users + keys + actor endpoints (2–4 days)
Goal: minimal actor model to enable federation + API auth.
- Minimal `users` schema: `id`, `ap_id`, `nickname`, `keys`, `local`, `inbox`, `outbox`.
- Key management (create + rotate) and signature helpers.
- Actor JSON endpoint (Person) + inbox/outbox skeleton.

**Deliverables**
- Tests for key generation/rotation and signature creation.
- Tests for actor JSON shape and lookup by `ap_id`/nickname.

---

### M2 — Minimal federation plumbing (2–4 days)
Goal: be discoverable and able to sign/verify.
- `.well-known/webfinger`, `.well-known/nodeinfo`, and nodeinfo payloads.
- HTTP Signatures: signing outgoing requests and verifying incoming.
- ActivityPub actor endpoint and inbox/outbox minimal.
 - Signature verification includes date skew policy.

**Deliverables**
- Request signature verification tests with fixtures.
- Webfinger tests for local user discovery.
- Nodeinfo tests for minimal metadata.
 - Tests for date skew rejection.

---

### M3 — Streaming baseline (2–4 days)
Goal: push new posts to connected clients without manual refresh.
- Minimal PubSub wiring for “new object/activity” events.
- LiveView (or channel/SSE) integration for timeline updates.
- Keep this small and local‑only first; federated inputs can be added later.
 - Align stream events with the canonical timeline query source.

**Deliverables**
- Tests that a new local post broadcasts to the timeline stream.
- A minimal live timeline view (or API stream) that updates in real time.

---

### M4 — Minimal activity set (Posts, Likes, Reposts, Follows, Unfollows, Emoji Reactions) (4–8 days)
Goal: core social primitives with tests for local+remote ingestion.
- Each activity defined in its own file (module) that:
  - Declares schema and validation rules.
  - Normalizes incoming payload.
  - Applies side‑effects (e.g., counters or relationships).
- Implement object/actor relationships as jsonb references (or minimal join tables only if necessary).
 - Content length rules and normalization tests.

**Deliverables**
- End‑to‑end tests for each activity (local create + remote ingest).
- One golden test per activity ensuring JSON shapes are stable.

---

### M5 — Mastodon API surface (4–10 days)
Goal: get an MVP client working.
- Implement the minimum set of endpoints for:
  - Auth, accounts, statuses, timelines, notifications, reactions.
- Provide API response projection from objects (via activity modules).

**Deliverables**
- Request/response contract tests for MVP endpoints.
- Compatibility tests against known Mastodon JSON fixtures.

---

### M6 — LiveView UI + Tailwind (3–6 days)
Goal: default UI that is pleasant and opinionated.
- Phoenix LiveView with a minimal layout.
- Tailwind config + simple light/dark themes.
- UI wired to the same API projections.
- Detailed roadmap: see `ui_plan.md`.

**Deliverables**
- UI tests for key flows (view timeline, create post, react, follow).
- Visual sanity check docs (screenshots optional).

---

### M7 — Timeline strategy (2–6 days)
Goal: decide and implement fast timelines.
- Evaluate 2 options:
  1) **Precomputed timeline** table (like streaming model).
  2) **Query‑time timeline** from objects + follow graph.
- Prototype both behind a minimal abstraction.

**Critique / recommendation**
- Precomputed timelines give *predictable read latency* but add write‑amplification, storage growth, and backfill complexity.
- Query‑time is simpler, but large instances may need caching or partial precomputation.
- Suggest hybrid: precompute **home** timeline only (optional), keep public/hashtag query‑time.
 - Ensure streaming emits only items that the timeline query would return.

**Deliverables**
- Benchmark tests for each approach with synthetic data.
- Decision doc with explicit trade‑offs and final choice.

---

### M8 — Alternative federation discovery (DHT/non‑DNS) (research + prototype) (timeboxed)
Goal: ensure design isn’t DNS‑locked.
- Abstract “instance discovery” with plug‑ins.
- Implement stub for DHT discovery (no production dependency).

**Deliverables**
- Interface + tests for discovery module.
- Prototype module that can be swapped for DNS‑based discovery.

---

## Activity module design (one file per type)
Proposed interface:
- `type/0` → activity type string
- `schema/0` → Ecto changeset schema
- `normalize/1` → normalize incoming payload
- `validate/1` → returns changeset/error
- `ingest/1` → stores object(s)
- `side_effects/1` → counters, relationships
- `project/1` → API/UI projection

This ensures each activity lives in a single module file and reduces cross‑file churn.

## Activity parsing via Ecto embedded schemas (refactor plan)
Goal: move from ad‑hoc `normalize/validate` pattern matching toward **Pleroma‑old style embedded schemas** that (1) define canonical shapes, (2) perform normalization during casting, and (3) produce consistent errors — without losing Pleroma‑Redux’s “one file per activity type” goal.

### Current state (Pleroma‑Redux)
- Each activity module implements `normalize/1` and `validate/1` using pattern matching and guards.
- Compatibility ingestion tests exist using real fixture payloads from `pleroma-old/test/fixtures` (`test/pleroma_redux/compat/pleroma_old_fixtures_test.exs`).
- Normalization is duplicated across modules (e.g. inline `"actor": {"id": ...}` handling).

### Reference (Pleroma‑old)
- Central validator dispatch: `pleroma-old/lib/pleroma/web/activity_pub/object_validator.ex`
- Per‑type embedded schema validators: `pleroma-old/lib/pleroma/web/activity_pub/object_validators/*_validator.ex`
- Shared Ecto types + fixes: `pleroma-old/lib/pleroma/ecto_type/activity_pub/object_validators/*`

### Target design (Redux)
- Keep activity ownership: **each activity module remains the only file you edit** to add/modify that activity.
- Add a single new “parsing entry point” per activity module:
  - `cast_and_validate/1` → returns `{:ok, normalized_activity_map}` or `{:error, %Ecto.Changeset{}}`
- Implement `cast_and_validate/1` via `embedded_schema` + changeset validations, using shared helper modules/types.
- Keep the ingestion pipeline stable (same return values, same side‑effects), and migrate activity types incrementally.

### Key decisions to make explicitly (before code moves)
1) **ID strictness (ObjectIDs)**
   - Pleroma‑old’s `ObjectID` requires `http/https` + host. Redux should likely be more permissive to avoid DNS‑lock (e.g. allow `did:`, `ap:`, `urn:` and future DHT‑style IDs).
   - Recommendation: start with “non‑empty string” (optionally parseable URI) and evolve strictness behind a mockable boundary.
2) **Preserve unknown keys**
   - Pleroma‑old discards unknown keys during casting; Redux currently preserves most keys in `object.data`.
   - Recommendation: keep the raw payload and overlay normalized canonical fields (e.g. normalized `"actor"`), so we don’t lose extensions/unknown fields while still enforcing the core schema.
3) **Embedded objects in activities**
   - `Create` and `Announce` commonly carry embedded objects.
   - Recommendation: keep embedded objects in the validated map (so ingestion can recurse), but normalize *IDs* consistently and extract `object` IDs for DB columns.

### Implementation plan (incremental, TDD‑first)
1) **Introduce shared validator building blocks (small, testable)**
   - Add `PleromaRedux.ActivityPub.ObjectValidators` helpers inspired by pleroma‑old:
     - `CommonFields` (macros or functions for common AP fields)
     - `CommonValidations` (actor/object presence, type inclusion, recipients shape)
     - `Types.ObjectID` (casts `"id"` maps → ID strings; permissive schemes)
     - `Types.Recipients` (casts string/map/list → normalized list of IDs)
     - `Types.DateTime` (casts AP datetime strings → normalized ISO8601 string)
   - Add unit tests for each type (casting edge‑cases pulled from real fixtures).

2) **Add a “new parsing path” to the pipeline (without rewriting everything)**
   - Update the pipeline to prefer `module.cast_and_validate/1` when exported, otherwise fall back to `normalize/validate`.
   - Add a pipeline test proving old + new paths both work.

3) **Migrate one activity type end‑to‑end (Follow first)**
   - Convert `PleromaRedux.Activities.Follow` to use `embedded_schema` + `cast_and_validate/1`.
   - Keep `normalize/validate` as thin wrappers (or remove after all migrations).
   - Tests:
     - Changeset unit tests for Follow shape rules.
     - Compatibility test using `hubzilla-follow-activity.json` stays green.

4) **Migrate core object types (Note) and Create**
   - `Note`: validate content, `attributedTo/actor` normalization, addressing fields (`to/cc`), timestamps.
   - `Create`: validate `object` is a map with `id/type`, normalize actor, and ensure address fields exist or can be derived.
   - Tests:
     - Schema tests for Note and Create derived from fixtures (`kroeg-post-activity.json`, plus additional Note fixtures as found).

5) **Migrate “union” object fields (Accept/Announce/Undo/Delete)**
   - Implement schema support for `object` being either an ID or an embedded object (validator types or explicit validations).
   - Preserve embedded objects in `data` when needed for recursive ingestion.
   - Tests:
     - Extend fixture coverage by pulling more cases from `pleroma-old/test/fixtures` (especially nested Undo/Accept/Announce variants).

6) **Migrate Like + EmojiReact**
   - Normalize recipients, validate content rules for EmojiReact.
   - Tests:
     - Use existing fixture tests (`mastodon-like.json`, `emoji-reaction.json`) and add more variants if available.

7) **Finalize + delete legacy parsing code**
   - Once all activity types implement `cast_and_validate/1`, simplify the pipeline to use only that entry point.
   - Standardize validation errors (HTTP 400 + machine‑readable reason for APIs; structured logs for federation).

### Testing plan (fixtures + unit tests)
- Keep `test/pleroma_redux/compat/pleroma_old_fixtures_test.exs` as the “real‑world smoke suite”.
- Add per‑type changeset tests that:
  - cover normalization (inline actor objects, nested `"id"` shapes),
  - assert *minimal* required fields (TDD‑friendly; tighten later as features demand),
  - and verify we preserve unknown keys when configured to do so.
- When tests need future behaviour (e.g. actor lookup, auth), model it as a behaviour boundary and use Mox to assert calls, rather than encoding permissive behaviour in the core parser.

## Registry and contracts
- Maintain a small **activity registry** mapping `type -> module` (explicit or auto‑discover via naming).
- Enforce a strict `normalize → validate` contract to avoid drift between modules.
- Standardize error shapes for pipeline/validation failures.

## Source audit (Pleroma → Pleroma‑Redux)
**Keep/port (core behavior, simplified implementation)**
- ActivityPub pipeline shape and validation: `../pleroma/lib/pleroma/web/activity_pub/pipeline.ex`, `../pleroma/lib/pleroma/web/activity_pub/object_validator.ex`, `../pleroma/lib/pleroma/web/activity_pub/object_validators/*`
- Containment + fetch/sign: `../pleroma/lib/pleroma/object/containment.ex`, `../pleroma/lib/pleroma/object/fetcher.ex`, `../pleroma/lib/pleroma/signature/api.ex`, `../pleroma/lib/pleroma/http_signatures_api.ex`
- Webfinger + nodeinfo: `../pleroma/lib/pleroma/web/web_finger.ex`, `../pleroma/lib/pleroma/web/web_finger/web_finger_controller.ex`, `../pleroma/lib/pleroma/web/nodeinfo/nodeinfo.ex`, `../pleroma/lib/pleroma/web/nodeinfo/nodeinfo_controller.ex`
- Federation publish/receive flow (conceptual): `../pleroma/lib/pleroma/web/federator.ex`, `../pleroma/lib/pleroma/web/activity_pub/publisher.ex`

**Reference but redesign (reduce tables/flags; keep intent)**
- Schemas: `../pleroma/lib/pleroma/activity.ex`, `../pleroma/lib/pleroma/object.ex`, `../pleroma/lib/pleroma/user.ex`
- Relationships: `../pleroma/lib/pleroma/following_relationship.ex`, `../pleroma/lib/pleroma/user_relationship.ex`
- API surface: `../pleroma/lib/pleroma/web/mastodon_api/controllers/*`, `../pleroma/lib/pleroma/web/mastodon_api/views/*`
- Action orchestration: `../pleroma/lib/pleroma/web/common_api.ex`

**Drop or postpone (scope‑cut for v1)**
- MRF policy zoo: `../pleroma/lib/pleroma/web/activity_pub/mrf/*`
- Legacy/alt APIs + static FE: `../pleroma/lib/pleroma/web/pleroma_api/*`, `../pleroma/lib/pleroma/web/twitter_api/*`, `../pleroma/lib/pleroma/web/o_status/*`, `../pleroma/lib/pleroma/web/static_fe/*`
- Media proxy / uploads / rich media extras: `../pleroma/lib/pleroma/media_proxy*`, `../pleroma/lib/pleroma/upload*`, `../pleroma/lib/pleroma/uploaders/*`, `../pleroma/lib/pleroma/web/rich_media/*`
- Chat/polls/lists/bookmarks/announcements/etc.: `../pleroma/lib/pleroma/chat*`, `../pleroma/lib/pleroma/announcement*`, `../pleroma/lib/pleroma/scheduled_activity.ex`, `../pleroma/lib/pleroma/list.ex`, `../pleroma/lib/pleroma/bookmark*`, `../pleroma/lib/pleroma/poll*`
- Auth extras: `../pleroma/lib/pleroma/mfa*`, `../pleroma/lib/pleroma/captcha*`, `../pleroma/lib/pleroma/ldap.ex`, `../pleroma/lib/pleroma/emails/*`

## Test strategy (TDD)
- Unit tests for schemas + validation per activity module.
- Integration tests for ingestion pipeline.
- API contract tests for Mastodon endpoints.
- Federation signature tests with fixtures.
- Property tests for jsonb storage (optional).
 - Idempotency tests (duplicate `ap_id` ingest).

## Open questions to resolve early
1) Timeline strategy (precompute vs query). Recommend prototype in M7.
2) Counters (likes/reposts) stored as materialized integers or derived from objects.
3) Minimum required Mastodon endpoints for client compatibility.
4) How to represent emoji reactions (as separate activity type or as extension).
5) Streaming transport choice (LiveView only vs SSE/WS for API).

## Risks / ideas
- **Risk**: Over‑engineering the ingestion pipeline before features exist. Mitigate by keeping interface minimal and evolving via tests.
- **Risk**: Mastodon API scope creep. Mitigate with a strict MVP spec.
- **Idea**: Use event sourcing semantics (object is event) which maps naturally to `objects` table and simplifies audit/debug.
