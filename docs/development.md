# Development

## Prerequisites

- Elixir + Erlang/OTP (versions are pinned in `mise.toml`)
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

`AGENTS.md` at the repository root is the working agreement: TDD first, one
module per ActivityPub type, behaviour boundaries with Mox for missing
behavior, and the Phoenix/LiveView/Ecto house style. Read it before adding
code.

Further reading:

- [`architecture.md`](architecture.md) — moving parts and data flow
- [`extending-activity-types.md`](extending-activity-types.md) — how to add a new
  ActivityPub type end to end
- [`security.md`](security.md) — security and privacy checklist
