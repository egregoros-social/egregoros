# Pleroma → Egregoros migration plan (draft)

This document is an engineering plan for migrating an existing **Pleroma** instance (codebase: `/Users/lainsoykaf/repos/pleroma-worktrees/develop`) to **Egregoros** (this repo), with a focus on preserving federation identity and minimizing user disruption.

It’s intentionally split into:
- **What’s feasible today** (with the current Egregoros architecture),
- **What gaps exist** (based on concrete Pleroma implementation details),
- **A phased plan** (from “minimum viable migration” to “near-seamless migration”).

## 0) Executive summary

Migration is feasible, but there are a few “must solve” compatibility areas:

1) **Passwords**: Pleroma stores password hashes in bcrypt/argon2/pbkdf2 formats and verifies them via pattern matching on the hash prefix; Egregoros uses a custom `pbkdf2_sha256$...` format. (Status: pbkdf2 compatibility is implemented; bcrypt/argon2 remain unsupported without additional deps.)
2) **Media URLs and storage layout**: Pleroma’s default upload URLs are under `/media/<uuid>/<filename>`; Egregoros serves uploads under `/uploads/...` with a different filesystem layout. (Status: `/media/*` static serving is implemented, configurable via `:pleroma_media_dir`.)
3) **Activity IDs and fetchability**: Pleroma ActivityPub activity IDs are `/activities/<uuid>`; Egregoros currently generates `/activities/<type>/<uuid>`. (Status: both `/activities/:uuid` and `/activities/:type/:uuid` are now routed and served.)
4) **IDs used by the Mastodon API**: Egregoros now uses Flake IDs (base62 string) as primary keys, matching Pleroma’s general approach. Remaining “seamless continuity” work is primarily about *which* resource owns the ID (Pleroma uses activity IDs for statuses; Egregoros uses object IDs for Note/Question statuses).

Given that, there are two sensible migration modes:

- **Mode A (MVP / federation-first):** preserve **ActivityPub URLs**, keys, posts, follows, and media; users re-login and re-authorize apps; Mastodon API IDs change.
- **Mode B (seamless-ish):** additionally preserve Pleroma-style IDs (flake/base62) for accounts + statuses (and ideally notifications/media), so existing clients don’t “forget” everything.

## 1) What Pleroma actually does (relevant implementation facts)

### 1.1 ActivityPub URL schemes

Pleroma generates:
- Object IDs: `https://<domain>/objects/<uuid>` via `Pleroma.Web.ActivityPub.Utils.generate_object_id/0` (UUID). (`lib/pleroma/web/activity_pub/utils.ex`)
- Activity IDs: `https://<domain>/activities/<uuid>` via `Pleroma.Web.ActivityPub.Utils.generate_activity_id/0` → `generate_id("activities")`. (`lib/pleroma/web/activity_pub/utils.ex`)
- Context IDs: `https://<domain>/contexts/<uuid>` via `generate_context_id/0`. (`lib/pleroma/web/activity_pub/utils.ex`)

Egregoros generates:
- Notes: `https://<domain>/objects/<uuid>` (`lib/egregoros/activities/note.ex`)
- Activities: `https://<domain>/activities/<type>/<uuid>` (`lib/egregoros/activities/*`)
…and now routes `/activities/:uuid` (Pleroma style) and `/activities/:type/:uuid` (Egregoros style). (`lib/egregoros_web/router.ex`)

### 1.2 Primary keys / “flake IDs” in this Pleroma worktree

This Pleroma tree uses `FlakeId.Ecto.CompatType` as the `@primary_key` for (at least) users and activities:
- `@primary_key {:id, FlakeId.Ecto.CompatType, autogenerate: true}` in `Pleroma.User` and `Pleroma.Activity`. (`lib/pleroma/user.ex`, `lib/pleroma/activity.ex`)

`FlakeId.Ecto.CompatType`:
- uses **Postgres `uuid`** as the storage type (`def type, do: :uuid`)
- autogenerates via `FlakeId.get/0`
- loads/casts to a **base62 string** (`FlakeId.to_string/1`) and dumps back to 128-bit binary. (`deps/flake_id/lib/flake_id/ecto/compat_type.ex`, `deps/flake_id/lib/flake_id.ex`)

