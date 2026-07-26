# Architecture

Egregoros is a **PostgreSQL + Elixir/OTP + Phoenix (LiveView)** implementation of an ActivityPub server with a Mastodon-compatible API and an integrated LiveView UI.

This document is a high-level map of the moving parts so a new developer can quickly understand where things live and how data flows.

## Goals (current shape)

- Store ActivityPub objects *and* activities in a single `objects` table (JSONB payloads, plus a few indexed “query columns”).
- Keep local and remote ingestion unified via a single ingestion pipeline.
- Expose:
  - ActivityPub server endpoints (inbox/outbox, object fetch, WebFinger, NodeInfo).
  - Mastodon API endpoints (sufficient for real clients).
  - A first-class LiveView UI (Tailwind-based) with live updates.
- Keep “swapability” via behaviour boundaries (HTTP, signature, discovery, media storage, auth/authz).

## High-level system picture

There are three main “front doors”:

1. **LiveView UI** (browser) → `EgregorosWeb.Live.*`
2. **Mastodon API** (mobile/web clients) → `EgregorosWeb.MastodonAPI.*`
3. **ActivityPub federation** (remote servers) → `EgregorosWeb.*Controller` (inbox/outbox/object/webfinger/nodeinfo)

All of them ultimately read/write the same data:

- `objects` (ActivityPub objects & activities)
- `relationships` (actor ↔ object state like follows/likes/reposts/reactions)
- `users` (local + remote actors)
- plus OAuth and a few supporting tables

## Data model (Postgres)

### `objects`
`lib/egregoros/object.ex`

Single table used for **everything ActivityPub**:

- `ap_id` (unique): canonical ActivityPub ID / URL for the object/activity
- `type`: ActivityStreams type (`Note`, `Create`, `Follow`, `Like`, `Announce`, `EmojiReact`, …)
- `data` (JSONB-ish map): the full ActivityPub payload (what we ingest and what we deliver)
- denormalized helpers:
  - `actor` (string): ActivityPub actor id
  - `object` (string): ActivityPub object id (for activities that target another object)
  - `published` (datetime)
  - `local` (boolean)

This keeps ingestion simple and makes it easy to add new activity types without schema churn.

### `relationships`
`lib/egregoros/relationship.ex`

Holds **stateful relationships** between an actor and an object, with a uniqueness constraint:

- `type` (string): e.g. `Follow`, `Like`, `Announce`, `Bookmark`, `EmojiReact:🔥`
- `actor` (string): actor ap_id
- `object` (string): object ap_id (or actor ap_id for actor↔actor relationships like follow)
- `activity_ap_id`: links back to the activity in `objects` that created this state

Why this exists: ActivityPub allows repeated actions (e.g. multiple follow attempts), but the *resulting state* should be unique and queryable.

### `users`
`lib/egregoros/user.ex`

Stores both **local and remote actors**:

- actor identity: `nickname`, `domain`, `ap_id`
- federation endpoints: `inbox`, `outbox`
- keys: `public_key`, and `private_key` for local users
- profile fields: `name`, `bio`, `avatar_url`, `banner_url`
- auth fields for local accounts: `email`, `password_hash`

### OAuth and supporting tables

- OAuth apps/tokens: `lib/egregoros/oauth/*`
- Markers: `lib/egregoros/marker.ex`

## Ingestion pipeline (the core)

### Pipeline entrypoint
`lib/egregoros/pipeline.ex`

`Egregoros.Pipeline.ingest/2` is the central “accept an ActivityPub map, make it real” function:

1. Resolve the activity type to a module via `Egregoros.ActivityRegistry`.
2. `cast_and_validate/1` using an embedded Ecto schema (normalization lives in validators).
3. `ingest/2` to upsert into `objects` (and sometimes ingest embedded objects).
4. `side_effects/2` to update derived state (relationships, notifications, broadcasts, delivery).

Local and remote ingestion use the same pipeline; the main switch is the `local: true/false` option.

### Activity modules: “one file per activity type”
`lib/egregoros/activities/*`

Each activity lives in a single module (e.g. `Note`, `Create`, `Follow`, `Like`, `Announce`, `EmojiReact`, `Undo`, `Delete`).

Convention:

- `type/0` returns the ActivityStreams type name.
- `cast_and_validate/1` defines the normalized shape and validation.
- `ingest/2` writes to `objects` (and may ingest embedded objects).
- `side_effects/2` performs:
  - relationship updates (`relationships`)
  - notification broadcasts
  - timeline broadcasts
  - outbound delivery for local activities

Discovery of activity modules is automatic:
`lib/egregoros/activity_registry.ex` scans `Egregoros.Activities.*` modules at runtime.

## Federation (ActivityPub)

### Inbound federation

- Inbox endpoint: `lib/egregoros_web/controllers/inbox_controller.ex`
  - Signature is verified by `EgregorosWeb.Plugs.VerifySignature`.
  - The request is enqueued into Oban (`Egregoros.Workers.IngestActivity`) and returns `202`.
  - Worker calls `Pipeline.ingest(activity, local: false)`.

