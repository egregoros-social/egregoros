# Development

## Prerequisites

- Elixir + Erlang/OTP — **use the versions pinned in `mise.toml`**
  (`mise install`). CI uses the same pair, so a mismatched local toolchain is the
  usual explanation for warnings nobody else sees: a newer Elixir's type checker
  reports things in files you never touched, which makes
  `compile --warnings-as-errors` fail locally while CI is green. If `mix` is
  resolving a different version than `mise current` reports, run it through
  `mise exec -- mix ...`.
- PostgreSQL

## Setup

```sh
mix setup
mix phx.server
```

Visit `http://localhost:4000`.

## Tests

Tests need PostgreSQL credentials:

```sh
POSTGRES_USER=your_user POSTGRES_PASSWORD=your_password MIX_ENV=test mix test
```

Useful variants:

```sh
mix test test/path/to/file_test.exs   # one file
mix test --failed                     # previously failing tests
mix test --cover                       # coverage (gate: total >= 85%)
```

Federation-in-a-box end-to-end tests (Egregoros + Pleroma + Mastodon, needs Docker):

```sh
mise run fed:test    # run the smoke suite
mise run fed:logs    # tail logs
mise run fed:down    # tear down containers/volumes
```

Those tests live in `docker/federation/test_runner/test/`.

## Before you push

```sh
mix format
mix precommit
```

`mix precommit` runs `compile --warnings-as-errors`, `deps.unlock --unused`,
`format --check-formatted`, `assets.test`, and `test --cover`.

## Benchmarks

See [`benchmarks.md`](benchmarks.md) for seeding data and running the built-in
benchmark harness.

## Conventions

`AGENTS.md` at the repository root is the short working agreement: TDD first,
review before committing, small topical commits, upstream Pleroma as the
protocol reference, and the rule that `Egregoros.Object.data` stays canonical
external ActivityPub JSON. Read it before adding code.

Beyond that, match the surrounding code. The structural conventions worth
knowing are documented rather than listed as rules:

- one module per ActivityPub type in `lib/egregoros/activities/*`
- swappable concerns (HTTP, caching, signatures, media storage, authz, rate
  limiting) sit behind behaviours, with Mox in tests
- `lib/egregoros/html.ex` is the single HTML safety boundary

Further reading:

- [`architecture.md`](architecture.md) — moving parts and data flow
- [`extending-activity-types.md`](extending-activity-types.md) — how to add a new
  ActivityPub type end to end
- [`security.md`](security.md) — security and privacy checklist
