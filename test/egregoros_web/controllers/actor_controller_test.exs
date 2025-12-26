defmodule EgregorosWeb.ActorControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.E2EE
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
  end

  test "GET /users/:nickname includes profile metadata when available", %{conn: conn} do
    {:ok, user} = Users.create_local_user("dana")

    {:ok, _} =
      Users.update_profile(user, %{
        "name" => "Dana Example",
        "bio" => "Hello federation",
        "avatar_url" => "https://cdn.example/dana.png"
      })

    conn = get(conn, "/users/dana")
    assert conn.status == 200

    decoded = Jason.decode!(conn.resp_body)
    assert decoded["name"] == "Dana Example"
    assert decoded["summary"] == "Hello federation"
    assert decoded["icon"]["url"] == "https://cdn.example/dana.png"
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

  test "GET /users/:nickname exposes e2ee public keys when configured", %{conn: conn} do
    {:ok, user} = Users.create_local_user("dana")

    kid = "e2ee-2025-12-26T00:00:00Z"

    public_key_jwk = %{
      "kty" => "EC",
      "crv" => "P-256",
      "x" => "pQECAwQFBgcICQoLDA0ODw",
      "y" => "AQIDBAUGBwgJCgsMDQ4PEA"
    }

    assert {:ok, _} =
             E2EE.enable_key_with_wrapper(user, %{
               kid: kid,
               public_key_jwk: public_key_jwk,
               wrapper: %{
                 type: "webauthn_hmac_secret",
                 wrapped_private_key: <<1, 2, 3>>,
                 params: %{
                   "credential_id" => Base.url_encode64("cred", padding: false),
                   "prf_salt" => Base.url_encode64("prf-salt", padding: false),
                   "hkdf_salt" => Base.url_encode64("hkdf-salt", padding: false),
                   "iv" => Base.url_encode64("iv", padding: false),
                   "alg" => "A256GCM",
                   "kdf" => "HKDF-SHA256",
                   "info" => "egregoros:e2ee:wrap:v1"
                 }
               }
             })

    conn = get(conn, "/users/dana")
    assert conn.status == 200

    decoded = Jason.decode!(conn.resp_body)

    assert %{"version" => 1, "keys" => [rendered_key]} = decoded["egregoros:e2ee"]
    assert rendered_key["kid"] == kid
    assert rendered_key["kty"] == "EC"
    assert rendered_key["crv"] == "P-256"
    assert rendered_key["x"] == public_key_jwk["x"]
    assert rendered_key["y"] == public_key_jwk["y"]
    assert String.starts_with?(rendered_key["fingerprint"], "sha256:")
  end
end
