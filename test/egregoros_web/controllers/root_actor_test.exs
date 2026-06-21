defmodule EgregorosWeb.RootActorTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.VerifiableCredentials.DidWeb
  alias EgregorosWeb.Endpoint

  test "GET / serves the instance actor for ActivityPub requests", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/activity+json")
      |> get("/")

    assert List.first(get_resp_header(conn, "content-type")) =~ "application/activity+json"
    assert List.first(get_resp_header(conn, "vary")) =~ "accept"

    body = Jason.decode!(response(conn, 200))

    assert body["id"] == Endpoint.url()
    assert body["type"] == "Application"
    assert body["inbox"] == Endpoint.url() <> "/inbox"

    assert body["publicKey"]["id"] == Endpoint.url() <> "#main-key"
    assert body["publicKey"]["owner"] == Endpoint.url()
    assert is_list(body["assertionMethod"])
    assert "https://w3id.org/security/v2" in body["@context"]
    assert "https://w3id.org/security/data-integrity/v2" in body["@context"]

    did = DidWeb.instance_did()
    assert did in List.wrap(body["alsoKnownAs"])

    assert Enum.any?(body["assertionMethod"], fn method ->
             method["id"] == Endpoint.url() <> "#ed25519-key" and
               method["type"] == "Multikey" and
               method["controller"] == Endpoint.url() and
               is_binary(method["publicKeyMultibase"])
           end)
  end
end
