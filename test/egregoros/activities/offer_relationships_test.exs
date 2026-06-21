defmodule Egregoros.Activities.OfferRelationshipsTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Object
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users

  test "accepting an offer records an accepted relationship" do
    {:ok, recipient} = Users.create_local_user("offer_accept_recipient")

    offer = build_offer(recipient)

    assert {:ok, %Object{} = offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: recipient.ap_id)

    assert Relationships.get_by_type_actor_object(
             "OfferPending",
             recipient.ap_id,
             offer_object.ap_id
           )

    offer_ap_id = offer_object.ap_id
    recipient_ap_id = recipient.ap_id

    accept_activity = %{
      "id" => "https://example.com/activities/accept/" <> Ecto.UUID.generate(),
      "type" => "Accept",
      "actor" => recipient.ap_id,
      "object" => offer_object.data,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert {:ok, _accept_object} = Pipeline.ingest(accept_activity, local: true)

    refute Relationships.get_by_type_actor_object("OfferPending", recipient_ap_id, offer_ap_id)

    assert %Egregoros.Relationship{
             type: "OfferAccepted",
             actor: ^recipient_ap_id,
             object: ^offer_ap_id,
             activity_ap_id: ^offer_ap_id
           } =
             Relationships.get_by_type_actor_object(
               "OfferAccepted",
               recipient_ap_id,
               offer_ap_id
             )
  end

  test "rejecting an offer records a rejected relationship" do
    {:ok, recipient} = Users.create_local_user("offer_reject_recipient")

    offer = build_offer(recipient)

    assert {:ok, %Object{} = offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: recipient.ap_id)

    assert Relationships.get_by_type_actor_object(
             "OfferPending",
             recipient.ap_id,
             offer_object.ap_id
           )

    offer_ap_id = offer_object.ap_id
    recipient_ap_id = recipient.ap_id

    reject_activity = %{
      "id" => "https://example.com/activities/reject/" <> Ecto.UUID.generate(),
      "type" => "Reject",
      "actor" => recipient.ap_id,
      "object" => offer_object.data,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert {:ok, _reject_object} = Pipeline.ingest(reject_activity, local: true)

    refute Relationships.get_by_type_actor_object("OfferPending", recipient_ap_id, offer_ap_id)

    assert %Egregoros.Relationship{
             type: "OfferRejected",
             actor: ^recipient_ap_id,
             object: ^offer_ap_id,
             activity_ap_id: ^offer_ap_id
           } =
             Relationships.get_by_type_actor_object(
               "OfferRejected",
               recipient_ap_id,
               offer_ap_id
             )
  end

  defp build_offer(%Egregoros.User{} = recipient) do
    credential_id = "https://example.com/objects/" <> Ecto.UUID.generate()
    offer_id = "https://example.com/activities/offer/" <> Ecto.UUID.generate()

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("id", credential_id)
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [recipient.ap_id, "https://www.w3.org/ns/activitystreams#Public"])
      |> put_in(["credentialSubject", "id"], recipient.ap_id)

    %{
      "id" => offer_id,
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [recipient.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }
  end
end
