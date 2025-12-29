defmodule Egregoros.FollowRequestsTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.Follow
  alias Egregoros.Activities.Undo
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.Users

  test "outgoing follow to remote user is stored as a follow request until accepted" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, bob} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    {:ok, follow_object} = Pipeline.ingest(Follow.build(alice, bob), local: true)

    assert Relationships.get_by_type_actor_object("Follow", alice.ap_id, bob.ap_id) == nil

    assert %{activity_ap_id: activity_ap_id} =
             Relationships.get_by_type_actor_object("FollowRequest", alice.ap_id, bob.ap_id)

    assert activity_ap_id == follow_object.ap_id
  end

  test "accepting a follow request finalizes the follow relationship" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, bob} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    {:ok, follow_object} = Pipeline.ingest(Follow.build(alice, bob), local: true)

    accept = %{
      "id" => "https://remote.example/activities/accept/1",
      "type" => "Accept",
      "actor" => bob.ap_id,
      "object" => follow_object.data
    }

    assert {:ok, _} = Pipeline.ingest(accept, local: false)

    assert %{activity_ap_id: activity_ap_id} =
             Relationships.get_by_type_actor_object("Follow", alice.ap_id, bob.ap_id)

    assert activity_ap_id == follow_object.ap_id
    assert Relationships.get_by_type_actor_object("FollowRequest", alice.ap_id, bob.ap_id) == nil
  end

  test "undoing a follow request removes the pending relationship" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, bob} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    {:ok, follow_object} = Pipeline.ingest(Follow.build(alice, bob), local: true)

    assert Relationships.get_by_type_actor_object("FollowRequest", alice.ap_id, bob.ap_id)

    undo = Undo.build(alice, follow_object.ap_id)
    assert {:ok, _} = Pipeline.ingest(undo, local: true)

    assert Relationships.get_by_type_actor_object("FollowRequest", alice.ap_id, bob.ap_id) == nil
    assert Relationships.get_by_type_actor_object("Follow", alice.ap_id, bob.ap_id) == nil
    assert Objects.get_by_ap_id(follow_object.ap_id) == nil
  end

  test "following a locked local user creates a follow request until accepted" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, bob} = Users.update_profile(bob, %{locked: true})

    {:ok, follow_object} = Pipeline.ingest(Follow.build(alice, bob), local: true)

    assert Relationships.get_by_type_actor_object("Follow", alice.ap_id, bob.ap_id) == nil

    assert %{activity_ap_id: activity_ap_id} =
             Relationships.get_by_type_actor_object("FollowRequest", alice.ap_id, bob.ap_id)

    assert activity_ap_id == follow_object.ap_id
  end
end
