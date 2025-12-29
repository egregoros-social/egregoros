defmodule Egregoros.Activities.Accept do
  use Ecto.Schema

  import Ecto.Changeset

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

  def ingest(activity, opts) do
    with :ok <- validate_inbox_target(activity, opts) do
      activity
      |> to_object_attrs(opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(object, opts) do
    _ = apply_follow_accept(object)

    if Keyword.get(opts, :local, true) do
      deliver_accept(object)
    end

    :ok
  end

  defp apply_follow_accept(%Object{} = accept_object) do
    follow_object =
      case accept_object.object do
        follow_ap_id when is_binary(follow_ap_id) ->
          Objects.get_by_ap_id(follow_ap_id)

        _ ->
          nil
      end

    follow_data =
      cond do
        match?(%Object{type: "Follow"}, follow_object) ->
          follow_object.data

        is_map(accept_object.data["object"]) ->
          accept_object.data["object"]

        true ->
          nil
      end

    case follow_data do
      %{"type" => "Follow", "actor" => actor, "object" => target} ->
        actor_ap_id = extract_id(actor)
        target_ap_id = extract_id(target)

        activity_ap_id =
          case follow_object do
            %Object{type: "Follow"} = stored_follow -> stored_follow.ap_id
            _ -> Map.get(follow_data, "id")
          end

        if is_binary(actor_ap_id) and actor_ap_id != "" and is_binary(target_ap_id) and
             target_ap_id != "" do
          _ =
            Relationships.upsert_relationship(%{
              type: "Follow",
              actor: actor_ap_id,
              object: target_ap_id,
              activity_ap_id: activity_ap_id
            })

          _ = Relationships.delete_by_type_actor_object("FollowRequest", actor_ap_id, target_ap_id)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp extract_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_id(id) when is_binary(id), do: id
  defp extract_id(_), do: nil

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate(opts, fn inbox_user_ap_id ->
      cond do
        InboxTargeting.addressed_to?(activity, inbox_user_ap_id) ->
          :ok

        accepted_follower_ap_id(activity) == inbox_user_ap_id ->
          :ok

        true ->
          {:error, :not_targeted}
      end
    end)
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp accepted_follower_ap_id(%{"object" => %{} = follow}) do
    follow
    |> Map.get("actor")
    |> normalize_ap_id()
  end

  defp accepted_follower_ap_id(%{"object" => object_id}) when is_binary(object_id) do
    case Objects.get_by_ap_id(object_id) do
      %Object{actor: actor} -> normalize_ap_id(actor)
      _ -> nil
    end
  end

  defp accepted_follower_ap_id(_activity), do: nil

  defp normalize_ap_id(nil), do: nil

  defp normalize_ap_id(ap_id) when is_binary(ap_id) do
    ap_id
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
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
