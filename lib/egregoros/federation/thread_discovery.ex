defmodule Egregoros.Federation.ThreadDiscovery do
  @moduledoc false

  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Workers.FetchThreadAncestors
  alias Egregoros.Workers.FetchThreadReplies

  @default_max_depth 20
  @default_replies_max_pages 2
  @default_replies_max_items 50

  def enqueue(object, opts \\ [])

  def enqueue(%Object{type: "Note", ap_id: ap_id, data: %{} = data} = object, opts)
      when is_list(opts) do
    if Keyword.get(opts, :thread_fetch, false) do
      :ok
    else
      parent_ap_id =
        data
        |> Map.get("inReplyTo")
        |> in_reply_to_ap_id()

      if should_enqueue?(object, parent_ap_id) do
        args = %{"start_ap_id" => ap_id, "max_depth" => @default_max_depth}
        _ = Oban.insert(FetchThreadAncestors.new(args))
        :ok
      else
        :ok
      end
    end
  end

  def enqueue(_object, _opts), do: :ok

  def enqueue_replies(object, opts \\ [])

  def enqueue_replies(%Object{type: "Note", local: false, ap_id: ap_id, data: %{} = data}, opts)
      when is_list(opts) do
    existing_descendants =
      opts
      |> Keyword.get(:existing_descendants, 0)
      |> normalize_nonneg_int(0)

    if existing_descendants > 0 do
      :ok
    else
      replies_url =
        data
        |> Map.get("replies")
        |> extract_link()

      if should_enqueue_replies?(replies_url) do
        max_pages =
          opts
          |> Keyword.get(:max_pages, @default_replies_max_pages)
          |> normalize_nonneg_int(@default_replies_max_pages)
          |> max(1)
          |> min(10)

        max_items =
          opts
          |> Keyword.get(:max_items, @default_replies_max_items)
          |> normalize_nonneg_int(@default_replies_max_items)
          |> max(1)
          |> min(200)

        args = %{
          "root_ap_id" => ap_id,
          "max_pages" => max_pages,
          "max_items" => max_items
        }

        _ = Oban.insert(FetchThreadReplies.new(args, priority: 9))
        :ok
      else
        :ok
      end
    end
  end

  def enqueue_replies(_object, _opts), do: :ok

  defp should_enqueue?(_object, parent_ap_id) when not is_binary(parent_ap_id), do: false

  defp should_enqueue?(_object, parent_ap_id) do
    parent_ap_id = String.trim(parent_ap_id)

    cond do
      parent_ap_id == "" -> false
      not String.starts_with?(parent_ap_id, ["http://", "https://"]) -> false
      Objects.get_by_ap_id(parent_ap_id) != nil -> false
      true -> true
    end
  end

  defp in_reply_to_ap_id(value) when is_binary(value), do: value
  defp in_reply_to_ap_id(%{"id" => id}) when is_binary(id), do: id
  defp in_reply_to_ap_id(_), do: nil

  defp should_enqueue_replies?(replies_url) when not is_binary(replies_url), do: false

  defp should_enqueue_replies?(replies_url) do
    replies_url = String.trim(replies_url)

    cond do
      replies_url == "" -> false
      not String.starts_with?(replies_url, ["http://", "https://"]) -> false
      true -> true
    end
  end

  defp extract_link(value) when is_binary(value), do: value
  defp extract_link(%{"id" => id}) when is_binary(id), do: id
  defp extract_link(%{id: id}) when is_binary(id), do: id
  defp extract_link(_), do: nil

  defp normalize_nonneg_int(value, default) when is_integer(default) and default >= 0 do
    case value do
      v when is_integer(v) and v >= 0 -> v
      _ -> default
    end
  end
end
