defmodule PleromaRedux.Activities.Undo do
  use Ecto.Schema

  import Ecto.Changeset

  alias PleromaRedux.ActivityPub.ObjectValidators.Types.ObjectID
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.Recipients
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias PleromaRedux.Federation.Delivery
  alias PleromaRedux.Object
  alias PleromaRedux.Objects
  alias PleromaRedux.Relationships
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  def type, do: "Undo"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :object, ObjectID
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
  end

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

  def normalize(%{"type" => "Undo"} = activity) do
    activity
  end

  def normalize(_), do: nil

  def cast_and_validate(activity) when is_map(activity) do
    changeset =
      %__MODULE__{}
      |> cast(activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object])
      |> validate_inclusion(:type, [type()])

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = undo} -> {:ok, apply_undo(activity, undo)}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  def validate(activity) when is_map(activity) do
    case cast_and_validate(activity) do
      {:ok, validated} -> {:ok, validated}
      {:error, %Ecto.Changeset{}} -> {:error, :invalid}
      {:error, _} = error -> error
    end
  end

  def validate(_), do: {:error, :invalid}

  def ingest(activity, opts) do
    activity
    |> to_object_attrs(opts)
    |> Objects.upsert_object()
  end

  def side_effects(object, opts) do
    target_activity = Objects.get_by_ap_id(object.object)

    if Keyword.get(opts, :local, true) do
      deliver_undo(object, target_activity)
    end

    _ = undo_target(target_activity)
    :ok
  end

  defp deliver_undo(%Object{} = undo_object, %Object{} = target_activity) do
    with %{} = actor <- Users.get_by_ap_id(undo_object.actor) do
      do_deliver(actor, target_activity, undo_object)
    end
  end

  defp deliver_undo(_undo_object, _target_activity), do: :ok

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
    |> Relationships.list_follows_to()
    |> Enum.each(fn follow ->
      with %{} = follower <- Users.get_by_ap_id(follow.actor),
           false <- follower.local do
        Delivery.deliver(actor, follower.inbox, undo_object.data)
      end
    end)
  end

  defp do_deliver(_actor, _activity, _undo_object), do: :ok

  defp undo_target(
         %Object{type: "Follow", actor: actor, object: object, ap_id: target_ap_id} =
           target_activity
       ) do
    case Relationships.get_by_type_actor_object("Follow", actor, object) do
      %{activity_ap_id: ^target_ap_id} ->
        _ = Relationships.delete_by_type_actor_object("Follow", actor, object)
        :ok

      _ ->
        :ok
    end

    Objects.delete_object(target_activity)
  end

  defp undo_target(
         %Object{type: type, actor: actor, object: object, ap_id: target_ap_id} = target_activity
       )
       when type in ["Like", "Announce"] do
    case Relationships.get_by_type_actor_object(type, actor, object) do
      %{activity_ap_id: ^target_ap_id} ->
        _ = Relationships.delete_by_type_actor_object(type, actor, object)
        :ok

      _ ->
        :ok
    end

    Objects.delete_object(target_activity)
  end

  defp undo_target(
         %Object{type: "EmojiReact", actor: actor, object: object, ap_id: target_ap_id} =
           target_activity
       ) do
    emoji = get_in(target_activity.data, ["content"])

    if is_binary(emoji) and emoji != "" do
      relationship_type = "EmojiReact:" <> emoji

      case Relationships.get_by_type_actor_object(relationship_type, actor, object) do
        %{activity_ap_id: ^target_ap_id} ->
          _ = Relationships.delete_by_type_actor_object(relationship_type, actor, object)
          :ok

        _ ->
          :ok
      end
    end

    Objects.delete_object(target_activity)
  end

  defp undo_target(_), do: :ok

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

  defp apply_undo(activity, %__MODULE__{} = undo) do
    activity
    |> Map.put("id", undo.id)
    |> Map.put("type", undo.type)
    |> Map.put("actor", undo.actor)
    |> Map.put("object", undo.object)
    |> maybe_put("to", undo.to)
    |> maybe_put("cc", undo.cc)
    |> maybe_put("published", undo.published)
  end

  defp maybe_put(activity, _key, nil), do: activity
  defp maybe_put(activity, key, value), do: Map.put(activity, key, value)

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
