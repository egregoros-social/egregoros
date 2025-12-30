defmodule EgregorosWeb.MastodonAPI.TrendsController do
  use EgregorosWeb, :controller

  alias Egregoros.Objects
  alias EgregorosWeb.MastodonAPI.Pagination
  alias EgregorosWeb.MastodonAPI.StatusRenderer
  alias EgregorosWeb.URL

  @tag_sample_size 200

  def index(conn, params), do: tags(conn, params)

  def tags(conn, params) do
    pagination = Pagination.parse(params)
    json(conn, trending_tags(pagination.limit))
  end

  def statuses(conn, params) do
    pagination = Pagination.parse(params)

    objects =
      Objects.list_public_notes(
        limit: pagination.limit + 1,
        max_id: pagination.max_id,
        since_id: pagination.since_id
      )

    has_more? = length(objects) > pagination.limit
    objects = Enum.take(objects, pagination.limit)

    conn
    |> Pagination.maybe_put_links(objects, has_more?, pagination)
    |> json(StatusRenderer.render_statuses(objects))
  end

  def links(conn, _params) do
    json(conn, [])
  end

  defp trending_tags(limit) when is_integer(limit) do
    Objects.list_public_notes(limit: @tag_sample_size)
    |> Enum.reduce(%{}, &count_hashtags/2)
    |> Enum.map(fn {name, info} ->
      %{
        "name" => name,
        "url" => URL.absolute("/tags/" <> name),
        "history" => [
          %{
            "day" => today_unix_day(),
            "accounts" => Integer.to_string(info.accounts |> MapSet.size()),
            "uses" => Integer.to_string(info.uses)
          }
        ]
      }
    end)
    |> Enum.sort_by(fn tag ->
      {-String.to_integer(tag["history"] |> hd() |> Map.get("uses")), tag["name"]}
    end)
    |> Enum.take(limit)
  end

  defp trending_tags(_limit), do: []

  defp count_hashtags(object, acc) do
    actor = Map.get(object, :actor)

    hashtags =
      object
      |> hashtags_from_activity_tags()
      |> case do
        [] -> hashtags_from_content(object)
        tags -> tags
      end

    Enum.reduce(hashtags, acc, fn hashtag, counts ->
      Map.update(
        counts,
        hashtag,
        %{uses: 1, accounts: MapSet.new(List.wrap(actor))},
        fn existing ->
          %{
            uses: existing.uses + 1,
            accounts: MapSet.union(existing.accounts, MapSet.new(List.wrap(actor)))
          }
        end
      )
    end)
  end

  defp hashtags_from_activity_tags(%{data: %{} = data}) do
    data
    |> Map.get("tag", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.filter(&(Map.get(&1, "type") == "Hashtag"))
    |> Enum.map(&Map.get(&1, "name"))
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize_hashtag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp hashtags_from_activity_tags(_object), do: []

  defp hashtags_from_content(%{data: %{} = data}) do
    content =
      data
      |> Map.get("content", "")
      |> to_string()
      |> strip_html()

    Regex.scan(~r/#([\p{L}\p{N}_][\p{L}\p{N}_-]{0,63})/u, content)
    |> Enum.map(fn
      [_full, name] -> normalize_hashtag(name)
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp hashtags_from_content(_object), do: []

  defp normalize_hashtag(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.trim_leading("#")
    |> String.downcase()
  end

  defp normalize_hashtag(_name), do: ""

  defp strip_html(text) when is_binary(text) do
    Regex.replace(~r/<[^>]*>/, text, " ")
  end

  defp strip_html(_text), do: ""

  defp today_unix_day do
    Date.utc_today()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.to_unix()
    |> Integer.to_string()
  end
end
