defmodule Egregoros.Activities.Undo do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.Activities.Offer
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.EmojiReactions
  alias Egregoros.Federation.Delivery
  alias Egregoros.InboxTargeting
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.Timeline
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

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

  def ingest(activity, opts) do
    with :ok <- validate_inbox_target(activity, opts) do
      activity
      |> to_object_attrs(opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(object, opts) do
    target_activity = Objects.get_by_ap_id(object.object)

    if authorized_undo?(object, target_activity) do
      if Keyword.get(opts, :local, true) do
        deliver_undo(object, target_activity)
      end

      _ = undo_target(target_activity)
    end

    :ok
  end

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate(opts, fn inbox_user_ap_id ->
      actor_ap_id = Map.get(activity, "actor")
      target_activity_ap_id = Map.get(activity, "object")

      cond do
        InboxTargeting.addressed_to?(activity, inbox_user_ap_id) ->
          :ok

        InboxTargeting.follows?(inbox_user_ap_id, actor_ap_id) ->
          :ok

        target_activity_ap_id
        |> targeted_via_undo_object?(inbox_user_ap_id) ->
          :ok

        true ->
          {:error, :not_targeted}
      end
    end)
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp targeted_via_undo_object?(target_activity_ap_id, inbox_user_ap_id)
       when is_binary(target_activity_ap_id) and is_binary(inbox_user_ap_id) do
    target_activity_ap_id = String.trim(target_activity_ap_id)
    inbox_user_ap_id = String.trim(inbox_user_ap_id)

    if target_activity_ap_id == "" or inbox_user_ap_id == "" do
      false
    else
      case Objects.get_by_ap_id(target_activity_ap_id) do
        %Object{type: "Follow", object: ^inbox_user_ap_id} ->
          true

        %Object{type: type, object: object_ap_id}
        when type in ["Like", "Announce", "EmojiReact"] ->
          InboxTargeting.object_owned_by?(object_ap_id, inbox_user_ap_id)

        %Object{type: "Offer"} = offer ->
          inbox_user_ap_id in Offer.recipient_ap_ids(offer)

        _ ->
          false
      end
    end
  end

  defp targeted_via_undo_object?(_target_activity_ap_id, _inbox_user_ap_id), do: false

  defp deliver_undo(%Object{} = undo_object, %Object{} = target_activity) do
    with %{} = actor <- Users.get_by_ap_id(undo_object.actor) do
      do_deliver(actor, target_activity, undo_object)
    end
  end

  defp deliver_undo(_undo_object, _target_activity), do: :ok

  defp authorized_undo?(%Object{actor: actor}, %Object{actor: actor}) when is_binary(actor),
    do: true

  defp authorized_undo?(_undo_object, _target_activity), do: false

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

  defp do_deliver(actor, %Object{type: "Offer"} = offer, undo_object) do
    offer
    |> Offer.recipient_ap_ids()
    |> Enum.each(fn recipient_ap_id ->
      case Users.get_by_ap_id(recipient_ap_id) do
        %User{local: false} = recipient ->
          Delivery.deliver(actor, recipient.inbox, undo_object.data)

        _ ->
          :ok
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

    case Relationships.get_by_type_actor_object("FollowRequest", actor, object) do
      %{activity_ap_id: ^target_ap_id} ->
        _ = Relationships.delete_by_type_actor_object("FollowRequest", actor, object)
        :ok

      _ ->
        :ok
    end

    Objects.delete_object(target_activity)
  end

  defp undo_target(%Object{type: "Offer", ap_id: target_ap_id} = target_activity)
       when is_binary(target_ap_id) do
    _ = Relationships.delete_all_for_object(target_ap_id)
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

    _ = maybe_broadcast_post_update(object)
    if type == "Announce", do: Timeline.broadcast_post_deleted(target_activity)
    Objects.delete_object(target_activity)
  end

  defp undo_target(
         %Object{type: "EmojiReact", actor: actor, object: object, ap_id: target_ap_id} =
           target_activity
       ) do
    emoji =
      target_activity.data
      |> get_in(["content"])
      |> EmojiReactions.normalize_content()

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

    _ = maybe_broadcast_post_update(object)
    Objects.delete_object(target_activity)
  end

  defp undo_target(_), do: :ok

  defp maybe_broadcast_post_update(object_ap_id) when is_binary(object_ap_id) do
    with %Object{} = object <- Objects.get_by_ap_id(object_ap_id),
         type when type in ["Note", "VerifiableCredential"] <- object.type do
      Timeline.broadcast_post_updated(object)
    else
      _ -> :ok
    end
  end

  defp maybe_broadcast_post_update(_object_ap_id), do: :ok

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
    |> Helpers.attach_type_metadata(opts)
  end

  defp apply_undo(activity, %__MODULE__{} = undo) do
    activity
    |> Map.put("id", undo.id)
    |> Map.put("type", undo.type)
    |> Map.put("actor", undo.actor)
    |> Map.put("object", undo.object)
    |> Helpers.maybe_put("to", undo.to)
    |> Helpers.maybe_put("cc", undo.cc)
    |> Helpers.maybe_put("published", undo.published)
  end
end
