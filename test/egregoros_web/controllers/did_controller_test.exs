defmodule EgregorosWeb.DidControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Federation.InstanceActor
  alias Egregoros.VerifiableCredentials.DidWeb
  alias EgregorosWeb.Endpoint

  test "GET /.well-known/did.json returns the instance DID document", %{conn: conn} do
    {:ok, _actor} = InstanceActor.get_actor()

    conn = get(conn, "/.well-known/did.json")
    assert conn.status == 200

    [content_type] = get_resp_header(conn, "content-type")
    assert String.contains?(content_type, "application/did+ld+json")

    decoded = Jason.decode!(conn.resp_body)

    did = DidWeb.instance_did()
    assert is_binary(did)
    assert decoded["id"] == did
    assert Endpoint.url() in List.wrap(decoded["alsoKnownAs"])

    method_id = did <> "#ed25519-key"

    assert Enum.any?(List.wrap(decoded["verificationMethod"]), fn method ->
             method["id"] == method_id and
               method["type"] == "Multikey" and
               method["controller"] == did and
               is_binary(method["publicKeyMultibase"])
           end)

    assert decoded["assertionMethod"] == [method_id]
  end
end
