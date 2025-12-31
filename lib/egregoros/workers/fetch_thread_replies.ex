defmodule Egregoros.Workers.FetchThreadReplies do
  use Oban.Worker,
    queue: :federation_incoming,
    max_attempts: 3,
    unique: [period: 60 * 60, keys: [:root_ap_id]]

  alias Egregoros.Federation.ObjectFetcher
  alias Egregoros.Federation.SignedFetch
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline

  @default_max_pages 2
  @default_max_items 50
  @max_pages_limit 10
  @max_items_limit 200

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"root_ap_id" => root_ap_id} = args})
      when is_binary(root_ap_id) do
    max_pages =
      args
      |> Map.get("max_pages", @default_max_pages)
      |> normalize_max_pages()

    max_items =
      args
      |> Map.get("max_items", @default_max_items)
      |> normalize_max_items()

    with %Object{} = root <- Objects.get_by_ap_id(root_ap_id),
         %Object{} = note <- normalize_note(root),
         replies_url when is_binary(replies_url) <- replies_url(note),
         replies_url <- String.trim(replies_url),
         true <- replies_url != "" do
      fetch_pages(replies_url, max_pages, max_items, MapSet.new())
    else
      nil ->
        case ObjectFetcher.fetch_and_ingest(root_ap_id) do
          {:ok, %Object{} = fetched} ->
            note = normalize_note(fetched)

            replies_url =
              note
              |> replies_url()
              |> normalize_binary()

            if replies_url == "" do
              :ok
            else
              fetch_pages(replies_url, max_pages, max_items, MapSet.new())
            end

          {:error, {:http_status, status}} when status in [401, 403, 404, 410] ->
            :ok

          {:error, :unsafe_url} ->
            :ok

          {:error, :id_mismatch} ->
            :ok

          {:error, :invalid_json} ->
            :ok

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, :object_fetch_failed}
        end

      _ ->
        :ok
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_args}

  defp fetch_pages(url, pages_left, items_left, visited)
       when is_binary(url) and is_integer(pages_left) and pages_left > 0 and is_integer(items_left) and
              items_left > 0 and is_map(visited) do
    url = String.trim(url)

    cond do
      url == "" ->
        :ok

      MapSet.member?(visited, url) ->
        :ok

      true ->
        visited = MapSet.put(visited, url)

        case fetch_json(url) do
          {:ok, %{} = json} ->
            {items, next_url} = collection_items_and_next(json)
            {items, remaining} = take_items(items, items_left)
            _ = ingest_items(items)

            next_url = normalize_binary(next_url)

            if next_url == "" or remaining <= 0 do
              :ok
            else
              fetch_pages(next_url, pages_left - 1, remaining, visited)
            end

          {:error, {:http_status, status}} when status in [401, 403, 404, 410] ->
            :ok

          {:error, :unsafe_url} ->
            :ok

          {:error, :invalid_json} ->
            :ok

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, :replies_fetch_failed}
        end
    end
  end

  defp fetch_pages(_url, _pages_left, _items_left, _visited), do: :ok

  defp fetch_json(url) when is_binary(url) do
    with {:ok, %{status: status, body: body}} <- SignedFetch.get(url),
         true <- status in 200..299,
         {:ok, %{} = json} <- decode_json(body) do
      {:ok, json}
    else
      false ->
        {:error, :replies_fetch_failed}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, _} = error ->
        error

      _ ->
        {:error, :replies_fetch_failed}
    end
  end

  defp decode_json(body) when is_map(body), do: {:ok, body}

  defp decode_json(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> {:error, :invalid_json}
    end
  end

  defp decode_json(_body), do: {:error, :invalid_json}

  defp collection_items_and_next(%{} = json) do
    items =
      json
      |> Map.get("orderedItems") ||
        Map.get(json, "items") ||
        []
      |> List.wrap()

    next =
      json
      |> Map.get("next")
      |> extract_link()

    first =
      json
      |> Map.get("first")
      |> extract_link()

    cond do
      items != [] ->
        {items, next}

      is_binary(first) ->
        {[], first}

      true ->
        {[], nil}
    end
  end

  defp extract_link(value) when is_binary(value), do: value
  defp extract_link(%{"id" => id}) when is_binary(id), do: id
  defp extract_link(%{id: id}) when is_binary(id), do: id
  defp extract_link(_), do: nil

  defp take_items(items, limit) when is_list(items) and is_integer(limit) and limit > 0 do
    {Enum.take(items, limit), limit - min(length(items), limit)}
  end

  defp take_items(_items, _limit), do: {[], 0}

  defp ingest_items(items) when is_list(items) do
    Enum.each(items, fn
      %{} = activity ->
        _ = Pipeline.ingest(activity, local: false, thread_fetch: true)
        :ok

      id when is_binary(id) ->
        _ = ObjectFetcher.fetch_and_ingest(id)
        :ok

      _ ->
        :ok
    end)

    :ok
  end

  defp replies_url(%Object{type: "Note", data: %{} = data}) do
    data
    |> Map.get("replies")
    |> extract_link()
  end

  defp replies_url(_object), do: nil

  defp normalize_note(%Object{type: "Create", object: embedded_ap_id} = create)
       when is_binary(embedded_ap_id) do
    case Objects.get_by_ap_id(embedded_ap_id) do
      %Object{type: "Note"} = note -> note
      _ -> create
    end
  end

  defp normalize_note(%Object{} = object), do: object

  defp normalize_binary(nil), do: ""

  defp normalize_binary(value) when is_binary(value) do
    value
    |> String.trim()
  end

  defp normalize_binary(_value), do: ""

  defp normalize_max_pages(value) when is_integer(value) do
    value
    |> max(1)
    |> min(@max_pages_limit)
  end

  defp normalize_max_pages(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> normalize_max_pages(int)
      _ -> @default_max_pages
    end
  end

  defp normalize_max_pages(_value), do: @default_max_pages

  defp normalize_max_items(value) when is_integer(value) do
    value
    |> max(1)
    |> min(@max_items_limit)
  end

  defp normalize_max_items(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> normalize_max_items(int)
      _ -> @default_max_items
    end
  end

  defp normalize_max_items(_value), do: @default_max_items
end

