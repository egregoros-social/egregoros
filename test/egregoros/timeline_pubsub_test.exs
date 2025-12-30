defmodule Egregoros.TimelinePubSubTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Timeline
  alias Egregoros.Users
  alias Egregoros.Objects
  alias Egregoros.Workers.FetchThreadAncestors

  test "broadcasts announces to the public timeline topic" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, create} = Publish.post_note(alice, "hello")

    bob_ap_id = bob.ap_id
    object_ap_id = create.object

    Timeline.subscribe_public()

    {:ok, _announce} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/announce/1",
          "type" => "Announce",
          "actor" => bob_ap_id,
          "object" => object_ap_id,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"]
        },
        local: true
      )

    assert_receive {:post_created, %{type: "Announce", actor: ^bob_ap_id, object: ^object_ap_id}}
  end

  test "remote announce for an unknown object is not broadcast until the object exists" do
    announced_id = "https://remote.example/objects/announced-1"

    Timeline.subscribe_public()

    assert {:ok, announce_object} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/activities/announce/1",
                 "type" => "Announce",
                 "actor" => "https://remote.example/users/alice",
                 "object" => announced_id,
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"]
               },
               local: false
             )

    assert announce_object.type == "Announce"

    refute_receive {:post_created, %{type: "Announce"}}, 25

    assert {:ok, _note} =
             Objects.create_object(%{
               ap_id: announced_id,
               type: "Note",
               actor: "https://remote.example/users/alice",
               local: false,
               data: %{
                 "id" => announced_id,
                 "type" => "Note",
                 "attributedTo" => "https://remote.example/users/alice",
                 "content" => "<p>hello</p>",
                 "to" => ["https://www.w3.org/ns/activitystreams#Public"]
               }
             })

    job = %Oban.Job{args: %{"start_ap_id" => announced_id}}
    assert :ok = FetchThreadAncestors.perform(job)

    assert_receive {:post_created, %{type: "Announce", object: ^announced_id}}
  end
end
