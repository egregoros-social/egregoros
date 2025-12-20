defmodule PleromaRedux.Activities.Like do
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

  def type, do: "Like"

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
    build(actor, object_id, object)
  end

  def build(%User{ap_id: actor}, object_id) when is_binary(object_id) do
    build(actor, object_id)
  end

  def build(actor, object_id) when is_binary(actor) and is_binary(object_id) do
    base =
      %{
        "id" => Endpoint.url() <> "/activities/like/" <> Ecto.UUID.generate(),
        "type" => type(),
        "actor" => actor,
        "object" => object_id,
        "published" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

    base
  end

  defp build(actor, object_id, %Object{} = object) do
    base = build(actor, object_id)

    case recipients(actor, object) do
      %{} = recipients when map_size(recipients) > 0 -> Map.merge(base, recipients)
      _ -> base
    end
  end

  def normalize(%{"type" => "Like"} = activity), do: activity
  def normalize(_), do: nil

  def cast_and_validate(activity) when is_map(activity) do
    changeset =
      %__MODULE__{}
      |> cast(activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object])
      |> validate_inclusion(:type, [type()])

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = like} -> {:ok, apply_like(activity, like)}
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
    _ =
      Relationships.upsert_relationship(%{
        type: object.type,
        actor: object.actor,
        object: object.object,
        activity_ap_id: object.ap_id
      })

    if Keyword.get(opts, :local, true) do
      deliver_like(object)
    end

    :ok
  end

  defp deliver_like(object) do
    with %{} = actor <- Users.get_by_ap_id(object.actor),
         %{} = liked_object <- Objects.get_by_ap_id(object.object),
         %{} = target <- get_or_fetch_user(liked_object.actor),
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

  defp recipients(actor, %Object{actor: object_actor} = object) when is_binary(object_actor) do
    to =
      if public_object?(object) do
        [actor <> "/followers", object_actor]
      else
        [object_actor]
      end

    %{"to" => Enum.uniq(to)}
  end

  defp recipients(_actor, _object), do: %{}

  defp public_object?(%Object{data: %{"to" => to}}) when is_list(to), do: @public in to
  defp public_object?(_), do: false

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

  defp apply_like(activity, %__MODULE__{} = like) do
    activity
    |> Map.put("id", like.id)
    |> Map.put("type", like.type)
    |> Map.put("actor", like.actor)
    |> Map.put("object", like.object)
    |> maybe_put("to", like.to)
    |> maybe_put("cc", like.cc)
    |> maybe_put("published", like.published)
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
