defmodule EgregorosWeb.PasskeysControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Passkeys
  alias Egregoros.Users

  test "passkey registration creates a local user without a password", %{conn: conn} do
    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/passkeys/registration/options", %{
        "_csrf_token" => csrf_token,
        "nickname" => "alice",
        "email" => ""
      })

    assert %{"publicKey" => public_key} = json_response(conn, 200)
    assert is_binary(public_key["challenge"])
    assert is_map(public_key["rp"])
    assert is_map(public_key["user"])

    {pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)
    cred_id = :crypto.strong_rand_bytes(16)

    payload =
      build_attestation_payload(
        public_key["challenge"],
        public_key["rp"]["id"],
        expected_origin(),
        cred_id,
        pub
      )

    conn =
      conn
      |> recycle()
      |> post("/passkeys/registration/finish", Map.put(payload, "_csrf_token", csrf_token))

    assert %{"redirect_to" => "/"} = json_response(conn, 201)
    assert is_integer(get_session(conn, :user_id))

    assert user = Users.get_by_nickname("alice")
    assert user.local
    assert user.email == nil
    assert user.password_hash == nil

    [credential] = Passkeys.list_credentials(user)
    assert credential.user_id == user.id
    assert credential.credential_id == cred_id
    assert credential.public_key == pub

    # Sanity check: can authenticate with the stored credential.
    assert {:ok, _user} = authenticate_with_passkey(conn, user, credential, priv)
  end

  test "passkey registration respects return_to", %{conn: conn} do
    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      post(conn, "/passkeys/registration/options", %{
        "_csrf_token" => csrf_token,
        "nickname" => "bob",
        "email" => "",
        "return_to" => "/settings"
      })

    assert %{"publicKey" => public_key} = json_response(conn, 200)

    {pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)
    cred_id = :crypto.strong_rand_bytes(16)

    payload =
      build_attestation_payload(
        public_key["challenge"],
        public_key["rp"]["id"],
        expected_origin(),
        cred_id,
        pub
      )

    conn =
      conn
      |> recycle()
      |> post("/passkeys/registration/finish", Map.put(payload, "_csrf_token", csrf_token))

    assert %{"redirect_to" => "/settings"} = json_response(conn, 201)

    assert user = Users.get_by_nickname("bob")
    [credential] = Passkeys.list_credentials(user)

    assert {:ok, _user} = authenticate_with_passkey(conn, user, credential, priv, return_to: "/settings")
  end

  defp authenticate_with_passkey(conn, user, credential, priv, opts \\ []) do
    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      conn
      |> recycle()
      |> post("/passkeys/authentication/options", %{
        "_csrf_token" => csrf_token,
        "nickname" => user.nickname,
        "return_to" => Keyword.get(opts, :return_to, "")
      })

    assert %{"publicKey" => public_key} = json_response(conn, 200)
    challenge_b64 = public_key["challenge"]

    assertion_payload =
      build_assertion_payload(
        challenge_b64,
        public_key["rpId"],
        expected_origin(),
        credential.credential_id,
        priv,
        user_verification?: true
      )

    conn =
      conn
      |> recycle()
      |> post("/passkeys/authentication/finish", Map.put(assertion_payload, "_csrf_token", csrf_token))

    expected_return_to = Keyword.get(opts, :return_to, "/")
    assert %{"redirect_to" => ^expected_return_to} = json_response(conn, 200)
    assert get_session(conn, :user_id) == user.id
    {:ok, user}
  end

  defp expected_origin do
    EgregorosWeb.Endpoint.url()
  end

  defp build_attestation_payload(challenge_b64, rp_id, origin, cred_id, pub_key) do
    rp_id_hash = :crypto.hash(:sha256, rp_id)

    <<4, x::binary-size(32), y::binary-size(32)>> = pub_key

    cose_key =
      %{
        1 => 2,
        3 => -7,
        -1 => 1,
        -2 => x,
        -3 => y
      }
      |> Egregoros.CBOR.encode()

    auth_data =
      rp_id_hash <>
        <<0x45, 0::32>> <>
        <<0::128, byte_size(cred_id)::16>> <>
        cred_id <>
        cose_key

    attestation_object =
      %{
        "fmt" => "none",
        "attStmt" => %{},
        "authData" => auth_data
      }
      |> Egregoros.CBOR.encode()

    client_data_json =
      %{
        "type" => "webauthn.create",
        "challenge" => challenge_b64,
        "origin" => origin,
        "crossOrigin" => false
      }
      |> Jason.encode!()

    %{
      "credential" => %{
        "id" => b64url(cred_id),
        "rawId" => b64url(cred_id),
        "type" => "public-key",
        "response" => %{
          "attestationObject" => b64url(attestation_object),
          "clientDataJSON" => b64url(client_data_json)
        }
      }
    }
  end

  defp build_assertion_payload(challenge_b64, rp_id, origin, cred_id, priv_key, opts) do
    rp_id_hash = :crypto.hash(:sha256, rp_id)

    flags =
      if Keyword.get(opts, :user_verification?, false) do
        0x05
      else
        0x01
      end

    authenticator_data = rp_id_hash <> <<flags, 1::32>>

    client_data_json =
      %{
        "type" => "webauthn.get",
        "challenge" => challenge_b64,
        "origin" => origin,
        "crossOrigin" => false
      }
      |> Jason.encode!()

    signed =
      authenticator_data <>
        :crypto.hash(:sha256, client_data_json)

    signature = :crypto.sign(:ecdsa, :sha256, signed, [priv_key, :prime256v1])

    %{
      "credential" => %{
        "id" => b64url(cred_id),
        "rawId" => b64url(cred_id),
        "type" => "public-key",
        "response" => %{
          "authenticatorData" => b64url(authenticator_data),
          "clientDataJSON" => b64url(client_data_json),
          "signature" => b64url(signature)
        }
      }
    }
  end

  defp b64url(value) when is_binary(value) do
    Base.url_encode64(value, padding: false)
  end
end
