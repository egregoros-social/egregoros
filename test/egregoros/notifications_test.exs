defmodule Egregoros.NotificationsTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.Announce
  alias Egregoros.Activities.EmojiReact
  alias Egregoros.Activities.Follow
  alias Egregoros.Activities.Like
  alias Egregoros.Notifications
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users

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

  test "lists emoji reactions on the user's notes" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, create} = Publish.post_note(alice, "hello")
    note_ap_id = create.object

    assert {:ok, react} = Pipeline.ingest(EmojiReact.build(bob, note_ap_id, "🔥"), local: true)

    notifications = Notifications.list_for_user(alice, limit: 10)

    assert Enum.any?(notifications, &(&1.id == react.id))
    assert Enum.any?(notifications, &(&1.type == "EmojiReact"))
  end

  test "lists notes that mention the user" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, create} = Publish.post_note(bob, "@alice Hello there")
    note_ap_id = create.object

    notifications = Notifications.list_for_user(alice, limit: 10)

    assert Enum.any?(notifications, &(&1.type == "Note" and &1.ap_id == note_ap_id))
  end

  test "lists offer notifications only when include_offers? is enabled" do
    {:ok, alice} = Users.create_local_user("alice")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [alice.ap_id])
      |> put_in(["credentialSubject", "id"], alice.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/notifications",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [alice.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, _offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: alice.ap_id)

    refute Enum.any?(Notifications.list_for_user(alice, limit: 10), &(&1.type == "Offer"))

    assert Enum.any?(
             Notifications.list_for_user(alice, limit: 10, include_offers?: true),
             &(&1.type == "Offer")
           )
  end

  test "broadcasts mention notifications to local recipients" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    Notifications.subscribe(alice.ap_id)
    assert {:ok, _create} = Publish.post_note(bob, "@alice hello!")

    assert_receive {:notification_created, %{type: "Note", actor: actor}}, 1_000
    assert actor == bob.ap_id
  end

  test "broadcasts emoji reaction notifications to local authors" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    Notifications.subscribe(alice.ap_id)
    {:ok, create} = Publish.post_note(alice, "hello")

    assert {:ok, _} = Pipeline.ingest(EmojiReact.build(bob, create.object, "🔥"), local: true)

    assert_receive {:notification_created, %{type: "EmojiReact", actor: actor}}, 1_000
    assert actor == bob.ap_id
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
