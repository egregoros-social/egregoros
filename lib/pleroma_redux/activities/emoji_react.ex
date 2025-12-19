defmodule PleromaRedux.Activities.EmojiReact do
  alias PleromaRedux.Federation.Delivery
  alias PleromaRedux.Objects
  alias PleromaRedux.Users

  def type, do: "EmojiReact"

  def normalize(%{"type" => "EmojiReact"} = activity) do
    trim_content(activity)
  end

  def normalize(_), do: nil

  def validate(
        %{
          "id" => id,
          "type" => "EmojiReact",
          "actor" => actor,
          "object" => object,
          "content" => content
        } = activity
      )
      when is_binary(id) and is_binary(actor) and is_binary(object) and is_binary(content) and
             content != "" do
    {:ok, activity}
  end

  def validate(_), do: {:error, :invalid}

  def ingest(activity, opts) do
    activity
    |> to_object_attrs(opts)
    |> Objects.upsert_object()
  end

  def side_effects(object, opts) do
    if Keyword.get(opts, :local, true) do
      deliver_reaction(object)
    end

    :ok
  end

  defp deliver_reaction(object) do
    with %{} = actor <- Users.get_by_ap_id(object.actor),
         %{} = reacted_object <- Objects.get_by_ap_id(object.object),
         %{} = target <- get_or_fetch_user(reacted_object.actor),
         false <- target.local do
      Delivery.deliver(actor, target.inbox, object.data)
    end
  end

  defp get_or_fetch_user(nil), do: nil

  defp get_or_fetch_user(ap_id) when is_binary(ap_id) do
    Users.get_by_ap_id(ap_id) ||
      case PleromaRedux.Federation.Actor.fetch_and_store(ap_id) do
        {:ok, user} -> user
        _ -> nil
      end
  end

  defp to_object_attrs(activity, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: activity["object"],
      data: activity,
      published: parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
  end

  defp trim_content(%{"content" => content} = activity) when is_binary(content) do
    Map.put(activity, "content", String.trim(content))
  end

  defp trim_content(activity), do: activity

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
