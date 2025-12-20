defmodule PleromaRedux.Activities.Note do
  alias PleromaRedux.Objects
  alias PleromaRedux.Timeline
  alias PleromaRedux.User
  alias PleromaReduxWeb.Endpoint

  def type, do: "Note"

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

  def normalize(%{"type" => "Note"} = note) do
    note
    |> put_actor()
    |> trim_content()
  end

  def normalize(_), do: nil

  def validate(%{"id" => id, "type" => "Note", "actor" => actor, "content" => content} = note)
      when is_binary(id) and is_binary(actor) and is_binary(content) and content != "" do
    {:ok, note}
  end

  def validate(_), do: {:error, :invalid}

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

  defp put_actor(%{"actor" => actor} = note) when is_binary(actor), do: note

  defp put_actor(%{"actor" => %{"id" => actor}} = note) when is_binary(actor) do
    Map.put(note, "actor", actor)
  end

  defp put_actor(%{"attributedTo" => actor} = note) when is_binary(actor) do
    Map.put(note, "actor", actor)
  end

  defp put_actor(%{"attributedTo" => %{"id" => actor}} = note) when is_binary(actor) do
    Map.put(note, "actor", actor)
  end

  defp put_actor(note), do: note

  defp trim_content(%{"content" => content} = note) when is_binary(content) do
    Map.put(note, "content", String.trim(content))
  end

  defp trim_content(note), do: note

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