Implication:
- Pleroma’s Mastodon API IDs (e.g. `status.id`) are base62 strings like `"9n2ciuz1wdesFnrGJU"`, because they render `to_string(activity.id)` (see `StatusView`). (`lib/pleroma/web/mastodon_api/views/status_view.ex`)
- If we want **client continuity**, we should preserve those IDs in Egregoros’ Mastodon API. The simplest way is to import each Pleroma “status activity id” (flake) as the **primary key of the corresponding status object row** in Egregoros (e.g. the Note/Question row), so `status.id` stays the same while `status.uri` remains the object’s ActivityPub ID.

### 1.3 Password hashing

Pleroma:
- stores `users.password_hash` in a format that can be bcrypt (`$2...`), pbkdf2 (`$pbkdf2...`), or argon2 (`$argon2...`).
- verifies using `Pleroma.Web.Plugs.AuthenticationPlug.checkpw/2` which dispatches by prefix. (`lib/pleroma/web/plugs/authentication_plug.ex`)

Egregoros:
- uses a custom `pbkdf2_sha256$<iters>$<salt>$<hash>` format. (`lib/egregoros/password.ex`)

Implication:
- importing `password_hash` from Pleroma will not work until Egregoros supports verifying these hashes (or forces password resets).

### 1.4 Upload URLs and storage

Pleroma uploads:
- default `base_url` is `Endpoint.url() <> "/media/"` (`Pleroma.Upload.base_url/0`)
- local uploader stores files under `uploads_root/<upload.path>` where `upload.path` defaults to `<uuid>/<filename>` (`Pleroma.Upload.store/2`, `Pleroma.Uploaders.Local.put_file/1`)
So historical posts will reference URLs like: `https://<domain>/media/<uuid>/<filename>`.

Egregoros uploads:
- served under `/uploads/...` (see `EgregorosWeb.Plugs.Uploads`)
- stored in a different directory layout (`uploads/media/<user_id>/...`, `uploads/avatars/<user_id>/...` etc).

Implication:
- without explicit compatibility, old media links break after cutover.

## 2) What Egregoros already matches well

Good news: the core federation URL shape is already close to Pleroma:
- `/users/:nickname`, `/users/:nickname/inbox`, `/users/:nickname/outbox`, `/users/:nickname/followers`, `/users/:nickname/following`
- `/inbox` and `/outbox`
- `/objects/:uuid`
(`lib/egregoros_web/router.ex`)

So **preserving ActivityPub actor IDs and object IDs** is mostly a matter of importing the right data and ensuring Egregoros serves the same domain.

## 3) Migration goals (clarify before implementing)

### 3.1 Minimum viable goals (recommended starting point)
- Preserve **actor IDs** and **object IDs** (AP URIs).
- Preserve **local users’ keypairs**, so remote servers can still verify signatures.
- Preserve **all local posts** (Create + Note/Question/etc).
- Preserve **follow graph** (followers + following).
- Preserve **media URLs** (`/media/...`) so historical attachments still load.

Acceptable trade-offs:
- Users re-login, re-authorize apps (OAuth tokens not migrated).
- Mastodon API IDs change (clients refresh state).

### 3.2 “Seamless-ish” goals (optional)
- Preserve Pleroma’s **account IDs** and **status IDs** as seen by the Mastodon API (flake/base62).
- Preserve scheduled posts, bookmarks, markers, filters, notification cursors, etc.

This requires extra schema/API compatibility work in Egregoros.

## 4) Proposed Egregoros changes (by priority)

### 4.1 Password compatibility (high priority)

Add a password verification layer similar to Pleroma:
- Accept `$2...` → bcrypt verify
- Accept `$argon2...` → argon2 verify
- Accept `$pbkdf2...` → pbkdf2-sha512 verify (Pleroma’s)
- Accept current Egregoros `pbkdf2_sha256$...`

Then “rehash on login” into the Egregoros native format.

