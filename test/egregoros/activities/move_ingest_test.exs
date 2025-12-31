defmodule Egregoros.Activities.MoveIngestTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.Users
  alias Egregoros.Workers.DeliverActivity

  @public "https://www.w3.org/ns/activitystreams#Public"

  test "ingest stores Move and migrates local followers when target confirms alsoKnownAs" do
    {:ok, follower} = Users.create_local_user("follower")

    old_ap_id = "https://remote.example/users/old"
    new_ap_id = "https://remote.example/users/new"

    {:ok, _old} =
      Users.create_user(%{
        nickname: "old",
        domain: "remote.example",
        ap_id: old_ap_id,
        inbox: old_ap_id <> "/inbox",
        outbox: old_ap_id <> "/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        private_key: nil,
        local: false
      })

    {:ok, _new} =
      Users.create_user(%{
        nickname: "new",
        domain: "remote.example",
        ap_id: new_ap_id,
        inbox: new_ap_id <> "/inbox",
        outbox: new_ap_id <> "/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        private_key: nil,
        local: false,
        also_known_as: [old_ap_id]
      })

    follow_activity = %{
      "id" => "https://egregoros.example/activities/follow/move-migration",
      "type" => "Follow",
      "actor" => follower.ap_id,
      "object" => old_ap_id,
      "to" => [old_ap_id],
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert {:ok, %Object{} = follow_object} =
             Objects.upsert_object(%{
               ap_id: follow_activity["id"],
               type: follow_activity["type"],
               actor: follow_activity["actor"],
               object: follow_activity["object"],
               data: follow_activity,
               local: true
             })

    assert {:ok, _} =
             Relationships.upsert_relationship(%{
               type: "Follow",
               actor: follower.ap_id,
               object: old_ap_id,
               activity_ap_id: follow_object.ap_id
             })

    move = %{
      "id" => "https://remote.example/activities/move/1",
      "type" => "Move",
      "actor" => old_ap_id,
      "object" => old_ap_id,
      "target" => new_ap_id,
      "to" => [@public],
      "cc" => [old_ap_id <> "/followers"],
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert {:ok, %Object{} = move_object} =
             Pipeline.ingest(move, local: false, inbox_user_ap_id: follower.ap_id)

    assert move_object.type == "Move"
    assert move_object.actor == old_ap_id
    assert move_object.object == old_ap_id

    assert Users.get_by_ap_id(old_ap_id).moved_to_ap_id == new_ap_id

    assert Relationships.get_by_type_actor_object("Follow", follower.ap_id, old_ap_id) == nil
    assert Relationships.get_by_type_actor_object("FollowRequest", follower.ap_id, new_ap_id)

    jobs = all_enqueued(worker: DeliverActivity) |> Enum.map(& &1.args)

    assert Enum.any?(jobs, fn
             %{"inbox_url" => inbox, "activity" => %{"type" => "Undo"}} ->
               inbox == old_ap_id <> "/inbox"

             _ ->
               false
           end)

    assert Enum.any?(jobs, fn
             %{
               "inbox_url" => inbox,
               "activity" => %{"type" => "Follow", "actor" => actor, "object" => object}
             } ->
               inbox == new_ap_id <> "/inbox" and actor == follower.ap_id and object == new_ap_id

             _ ->
               false
           end)
  end

  test "ingest applies Move when the target actor is fetched and confirms alsoKnownAs" do
    {:ok, follower} = Users.create_local_user("follower")

    old_ap_id = "https://remote.example/users/old"
    new_ap_id = "https://remote.example/users/new"

    {:ok, _old} =
      Users.create_user(%{
        nickname: "old",
        domain: "remote.example",
        ap_id: old_ap_id,
        inbox: old_ap_id <> "/inbox",
        outbox: old_ap_id <> "/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        private_key: nil,
        local: false
      })

    follow_activity = %{
      "id" => "https://egregoros.example/activities/follow/move-migration-2",
      "type" => "Follow",
      "actor" => follower.ap_id,
      "object" => old_ap_id,
      "to" => [old_ap_id],
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert {:ok, %Object{} = follow_object} =
             Objects.upsert_object(%{
               ap_id: follow_activity["id"],
               type: follow_activity["type"],
               actor: follow_activity["actor"],
               object: follow_activity["object"],
               data: follow_activity,
               local: true
             })

    assert {:ok, _} =
             Relationships.upsert_relationship(%{
               type: "Follow",
               actor: follower.ap_id,
               object: old_ap_id,
               activity_ap_id: follow_object.ap_id
             })

    Egregoros.HTTP.Mock
    |> expect(:get, fn url, _headers ->
      assert url == new_ap_id

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => new_ap_id,
           "type" => "Person",
           "preferredUsername" => "new",
           "inbox" => new_ap_id <> "/inbox",
           "outbox" => new_ap_id <> "/outbox",
           "alsoKnownAs" => [old_ap_id],
           "publicKey" => %{
             "id" => new_ap_id <> "#main-key",
             "owner" => new_ap_id,
             "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n"
           }
         },
         headers: []
       }}
    end)

    move = %{
      "id" => "https://remote.example/activities/move/2",
      "type" => "Move",
      "actor" => old_ap_id,
      "object" => old_ap_id,
      "target" => new_ap_id,
      "to" => [@public],
      "cc" => [old_ap_id <> "/followers"],
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert {:ok, %Object{} = move_object} =
             Pipeline.ingest(move, local: false, inbox_user_ap_id: follower.ap_id)

    assert move_object.type == "Move"

    assert Users.get_by_ap_id(new_ap_id).also_known_as == [old_ap_id]
    assert Users.get_by_ap_id(old_ap_id).moved_to_ap_id == new_ap_id
  end
end
