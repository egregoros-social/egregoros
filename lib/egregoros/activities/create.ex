defmodule Egregoros.Activities.Create do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.ActivityPub.TypeNormalizer
  alias Egregoros.Federation.Delivery
  alias Egregoros.Federation.DeliveryPayload
  alias Egregoros.InboxTargeting
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  def type, do: "Create"

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :object, :map
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
  end

  def build(%User{ap_id: actor}, object) when is_map(object) do
    build(actor, object)
  end

  def build(actor, object) when is_binary(actor) and is_map(object) do
    to = object["to"] || ["https://www.w3.org/ns/activitystreams#Public"]
    cc = object["cc"] || [actor <> "/followers"]

    %{
      "id" => Endpoint.url() <> "/activities/create/" <> Ecto.UUID.generate(),
      "type" => type(),
      "actor" => actor,
      "to" => to,
      "cc" => cc,
      "object" => object,
      "published" => object["published"] || DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def cast_and_validate(activity) when is_map(activity) do
    activity =
      activity
      |> normalize_actor()
      |> normalize_poll_answer()

    changeset =
      %__MODULE__{}
      |> cast(activity, __schema__(:fields))
      |> validate_required([:id, :type, :actor, :object])
      |> validate_inclusion(:type, [type()])
      |> validate_object()

    case apply_action(changeset, :insert) do
      {:ok, %__MODULE__{} = create} ->
        {:ok, apply_create(activity, create)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def ingest(activity, opts) do
    with :ok <- validate_inbox_target(activity, opts),
         {:ok, object} <- Pipeline.ingest(activity["object"], opts) do
      activity
      |> to_object_attrs(object, opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(object, opts) do
    if Keyword.get(opts, :local, true) and Keyword.get(opts, :deliver, true) do
      deliver(object)
    end

    :ok
  end

  defp deliver(create_object) do
    with %User{} = actor <- Users.get_by_ap_id(create_object.actor),
         inboxes when is_list(inboxes) and inboxes != [] <-
           inboxes_for_delivery(create_object, actor) do
      Enum.each(inboxes, fn inbox_url ->
        Delivery.deliver(actor, inbox_url, DeliveryPayload.for_delivery(create_object.data))
      end)
    else
      _ -> :ok
    end
  end

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate_addressed_or_followed_or_addressed_to_object(
      opts,
      activity,
      Map.get(activity, "actor"),
      Map.get(activity, "object")
    )
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp inboxes_for_delivery(%{data: %{} = data} = create_object, %User{} = actor) do
    follower_inboxes =
      if followers_addressed?(data, create_object.actor) do
        actor.ap_id
        |> Relationships.list_follows_to()
        |> Enum.map(fn follow ->
          case Users.get_by_ap_id(follow.actor) do
            %User{local: false, inbox: inbox} when is_binary(inbox) and inbox != "" -> inbox
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    recipient_inboxes =
      data
      |> Egregoros.Recipients.recipient_actor_ids(fields: ["to", "cc"])
      |> Enum.map(fn actor_id ->
        case Users.get_by_ap_id(actor_id) do
          %User{local: false, inbox: inbox} when is_binary(inbox) and inbox != "" -> inbox
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    (follower_inboxes ++ recipient_inboxes)
    |> Enum.uniq()
  end

  defp inboxes_for_delivery(_create_object, _actor), do: []

  defp followers_addressed?(%{} = data, actor_ap_id) when is_binary(actor_ap_id) do
    followers = actor_ap_id <> "/followers"
    to = data |> Map.get("to", []) |> List.wrap()
    cc = data |> Map.get("cc", []) |> List.wrap()
    followers in to or followers in cc
  end

  defp followers_addressed?(_data, _actor_ap_id), do: false

  defp to_object_attrs(activity, embedded_object, opts) do
    %{
      ap_id: activity["id"],
      type: activity["type"],
      actor: activity["actor"],
      object: embedded_object.ap_id,
      data: activity,
      published: Helpers.parse_datetime(activity["published"]),
      local: Keyword.get(opts, :local, true)
    }
    |> Helpers.attach_type_metadata(opts)
  end

  defp apply_create(activity, %__MODULE__{} = create) do
    activity
    |> Map.put("id", create.id)
    |> Map.put("type", create.type)
    |> Map.put("actor", create.actor)
    |> Map.put("object", create.object)
    |> Helpers.maybe_put("to", create.to)
    |> Helpers.maybe_put("cc", create.cc)
    |> Helpers.maybe_put("published", create.published)
  end

  defp normalize_actor(%{"actor" => _} = activity), do: activity

  defp normalize_actor(%{"attributedTo" => actor} = activity) do
    Map.put(activity, "actor", actor)
  end

  defp normalize_actor(activity), do: activity

  defp normalize_poll_answer(%{"object" => %{} = object} = activity) do
    object =
      object
      |> inherit_object_recipients_from_create(activity)
      |> maybe_convert_poll_answer()

    Map.put(activity, "object", object)
  end

  defp normalize_poll_answer(activity), do: activity

  defp inherit_object_recipients_from_create(%{} = object, %{} = activity) do
    object_to = object |> Map.get("to", []) |> List.wrap()
    object_cc = object |> Map.get("cc", []) |> List.wrap()

    if object_to == [] and object_cc == [] do
      object
      |> maybe_copy_recipients_from_create(activity, "to")
      |> maybe_copy_recipients_from_create(activity, "cc")
    else
      object
    end
  end

  defp inherit_object_recipients_from_create(object, _activity), do: object

  defp maybe_copy_recipients_from_create(%{} = object, %{} = activity, field)
       when field in ["to", "cc"] do
    case Map.get(activity, field) do
      recipients when is_list(recipients) and recipients != [] ->
        Map.put(object, field, recipients)

      _ ->
        object
    end
  end

  defp maybe_copy_recipients_from_create(object, _activity, _field), do: object

  defp maybe_convert_poll_answer(%{"type" => "Note", "name" => name} = object)
       when is_binary(name) do
    case extract_in_reply_to_id(object) do
      reply_id when is_binary(reply_id) and reply_id != "" ->
        case Objects.get_by_ap_id(reply_id) do
          %Object{type: "Question"} -> Map.put(object, "type", "Answer")
          _ -> object
        end

      _ ->
        object
    end
  end

  defp maybe_convert_poll_answer(object), do: object

  defp extract_in_reply_to_id(%{"inReplyTo" => reply_to}) do
    extract_reply_to_id(reply_to)
  end

  defp extract_in_reply_to_id(%{inReplyTo: reply_to}) do
    extract_reply_to_id(reply_to)
  end

  defp extract_in_reply_to_id(_object), do: nil

  defp extract_reply_to_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_reply_to_id(%{id: id}) when is_binary(id), do: id
  defp extract_reply_to_id(id) when is_binary(id), do: id
  defp extract_reply_to_id(_reply_to), do: nil

  defp validate_object(changeset) do
    create_actor = get_field(changeset, :actor)

    validate_change(changeset, :object, fn :object, object_value ->
      object_id = get_in(object_value, ["id"]) || get_in(object_value, [:id])
      # Accept multi-type objects by validating against the primary type only.
      object_type = TypeNormalizer.primary_type(object_value)

      errors =
        if is_binary(object_id) and object_id != "" and is_binary(object_type) and
             object_type != "" do
          []
        else
          [object: "must be an object with id and type"]
        end

      object_actor_ids = extract_object_actor_ids(object_value)

      if is_binary(create_actor) and create_actor != "" and object_actor_ids != [] and
           create_actor not in object_actor_ids do
        errors ++ [object: "actor does not match Create actor"]
      else
        errors
      end
    end)
  end

  defp extract_object_actor_ids(object) when is_map(object) do
    object
    |> object_author_field()
    |> List.wrap()
    |> Enum.map(&extract_actor_id/1)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  defp extract_object_actor_ids(_), do: []

  defp object_author_field(%{"attributedTo" => value}), do: value
  defp object_author_field(%{attributedTo: value}), do: value
  defp object_author_field(%{"actor" => value}), do: value
  defp object_author_field(%{actor: value}), do: value
  defp object_author_field(_), do: nil

  defp extract_actor_id(%{"id" => id}) when is_binary(id), do: id
  defp extract_actor_id(%{id: id}) when is_binary(id), do: id
  defp extract_actor_id(id) when is_binary(id), do: id
  defp extract_actor_id(_), do: nil
end
