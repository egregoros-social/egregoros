defmodule Egregoros.Activities.EmojiReact do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.EmojiReactions
  alias Egregoros.Federation.Delivery
  alias Egregoros.InboxTargeting
  alias Egregoros.Notifications
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  @public "https://www.w3.org/ns/activitystreams#Public"

  def type, do: "EmojiReact"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :object, ObjectID
    field :content, :string
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
  end

  def build(%User{ap_id: actor}, %Object{} = object, content) when is_binary(content) do
    build(actor, object, content)
  end

  def build(actor, %Object{ap_id: object_id} = object, content)
      when is_binary(actor) and is_binary(object_id) and is_binary(content) do
    build(actor, object_id, content, object)
  end

  def build(%User{ap_id: actor}, object_id, content)
      when is_binary(object_id) and is_binary(content) do
    build(actor, object_id, content)
  end

  def build(actor, object_id, content)
      when is_binary(actor) and is_binary(object_id) and is_binary(content) do
    %{
      "id" => Endpoint.url() <> "/activities/react/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "object" => object_id,
      "content" => String.trim(content),
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp build(actor, object_id, content, %Object{} = object) do
    base = build(actor, object_id, content)

    case recipients(actor, object) do
      %{} = recipients when map_size(recipients) > 0 -> Map.merge(base, recipients)
      _ -> base
    end
  end

  def cast_and_validate(activity) when is_map(activity) do
    activity = trim_content(activity)

    changeset =
      %__MODULE__{}
      |> cast(activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object, :content])
      |> validate_inclusion(:type, [type()])
      |> validate_length(:content, min: 1)

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = react} -> {:ok, apply_react(activity, react)}
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
    content = get_in(object.data, ["content"])
    emoji = EmojiReactions.normalize_content(content)
    emoji_url = EmojiReactions.find_custom_emoji_url(emoji, get_in(object.data, ["tag"]))

    if is_binary(emoji) and emoji != "" do
      _ =
        Relationships.upsert_relationship(%{
          type: type() <> ":" <> emoji,
          actor: object.actor,
          object: object.object,
          activity_ap_id: object.ap_id,
          emoji_url: emoji_url
        })
    end

    maybe_broadcast_notification(object)

    if Keyword.get(opts, :local, true) do
      deliver_reaction(object)
    end

    :ok
  end

  defp maybe_broadcast_notification(object) do
    with %{} = reacted_object <- Objects.get_by_ap_id(object.object),
         %{} = target <- Users.get_by_ap_id(reacted_object.actor),
         true <- target.local,
         true <- target.ap_id != object.actor do
      Notifications.broadcast(target.ap_id, object)
    else
      _ -> :ok
    end
  end

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate(opts, fn inbox_user_ap_id ->
      actor_ap_id = Map.get(activity, "actor")
      object_ap_id = Map.get(activity, "object")

      cond do
        InboxTargeting.addressed_to?(activity, inbox_user_ap_id) ->
          :ok

        InboxTargeting.follows?(inbox_user_ap_id, actor_ap_id) ->
          :ok

        InboxTargeting.object_owned_by?(object_ap_id, inbox_user_ap_id) ->
          :ok

        true ->
          {:error, :not_targeted}
      end
    end)
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp deliver_reaction(object) do
    with %{} = actor <- Users.get_by_ap_id(object.actor),
         %{} = reacted_object <- Objects.get_by_ap_id(object.object),
         %{} = target <- get_or_fetch_user(reacted_object.actor),
         false <- target.local do
      Delivery.deliver(actor, target.inbox, object.data)
    end
  end

  defp get_or_fetch_user(nil), do: nil

  defp get_or_fetch_user(ap_id) when is_binary(ap_id) do
    Users.get_by_ap_id(ap_id) ||
      case Egregoros.Federation.Actor.fetch_and_store(ap_id) do
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

  defp apply_react(activity, %__MODULE__{} = react) do
    activity
    |> Map.put("id", react.id)
    |> Map.put("type", react.type)
    |> Map.put("actor", react.actor)
    |> Map.put("object", react.object)
    |> Map.put("content", react.content)
    |> maybe_put("to", react.to)
    |> maybe_put("cc", react.cc)
    |> maybe_put("published", react.published)
  end

  defp maybe_put(activity, _key, nil), do: activity
  defp maybe_put(activity, key, value), do: Map.put(activity, key, value)

  defp trim_content(%{"content" => content} = activity) when is_binary(content) do
    Map.put(activity, "content", String.trim(content))
  end

  defp trim_content(activity), do: activity

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
