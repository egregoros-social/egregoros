defmodule PleromaRedux.Activities.Follow do
  use Ecto.Schema

  import Ecto.Changeset

  alias PleromaRedux.ActivityPub.ObjectValidators.Types.ObjectID
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.Recipients
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias PleromaRedux.Activities.Accept
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.User
  alias PleromaRedux.Users
  alias PleromaReduxWeb.Endpoint

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

  def normalize(%{"type" => "Follow"} = activity) do
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
      {:ok, %__MODULE__{} = follow} ->
        {:ok, apply_follow(activity, follow)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
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
      deliver_follow(object)
    else
      accept_follow(object)
    end

    :ok
  end

  defp deliver_follow(object) do
    with %{} = actor <- Users.get_by_ap_id(object.actor),
         %{} = target <- Users.get_by_ap_id(object.object),
         false <- target.local do
      PleromaRedux.Federation.Delivery.deliver(actor, target.inbox, object.data)
    end
  end

  defp accept_follow(object) do
    with %{} = target <- Users.get_by_ap_id(object.object),
         true <- target.local do
      accept = Accept.build(target, object)
      _ = Pipeline.ingest(accept, local: true)
      :ok
    else
      _ -> :ok
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
