defmodule PleromaReduxWeb.MastodonAPI.Pagination do
  alias PleromaReduxWeb.Endpoint

  @default_limit 20
  @max_limit 40

  def parse(params) when is_map(params) do
    %{
      limit: parse_limit(Map.get(params, "limit")),
      max_id: parse_id(Map.get(params, "max_id")),
      since_id: parse_id(Map.get(params, "since_id"))
    }
  end

  def maybe_put_links(conn, items, has_more?, %{limit: limit}) when is_list(items) do
    case items do
      [] ->
        conn

      _ ->
        first_id = List.first(items).id
        last_id = List.last(items).id

        base_params =
          conn.query_params
          |> Map.drop(["max_id", "since_id", "min_id"])
          |> Map.put("limit", Integer.to_string(limit))

        links =
          []
          |> maybe_put_prev(conn, base_params, first_id)
          |> maybe_put_next(conn, base_params, last_id, has_more?)

        if links == [] do
          conn
        else
          Plug.Conn.put_resp_header(conn, "link", Enum.join(links, ", "))
        end
    end
  end

  defp maybe_put_prev(links, conn, base_params, first_id) when is_list(links) do
    prev_params = Map.put(base_params, "since_id", Integer.to_string(first_id))
    prev_url = build_url(conn.request_path, prev_params)
    links ++ ["<#{prev_url}>; rel=\"prev\""]
  end

  defp maybe_put_next(links, conn, base_params, last_id, true) when is_list(links) do
    next_params = Map.put(base_params, "max_id", Integer.to_string(last_id))
    next_url = build_url(conn.request_path, next_params)
    links ++ ["<#{next_url}>; rel=\"next\""]
  end

  defp maybe_put_next(links, _conn, _base_params, _last_id, false), do: links

  defp build_url(path, params) when is_binary(path) and is_map(params) do
    query = URI.encode_query(params)

    Endpoint.url() <>
      path <>
      if query == "" do
        ""
      else
        "?" <> query
      end
  end

  defp parse_limit(nil), do: @default_limit

  defp parse_limit(value) when is_integer(value) do
    value
    |> max(1)
    |> min(@max_limit)
  end

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> parse_limit(int)
      _ -> @default_limit
    end
  end

  defp parse_limit(_), do: @default_limit

  defp parse_id(nil), do: nil

  defp parse_id(value) when is_integer(value) and value > 0, do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end

