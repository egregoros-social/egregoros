defmodule PleromaRedux.ObjectsTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Object
  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

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

  test "get_by_type_actor_object returns the latest matching object without raising" do
    like_1 = Map.put(@like_attrs, :ap_id, "https://example.com/activities/like/latest/1")
    like_2 = Map.put(@like_attrs, :ap_id, "https://example.com/activities/like/latest/2")

    assert {:ok, %Object{} = obj_1} = Objects.create_object(like_1)
    assert {:ok, %Object{} = obj_2} = Objects.create_object(like_2)

    assert %Object{} =
             latest = Objects.get_by_type_actor_object("Like", obj_1.actor, obj_1.object)

    assert latest.id == obj_2.id
  end

  test "delete_all_notes clears notes" do
    assert {:ok, %Object{}} = Objects.create_object(@note_attrs)
    Objects.delete_all_notes()
    assert [] == Objects.list_notes()
  end

  test "list_home_notes returns own notes and notes from followed actors" do
    {:ok, alice} = Users.create_local_user("alice")

    bob_ap_id = "https://remote.example/users/bob"
    carol_ap_id = "https://remote.example/users/carol"

    assert {:ok, %Object{}} =
             Pipeline.ingest(
               %{
                 "id" => "https://local.example/activities/follow/1",
                 "type" => "Follow",
                 "actor" => alice.ap_id,
                 "object" => bob_ap_id
               },
               local: true
             )

    assert {:ok, %Object{}} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/bob-1",
               type: "Note",
               actor: bob_ap_id,
               object: nil,
               data: %{
                 "id" => "https://remote.example/objects/bob-1",
                 "type" => "Note",
                 "actor" => bob_ap_id,
                 "to" => [bob_ap_id <> "/followers"],
                 "cc" => [],
                 "content" => "hello"
               },
               local: false
             })

    assert {:ok, %Object{}} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/carol-1",
               type: "Note",
               actor: carol_ap_id,
               object: nil,
               data: %{
                 "id" => "https://remote.example/objects/carol-1",
                 "type" => "Note",
                 "actor" => carol_ap_id,
                 "content" => "hello"
               },
               local: false
             })

    assert {:ok, %Object{}} =
             Objects.create_object(%{
               ap_id: "https://local.example/objects/alice-1",
               type: "Note",
               actor: alice.ap_id,
               object: nil,
               data: %{
                 "id" => "https://local.example/objects/alice-1",
                 "type" => "Note",
                 "actor" => alice.ap_id,
                 "content" => "hello"
               },
               local: true
             })

    notes = Objects.list_home_notes(alice.ap_id)
    assert Enum.any?(notes, &(&1.actor == alice.ap_id))
    assert Enum.any?(notes, &(&1.actor == bob_ap_id))
    refute Enum.any?(notes, &(&1.actor == carol_ap_id))
  end

  test "search_notes finds notes by content or summary" do
    assert {:ok, %Object{} = content_note} =
             Objects.create_object(%{
               ap_id: "https://local.example/objects/search-1",
               type: "Note",
               actor: "https://local.example/users/alice",
               object: nil,
               data: %{
                 "id" => "https://local.example/objects/search-1",
                 "type" => "Note",
                 "actor" => "https://local.example/users/alice",
                 "content" => "Hello world"
               },
               local: true
             })

    assert {:ok, %Object{} = summary_note} =
             Objects.create_object(%{
               ap_id: "https://local.example/objects/search-2",
               type: "Note",
               actor: "https://local.example/users/alice",
               object: nil,
               data: %{
                 "id" => "https://local.example/objects/search-2",
                 "type" => "Note",
                 "actor" => "https://local.example/users/alice",
                 "content" => "Something else",
                 "summary" => "hello from summary"
               },
               local: true
             })

    assert {:ok, %Object{}} =
             Objects.create_object(%{
               ap_id: "https://local.example/objects/search-3",
               type: "Note",
               actor: "https://local.example/users/alice",
               object: nil,
               data: %{
                 "id" => "https://local.example/objects/search-3",
                 "type" => "Note",
                 "actor" => "https://local.example/users/alice",
                 "content" => "No match here"
               },
               local: true
             })

    assert {:ok, %Object{}} =
             Objects.create_object(%{
               ap_id: "https://local.example/activities/like/search-1",
               type: "Like",
               actor: "https://local.example/users/alice",
               object: "https://local.example/objects/search-1",
               data: %{
                 "id" => "https://local.example/activities/like/search-1",
                 "type" => "Like",
                 "content" => "hello from like"
               },
               local: true
             })

    results = Objects.search_notes("hello", limit: 10)

    assert Enum.all?(results, &(&1.type == "Note"))
    assert Enum.any?(results, &(&1.id == content_note.id))
    assert Enum.any?(results, &(&1.id == summary_note.id))
  end

  test "search_notes ignores blank queries" do
    assert [] == Objects.search_notes(" ")
  end
end
