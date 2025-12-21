defmodule PleromaRedux.NotificationsTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Activities.Announce
  alias PleromaRedux.Activities.Follow
  alias PleromaRedux.Activities.Like
  alias PleromaRedux.Notifications
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Publish
  alias PleromaRedux.Users

  test "lists follow notifications for the recipient" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    assert {:ok, follow} = Pipeline.ingest(Follow.build(bob, alice), local: true)

    [notification] = Notifications.list_for_user(alice, limit: 1)
    assert notification.id == follow.id
    assert notification.type == "Follow"
    assert notification.object == alice.ap_id
  end

  test "lists likes and announces on the user's notes" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, create} = Publish.post_note(alice, "hello")
    note_ap_id = create.object

    assert {:ok, like} = Pipeline.ingest(Like.build(bob, note_ap_id), local: true)
    assert {:ok, announce} = Pipeline.ingest(Announce.build(bob, note_ap_id), local: true)

    notifications = Notifications.list_for_user(alice, limit: 10)

    assert Enum.map(notifications, & &1.id) |> Enum.take(2) == [announce.id, like.id]
    assert Enum.map(notifications, & &1.type) |> Enum.take(2) == ["Announce", "Like"]
  end

  test "supports max_id and since_id pagination" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    ids =
      for idx <- 1..5 do
        {:ok, object} =
          Pipeline.ingest(
            %{
              "id" => "https://example.com/activities/follow/#{idx}",
              "type" => "Follow",
              "actor" => bob.ap_id,
              "object" => alice.ap_id
            },
            local: true
          )

        object.id
      end

    [_id1, id2, id3, id4, id5] = ids

    older = Notifications.list_for_user(alice, limit: 10, max_id: id4)
    assert Enum.all?(older, &(&1.id < id4))
    assert Enum.any?(older, &(&1.id == id3))
    refute Enum.any?(older, &(&1.id == id4))

    newer = Notifications.list_for_user(alice, limit: 10, since_id: id2)
    assert Enum.all?(newer, &(&1.id > id2))
    assert Enum.any?(newer, &(&1.id == id5))
    refute Enum.any?(newer, &(&1.id == id2))

    mixed = Notifications.list_for_user(alice, limit: 10, max_id: "#{id5}", since_id: "#{id2}")
    assert Enum.all?(mixed, &(&1.id < id5 and &1.id > id2))
  end

  test "normalizes limit values" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    for idx <- 1..50 do
      assert {:ok, _} =
               Pipeline.ingest(
                 %{
                   "id" => "https://example.com/activities/follow/#{idx}",
                   "type" => "Follow",
                   "actor" => bob.ap_id,
                   "object" => alice.ap_id
                 },
                 local: true
               )
    end

    assert length(Notifications.list_for_user(alice, limit: 999)) == 40
    assert length(Notifications.list_for_user(alice, limit: 0)) == 1
    assert length(Notifications.list_for_user(alice, limit: "5")) == 5
    assert length(Notifications.list_for_user(alice, limit: "nope")) == 20
  end

  test "returns an empty list for invalid users" do
    assert Notifications.list_for_user(nil) == []
    assert Notifications.list_for_user(%{}, limit: 10) == []
  end
end
