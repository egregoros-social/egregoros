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

Implements a Mastodon-compatible API sufficient for real clients (including WebSocket streaming). Exact surface area is still evolving; keep an eye on `tasks.md` for compatibility work.

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

For the full overview, read `architecture.md`.

## Development

### Prerequisites

- Elixir + Erlang/OTP
- PostgreSQL

### Setup

```sh
mix setup
mix phx.server
```

Visit `http://localhost:4000`.

## Docker / Coolify

For a self-contained stack (app + Postgres), use `docker-compose.yml`.

```sh
cp .env.example .env
# Set SECRET_KEY_BASE (generate one with: mix phx.gen.secret)
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build
```

The local override also publishes two optional web front-ends:

- Pleroma-FE: `http://localhost:4001`
- pl-fe: `http://localhost:4002`

For production, change `POSTGRES_PASSWORD` (and use URL-safe characters or URL-encode it in `DATABASE_URL`).

The container runs migrations automatically on startup via `Egregoros.Release.migrate/0`.
For multi-node deployments, run migrations as a one-off task instead of on every boot.

### Standalone (Caddy on 80/443)

If you’re deploying without Coolify/Traefik and want HTTPS termination + host-based routing in the compose stack,
use `docker-compose.standalone.yml` (Caddy binds to ports 80/443 and uses Let’s Encrypt).

```sh
cp .env.example .env
# Set: SECRET_KEY_BASE, POSTGRES_PASSWORD, EGREGOROS_DOMAIN
docker compose -f docker-compose.yml -f docker-compose.standalone.yml up -d --build
```

DNS is expected to point at the server for:

- `EGREGOROS_DOMAIN` (main app / LiveView / ActivityPub)
- `i.EGREGOROS_DOMAIN` (uploads)
- `fe.EGREGOROS_DOMAIN` (Pleroma-FE)
- `pl-fe.EGREGOROS_DOMAIN` (pl-fe)

You can customize routing/TLS options by editing `docker/caddy/Caddyfile`.

Uploads are stored on the `egregoros_uploads` named volume (mounted at `/data/uploads` in the `web` container).
In the standalone setup, uploads are served from `https://i.${EGREGOROS_DOMAIN}` by default.

For backups, persist/backup at least:

- `egregoros_db` (PostgreSQL data)
- `egregoros_uploads` (user uploads)
- `caddy_data` + `caddy_config` (TLS certs/config; optional but avoids re-issuing)

### Migrating from Pleroma (systemd + host PostgreSQL)

If you have an existing Pleroma deployment managed via `systemd` and PostgreSQL installed on the host (Ubuntu packages),
you can migrate users + statuses into Egregoros (preserving status IDs) by letting the **Egregoros container connect to
the host Postgres over TCP**.

1) Start Egregoros (standalone Caddy):

```sh
cp .env.example .env
# Set: SECRET_KEY_BASE, POSTGRES_PASSWORD, EGREGOROS_DOMAIN
docker compose -f docker-compose.yml -f docker-compose.standalone.yml up -d --build
```

2) Temporarily allow the container network to reach host Postgres:

- Ensure your Pleroma DB user has a password (peer/local auth won’t work from Docker).
- Edit host Postgres config:
  - `/etc/postgresql/<ver>/main/postgresql.conf`: set `listen_addresses = '*'` (or include the docker bridge iface)
  - `/etc/postgresql/<ver>/main/pg_hba.conf`: add an allow rule for your Docker compose subnet

Get the compose subnet:

```sh
docker network inspect egregoros_default --format '{{(index .IPAM.Config 0).Subnet}}'
```

Add a rule like:

```conf
host  pleroma  pleroma  <SUBNET_FROM_ABOVE>  scram-sha-256
```

Reload:

```sh
sudo systemctl reload postgresql
```

3) On Linux, make `host.docker.internal` resolve to the host gateway for the `web` container.
Create `docker-compose.migrate.yml`:

```yml
services:
  web:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

4) Run the import from inside the release container:

```sh
docker compose \
  -f docker-compose.yml \
  -f docker-compose.standalone.yml \
  -f docker-compose.migrate.yml \
  run --rm \
  -e PLEROMA_DATABASE_URL='postgres://pleroma:PASSWORD@host.docker.internal:5432/pleroma' \
  web sh -lc 'bin/egregoros eval "case Application.ensure_all_started(:egregoros) do {:ok, _} -> :ok; other -> IO.inspect(other, label: :start_error); System.halt(1) end; IO.inspect(Egregoros.PleromaMigration.run(), label: :import)"'
