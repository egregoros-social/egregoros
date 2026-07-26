# Deployment

Egregoros ships as a Docker Compose stack (app + PostgreSQL). Pick the flavour
that matches your environment:

- **Behind an existing reverse proxy** (Coolify, Traefik, nginx): base
  `docker-compose.yml`.
- **Standalone with HTTPS**: add `docker-compose.standalone.yml` (Caddy on
  80/443, Let's Encrypt).
- **Local development against the container stack**: add
  `docker-compose.local.yml`.

## Docker Compose

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

## Troubleshooting

### `:emfile` / "too many open files" crash under load

If you see errors like `Unexpected error in accept: :emfile` (Bandit/ThousandIsland) or
`File operation error: emfile`, your OS file descriptor limit is too low (often `ulimit -n 256`).

Increase it before starting the server:

```sh
ulimit -n 8192
mix phx.server
```
