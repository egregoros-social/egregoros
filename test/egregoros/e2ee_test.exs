defmodule Egregoros.E2EETest do
  use Egregoros.DataCase, async: true

  alias Egregoros.E2EE
  alias Egregoros.Users

  describe "enable_key_with_wrapper/2" do
    test "stores an active key and a wrapper for a user" do
      {:ok, user} = Users.create_local_user("alice")

      kid = "e2ee-2025-12-26T00:00:00Z"

      public_key_jwk = %{
        "kty" => "EC",
        "crv" => "P-256",
        "x" => "pQECAwQFBgcICQoLDA0ODw",
        "y" => "AQIDBAUGBwgJCgsMDQ4PEA"
      }

      wrapped_private_key = <<1, 2, 3, 4, 5, 6>>

      params = %{
        "credential_id" => Base.url_encode64("cred", padding: false),
        "prf_salt" => Base.url_encode64("prf-salt", padding: false),
        "hkdf_salt" => Base.url_encode64("hkdf-salt", padding: false),
        "iv" => Base.url_encode64("iv", padding: false),
        "alg" => "A256GCM",
        "kdf" => "HKDF-SHA256",
        "info" => "egregoros:e2ee:wrap:v1"
      }

      assert {:ok, %{key: key, wrapper: wrapper}} =
               E2EE.enable_key_with_wrapper(user, %{
                 kid: kid,
                 public_key_jwk: public_key_jwk,
                 wrapper: %{
                   type: "webauthn_hmac_secret",
                   wrapped_private_key: wrapped_private_key,
                   params: params
                 }
               })

      assert key.user_id == user.id
      assert key.kid == kid
      assert key.active == true
      assert key.public_key_jwk == public_key_jwk
      assert is_binary(key.fingerprint)
      assert String.starts_with?(key.fingerprint, "sha256:")

      assert wrapper.user_id == user.id
      assert wrapper.kid == kid
      assert wrapper.type == "webauthn_hmac_secret"
      assert wrapper.wrapped_private_key == wrapped_private_key
      assert wrapper.params == params

      assert E2EE.get_active_key(user).kid == kid
    end

    test "returns :already_enabled when the user already has an active key" do
      {:ok, user} = Users.create_local_user("alice")

      kid = "e2ee-2025-12-26T00:00:00Z"

      public_key_jwk = %{
        "kty" => "EC",
        "crv" => "P-256",
        "x" => "pQECAwQFBgcICQoLDA0ODw",
        "y" => "AQIDBAUGBwgJCgsMDQ4PEA"
      }

      wrapper = %{
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

      assert {:ok, _} =
               E2EE.enable_key_with_wrapper(user, %{
                 kid: kid,
                 public_key_jwk: public_key_jwk,
                 wrapper: wrapper
               })

      assert {:error, :already_enabled} =
               E2EE.enable_key_with_wrapper(user, %{
                 kid: "e2ee-2025-12-26T01:00:00Z",
                 public_key_jwk: public_key_jwk,
                 wrapper: wrapper
               })
    end
  end

  describe "fingerprint_public_key_jwk/1" do
    test "is stable and changes when the key changes" do
      jwk1 = %{"kty" => "EC", "crv" => "P-256", "x" => "a", "y" => "b"}
      jwk2 = %{"kty" => "EC", "crv" => "P-256", "x" => "a", "y" => "c"}

      assert {:ok, fp1} = E2EE.fingerprint_public_key_jwk(jwk1)
      assert {:ok, fp1_again} = E2EE.fingerprint_public_key_jwk(jwk1)
      assert {:ok, fp2} = E2EE.fingerprint_public_key_jwk(jwk2)

      assert fp1 == fp1_again
      assert fp1 != fp2
      assert String.starts_with?(fp1, "sha256:")
      assert String.starts_with?(fp2, "sha256:")
    end
  end
end
