defmodule PleromaRedux.Activities.Announce do
  alias PleromaRedux.Federation.Delivery
  alias PleromaRedux.Object
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  @public "https://www.w3.org/ns/activitystreams#Public"

  def type, do: "Announce"

  def build(%User{ap_id: actor}, %Object{} = object) do
    build(actor, object)
  end

  def build(actor, %Object{ap_id: object_id} = object)
      when is_binary(actor) and is_binary(object_id) do
    build(actor, object_id, object)
  end

  def build(%User{ap_id: actor}, object_id) when is_binary(object_id) do
    build(actor, object_id)
  end

  def build(actor, object_id) when is_binary(actor) and is_binary(object_id) do
    %{
      "id" => Endpoint.url() <> "/activities/announce/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "object" => object_id,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build(actor, object_id, %Object{} = object) do
    base = build(actor, object_id)
    Map.merge(base, recipients(actor, object))
  end

  def normalize(%{"type" => "Announce"} = activity) do
    activity
    |> normalize_actor()
  end

  def normalize(_), do: nil

  def validate(
        %{"id" => id, "type" => "Announce", "actor" => actor, "object" => object} = activity
      )
      when is_binary(id) and is_binary(actor) do
    cond do
      is_binary(object) ->
        {:ok, activity}

      is_map(object) and is_binary(object["id"]) ->
        {:ok, activity}

      true ->
        {:error, :invalid}
    end
  end

  def validate(_), do: {:error, :invalid}

  def ingest(%{"object" => %{} = embedded_object} = activity, opts) do
    with {:ok, _} <- Pipeline.ingest(embedded_object, opts) do
      activity
      |> to_object_attrs(opts)
      |> Objects.upsert_object()
    end
  end

  def ingest(activity, opts) do
    activity
    |> to_object_attrs(opts)
    |> Objects.upsert_object()
  end

  def side_effects(object, opts) do
    _ =
      Relationships.upsert_relationship(%{
        type: object.type,
        actor: object.actor,
        object: object.object,
        activity_ap_id: object.ap_id
      })

    if Keyword.get(opts, :local, true) do
      deliver_to_followers(object)
    end

    :ok
  end

  defp deliver_to_followers(announce_object) do
    with %{} = actor <- Users.get_by_ap_id(announce_object.actor) do
      actor.ap_id
      |> Relationships.list_follows_to()
      |> Enum.each(fn follow ->
        with %{} = follower <- Users.get_by_ap_id(follow.actor),
             false <- follower.local do
          Delivery.deliver(actor, follower.inbox, announce_object.data)
        end
      end)
    end
  end

  defp recipients(actor, %Object{actor: object_actor}) when is_binary(object_actor) do
    %{"to" => Enum.uniq([@public, actor <> "/followers", object_actor])}
  end

  defp recipients(actor, _object) do
    %{"to" => Enum.uniq([@public, actor <> "/followers"])}
  end

  defp to_object_attrs(activity, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: extract_object_id(activity["object"]),
      data: activity,
      published: parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
  end

  defp normalize_actor(%{"actor" => %{"id" => id}} = activity) when is_binary(id) do
    Map.put(activity, "actor", id)
  end

  defp normalize_actor(activity), do: activity

  defp extract_object_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_id(id) when is_binary(id), do: id
  defp extract_object_id(_), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
