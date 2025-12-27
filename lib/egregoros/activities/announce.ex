defmodule Egregoros.Activities.Announce do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.Federation.Delivery
  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.Timeline
  alias Egregoros.User
  alias Egregoros.Users
  alias Egregoros.Workers.FetchThreadAncestors
  alias EgregorosWeb.Endpoint

  @public "https://www.w3.org/ns/activitystreams#Public"
  @fetch_priority 9

  def type, do: "Announce"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :object, ObjectID
    field :embedded_object, :map
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
  end

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

  def cast_and_validate(activity) when is_map(activity) do
    cast_activity = maybe_embed_object(activity)

    changeset =
      %__MODULE__{}
      |> cast(cast_activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object])
      |> validate_inclusion(:type, [type()])

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = announce} -> {:ok, apply_announce(activity, announce)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

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
    maybe_fetch_announced_object(object, opts)

    _ =
      Relationships.upsert_relationship(%{
        type: object.type,
        actor: object.actor,
        object: object.object,
        activity_ap_id: object.ap_id
      })

    maybe_broadcast_notification(object)
    Timeline.broadcast_post(object)

    if Keyword.get(opts, :local, true) do
      deliver_to_followers(object)
    end

    :ok
  end

  defp maybe_fetch_announced_object(%Object{object: announced_ap_id, data: %{} = data}, opts)
       when is_binary(announced_ap_id) and is_list(opts) do
    if Keyword.get(opts, :local, true) do
      :ok
    else
      announced_ap_id = String.trim(announced_ap_id)

      cond do
        announced_ap_id == "" ->
          :ok

        not public_activity?(data) ->
          :ok

        not String.starts_with?(announced_ap_id, ["http://", "https://"]) ->
          :ok

        Objects.get_by_ap_id(announced_ap_id) != nil ->
          :ok

        true ->
          _ =
            Oban.insert(
              FetchThreadAncestors.new(%{"start_ap_id" => announced_ap_id},
                priority: @fetch_priority
              )
            )

          :ok
      end
    end
  end

  defp maybe_fetch_announced_object(_object, _opts), do: :ok

  defp public_activity?(%{} = data) do
    data
    |> Map.get("to", [])
    |> List.wrap()
    |> Enum.any?(&(&1 == @public))
  end

  defp public_activity?(_), do: false

  defp maybe_broadcast_notification(object) do
    with %{} = announced_object <- Objects.get_by_ap_id(object.object),
         %{} = target <- Users.get_by_ap_id(announced_object.actor),
         true <- target.local,
         true <- target.ap_id != object.actor do
      Notifications.broadcast(target.ap_id, object)
    else
      _ -> :ok
    end
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

  defp apply_announce(activity, %__MODULE__{} = announce) do
    object_value = announce.embedded_object || announce.object

    activity
    |> Map.put("id", announce.id)
    |> Map.put("type", announce.type)
    |> Map.put("actor", announce.actor)
    |> Map.put("object", object_value)
    |> maybe_put("to", announce.to)
    |> maybe_put("cc", announce.cc)
    |> maybe_put("published", announce.published)
  end

  defp maybe_embed_object(%{"object" => %{} = object} = activity) do
    Map.put(activity, "embedded_object", object)
  end

  defp maybe_embed_object(activity), do: activity

  defp maybe_put(activity, _key, maybe_nil) when is_nil(maybe_nil), do: activity
  defp maybe_put(activity, key, value), do: Map.put(activity, key, value)

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