Status:
- Implemented `$pbkdf2-...` verification and rehash-on-login to `pbkdf2_sha256$...` (`lib/egregoros/password.ex`, `lib/egregoros/users.ex`).
- bcrypt/argon2 remain TODO (requires deps).

This keeps migration friction low without needing to import Pleroma auth/session tables.

### 4.2 Serve Pleroma media URLs (high priority)

Add a Plug/static mount for `/media/*`:
- configurable filesystem root pointing at the existing Pleroma uploads directory
- served read-only (or optionally allow new uploads there too, but that’s not required for migration)

Alternatively, implement a 301 redirect `/media/<path>` → `/uploads/<mapped-path>` but this is hard because Egregoros’ storage layout differs; serving the old directory is the simplest.

Status:
- Implemented `/media/*` serving via `EgregorosWeb.Plugs.PleromaMedia` and `:pleroma_media_dir` runtime config (`lib/egregoros_web/plugs/pleroma_media.ex`).

### 4.3 Activity fetch endpoint(s) (medium-high priority)

Implement GET:
- `/activities/:uuid` (Pleroma style), and optionally also accept Egregoros’ current `/activities/<type>/<uuid>`
Return `application/activity+json` and serve the stored activity by AP id.

This is important because historical activity IDs in remote databases point to `/activities/<uuid>`.

Status:
- Implemented `EgregorosWeb.ActivityController` and routes for both shapes (`lib/egregoros_web/controllers/activity_controller.ex`, `lib/egregoros_web/router.ex`).

### 4.4 Decide on Mastodon API ID strategy (big fork)

**Option 1: Mapping layer (smaller DB change)**
- Keep integer primary keys internally.
- Add a column (or table) to store “external_id” for relevant resources:
  - accounts (users)
  - statuses (notes/questions/announces)
  - media attachments
  - notifications
- Update Mastodon API renderers to emit `external_id` when present.
- Update controllers to accept either integer IDs or external IDs and resolve them.
- Update pagination to work with external IDs.

**Option 2: Adopt Flake IDs as primary keys (bigger, but clean)**
- Introduce FlakeId generation and change `users.id`, `objects.id`, etc to `uuid` flake IDs (base62 string at the API boundary).
- This aligns with Pleroma’s scheme and can simplify “seamless-ish” migration, but it’s a sweeping refactor in Egregoros.

Recommendation:
- Start with **Option 1** unless we’re committed to full Pleroma-like client continuity.

Status:
- Option 2 is now implemented: Egregoros uses Flake IDs as primary keys and returns base62 IDs via the Mastodon API.

Additional status-id note:
- Pleroma uses `status.id == activity.id` (Create/Announce primary key), while Egregoros historically used the Note/Question object primary key.
- For migration, we can preserve Pleroma status IDs by assigning the imported Note/Question/Announce row’s **primary key** to the Pleroma activity flake ID during import (implemented in `Egregoros.PleromaMigration.import_statuses/1`).

### 4.5 Prevent federation side-effects during import (required for any importer)

Egregoros currently delivers many local side effects purely gated by `opts[:local]` (e.g. Like/Announce/Delete/Undo/Follow), not by a `deliver: false` option.

For safe imports, we need either:
- a global `side_effects: false` / `deliver: false` option honored by all activities, **or**
- an importer that inserts DB rows directly and never calls `Pipeline.ingest/2`.

## 5) Import strategy (recommended: DB-level import, idempotent, no side effects)

Because table names collide (`users`, `objects` exist in both apps), do **not** point Egregoros at the same DB.

Instead:
- Create a fresh Egregoros DB.
- Treat the Pleroma DB as **read-only source**.
- Run a one-shot importer (Mix task) that reads from Pleroma and writes to Egregoros.

Status:
- Implemented `mix egregoros.import_pleroma` which imports **users** and **status activities** from a Pleroma Postgres DB.
  - It imports both **local and remote** statuses and preserves Pleroma-style `status.id` by setting the imported status object primary key to the Pleroma activity flake ID.
  - It uses Pleroma’s `associated_object_id/1` database function to join Create activities to their objects.
  - Configure the source DB via `--url` or `PLEROMA_DATABASE_URL`.