This keeps the HTTP endpoint responsive under bursty federation load.

### Outbound federation

- Delivery entrypoint: `lib/egregoros/federation/delivery.ex`
  - Enqueues `Egregoros.Workers.DeliverActivity` for async delivery.
  - `deliver_now/3` signs the request and posts JSON to a remote inbox.

### Signed fetch

Some servers require signed object fetches even for public objects.

- `lib/egregoros/federation/signed_fetch.ex` performs `GET` with HTTP Signatures.
- `lib/egregoros/federation/internal_fetch_actor.ex` provides a local “system actor” used only for signed fetch.

### Safety / SSRF boundaries

Outbound and fetch URLs are validated to avoid SSRF:

- `lib/egregoros/safe_url.ex` rejects localhost/private IP ranges (and IP literals).

### Discovery

Discovery is abstracted behind a behaviour:

- `lib/egregoros/discovery.ex`
- DNS / DHT implementations live in `lib/egregoros/discovery/*`

Right now DNS is the default, but the architecture keeps room for non-DNS instance discovery.

## APIs

### ActivityPub endpoints
Defined in `lib/egregoros_web/router.ex` and implemented in `EgregorosWeb.*Controller`.

Key endpoints:

- WebFinger: `/.well-known/webfinger`
- NodeInfo: `/.well-known/nodeinfo`, `/nodeinfo/2.0(.json)`
- Actor: `/users/:nickname`
- Inbox: `/users/:nickname/inbox`
- Outbox: `/users/:nickname/outbox`
- Object fetch: `/objects/:uuid`

### Mastodon API
`lib/egregoros_web/controllers/mastodon_api/*` + renderers in `lib/egregoros_web/mastodon_api/*_renderer.ex`.

Important implementation notes:

- Visibility checks must match Mastodon semantics: public timelines are filtered; authenticated `GET /api/v1/statuses/:id` is allowed if the user is a recipient.
- Rendering:
  - local posts are treated as **plain text** and escaped/linkified
  - remote posts are treated as **HTML** and sanitized
  - both use `Egregoros.HTML`

### Streaming (Mastodon-compatible)

- WebSocket endpoint: `GET /api/v1/streaming`
  - controller: `lib/egregoros_web/controllers/mastodon_api/streaming_controller.ex`
  - socket handler: `lib/egregoros_web/mastodon_api/streaming_socket.ex`

Implementation uses Phoenix PubSub broadcasts from:

- `Egregoros.Timeline` (topic: `"timeline"`)
- `Egregoros.Notifications` (topic per user: `"notifications:<ap_id>"`)

## LiveView UI

LiveViews live under `lib/egregoros_web/live/*` and use:

- reusable components: `lib/egregoros_web/components/*`
- view models / decorators: `lib/egregoros_web/view_models/*`

Key patterns:

- timelines use LiveView streams for efficient append/prepend
- “UI-only” toggles should prefer client-side `JS.*` and hooks to avoid server roundtrips

## Media and uploads

Storage is abstracted behind behaviours so we can swap backends later:

- Media: `lib/egregoros/media_storage.ex` (default: local filesystem)
- Avatars: `lib/egregoros/avatar_storage.ex`

LiveView uploads are handled with `allow_upload/3` and then persisted via the storage behaviour.

## HTML safety (rendering user content)

`lib/egregoros/html.ex` is the single place that turns AP content into safe HTML.

- Remote content: sanitize HTML with `FastSanitize` scrubber rules.
- Local content: treat as text → escape → linkify → sanitize.
- Custom emojis:
  - parsed from ActivityPub `tag` entries (`type: "Emoji"`)
  - rendered as `<img class="emoji">` only for http/https URLs (and still scrubbed)

See also [`security.md`](security.md) for known security considerations and fixes.

## Background jobs (Oban)

Oban is configured in `config/config.exs` with two primary queues:

- `federation_incoming` (ingest)
- `federation_outgoing` (deliver)

Workers:

- `lib/egregoros/workers/ingest_activity.ex`
- `lib/egregoros/workers/deliver_activity.ex`

## Testing and fixtures

- ExUnit test suite under `test/`
- Oban is run in manual testing mode in tests (`Oban.Testing`)
- Behaviour boundaries are designed to be mocked with Mox
- Real-world federation fixtures live in `test/fixtures`

## Where to start when making changes

- Adding a new activity type: `lib/egregoros/activities/*` (single file), plus tests under `test/egregoros/activities/*`.
- Mastodon compatibility: start with `lib/egregoros_web/controllers/mastodon_api/*` and the renderers.
- Federation issues: `lib/egregoros_web/controllers/inbox_controller.ex`, `lib/egregoros/signature/http.ex`, `lib/egregoros/federation/*`.
- UI work: LiveViews + components + view models.

