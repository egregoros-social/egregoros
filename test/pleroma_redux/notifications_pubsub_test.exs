defmodule PleromaRedux.NotificationsPubSubTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Notifications
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Publish
  alias PleromaRedux.Users

  test "broadcasts follow notifications to the followed user" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    alice_ap_id = alice.ap_id
    bob_ap_id = bob.ap_id

    Notifications.subscribe(alice.ap_id)

    {:ok, _follow} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/1",
          "type" => "Follow",
          "actor" => bob_ap_id,
          "object" => alice_ap_id
        },
        local: true
      )

    assert_receive {:notification_created,
                    %{type: "Follow", actor: ^bob_ap_id, object: ^alice_ap_id}}
  end

  test "broadcasts favourite notifications to the status author" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, create} = Publish.post_note(alice, "hello")

    bob_ap_id = bob.ap_id
    object_ap_id = create.object

    Notifications.subscribe(alice.ap_id)

    {:ok, _like} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/like/1",
          "type" => "Like",
          "actor" => bob_ap_id,
          "object" => object_ap_id
        },
        local: true
      )

    assert_receive {:notification_created,
                    %{type: "Like", actor: ^bob_ap_id, object: ^object_ap_id}}
  end
end
