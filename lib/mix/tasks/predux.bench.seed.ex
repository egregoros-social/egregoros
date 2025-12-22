defmodule Mix.Tasks.Predux.Bench.Seed do
  use Mix.Task

  @shortdoc "Seed the database with benchmark data (destructive)"

  @moduledoc """
  Seeds the current database with a synthetic dataset intended for performance testing.

  This task is destructive by default (it deletes existing users/objects/relationships),
  so you must pass `--force` unless you also pass `--no-reset`.

  Recommended usage (isolated DB):

      MIX_ENV=bench mix ecto.create
      MIX_ENV=bench mix ecto.migrate
      MIX_ENV=bench mix predux.bench.seed --force

  Options:

    * `--local-users` (default: 10)
    * `--remote-users` (default: 200)
    * `--days` (default: 365)
    * `--posts-per-day` (default: 200)
    * `--follows-per-user` (default: 50)
    * `--seed` (integer; optional)
    * `--[no-]reset` (default: reset)
    * `--force` (required when reset is enabled)
  """

  @switches [
    local_users: :integer,
    remote_users: :integer,
    days: :integer,
    posts_per_day: :integer,
    follows_per_user: :integer,
    seed: :integer,
    reset: :boolean,
    force: :boolean
  ]

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _args, _invalid} = OptionParser.parse(argv, switches: @switches)

    reset? = Keyword.get(opts, :reset, true)
    force? = Keyword.get(opts, :force, false)

    if reset? and not force? do
      Mix.raise("refusing to reset the database without --force (or pass --no-reset)")
    end

    summary =
      PleromaRedux.Bench.Seed.seed!(
        local_users: Keyword.get(opts, :local_users),
        remote_users: Keyword.get(opts, :remote_users),
        days: Keyword.get(opts, :days),
        posts_per_day: Keyword.get(opts, :posts_per_day),
        follows_per_user: Keyword.get(opts, :follows_per_user),
        seed: Keyword.get(opts, :seed),
        reset?: reset?
      )

    Mix.shell().info("""
    Bench seed complete:
      users:  local=#{summary.users.local} remote=#{summary.users.remote}
      notes:  #{summary.objects.notes}
      follows: #{summary.relationships.follows}
    """)
  end
end
