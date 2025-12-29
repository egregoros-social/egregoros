defmodule Egregoros.Activities.Follow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.Activities.Accept
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  def type, do: "Follow"

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

  def build(%User{ap_id: actor}, %User{ap_id: object}) do
    build(actor, object)
  end

  def build(actor, object) when is_binary(actor) and is_binary(object) do
    %{
      "id" => Endpoint.url() <> "/activities/follow/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "object" => object,
      "to" => [object],
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
      {:ok, %__MODULE__{} = follow} ->
        {:ok, apply_follow(activity, follow)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def ingest(activity, opts) do
    with :ok <- validate_inbox_target(activity, opts) do
      activity
      |> to_object_attrs(opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(object, opts) do
    relationship_type = relationship_type(object, opts)

    _ =
      Relationships.upsert_relationship(%{
        type: relationship_type,
        actor: object.actor,
        object: object.object,
        activity_ap_id: object.ap_id
      })

    maybe_broadcast_notification(object)

    if Keyword.get(opts, :local, true) do
      deliver_follow(object)
    else
      accept_follow(object)
    end

    :ok
  end

  defp relationship_type(%{type: "Follow", object: object_ap_id}, opts)
       when is_binary(object_ap_id) and is_list(opts) do
    if Keyword.get(opts, :local, true) do
      case Users.get_by_ap_id(object_ap_id) do
        %User{local: true, locked: true} -> "FollowRequest"
        %User{local: true} -> "Follow"
        _ -> "FollowRequest"
      end
    else
      case Users.get_by_ap_id(object_ap_id) do
        %User{local: true, locked: true} -> "FollowRequest"
        _ -> "Follow"
      end
    end
  end

  defp relationship_type(_object, _opts), do: "Follow"

  defp maybe_broadcast_notification(object) do
    with %{} = target <- Users.get_by_ap_id(object.object),
         true <- target.local,
         true <- target.ap_id != object.actor do
      Notifications.broadcast(target.ap_id, object)
    else
      _ -> :ok
    end
  end

  defp deliver_follow(object) do
    with %{} = actor <- Users.get_by_ap_id(object.actor),
         %{} = target <- Users.get_by_ap_id(object.object),
         false <- target.local do
      Egregoros.Federation.Delivery.deliver(actor, target.inbox, object.data)
    end
  end

  defp accept_follow(object) do
    with %{} = target <- Users.get_by_ap_id(object.object),
         true <- target.local,
         false <- target.locked do
      accept = Accept.build(target, object)
      _ = Pipeline.ingest(accept, local: true)
      :ok
    else
      _ -> :ok
    end
  end

  defp validate_inbox_target(%{"object" => object}, opts)
       when is_binary(object) and is_list(opts) do
    if Keyword.get(opts, :local, true) do
      :ok
    else
      case Keyword.get(opts, :inbox_user_ap_id) do
        inbox_user_ap_id when is_binary(inbox_user_ap_id) and inbox_user_ap_id != "" ->
          if object == inbox_user_ap_id, do: :ok, else: {:error, :not_targeted}

        _ ->
          :ok
      end
    end
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

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

  defp apply_follow(activity, %__MODULE__{} = follow) do
    activity
    |> Map.put("id", follow.id)
    |> Map.put("type", follow.type)
    |> Map.put("actor", follow.actor)
    |> Map.put("object", follow.object)
    |> maybe_put("to", follow.to)
    |> maybe_put("cc", follow.cc)
    |> maybe_put("published", follow.published)
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
