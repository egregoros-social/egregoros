defmodule Egregoros.Workers.FetchThreadAncestors do
  use Oban.Worker,
    queue: :federation_incoming,
    max_attempts: 3,
    unique: [period: 60 * 60, keys: [:start_ap_id]]

  alias Egregoros.Federation.ObjectFetcher
  alias Egregoros.Object
  alias Egregoros.Objects

  @default_max_depth 20
  @max_depth_limit 50

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"start_ap_id" => start_ap_id} = args})
      when is_binary(start_ap_id) do
    max_depth =
      args
      |> Map.get("max_depth", @default_max_depth)
      |> normalize_max_depth()

    case Objects.get_by_ap_id(start_ap_id) do
      %Object{} = start ->
        start_for_ancestors = normalize_start_object(start)

        visited =
          [start_ap_id, start_for_ancestors.ap_id]
          |> Enum.filter(&is_binary/1)
          |> MapSet.new()

        fetch_ancestors(start_for_ancestors, visited, max_depth)

      nil ->
        case ObjectFetcher.fetch_and_ingest(start_ap_id) do
          {:ok, %Object{} = start} ->
            start_for_ancestors = normalize_start_object(start)

            visited =
              [start_ap_id, start_for_ancestors.ap_id]
              |> Enum.filter(&is_binary/1)
              |> MapSet.new()

            fetch_ancestors(start_for_ancestors, visited, max_depth)

          {:error, reason} ->
            {:error, reason}

          _ ->
            {:error, :object_fetch_failed}
        end
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_args}

  defp fetch_ancestors(%Object{} = object, visited, remaining)
       when is_integer(remaining) and remaining > 0 do
    parent_ap_id =
      object.data
      |> Map.get("inReplyTo")
      |> in_reply_to_ap_id()

    cond do
      not is_binary(parent_ap_id) ->
        :ok

      MapSet.member?(visited, parent_ap_id) ->
        :ok

      true ->
        case Objects.get_by_ap_id(parent_ap_id) do
          %Object{} = parent ->
            fetch_ancestors(parent, MapSet.put(visited, parent_ap_id), remaining - 1)

          nil ->
            case ObjectFetcher.fetch_and_ingest(parent_ap_id) do
              {:ok, %Object{} = parent} ->
                fetch_ancestors(parent, MapSet.put(visited, parent_ap_id), remaining - 1)

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
        end
    end
  end

  defp fetch_ancestors(_object, _visited, _remaining), do: :ok

  defp in_reply_to_ap_id(value) when is_binary(value), do: value
  defp in_reply_to_ap_id(%{"id" => id}) when is_binary(id), do: id
  defp in_reply_to_ap_id(_), do: nil

  defp normalize_start_object(%Object{type: "Create", object: embedded_ap_id} = create)
       when is_binary(embedded_ap_id) do
    case Objects.get_by_ap_id(embedded_ap_id) do
      %Object{type: "Note"} = note -> note
      _ -> create
    end
  end

  defp normalize_start_object(%Object{} = object), do: object

  defp normalize_max_depth(max_depth) when is_integer(max_depth) do
    max_depth
    |> max(1)
    |> min(@max_depth_limit)
  end

  defp normalize_max_depth(max_depth) when is_binary(max_depth) do
    case Integer.parse(max_depth) do
      {int, ""} -> normalize_max_depth(int)
      _ -> @default_max_depth
    end
  end

  defp normalize_max_depth(_max_depth), do: @default_max_depth
end
