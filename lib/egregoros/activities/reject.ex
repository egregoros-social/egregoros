defmodule Egregoros.Activities.Reject do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.ActivityPub.TypeNormalizer
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.Federation.Delivery
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.InboxTargeting
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.Relays
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  def type, do: "Reject"

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
      {:ok, %__MODULE__{} = reject} -> {:ok, apply_reject(activity, reject)}
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
    _ = apply_follow_reject(object)
    _ = apply_offer_reject(object)

    if Keyword.get(opts, :local, true) do
      deliver_reject(object)
    end

    :ok
  end

  def build(%User{} = actor, %Object{type: "Follow"} = follow_object) do
    %{
      "id" => Endpoint.url() <> "/activities/reject/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor.ap_id,
      "object" => follow_object.data,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def build(%User{} = actor, %Object{type: "Offer"} = offer_object) do
    %{
      "id" => Endpoint.url() <> "/activities/reject/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor.ap_id,
      "object" => offer_object.data,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp apply_follow_reject(%Object{} = reject_object) do
    follow_object =
      case reject_object.object do
        follow_ap_id when is_binary(follow_ap_id) ->
          Objects.get_by_ap_id(follow_ap_id)

        _ ->
          nil
      end

    follow_data =
      cond do
        match?(%Object{type: "Follow"}, follow_object) ->
          follow_object.data

        is_map(reject_object.data["object"]) ->
          reject_object.data["object"]

        true ->
          nil
      end

    case follow_data do
      %{"type" => "Follow", "actor" => actor, "object" => target} ->
        actor_ap_id = extract_id(actor)
        target_ap_id = extract_id(target)

        if is_binary(actor_ap_id) and actor_ap_id != "" and is_binary(target_ap_id) and
             target_ap_id != "" do
          _ =
            Relationships.delete_by_type_actor_object("FollowRequest", actor_ap_id, target_ap_id)

          _ = Relationships.delete_by_type_actor_object("Follow", actor_ap_id, target_ap_id)
          _ = maybe_unsubscribe_relay(actor_ap_id, target_ap_id)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp apply_offer_reject(%Object{} = reject_object) do
    offer_ap_id = offer_ap_id_from_reject(reject_object)
    recipient_ap_id = normalize_ap_id(reject_object.actor)

    with offer_ap_id when is_binary(offer_ap_id) <- offer_ap_id,
         recipient_ap_id when is_binary(recipient_ap_id) <- recipient_ap_id do
      _ = Relationships.delete_by_type_actor_object("OfferPending", recipient_ap_id, offer_ap_id)

      _ =
        Relationships.upsert_relationship(%{
          type: "OfferRejected",
          actor: recipient_ap_id,
          object: offer_ap_id,
          activity_ap_id: offer_ap_id
        })

      :ok
    else
      _ -> :ok
    end
  end

  defp offer_ap_id_from_reject(%Object{} = reject_object) do
    embedded_offer =
      case reject_object.data do
        %{"object" => %{} = offer} -> offer
        _ -> nil
      end

    embedded_offer_id =
      if is_map(embedded_offer) and TypeNormalizer.primary_type(embedded_offer) == "Offer" do
        extract_id(embedded_offer)
      else
        nil
      end

    offer_ap_id_from_object(embedded_offer_id) || offer_ap_id_from_object(reject_object.object)
  end

  defp offer_ap_id_from_reject(_reject_object), do: nil

  defp offer_ap_id_from_object(offer_ap_id) when is_binary(offer_ap_id) do
    offer_ap_id = String.trim(offer_ap_id)

    if offer_ap_id == "" do
      nil
    else
      case Objects.get_by_ap_id(offer_ap_id) do
        %Object{type: "Offer"} -> offer_ap_id
        _ -> nil
      end
    end
  end

  defp offer_ap_id_from_object(_offer_ap_id), do: nil

  defp extract_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_id(id) when is_binary(id), do: id
  defp extract_id(_), do: nil

  defp maybe_unsubscribe_relay(follower_ap_id, relay_ap_id)
       when is_binary(follower_ap_id) and is_binary(relay_ap_id) do
    instance_actor_ap_id = InstanceActor.ap_id()
    follower_ap_id = String.trim(follower_ap_id)

    if follower_ap_id == instance_actor_ap_id do
      if Relays.subscribed?(relay_ap_id) do
        _ = Relays.delete_by_ap_id(relay_ap_id)
      end

      :ok
    else
      :ok
    end
  end

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate(opts, fn inbox_user_ap_id ->
      cond do
        InboxTargeting.addressed_to?(activity, inbox_user_ap_id) ->
          :ok

        rejected_follower_ap_id(activity) == inbox_user_ap_id ->
          :ok

        true ->
          {:error, :not_targeted}
      end
    end)
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp rejected_follower_ap_id(%{"object" => %{} = follow}) do
    follow
    |> Map.get("actor")
    |> normalize_ap_id()
  end

  defp rejected_follower_ap_id(%{"object" => object_id}) when is_binary(object_id) do
    case Objects.get_by_ap_id(object_id) do
      %Object{actor: actor} -> normalize_ap_id(actor)
      _ -> nil
    end
  end

  defp rejected_follower_ap_id(_activity), do: nil

  defp normalize_ap_id(nil), do: nil

  defp normalize_ap_id(ap_id) when is_binary(ap_id) do
    ap_id
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp deliver_reject(%Object{} = reject_object) do
    with %{} = actor <- Users.get_by_ap_id(reject_object.actor),
         %{} = target <- rejected_target(reject_object),
         false <- target.local do
      Delivery.deliver(actor, target.inbox, reject_object.data)
    end
  end

  defp rejected_follower(%Object{} = reject_object) do
    case reject_object.data["object"] do
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

  defp rejected_target(%Object{} = reject_object) do
    rejected_follower(reject_object) || rejected_offer_actor(reject_object)
  end

  defp rejected_offer_actor(%Object{} = reject_object) do
    case reject_object.data["object"] do
      %{} = offer ->
        if TypeNormalizer.primary_type(offer) == "Offer" do
          offer
          |> Map.get("actor")
          |> extract_id()
          |> Users.get_by_ap_id()
        else
          nil
        end

      offer_ap_id when is_binary(offer_ap_id) ->
        case Objects.get_by_ap_id(offer_ap_id) do
          %Object{type: "Offer", actor: actor} when is_binary(actor) ->
            Users.get_by_ap_id(actor)

          _ ->
            nil
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
      published: Helpers.parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
    |> Helpers.attach_type_metadata(opts)
  end

  defp apply_reject(activity, %__MODULE__{} = reject) do
    object_value = reject.embedded_object || reject.object

    activity
    |> Map.put("id", reject.id)
    |> Map.put("type", reject.type)
    |> Map.put("actor", reject.actor)
    |> Map.put("object", object_value)
    |> Helpers.maybe_put("to", reject.to)
    |> Helpers.maybe_put("cc", reject.cc)
    |> Helpers.maybe_put("published", reject.published)
  end

  defp maybe_embed_object(%{"object" => %{} = object} = activity) do
    Map.put(activity, "embedded_object", object)
  end

  defp maybe_embed_object(activity), do: activity

  defp extract_object_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_object_id(id) when is_binary(id), do: id
  defp extract_object_id(_), do: nil
end
