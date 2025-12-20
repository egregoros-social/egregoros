defmodule PleromaRedux.Activities.Accept do
  use Ecto.Schema

  import Ecto.Changeset

  alias PleromaRedux.ActivityPub.ObjectValidators.Types.ObjectID
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.Recipients
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias PleromaRedux.Federation.Delivery
  alias PleromaRedux.Object
  alias PleromaRedux.Objects
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

  def type, do: "Accept"

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

  def normalize(%{"type" => "Accept"} = activity), do: activity
  def normalize(_), do: nil

  def cast_and_validate(activity) when is_map(activity) do
    cast_activity = maybe_embed_object(activity)

    changeset =
      %__MODULE__{}
      |> cast(cast_activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object])
      |> validate_inclusion(:type, [type()])

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = accept} -> {:ok, apply_accept(activity, accept)}
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
    if Keyword.get(opts, :local, true) do
      deliver_accept(object)
    end

    :ok
  end

  def build(%User{} = actor, %Object{type: "Follow"} = follow_object) do
    %{
      "id" => Endpoint.url() <> "/activities/accept/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor.ap_id,
      "object" => follow_object.data,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp deliver_accept(%Object{} = accept_object) do
    with %{} = actor <- Users.get_by_ap_id(accept_object.actor),
         %{} = follower <- accepted_follower(accept_object),
         false <- follower.local do
      Delivery.deliver(actor, follower.inbox, accept_object.data)
    end
  end

  defp accepted_follower(%Object{} = accept_object) do
    case accept_object.data["object"] do
      %{"actor" => actor} when is_binary(actor) ->
        Users.get_by_ap_id(actor)

      object_id when is_binary(object_id) ->
        case Objects.get_by_ap_id(object_id) do
          %Object{actor: actor} when is_binary(actor) -> Users.get_by_ap_id(actor)
          _ -> nil
        end

      _ ->
        nil
    end
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

  defp apply_accept(activity, %__MODULE__{} = accept) do
    object_value = accept.embedded_object || accept.object

    activity
    |> Map.put("id", accept.id)
    |> Map.put("type", accept.type)
    |> Map.put("actor", accept.actor)
    |> Map.put("object", object_value)
    |> maybe_put("to", accept.to)
    |> maybe_put("cc", accept.cc)
    |> maybe_put("published", accept.published)
  end

  defp maybe_embed_object(%{"object" => %{} = object} = activity) do
    Map.put(activity, "embedded_object", object)
  end

  defp maybe_embed_object(activity), do: activity

  defp maybe_put(activity, _key, nil), do: activity
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
