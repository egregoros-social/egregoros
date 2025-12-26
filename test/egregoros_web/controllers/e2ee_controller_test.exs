defmodule EgregorosWeb.E2EEControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Users

  test "GET /settings/e2ee returns 401 when not logged in", %{conn: conn} do
    conn = get(conn, "/settings/e2ee")
    assert conn.status == 401
  end

  test "POST /settings/e2ee/passkey enables E2EE and stores encrypted key material", %{conn: conn} do
    {:ok, user} =
      Users.register_local_user(%{
        nickname: "alice",
        email: "alice@example.com",
        password: "very secure password"
      })

    kid = "e2ee-2025-12-26T00:00:00Z"

    public_key_jwk = %{
      "kty" => "EC",
      "crv" => "P-256",
      "x" => "pQECAwQFBgcICQoLDA0ODw",
      "y" => "AQIDBAUGBwgJCgsMDQ4PEA"
    }

    wrapped_private_key_b64 =
      <<1, 2, 3, 4, 5, 6>>
      |> Base.url_encode64(padding: false)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> post("/settings/e2ee/passkey", %{
        "kid" => kid,
        "public_key_jwk" => public_key_jwk,
        "wrapper" => %{
          "type" => "webauthn_hmac_secret",
          "wrapped_private_key" => wrapped_private_key_b64,
          "params" => %{
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

    assert conn.status == 201
    decoded = json_response(conn, 201)
    assert decoded["kid"] == kid
    assert String.starts_with?(decoded["fingerprint"], "sha256:")

    conn = get(conn, "/settings/e2ee")
    assert conn.status == 200
    status = json_response(conn, 200)
    assert status["enabled"] == true
    assert status["active_key"]["kid"] == kid
    assert is_list(status["wrappers"])
    assert length(status["wrappers"]) == 1
  end
end
