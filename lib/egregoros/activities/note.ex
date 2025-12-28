defmodule Egregoros.Activities.Note do
  use Ecto.Schema

  import Ecto.Changeset

  alias Egregoros.ActivityPub.ObjectValidators.Types.ObjectID
  alias Egregoros.ActivityPub.ObjectValidators.Types.Recipients
  alias Egregoros.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias Egregoros.Federation.ThreadDiscovery
  alias Egregoros.InboxTargeting
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Timeline
  alias Egregoros.User
  alias Egregoros.Users
  alias EgregorosWeb.Endpoint

  def type, do: "Note"

  @as_public "https://www.w3.org/ns/activitystreams#Public"

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
    note =
      note
      |> normalize_actor()
      |> Map.put_new("content", "")
      |> trim_content()

    has_attachments? =
      note
      |> Map.get("attachment")
      |> List.wrap()
      |> Enum.any?(&is_map/1)

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

  def to_object_attrs(note, opts) do
    %{
      ap_id: note["id"],
      type: note["type"],
      actor: note["actor"],
      object: nil,
      data: note,
      published: parse_datetime(note["published"]),
      local: Keyword.get(opts, :local, true)
    }
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
    |> recipient_actor_ids()
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

  defp recipient_actor_ids(%{} = data) do
    ((data |> Map.get("to", []) |> List.wrap()) ++ (data |> Map.get("cc", []) |> List.wrap()))
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or &1 == @as_public or String.ends_with?(&1, "/followers")))
    |> Enum.uniq()
  end

  defp recipient_actor_ids(_data), do: []

  defp validate_inbox_target(%{} = activity, opts) when is_list(opts) do
    InboxTargeting.validate(opts, fn inbox_user_ap_id ->
      actor_ap_id = Map.get(activity, "actor")

      cond do
        InboxTargeting.addressed_to?(activity, inbox_user_ap_id) ->
          :ok

        InboxTargeting.follows?(inbox_user_ap_id, actor_ap_id) ->
          :ok

        true ->
          {:error, :not_targeted}
      end
    end)
  end

  defp validate_inbox_target(_activity, _opts), do: :ok

  defp apply_note(note, %__MODULE__{} = validated_note) do
    note
    |> Map.put("id", validated_note.id)
    |> Map.put("type", validated_note.type)
    |> Map.put("actor", validated_note.actor)
    |> Map.put("content", validated_note.content || Map.get(note, "content", ""))
    |> maybe_put("to", validated_note.to)
    |> maybe_put("cc", validated_note.cc)
    |> maybe_put("published", validated_note.published)
  end

  defp normalize_actor(%{"actor" => _} = note), do: note

  defp normalize_actor(%{"attributedTo" => actor} = note) do
    Map.put(note, "actor", actor)
  end

  defp normalize_actor(note), do: note

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

  defp maybe_put(note, _key, nil), do: note
  defp maybe_put(note, key, value), do: Map.put(note, key, value)

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
