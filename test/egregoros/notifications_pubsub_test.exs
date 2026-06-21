defmodule Egregoros.NotificationsPubSubTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Notifications
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users

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

  test "broadcasts offer notifications to the recipient" do
    {:ok, alice} = Users.create_local_user("alice")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [alice.ap_id])
      |> put_in(["credentialSubject", "id"], alice.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/pubsub",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [alice.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    Notifications.subscribe(alice.ap_id)

    assert {:ok, _offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: alice.ap_id)

    assert_receive {:notification_created,
                    %{type: "Offer", actor: "https://example.com/users/issuer"}}
  end
end
