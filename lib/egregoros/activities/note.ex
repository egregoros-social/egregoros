defmodule Egregoros.Activities.Note do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.Activities.Helpers
  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.ActivityPub.ContentMap
  alias Egregoros.Federation.ThreadDiscovery
  alias Egregoros.InboxTargeting
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Timeline
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  def type, do: "Note"

  @max_inbound_note_chars 20_000

  @primary_key false
  embedded_schema do
    field :id, ObjectID
    field :type, :string
    field :actor, ObjectID
    field :content, :string
    field :to, Recipients
    field :cc, Recipients
    field :published, APDateTime
  end

  def build(%User{ap_id: actor}, content) when is_binary(content) do
    build(actor, content)
  end

  def build(actor, content) when is_binary(actor) and is_binary(content) do
    %{
      "id" => Endpoint.url() <> "/objects/" <> Ecto.UUID.generate(),
      "type" => type(),
      "attributedTo" => actor,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [actor <> "/followers"],
      "content" => content,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def cast_and_validate(note) when is_map(note) do
    cast_and_validate(note, [])
  end

  def cast_and_validate(note, opts) when is_map(note) and is_list(opts) do
    note =
      note
      |> normalize_actor()
      |> normalize_tags()
      |> ContentMap.normalize()
      |> Map.put_new("content", "")
      |> trim_content()

    has_attachments? =
      note
      |> Map.get("attachment")
      |> List.wrap()
      |> Enum.any?(&is_map/1)

    with :ok <- validate_inbound_note_length(note, opts) do
      changeset =
        %__MODULE__{}
        |> cast(note, __schema__(:fields))
        |> validate_required([:id, :type, :actor])
        |> validate_inclusion(:type, [type()])
        |> validate_content(has_attachments?)

      case apply_action(changeset, :insert) do
        {:ok, %__MODULE__{} = validated_note} ->
          {:ok, apply_note(note, validated_note)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}
      end
    end
  end

  defp validate_inbound_note_length(%{} = note, opts) when is_list(opts) do
    if Keyword.get(opts, :local, true) do
      :ok
    else
      content =
        case Map.get(note, "content") do
          content when is_binary(content) -> content
          _ -> ""
        end

      if String.length(content) > @max_inbound_note_chars do
        {:error, :too_long}
      else
        :ok
      end
    end
  end

  defp validate_inbound_note_length(_note, _opts), do: :ok

  def to_object_attrs(note, opts) do
    %{
      ap_id: note["id"],
      type: note["type"],
      actor: note["actor"],
      object: nil,
      data: note,
      published: Helpers.parse_datetime(note["published"]),
      local: Keyword.get(opts, :local, true)
    }
    |> Helpers.attach_type_metadata(opts)
  end

  def ingest(note, opts) do
    with :ok <- validate_inbox_target(note, opts) do
      note
      |> to_object_attrs(opts)
      |> Objects.upsert_object()
    end
  end

  def side_effects(object, opts) do
    Timeline.broadcast_post(object)
    maybe_broadcast_mentions(object)
    _ = ThreadDiscovery.enqueue(object, opts)
    :ok
  end

  defp maybe_broadcast_mentions(%{actor: actor_ap_id, data: %{} = data} = object)
       when is_binary(actor_ap_id) do
    data
    |> Egregoros.Recipients.recipient_actor_ids(fields: ["to", "cc"])
    |> Enum.each(fn recipient_ap_id ->
      case Users.get_by_ap_id(recipient_ap_id) do
        %User{local: true, ap_id: ap_id} when ap_id != actor_ap_id ->
          Notifications.broadcast(ap_id, object)

        _ ->
          :ok
      end
    end)
  end

  defp maybe_broadcast_mentions(_object), do: :ok

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate_addressed_or_followed(opts, activity, Map.get(activity, "actor"))
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp apply_note(note, %__MODULE__{} = validated_note) do
    note
    |> Map.put("id", validated_note.id)
    |> Map.put("type", validated_note.type)
    |> Map.put("actor", validated_note.actor)
    |> Map.put("content", validated_note.content || Map.get(note, "content", ""))
    |> Helpers.maybe_put("to", validated_note.to)
    |> Helpers.maybe_put("cc", validated_note.cc)
    |> Helpers.maybe_put("published", validated_note.published)
  end

  defp normalize_actor(%{"actor" => _} = note), do: note

  defp normalize_actor(%{"attributedTo" => actor} = note) do
    Map.put(note, "actor", actor)
  end

  defp normalize_actor(note), do: note

  defp normalize_tags(%{"tag" => tags} = note) do
    tags =
      tags
      |> List.wrap()
      |> Enum.map(&normalize_tag/1)

    Map.put(note, "tag", tags)
  end

  defp normalize_tags(note), do: note

  defp normalize_tag(%{"type" => "Hashtag"} = tag) do
    name =
      tag
      |> Map.get("name", "")
      |> to_string()
      |> String.trim()
      |> String.trim(":")
      |> String.trim_leading("#")
      |> String.downcase()

    if valid_hashtag?(name) do
      Map.put(tag, "name", "#" <> name)
    else
      tag
    end
  end

  defp normalize_tag(tag), do: tag

  defp valid_hashtag?(tag) when is_binary(tag) do
    Regex.match?(~r/^[\p{L}\p{N}_][\p{L}\p{N}_-]{0,63}$/u, tag)
  end

  defp valid_hashtag?(_tag), do: false

  defp trim_content(%{"content" => content} = note) when is_binary(content) do
    Map.put(note, "content", String.trim(content))
  end

  defp trim_content(note), do: note

  defp validate_content(%Ecto.Changeset{} = changeset, true), do: changeset

  defp validate_content(%Ecto.Changeset{} = changeset, false) do
    changeset
    |> validate_required([:content])
    |> validate_length(:content, min: 1)
  end
end
