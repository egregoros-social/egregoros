defmodule EgregorosWeb.ActorControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Users

  test "GET /users/:nickname returns ActivityPub actor", %{conn: conn} do
    {:ok, user} = Users.create_local_user("dana")

    conn = get(conn, "/users/dana")
    assert conn.status == 200

    [content_type] = get_resp_header(conn, "content-type")
    assert String.contains?(content_type, "application/activity+json")

    decoded = Jason.decode!(conn.resp_body)
    assert decoded["id"] == user.ap_id
    assert decoded["preferredUsername"] == "dana"
    assert decoded["followers"] == user.ap_id <> "/followers"
    assert decoded["following"] == user.ap_id <> "/following"
    assert decoded["publicKey"]["publicKeyPem"] == user.public_key
    assert is_list(decoded["assertionMethod"])
    assert "https://w3id.org/security/v2" in decoded["@context"]
    assert "https://w3id.org/security/data-integrity/v2" in decoded["@context"]

    assert Enum.any?(decoded["assertionMethod"], fn method ->
             method["id"] == user.ap_id <> "#ed25519-key" and
               method["type"] == "Multikey" and
               method["controller"] == user.ap_id and
               is_binary(method["publicKeyMultibase"])
           end)
  end

  test "GET /users/:nickname includes profile metadata when available", %{conn: conn} do
    {:ok, user} = Users.create_local_user("dana")

    {:ok, _} =
      Users.update_profile(user, %{
        "name" => "Dana Example",
        "bio" => "Hello federation",
        "avatar_url" => "https://cdn.example/dana.png",
        "locked" => true
      })

    conn = get(conn, "/users/dana")
    assert conn.status == 200

    decoded = Jason.decode!(conn.resp_body)
    assert decoded["name"] == "Dana Example"
    assert decoded["summary"] == "Hello federation"
    assert decoded["icon"]["url"] == "https://cdn.example/dana.png"
    assert decoded["manuallyApprovesFollowers"] == true
  end

  test "GET /users/:nickname renders uploaded avatar paths as absolute urls", %{conn: conn} do
    {:ok, user} = Users.create_local_user("dana")

    {:ok, _} =
      Users.update_profile(user, %{
        "avatar_url" => "/uploads/avatars/#{user.id}/avatar.png"
      })

    conn = get(conn, "/users/dana")
    assert conn.status == 200

    decoded = Jason.decode!(conn.resp_body)

    assert decoded["icon"]["url"] ==
             EgregorosWeb.Endpoint.url() <> "/uploads/avatars/#{user.id}/avatar.png"
  end

  test "GET /users/:nickname never advertises e2ee keys", %{conn: conn} do
    {:ok, _user} = Users.create_local_user("dana")

    conn = get(conn, "/users/dana")
    assert conn.status == 200

    decoded = Jason.decode!(conn.resp_body)

    refute Map.has_key?(decoded, "egregoros:e2ee")

    refute Enum.any?(decoded["@context"], fn entry ->
             is_map(entry) and Map.has_key?(entry, "egregoros")
           end)
  end
end
