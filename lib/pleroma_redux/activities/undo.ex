defmodule PleromaRedux.Activities.Undo do
  alias PleromaRedux.Federation.Delivery
  alias PleromaRedux.Object
  alias PleromaRedux.Objects
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  def type, do: "Undo"

  def build(%User{ap_id: actor}, %Object{} = target_activity) do
    build(actor, target_activity)
  end

  def build(actor, %Object{} = target_activity) when is_binary(actor) do
    base =
      %{
        "id" => Endpoint.url() <> "/activities/undo/" <> Ecto.UUID.generate(),
        "type" => type(),
        "actor" => actor,
        "object" => target_activity.ap_id,
        "published" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

    base
    |> maybe_copy_addressing(target_activity.data)
  end

  def build(%User{ap_id: actor}, object_id) when is_binary(object_id) do
    build(actor, object_id)
  end

  def build(actor, object_id) when is_binary(actor) and is_binary(object_id) do
    %{
      "id" => Endpoint.url() <> "/activities/undo/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "object" => object_id,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def normalize(%{"type" => "Undo"} = activity), do: activity
  def normalize(_), do: nil

  def validate(%{"id" => id, "type" => "Undo", "actor" => actor, "object" => object} = activity)
      when is_binary(id) and is_binary(actor) and is_binary(object) do
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
      deliver_undo(object)
    end

    :ok
  end

  defp deliver_undo(%Object{} = undo_object) do
    with %{} = actor <- Users.get_by_ap_id(undo_object.actor),
         %{} = target_activity <- Objects.get_by_ap_id(undo_object.object) do
      do_deliver(actor, target_activity, undo_object)
    end
  end

  defp do_deliver(actor, %Object{type: "Follow"} = follow, undo_object) do
    with %{} = target <- Users.get_by_ap_id(follow.object),
         false <- target.local do
      Delivery.deliver(actor, target.inbox, undo_object.data)
    end
  end

  defp do_deliver(actor, %Object{type: type} = activity, undo_object)
       when type in ["Like", "EmojiReact"] do
    with %{} = target_object <- Objects.get_by_ap_id(activity.object),
         %{} = target <- Users.get_by_ap_id(target_object.actor),
         false <- target.local do
      Delivery.deliver(actor, target.inbox, undo_object.data)
    end
  end

  defp do_deliver(actor, %Object{type: "Announce"}, undo_object) do
    actor.ap_id
    |> Objects.list_follows_to()
    |> Enum.filter(&(&1.local == false))
    |> Enum.each(fn follow ->
      with %{} = follower <- Users.get_by_ap_id(follow.actor) do
        Delivery.deliver(actor, follower.inbox, undo_object.data)
      end
    end)
  end

  defp do_deliver(_actor, _activity, _undo_object), do: :ok

  defp maybe_copy_addressing(activity, %{"to" => to} = target_data) when is_list(to) do
    activity
    |> Map.put("to", to)
    |> maybe_copy_cc(target_data)
  end

  defp maybe_copy_addressing(activity, target_data), do: maybe_copy_cc(activity, target_data)

  defp maybe_copy_cc(activity, %{"cc" => cc}) when is_list(cc), do: Map.put(activity, "cc", cc)
  defp maybe_copy_cc(activity, _), do: activity

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

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
