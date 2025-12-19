defmodule PleromaRedux.Activities.Announce do
  alias PleromaRedux.Federation.Delivery
  alias PleromaRedux.Objects
  alias PleromaRedux.Users

  def type, do: "Announce"

  def normalize(%{"type" => "Announce"} = activity), do: activity
  def normalize(_), do: nil

  def validate(
        %{"id" => id, "type" => "Announce", "actor" => actor, "object" => object} = activity
      )
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
      deliver_to_followers(object)
    end

    :ok
  end

  defp deliver_to_followers(announce_object) do
    with %{} = actor <- Users.get_by_ap_id(announce_object.actor) do
      actor.ap_id
      |> Objects.list_follows_to()
      |> Enum.filter(&(&1.local == false))
      |> Enum.each(fn follow ->
        with %{} = follower <- Users.get_by_ap_id(follow.actor) do
          Delivery.deliver(actor, follower.inbox, announce_object.data)
        end
      end)
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

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