```

After the import, remove the `pg_hba.conf` rule (and tighten `listen_addresses`) if you don’t want host Postgres reachable
from Docker anymore.

Note: this importer currently migrates **users + statuses** only. It does not copy Pleroma’s local media uploads or rewrite
historic attachment URLs.

### Running via systemd (Docker Compose)

If you want systemd to (re)start the compose stack on boot, see:

- `deploy/systemd/egregoros-compose.service`

Copy it to `/etc/systemd/system/egregoros-compose.service`, adjust `WorkingDirectory`, then:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now egregoros-compose
```

### Coolify notes

- Use the **Docker Compose** deployment type and point it at this repo.
- Do not publish the app port with `ports:`; let Coolify/Traefik route to the container port instead.
- Because the app listens on port `4000`, add the port in Coolify’s domain mapping (e.g. `https://example.com:4000`).
- Set `PHX_HOST` / `PHX_SCHEME` / `PHX_PORT` to the public URL of your instance (important for federation).
- Persist volumes `egregoros_db` and `egregoros_uploads` (Coolify will create named volumes automatically).

### Serving uploads from a separate subdomain

To isolate user uploads on a separate origin (recommended defense-in-depth), you can serve them from a dedicated
subdomain like `i.example.com`:

- Point `i.example.com` at the same Coolify app/service as the main domain.
- Set `EGREGOROS_UPLOADS_BASE_URL=https://i.example.com` so URLs for `/uploads/*` are generated on that host.
- Set `EGREGOROS_SESSION_COOKIE_DOMAIN=example.com` (or `.example.com`) so the browser can send the session cookie
  to the uploads host (required for followers-only/direct media visibility checks).

When `EGREGOROS_UPLOADS_BASE_URL` is set, Egregoros will only serve `/uploads/*` when the request `Host` matches that
uploads host, so uploads aren’t accessible on the main app origin.

### External host (ngrok / reverse proxies)

ActivityPub IDs and API URLs are generated from the configured endpoint URL. To run behind ngrok, set:

- `PHX_HOST` (or `EGREGOROS_EXTERNAL_HOST`) to your ngrok hostname
- `PHX_SCHEME` (or `EGREGOROS_EXTERNAL_SCHEME`) to `https`
- `PHX_PORT` (or `EGREGOROS_EXTERNAL_PORT`) to `443`

These are read in `config/runtime.exs`.

### HTTP signature strictness (optional)

By default, Egregoros verifies HTTP signatures in a compatibility-focused way (e.g. allowing signatures that only
cover `(request-target)` + `date`).

For hardened deployments you can enable **strict** mode, which requires the signature to cover:

- `(request-target)` (or `@request-target`)
- `host` + `date`
- and for `POST`/`PUT`/`PATCH`: also `digest` + `content-length`

Enable it in `config/runtime.exs` or `config/prod.exs`:

```elixir
config :egregoros, :signature_strict, true

# Optional: max allowed clock skew for the signed Date header, in seconds (default: 300)
config :egregoros, :signature_skew_seconds, 300
```

Note: strict mode can break federation with servers that sign fewer headers.

### Tests

```sh
mix test
mix test --cover
```

When you’re done with a batch of changes, run:

```sh
mix precommit
```

### Benchmarks

See `BENCHMARKS.md` for seeding and running the built-in benchmark harness.

## Docs / checklists

- `architecture.md` — moving parts and data flow
- `security.md` — security & privacy checklist
- `tasks.md` — current backlog and priorities
- `frontend_checklist.md` — UI parity checklist
- `BENCHMARKS.md` — benchmark harness
- `e2ee_dm.md` — parked design notes for end-to-end encrypted DMs (removed from the code; see the doc header)

## Troubleshooting

### `:emfile` / "too many open files" crash under load

If you see errors like `Unexpected error in accept: :emfile` (Bandit/ThousandIsland) or
`File operation error: emfile`, your OS file descriptor limit is too low (often `ulimit -n 256`).

Increase it before starting the server:

```sh
ulimit -n 8192
mix phx.server
```
