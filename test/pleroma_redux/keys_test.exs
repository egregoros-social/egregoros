defmodule PleromaRedux.KeysTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.Keys

  test "generate_rsa_keypair returns PEM strings" do
    {public_pem, private_pem} = Keys.generate_rsa_keypair()

    assert is_binary(public_pem)
    assert is_binary(private_pem)
    assert String.starts_with?(public_pem, "-----BEGIN PUBLIC KEY-----")
    assert String.starts_with?(private_pem, "-----BEGIN PRIVATE KEY-----")
  end
end
