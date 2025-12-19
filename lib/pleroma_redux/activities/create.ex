defmodule PleromaRedux.Activities.Create do
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  def type, do: "Create"

  def build(%User{ap_id: actor}, object) when is_map(object) do
    build(actor, object)
  end

  def build(actor, object) when is_binary(actor) and is_map(object) do
    to = object["to"] || ["https://www.w3.org/ns/activitystreams#Public"]
    cc = object["cc"] || [actor <> "/followers"]

    %{
      "id" => Endpoint.url() <> "/activities/create/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "to" => to,
      "cc" => cc,
      "object" => object,
      "published" => object["published"] || DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def normalize(%{"type" => "Create"} = activity) do
    activity
    |> put_actor()
  end

  def normalize(_), do: nil

  def validate(%{"id" => id, "type" => "Create", "actor" => actor, "object" => object} = activity)
      when is_binary(id) and is_binary(actor) and is_map(object) do
    if is_binary(object["id"]) and is_binary(object["type"]) do
      {:ok, activity}
    else
      {:error, :invalid}
    end
  end

  def validate(_), do: {:error, :invalid}

  def ingest(activity, opts) do
    with {:ok, object} <- Pipeline.ingest(activity["object"], opts) do
      activity
      |> to_object_attrs(object, opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(object, opts) do
    if Keyword.get(opts, :local, true) do
      deliver_to_followers(object)
    end

    :ok
  end

  defp deliver_to_followers(create_object) do
    with %{} = actor <- Users.get_by_ap_id(create_object.actor) do
      actor.ap_id
      |> Relationships.list_follows_to()
      |> Enum.each(fn follow ->
        with %{} = follower <- Users.get_by_ap_id(follow.actor),
             false <- follower.local do
          PleromaRedux.Federation.Delivery.deliver(actor, follower.inbox, create_object.data)
        end
      end)
    end
  end

  defp to_object_attrs(activity, embedded_object, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: embedded_object.ap_id,
      data: activity,
      published: parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
  end

  defp put_actor(%{"actor" => _} = activity), do: activity

  defp put_actor(%{"attributedTo" => actor} = activity) when is_binary(actor) do
    Map.put(activity, "actor", actor)
  end

  defp put_actor(activity), do: activity

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