### 5.1 Data sets to import (MVP)

1) **Local users**
   - from `pleroma.users`
   - map:
     - `nickname`, `ap_id`, `inbox`, `outbox`, `public_key`
     - private key: `users.keys` (RSA private pem) → `egregoros.users.private_key`
     - profile: `name`, `bio`, avatar/banner URLs (best-effort)
     - auth: `password_hash` (store as-is; requires password compatibility in Egregoros)
2) **Remote users (minimum subset)**
   - at least: users involved in follow graph and in local objects/activities
   - split Pleroma remote nickname (`"user@domain"`) into `nickname` + `domain` for Egregoros
3) **Objects**
   - from `pleroma.objects.data` (JSONB)
   - insert into `egregoros.objects` with:
     - `ap_id = data["id"]`
     - `type = data["type"]`
     - `actor` derived from `actor` or `attributedTo`
     - `published` from `data["published"]` when present
     - `local` derived from domain match
4) **Activities**
   - from `pleroma.activities.data` (JSONB)
   - insert into `egregoros.objects` similarly
   - set `object` column from the activity’s object id (for Create, use embedded object id if present)
5) **Follow graph**
   - Prefer deriving from Pleroma’s `following_relationships` (accepted state) and/or Follow activities:
     - insert into `egregoros.relationships` with
       - `type = "Follow"` (or `"FollowRequest"` if pending)
       - `actor = follower.ap_id`
       - `object = following.ap_id`
       - `activity_ap_id = <follow activity id>` (must be non-null in Egregoros DB)

### 5.2 “Nice to have” imports
- Likes / boosts / emoji reactions (relationships)
- Scheduled posts (`scheduled_activities` → `scheduled_statuses`)
- Markers / bookmarks

### 5.3 Preserve ordering / timestamps

Egregoros currently orders many collections by `objects.id` and/or `inserted_at`.
If we bulk-import with “now” timestamps, timelines and outbox ordering will be wrong.

Importer should preserve:
- `inserted_at` and `updated_at` from Pleroma rows where possible
- and/or `published` timestamps

This likely implies using `Repo.insert_all/3` so we can set timestamps explicitly in bulk.

## 6) Cutover procedure (Mode A / MVP)

1) Put Pleroma in maintenance / read-only, stop federation jobs if possible.
2) Snapshot:
   - Postgres DB dump
   - uploads directory (Pleroma local storage)
3) Deploy Egregoros on the same domain (behind the same proxy).
4) Configure Egregoros:
   - endpoint base URL matches old Pleroma
   - `/media/*` serves the old uploads directory
5) Run importer into a fresh Egregoros DB.
6) Smoke tests:
   - local login for at least one migrated user
   - actor + object URLs resolve
   - `/media/...` resolves for a historical post
   - fedbox: follow, receive post, replies, likes, boosts, deletes
7) Re-enable federation and monitor.

Rollback: switch traffic back to the old Pleroma deployment and DB snapshot.

## 7) Risks / unknowns to validate early

- Some remote servers may dereference old activity IDs (`/activities/<uuid>`). Egregoros needs to serve them.
- Media path mismatches will break historical posts unless `/media` is preserved.
- Importing large datasets: performance and lock time; design importer to be resumable and idempotent.
- If we want “seamless-ish” client continuity, ID strategy becomes a major architectural decision (flake/base62 vs int).

## 8) Next concrete steps (recommended)

1) Decide migration mode (A vs B).
2) Prototype a read-only “Pleroma DB scanner”:
   - count rows by type for `activities.data->>'type'` and `objects.data->>'type'`
   - list unknown/unhandled types
3) Implement Egregoros password compatibility.
4) Implement `/media` static serving.
5) Implement `/activities/:uuid` fetch controller.
6) Implement `mix egregoros.import_pleroma` importer (users → objects → activities → follows).
7) Test in fedbox-like environment by restoring a small Pleroma DB snapshot into a container and running the importer + federation smoke tests.

## Appendix: operator runbook (systemd + host PostgreSQL)

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
