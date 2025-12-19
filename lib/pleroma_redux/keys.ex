defmodule PleromaRedux.Keys do
  def generate_rsa_keypair do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    public_key = public_key_from_private(private_key)

    public_pem =
      :public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)
      |> List.wrap()
      |> :public_key.pem_encode()
      |> IO.iodata_to_binary()

    private_pem =
      :public_key.pem_entry_encode(:PrivateKeyInfo, private_key)
      |> List.wrap()
      |> :public_key.pem_encode()
      |> IO.iodata_to_binary()

    {public_pem, private_pem}
  end

  defp public_key_from_private({:RSAPrivateKey, _, modulus, public_exponent, _private_exponent,
        _prime1, _prime2, _exponent1, _exponent2, _coefficient, _other_prime_infos}) do
    {:RSAPublicKey, modulus, public_exponent}
  end
end
