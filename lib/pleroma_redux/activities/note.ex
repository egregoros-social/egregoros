defmodule PleromaRedux.Activities.Note do
  use Ecto.Schema

  import Ecto.Changeset

  alias PleromaRedux.ActivityPub.ObjectValidators.Types.ObjectID
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.Recipients
  alias PleromaRedux.ActivityPub.ObjectValidators.Types.DateTime, as: APDateTime
  alias PleromaRedux.Objects
  alias PleromaRedux.Timeline
  alias PleromaRedux.User
  alias PleromaReduxWeb.Endpoint

  def type, do: "Note"

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
    note
    |> to_object_attrs(opts)
    |> Objects.upsert_object()
  end

  def side_effects(object, _opts) do
    Timeline.broadcast_post(object)
    :ok
  end

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
