defmodule PleromaRedux.Activities.Delete do
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

  @public "https://www.w3.org/ns/activitystreams#Public"

  def type, do: "Delete"

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

  def build(%User{ap_id: actor}, %Object{} = object) do
    build(actor, object)
  end

  def build(actor, %Object{ap_id: object_id} = object)
      when is_binary(actor) and is_binary(object_id) do
    base = build(actor, object_id)

    case object.data do
      %{} = data when map_size(data) > 0 -> maybe_copy_addressing(base, data)
      _ -> base
    end
  end

  def build(%User{ap_id: actor}, object_id) when is_binary(object_id) do
    build(actor, object_id)
  end

  def build(actor, object_id) when is_binary(actor) and is_binary(object_id) do
    %{
      "id" => Endpoint.url() <> "/activities/delete/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "object" => object_id,
      "to" => [@public],
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def normalize(%{"type" => "Delete"} = activity), do: activity
  def normalize(_), do: nil

  def cast_and_validate(activity) when is_map(activity) do
    changeset =
      %__MODULE__{}
      |> cast(activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object])
      |> validate_inclusion(:type, [type()])

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = delete} -> {:ok, apply_delete(activity, delete)}
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

  def side_effects(%Object{} = delete_object, opts) do
    target = Objects.get_by_ap_id(delete_object.object)
    _ = delete_target(delete_object, target)

    if Keyword.get(opts, :local, true) do
      deliver_delete(delete_object)
    end

    :ok
  end

  defp delete_target(%Object{actor: actor} = _delete_object, %Object{actor: actor} = target) do
    _ = Objects.delete_object(target)
    _ = Relationships.delete_all_for_object(target.ap_id)
    :ok
  end

  defp delete_target(_delete_object, _target), do: :ok

  defp deliver_delete(%Object{} = delete_object) do
    with %{} = actor <- Users.get_by_ap_id(delete_object.actor) do
      actor.ap_id
      |> Relationships.list_follows_to()
      |> Enum.each(fn follow ->
        with %{} = follower <- Users.get_by_ap_id(follow.actor),
             false <- follower.local do
          Delivery.deliver(actor, follower.inbox, delete_object.data)
        end
      end)
    end
  end

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

  defp apply_delete(activity, %__MODULE__{} = delete) do
    activity
    |> Map.put("id", delete.id)
    |> Map.put("type", delete.type)
    |> Map.put("actor", delete.actor)
    |> Map.put("object", delete.object)
    |> maybe_put("to", delete.to)
    |> maybe_put("cc", delete.cc)
    |> maybe_put("published", delete.published)
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
