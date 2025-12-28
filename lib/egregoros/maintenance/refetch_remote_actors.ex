defmodule Egregoros.Maintenance.RefetchRemoteActors do
  @moduledoc false

  import Ecto.Query, only: [from: 2]

  alias Egregoros.Federation.Actor
  alias Egregoros.Repo
  alias Egregoros.User

  def refetch(opts \\ []) when is_list(opts) do
    ap_ids = list_ap_ids(opts)

    {ok, error} =
      Enum.reduce(ap_ids, {0, 0}, fn ap_id, {ok, error} ->
        case Actor.fetch_and_store(ap_id) do
          {:ok, _user} -> {ok + 1, error}
          _ -> {ok, error + 1}
        end
      end)

    %{total: length(ap_ids), ok: ok, error: error}
  end

  def list_ap_ids(opts \\ []) when is_list(opts) do
    query =
      opts
      |> base_query()
      |> maybe_limit(opts)

    Repo.all(from(u in query, select: u.ap_id))
  end

  defp base_query(opts) when is_list(opts) do
    only_missing_emojis = Keyword.get(opts, :only_missing_emojis, true)
    name_has_shortcodes = Keyword.get(opts, :name_has_shortcodes, false)
    domain = opts |> Keyword.get(:domain, nil) |> normalize_optional_string()

    query = from(u in User, where: u.local == false)

    query =
      if only_missing_emojis do
        from(u in query, where: fragment("cardinality(?) = 0", u.emojis))
      else
        query
      end

    query =
      if is_binary(domain) do
        from(u in query, where: u.domain == ^domain)
      else
        query
      end

    if name_has_shortcodes do
      from(u in query, where: fragment("? ~ ?", u.name, ":([A-Za-z0-9_+-]{1,64}):"))
    else
      query
    end
  end

  defp maybe_limit(query, opts) when is_list(opts) do
    case Keyword.get(opts, :limit, nil) do
      limit when is_integer(limit) and limit > 0 ->
        from(u in query, limit: ^limit)

      _ ->
        query
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
