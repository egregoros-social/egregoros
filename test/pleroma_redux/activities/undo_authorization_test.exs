defmodule PleromaRedux.Activities.UndoAuthorizationTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.Users

  test "does not undo state when actor does not match the target activity actor" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, eve} = Users.create_local_user("eve")

    follow = %{
      "id" => "https://example.com/activities/follow/1",
      "type" => "Follow",
      "actor" => alice.ap_id,
      "object" => bob.ap_id
    }

    assert {:ok, follow_object} = Pipeline.ingest(follow, local: true)
    assert Relationships.get_by_type_actor_object("Follow", alice.ap_id, bob.ap_id)

    undo = %{
      "id" => "https://example.com/activities/undo/1",
      "type" => "Undo",
      "actor" => eve.ap_id,
      "object" => follow_object.ap_id
    }

    assert {:ok, _undo_object} = Pipeline.ingest(undo, local: false)

    assert Relationships.get_by_type_actor_object("Follow", alice.ap_id, bob.ap_id)
    assert Objects.get_by_ap_id(follow_object.ap_id)
  end
end

