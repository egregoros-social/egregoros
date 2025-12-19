defmodule PleromaRedux.ObjectsTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Object
  alias PleromaRedux.Objects

  @note_attrs %{
    ap_id: "https://example.com/objects/1",
    type: "Note",
    actor: "https://example.com/users/alice",
    object: nil,
    data: %{"type" => "Note", "content" => "Hello from Redux"},
    published: ~U[2025-01-01 00:00:00Z],
    local: true
  }

  @like_attrs %{
    ap_id: "https://example.com/activities/like/1",
    type: "Like",
    actor: "https://example.com/users/alice",
    object: "https://example.com/objects/1",
    data: %{"type" => "Like", "object" => "https://example.com/objects/1"},
    published: ~U[2025-01-01 00:00:01Z],
    local: false
  }

  test "create_object stores jsonb data" do
    assert {:ok, %Object{} = object} = Objects.create_object(@note_attrs)
    assert object.ap_id == @note_attrs.ap_id
    assert object.data["content"] == "Hello from Redux"
  end

  test "get_by_ap_id returns stored object" do
    assert {:ok, %Object{} = object} = Objects.create_object(@note_attrs)
    assert %Object{id: id} = Objects.get_by_ap_id(@note_attrs.ap_id)
    assert id == object.id
  end

  test "ap_id is unique" do
    assert {:ok, %Object{}} = Objects.create_object(@note_attrs)
    assert {:error, changeset} = Objects.create_object(@note_attrs)
    assert "has already been taken" in errors_on(changeset).ap_id
  end

  test "upsert_object returns existing record" do
    assert {:ok, %Object{id: id}} = Objects.upsert_object(@note_attrs)
    assert {:ok, %Object{id: id_again}} = Objects.upsert_object(@note_attrs)
    assert id == id_again
  end

  test "list_notes returns only notes" do
    assert {:ok, %Object{}} = Objects.create_object(@note_attrs)
    assert {:ok, %Object{}} = Objects.create_object(@like_attrs)

    notes = Objects.list_notes()
    assert Enum.all?(notes, &(&1.type == "Note"))
  end

  test "delete_all_notes clears notes" do
    assert {:ok, %Object{}} = Objects.create_object(@note_attrs)
    Objects.delete_all_notes()
    assert [] == Objects.list_notes()
  end
end
