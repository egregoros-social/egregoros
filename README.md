# Egregoros

Egregoros is a **PostgreSQL + Elixir/OTP + Phoenix (LiveView)** ActivityPub server with:

- a Mastodon-compatible API (including streaming),
- a first-class LiveView UI (Tailwind v4),
- a reduced, opinionated architecture designed to stay maintainable.

## Design goals

- **Single ActivityPub storage model:** everything ActivityPub (objects *and* activities) is stored in one Postgres table (`objects`) using a JSONB payload plus a few denormalized query columns.
- **One module per ActivityPub type:** activity handling lives in `lib/egregoros/activities/*` (Ecto embedded schema + ingestion + side effects) so adding new types doesn’t require editing many files.
- **Unified ingestion:** local authoring, inbound federation, and on-demand fetches all go through a single ingestion pipeline (`Egregoros.Pipeline`).
- **Swapability:** caching, discovery, HTTP, signatures, media storage, authz, and rate limiting sit behind behaviour boundaries so they can be replaced later without rewrites.

## Feature highlights

### Federation (ActivityPub)

- WebFinger + NodeInfo 2.0
- Actor endpoints, inbox/outbox, object fetch (`/objects/:uuid`)
- HTTP Signatures for deliveries
- Signed fetch (for servers that require signed GETs for public objects)
- Async ingestion/delivery via Oban (burst-resistant federation)
- Thread completion (best-effort, bounded, async):
  - fetch missing ancestors via `inReplyTo`
  - fetch replies via ActivityPub `replies` collections when available

### Social features

- Posts (Notes)
- Attachments (images/video/audio) with alt text
- Likes, reposts (Announce), emoji reactions (including custom emoji reactions)
- Follows + unfollows, follow requests (locked accounts)
- Bookmarks, favourites

### Mastodon API

Implements a Mastodon-compatible API sufficient for real clients (including WebSocket streaming). The exact surface area is still evolving; open compatibility work is tracked in [`meta/issues.md`](meta/issues.md).

### LiveView UI

- Public + home timelines with live updates
- Status/thread view (`/@:nickname/:uuid`) with reply modal
- Composer with visibility, language, content warnings, sensitive toggle, attachments, emoji picker, mention autocomplete
- Profiles, notifications, settings, light/dark/system theme

## Architecture (quick tour)

- **Core ingestion:** `lib/egregoros/pipeline.ex` → activity module (`lib/egregoros/activities/*`) → `objects` + `relationships` + side effects (broadcast, notifications, delivery).
- **Storage model:**
  - `objects` (`lib/egregoros/object.ex`): ActivityPub objects/activities (JSON payload + columns: `ap_id`, `type`, `actor`, `object`, `published`, `local`)
  - `relationships` (`lib/egregoros/relationship.ex`): unique actor↔object state (Follow/Like/Announce/Bookmark/EmojiReact:* etc)
  - `users` (`lib/egregoros/user.ex`): local + remote actors
- **Federation:** inbox/outbox/object controllers, `Egregoros.Federation.Delivery` (outbound), `Egregoros.Federation.SignedFetch` (signed GET).
- **Background work:** Oban workers under `lib/egregoros/workers/*` for ingestion, delivery, and thread completion.
- **Rendering safety:** `lib/egregoros/html.ex` is the single HTML safety boundary (sanitize remote HTML; escape+linkify local text).

For the full overview, read [`docs/architecture.md`](docs/architecture.md).

## Getting started

You need Elixir + Erlang/OTP (versions pinned in `mise.toml`) and PostgreSQL.

```sh
mix setup
mix phx.server
```

Visit `http://localhost:4000`. See [`docs/development.md`](docs/development.md)
for tests, the precommit gate, and project conventions.

To run it for real (Docker Compose, standalone HTTPS, Coolify, systemd), see
[`docs/deployment.md`](docs/deployment.md).

## Documentation

[`docs/`](docs/README.md) has the full index. Starting points:

- [Development](docs/development.md) — setup, tests, conventions
- [Architecture](docs/architecture.md) — moving parts and data flow
- [Deployment](docs/deployment.md) — running an instance
- [Adding an ActivityPub type](docs/extending-activity-types.md)
- [Security checklist](docs/security.md)

Open work is tracked in-repo in [`meta/issues.md`](meta/issues.md).

## Status

Egregoros is under active development. It federates and runs a usable web UI,
but it has not been through a production hardening pass — treat it as
pre-release and read [`docs/security.md`](docs/security.md) before exposing an
instance you care about.

## License

Released into the public domain under [the Unlicense](UNLICENSE).
