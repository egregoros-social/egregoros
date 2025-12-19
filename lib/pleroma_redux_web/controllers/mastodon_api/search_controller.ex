defmodule PleromaReduxWeb.MastodonAPI.SearchController do
  use PleromaReduxWeb, :controller

  alias PleromaRedux.Federation.Actor
  alias PleromaRedux.Federation.WebFinger
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint
  alias PleromaReduxWeb.MastodonAPI.AccountRenderer

  def index(conn, params) do
    q = params |> Map.get("q", "") |> to_string() |> String.trim()
    resolve? = Map.get(params, "resolve") in [true, "true"]
    limit = params |> Map.get("limit") |> parse_limit()

    accounts =
      q
      |> search_accounts(resolve?, limit)
      |> Enum.map(&AccountRenderer.render_account/1)

    json(conn, %{"accounts" => accounts, "statuses" => [], "hashtags" => []})
  end

  defp search_accounts("", _resolve?, _limit), do: []

  defp search_accounts(q, resolve?, limit) do
    local_matches = Users.search(q, limit: limit)

    matches =
      if resolve? and String.contains?(q, "@") do
        case resolve_account(q) do
          {:ok, user} -> [user | local_matches]
          _ -> local_matches
        end
      else
        local_matches
      end

    matches
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(limit)
  end

  defp resolve_account(q) do
    q =
      q
      |> String.trim()
      |> String.trim_leading("@")

    case String.split(q, "@", parts: 2) do
      [nickname, domain] when nickname != "" and domain != "" ->
        if domain == local_domain() do
          case Users.get_by_nickname(nickname) do
            nil -> {:error, :not_found}
            user -> {:ok, user}
          end
        else
          with {:ok, actor_url} <- WebFinger.lookup(q),
               {:ok, user} <- Actor.fetch_and_store(actor_url) do
            {:ok, user}
          end
        end

      _ ->
        {:error, :invalid_handle}
    end
  end

  defp local_domain do
    Endpoint.url()
    |> URI.parse()
    |> Map.get(:host)
    |> case do
      nil -> "localhost"
      host -> host
    end
  end

  defp parse_limit(nil), do: 20

  defp parse_limit(value) when is_integer(value) do
    value
    |> max(1)
    |> min(40)
  end

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> parse_limit(int)
      _ -> 20
    end
  end

  defp parse_limit(_), do: 20
end

