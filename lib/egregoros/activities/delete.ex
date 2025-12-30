defmodule Egregoros.Activities.Delete do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.Federation.Delivery
  alias Egregoros.InboxTargeting
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

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

  def ingest(activity, opts) do
    with :ok <- validate_inbox_target(activity, opts) do
      activity
      |> to_object_attrs(opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(%Object{} = delete_object, opts) do
    target = Objects.get_by_ap_id(delete_object.object)
    _ = delete_target(delete_object, target)

    if Keyword.get(opts, :local, true) do
      deliver_delete(delete_object)
    end

    :ok
  end

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate(opts, fn inbox_user_ap_id ->
      actor_ap_id = Map.get(activity, "actor")

      cond do
        InboxTargeting.addressed_to?(activity, inbox_user_ap_id) ->
          :ok

        InboxTargeting.follows?(inbox_user_ap_id, actor_ap_id) ->
          :ok

        true ->
          {:error, :not_targeted}
      end
    end)
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

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
      published: Helpers.parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
  end

  defp apply_delete(activity, %__MODULE__{} = delete) do
    activity
    |> Map.put("id", delete.id)
    |> Map.put("type", delete.type)
    |> Map.put("actor", delete.actor)
    |> Map.put("object", delete.object)
    |> Helpers.maybe_put("to", delete.to)
    |> Helpers.maybe_put("cc", delete.cc)
    |> Helpers.maybe_put("published", delete.published)
  end

end
