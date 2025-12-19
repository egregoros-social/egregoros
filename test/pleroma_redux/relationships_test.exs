defmodule PleromaRedux.RelationshipsTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users

  test "ingesting multiple Follow activities produces a single relationship state" do
    {:ok, local} = Users.create_local_user("alice")

    remote_actor = "https://remote.example/users/bob"

    follow_1 = %{
      "id" => "https://remote.example/activities/follow/1",
      "type" => "Follow",
      "actor" => remote_actor,
      "object" => local.ap_id
    }

    follow_2 = %{
      "id" => "https://remote.example/activities/follow/2",
      "type" => "Follow",
      "actor" => remote_actor,
      "object" => local.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow_1, local: false)
    assert {:ok, _} = Pipeline.ingest(follow_2, local: false)

    assert [relationship] = Relationships.list_follows_to(local.ap_id)
    assert relationship.actor == remote_actor
    assert relationship.object == local.ap_id
    assert relationship.activity_ap_id == follow_2["id"]
  end

  test "Undo of an older Follow does not remove the current follow relationship state" do
    {:ok, local} = Users.create_local_user("alice")

    remote_actor = "https://remote.example/users/bob"

    follow_1 = %{
      "id" => "https://remote.example/activities/follow/1",
      "type" => "Follow",
      "actor" => remote_actor,
      "object" => local.ap_id
    }

    follow_2 = %{
      "id" => "https://remote.example/activities/follow/2",
      "type" => "Follow",
      "actor" => remote_actor,
      "object" => local.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow_1, local: false)
    assert {:ok, _} = Pipeline.ingest(follow_2, local: false)

    undo_1 = %{
      "id" => "https://remote.example/activities/undo/1",
      "type" => "Undo",
      "actor" => remote_actor,
      "object" => follow_1["id"]
    }

    assert {:ok, _} = Pipeline.ingest(undo_1, local: false)

    assert [relationship] = Relationships.list_follows_to(local.ap_id)
    assert relationship.activity_ap_id == follow_2["id"]
  end

  test "Undo of the latest Follow removes the follow relationship state" do
    {:ok, local} = Users.create_local_user("alice")

    remote_actor = "https://remote.example/users/bob"

    follow_1 = %{
      "id" => "https://remote.example/activities/follow/1",
      "type" => "Follow",
      "actor" => remote_actor,
      "object" => local.ap_id
    }

    follow_2 = %{
      "id" => "https://remote.example/activities/follow/2",
      "type" => "Follow",
      "actor" => remote_actor,
      "object" => local.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow_1, local: false)
    assert {:ok, _} = Pipeline.ingest(follow_2, local: false)

    undo_2 = %{
      "id" => "https://remote.example/activities/undo/2",
      "type" => "Undo",
      "actor" => remote_actor,
      "object" => follow_2["id"]
    }

    assert {:ok, _} = Pipeline.ingest(undo_2, local: false)

    assert [] == Relationships.list_follows_to(local.ap_id)
  end

  test "ingesting multiple Like activities produces a single relationship state" do
    actor = "https://remote.example/users/bob"
    object = "https://local.example/objects/1"

    like_1 = %{
      "id" => "https://remote.example/activities/like/1",
      "type" => "Like",
      "actor" => actor,
      "object" => object
    }

    like_2 = %{
      "id" => "https://remote.example/activities/like/2",
      "type" => "Like",
      "actor" => actor,
      "object" => object
    }

    assert {:ok, _} = Pipeline.ingest(like_1, local: false)
    assert {:ok, _} = Pipeline.ingest(like_2, local: false)

    assert %{} = relationship = Relationships.get_by_type_actor_object("Like", actor, object)
    assert relationship.activity_ap_id == like_2["id"]
  end

  test "ingesting multiple Announce activities produces a single relationship state" do
    actor = "https://remote.example/users/bob"
    object = "https://local.example/objects/1"

    announce_1 = %{
      "id" => "https://remote.example/activities/announce/1",
      "type" => "Announce",
      "actor" => actor,
      "object" => object
    }

    announce_2 = %{
      "id" => "https://remote.example/activities/announce/2",
      "type" => "Announce",
      "actor" => actor,
      "object" => object
    }

    assert {:ok, _} = Pipeline.ingest(announce_1, local: false)
    assert {:ok, _} = Pipeline.ingest(announce_2, local: false)

    assert %{} = relationship = Relationships.get_by_type_actor_object("Announce", actor, object)
    assert relationship.activity_ap_id == announce_2["id"]
  end

  test "Undo of Like removes the like relationship state" do
    actor = "https://remote.example/users/bob"
    object = "https://local.example/objects/1"

    like = %{
      "id" => "https://remote.example/activities/like/1",
      "type" => "Like",
      "actor" => actor,
      "object" => object
    }

    assert {:ok, _} = Pipeline.ingest(like, local: false)
    assert Relationships.get_by_type_actor_object("Like", actor, object)

    undo = %{
      "id" => "https://remote.example/activities/undo/like-1",
      "type" => "Undo",
      "actor" => actor,
      "object" => like["id"]
    }

    assert {:ok, _} = Pipeline.ingest(undo, local: false)
    assert Relationships.get_by_type_actor_object("Like", actor, object) == nil
  end

  test "Undo of Announce removes the announce relationship state" do
    actor = "https://remote.example/users/bob"
    object = "https://local.example/objects/1"

    announce = %{
      "id" => "https://remote.example/activities/announce/1",
      "type" => "Announce",
      "actor" => actor,
      "object" => object
    }

    assert {:ok, _} = Pipeline.ingest(announce, local: false)
    assert Relationships.get_by_type_actor_object("Announce", actor, object)

    undo = %{
      "id" => "https://remote.example/activities/undo/announce-1",
      "type" => "Undo",
      "actor" => actor,
      "object" => announce["id"]
    }

    assert {:ok, _} = Pipeline.ingest(undo, local: false)
    assert Relationships.get_by_type_actor_object("Announce", actor, object) == nil
  end
end
