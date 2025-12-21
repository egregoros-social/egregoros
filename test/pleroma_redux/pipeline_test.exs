defmodule PleromaRedux.PipelineTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Object
  alias PleromaRedux.Pipeline
  alias PleromaReduxWeb.Endpoint

  @note %{
    "id" => "https://example.com/objects/1",
    "type" => "Note",
    "attributedTo" => "https://example.com/users/alice",
    "content" => "Hello from pipeline"
  }

  @create %{
    "id" => "https://example.com/activities/create/1",
    "type" => "Create",
    "actor" => "https://example.com/users/alice",
    "object" => @note
  }

  @like %{
    "id" => "https://example.com/activities/like/1",
    "type" => "Like",
    "actor" => "https://example.com/users/alice",
    "object" => "https://example.com/objects/1"
  }

  @announce %{
    "id" => "https://example.com/activities/announce/1",
    "type" => "Announce",
    "actor" => "https://example.com/users/alice",
    "object" => "https://example.com/objects/1"
  }

  @follow %{
    "id" => "https://example.com/activities/follow/1",
    "type" => "Follow",
    "actor" => "https://example.com/users/alice",
    "object" => "https://example.com/users/bob"
  }

  @undo %{
    "id" => "https://example.com/activities/undo/1",
    "type" => "Undo",
    "actor" => "https://example.com/users/alice",
    "object" => "https://example.com/activities/follow/1"
  }

  @emoji_react %{
    "id" => "https://example.com/activities/react/1",
    "type" => "EmojiReact",
    "actor" => "https://example.com/users/alice",
    "object" => "https://example.com/objects/1",
    "content" => ":fire:"
  }

  test "ingest stores a Note as an object" do
    assert {:ok, %Object{} = object} = Pipeline.ingest(@note, local: true)
    assert object.ap_id == @note["id"]
    assert object.type == "Note"
    assert object.actor == @note["attributedTo"]
    assert object.data["content"] == "Hello from pipeline"
    assert object.local == true
  end

  test "ingest stores Like" do
    assert {:ok, %Object{} = object} = Pipeline.ingest(@like, local: false)
    assert object.type == "Like"
    assert object.actor == @like["actor"]
    assert object.object == @like["object"]
    assert object.local == false
  end

  test "ingest stores Announce" do
    assert {:ok, %Object{} = object} = Pipeline.ingest(@announce, local: false)
    assert object.type == "Announce"
    assert object.actor == @announce["actor"]
    assert object.object == @announce["object"]
  end

  test "ingest stores Follow" do
    assert {:ok, %Object{} = object} = Pipeline.ingest(@follow, local: false)
    assert object.type == "Follow"
    assert object.actor == @follow["actor"]
    assert object.object == @follow["object"]
  end

  test "ingest stores Undo" do
    assert {:ok, %Object{} = object} = Pipeline.ingest(@undo, local: false)
    assert object.type == "Undo"
    assert object.actor == @undo["actor"]
    assert object.object == @undo["object"]
  end

  test "ingest stores EmojiReact" do
    assert {:ok, %Object{} = object} = Pipeline.ingest(@emoji_react, local: false)
    assert object.type == "EmojiReact"
    assert object.actor == @emoji_react["actor"]
    assert object.object == @emoji_react["object"]
    assert object.data["content"] == ":fire:"
  end

  test "ingest stores Create and its embedded object" do
    assert {:ok, %Object{} = object} = Pipeline.ingest(@create, local: false)
    assert object.type == "Create"
    assert object.actor == @create["actor"]
    assert object.object == @note["id"]

    assert PleromaRedux.Objects.get_by_ap_id(@note["id"])
  end

  test "ingest rejects unknown types" do
    assert {:error, :unknown_type} =
             Pipeline.ingest(%{"type" => "Wobble", "id" => "x"}, local: true)
  end

  test "ingest rejects empty content" do
    assert {:error, :invalid} =
             Pipeline.ingest(Map.put(@note, "content", "  "), local: true)
  end

  test "ingest rejects remote objects that claim a local id" do
    uuid = Ecto.UUID.generate()

    note =
      @note
      |> Map.put("id", Endpoint.url() <> "/objects/" <> uuid)
      |> Map.put("attributedTo", "https://example.com/users/alice")

    assert {:error, :local_id} = Pipeline.ingest(note, local: false)
  end
end
