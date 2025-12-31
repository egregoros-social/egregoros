defmodule Egregoros.Activities.DeleteSideEffectsTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.Users

  test "does not delete an object when Delete.actor does not match the target actor" do
    {:ok, inbox_user} = Users.create_local_user("inbox-user")

    alice_ap_id = "https://remote.example/users/alice"
    bob_ap_id = "https://remote.example/users/bob"

    assert {:ok, _} =
             Relationships.upsert_relationship(%{
               type: "Follow",
               actor: inbox_user.ap_id,
               object: bob_ap_id,
               activity_ap_id: "https://egregoros.example/activities/follow/bob"
             })

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/1",
        type: "Note",
        actor: alice_ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/1",
          "type" => "Note",
          "actor" => alice_ap_id,
          "content" => "hello"
        }
      })

    delete = %{
      "id" => "https://remote.example/activities/delete/1",
      "type" => "Delete",
      "actor" => bob_ap_id,
      "object" => note.ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => []
    }

    assert {:ok, _delete_object} =
             Pipeline.ingest(delete, local: false, inbox_user_ap_id: inbox_user.ap_id)

    assert Objects.get_by_ap_id(note.ap_id)
  end

  test "deletes the target object and relationships when Delete.actor matches the target actor" do
    {:ok, inbox_user} = Users.create_local_user("inbox-user")

    alice_ap_id = "https://remote.example/users/alice"

    assert {:ok, _} =
             Relationships.upsert_relationship(%{
               type: "Follow",
               actor: inbox_user.ap_id,
               object: alice_ap_id,
               activity_ap_id: "https://egregoros.example/activities/follow/alice"
             })

    {:ok, note} =
      Objects.create_object(%{
        ap_id: "https://remote.example/objects/2",
        type: "Note",
        actor: alice_ap_id,
        local: false,
        data: %{
          "id" => "https://remote.example/objects/2",
          "type" => "Note",
          "actor" => alice_ap_id,
          "content" => "hello"
        }
      })

    assert {:ok, _like} =
             Relationships.upsert_relationship(%{
               type: "Like",
               actor: inbox_user.ap_id,
               object: note.ap_id,
               activity_ap_id: "https://egregoros.example/activities/like/1"
             })

    delete = %{
      "id" => "https://remote.example/activities/delete/2",
      "type" => "Delete",
      "actor" => alice_ap_id,
      "object" => note.ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => []
    }

    assert {:ok, _delete_object} =
             Pipeline.ingest(delete, local: false, inbox_user_ap_id: inbox_user.ap_id)

    refute Objects.get_by_ap_id(note.ap_id)
    refute Relationships.get_by_type_actor_object("Like", inbox_user.ap_id, note.ap_id)
  end
end

