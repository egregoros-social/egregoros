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
end

