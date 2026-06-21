defmodule EgregorosWeb.PleromaAPI.OffersControllerTest do
  use EgregorosWeb.ConnCase, async: true

  import Mox

  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.TestSupport.Fixtures
  alias Egregoros.Users

  test "POST /api/v1/pleroma/offers/:id/accept accepts the offer", %{conn: conn} do
    {:ok, alice} = Users.create_local_user("alice")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [alice.ap_id])
      |> put_in(["credentialSubject", "id"], alice.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/api-accept",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [alice.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: alice.ap_id)

    encoded_id = URI.encode_www_form(offer_object.ap_id)

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, alice} end)

    conn = post(conn, "/api/v1/pleroma/offers/#{encoded_id}/accept")
    assert json_response(conn, 200) == %{}

    assert Objects.get_by_type_actor_object("Accept", alice.ap_id, offer_object.ap_id)
  end

  test "POST /api/v1/pleroma/offers/:id/reject rejects the offer", %{conn: conn} do
    {:ok, alice} = Users.create_local_user("alice")

    credential =
      Fixtures.json!("openbadge_vc.json")
      |> Map.put("issuer", "https://example.com/users/issuer")
      |> Map.put("to", [alice.ap_id])
      |> put_in(["credentialSubject", "id"], alice.ap_id)

    offer = %{
      "id" => "https://example.com/activities/offer/api-reject",
      "type" => "Offer",
      "actor" => "https://example.com/users/issuer",
      "to" => [alice.ap_id],
      "object" => credential,
      "published" => "2026-01-29T00:00:00Z"
    }

    assert {:ok, offer_object} =
             Pipeline.ingest(offer, local: false, inbox_user_ap_id: alice.ap_id)

    encoded_id = URI.encode_www_form(offer_object.ap_id)

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, alice} end)

    conn = post(conn, "/api/v1/pleroma/offers/#{encoded_id}/reject")
    assert json_response(conn, 200) == %{}

    assert Objects.get_by_type_actor_object("Reject", alice.ap_id, offer_object.ap_id)
  end
end
