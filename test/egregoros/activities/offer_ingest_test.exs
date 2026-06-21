defmodule Egregoros.Activities.OfferIngestTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users

  test "ingests Offer with a multi-type OpenBadge verifiable credential" do
    {:ok, inbox_user} = Users.create_local_user("offer_ingest_inbox_user")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [inbox_user.ap_id, "https://www.w3.org/ns/activitystreams#Public"])
      |> put_in(["credentialSubject", "id"], inbox_user.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/1",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [inbox_user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, %Object{} = offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: inbox_user.ap_id)

    assert offer_object.type == "Offer"
    assert offer_object.object == credential["id"]

    stored_credential = Objects.get_by_ap_id(credential["id"])
    assert %Object{} = stored_credential
    assert stored_credential.type == "VerifiableCredential"
    assert stored_credential.data["type"] == ["VerifiableCredential", "OpenBadgeCredential"]
    assert stored_credential.internal["auxiliary_types"] == ["OpenBadgeCredential"]

    offer_ap_id = offer_object.ap_id
    recipient_ap_id = inbox_user.ap_id

    assert %Egregoros.Relationship{
             type: "OfferPending",
             actor: ^recipient_ap_id,
             object: ^offer_ap_id,
             activity_ap_id: ^offer_ap_id
           } =
             Relationships.get_by_type_actor_object(
               "OfferPending",
               recipient_ap_id,
               offer_ap_id
             )
  end

  test "rejects Offer when credential domain differs from offer domain" do
    {:ok, inbox_user} = Users.create_local_user("offer_ingest_domain_user")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [inbox_user.ap_id])
      |> put_in(["credentialSubject", "id"], inbox_user.ap_id)
      |> Map.put("id", "https://other.example/objects/credential")

    offer = %{
      "id" => "https://example.com/activities/offer/2",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [inbox_user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:error, :invalid} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: inbox_user.ap_id)
  end

  test "rejects Offer when credential recipient is not local" do
    {:ok, inbox_user} = Users.create_local_user("offer_ingest_remote_recipient")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [inbox_user.ap_id])
      |> put_in(["credentialSubject", "id"], "https://remote.example/users/alice")

    offer = %{
      "id" => "https://example.com/activities/offer/3",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [inbox_user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:error, :invalid} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: inbox_user.ap_id)
  end

  test "rejects Offer when credential issuer is not a valid actor url" do
    {:ok, inbox_user} = Users.create_local_user("offer_ingest_invalid_issuer")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "not-a-url")
      |> Map.put("to", [inbox_user.ap_id])
      |> put_in(["credentialSubject", "id"], inbox_user.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/4",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [inbox_user.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:error, :invalid} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: inbox_user.ap_id)
  end
end
