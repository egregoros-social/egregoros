defmodule Mix.Tasks.Egregoros.Actors.Refetch do
  use Mix.Task

  @shortdoc "Refetch remote ActivityPub actors to refresh stored profile metadata"

  @moduledoc """
  Refetch remote ActivityPub actors to refresh stored profile metadata (e.g. custom emoji tags).

  Usage:

      # Refetch remote users missing emoji metadata (default)
      mix egregoros.actors.refetch

      # Refetch all remote users
      mix egregoros.actors.refetch --all

      # Narrow down the set
      mix egregoros.actors.refetch --domain remote.example --limit 50 --name-has-shortcodes

      # Refetch specific users by handle (if already in DB) or by AP id URL
      mix egregoros.actors.refetch @bob@remote.example https://remote.example/users/alice

      # Only show how many would be refetched
      mix egregoros.actors.refetch --dry-run
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, targets, invalid} =
      OptionParser.parse(argv,
        strict: [
          all: :boolean,
          only_missing_emojis: :boolean,
          name_has_shortcodes: :boolean,
          domain: :string,
          limit: :integer,
          dry_run: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    opts = normalize_opts(opts)

    if targets != [] do
      refetch_targets(targets)
    else
      refetch_query(opts)
    end
  end

  defp normalize_opts(opts) do
    if Keyword.get(opts, :all, false) do
      opts
      |> Keyword.put(:only_missing_emojis, false)
      |> Keyword.delete(:all)
    else
      opts
      |> Keyword.delete(:all)
      |> Keyword.put_new(:only_missing_emojis, true)
    end
  end

  defp refetch_query(opts) do
    if Keyword.get(opts, :dry_run, false) do
      total =
        opts
        |> Keyword.delete(:dry_run)
        |> Egregoros.Maintenance.RefetchRemoteActors.list_ap_ids()
        |> length()

      Mix.shell().info("would refetch #{total} remote actors")
    else
      summary = Egregoros.Maintenance.RefetchRemoteActors.refetch(opts)
      Mix.shell().info("refetch complete: #{inspect(summary)}")
    end
  end

  defp refetch_targets(targets) when is_list(targets) do
    {ok, error} =
      Enum.reduce(targets, {0, 0}, fn target, {ok, error} ->
        case resolve_target(target) do
          {:ok, ap_id} ->
            case Egregoros.Federation.Actor.fetch_and_store(ap_id) do
              {:ok, _user} -> {ok + 1, error}
              _ -> {ok, error + 1}
            end

          {:error, reason} ->
            Mix.shell().error("skipping #{target}: #{inspect(reason)}")
            {ok, error + 1}
        end
      end)

    Mix.shell().info("refetch complete: %{total: #{length(targets)}, ok: #{ok}, error: #{error}}")
  end

  defp resolve_target(target) when is_binary(target) do
    case Egregoros.Users.get_by_handle(target) do
      %{ap_id: ap_id} when is_binary(ap_id) -> {:ok, ap_id}
      _ -> {:ok, target}
    end
  end

  defp resolve_target(_), do: {:error, :invalid_target}
end
