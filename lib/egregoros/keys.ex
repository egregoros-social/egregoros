defmodule Egregoros.Keys do
  @base58_alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @base58_map Map.new(Enum.with_index(@base58_alphabet))

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

  def generate_ed25519_keypair do
    :crypto.generate_key(:eddsa, :ed25519)
  end

  def ed25519_public_key_from_private_key(private_key)
      when is_binary(private_key) and byte_size(private_key) == 32 do
    {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519, private_key)
    {:ok, public_key}
  end

  def ed25519_public_key_from_private_key(_private_key), do: {:error, :invalid_ed25519_key}

  def ed25519_public_key_multibase(public_key)
      when is_binary(public_key) and byte_size(public_key) == 32 do
    "z" <> base58btc_encode(<<0xED, 0x01>> <> public_key)
  end

  def ed25519_public_key_multibase(_public_key), do: nil

  def ed25519_public_key_from_multibase("z" <> encoded) do
    with {:ok, decoded} <- base58btc_decode(encoded),
         <<0xED, 0x01, public_key::binary>> <- decoded,
         32 <- byte_size(public_key) do
      {:ok, public_key}
    else
      _ -> {:error, :invalid_ed25519_key}
    end
  end

  def ed25519_public_key_from_multibase(_), do: {:error, :invalid_ed25519_key}

  defp public_key_from_private(
         {:RSAPrivateKey, _, modulus, public_exponent, _private_exponent, _prime1, _prime2,
          _exponent1, _exponent2, _coefficient, _other_prime_infos}
       ) do
    {:RSAPublicKey, modulus, public_exponent}
  end

  defp base58btc_encode(bin) when is_binary(bin) do
    leading_zeros = count_leading_zeros(bin)
    encoded = encode_base58_integer(:binary.decode_unsigned(bin))

    case {leading_zeros, encoded} do
      {0, ""} -> ""
      {count, ""} -> String.duplicate("1", count)
      {count, _} -> String.duplicate("1", count) <> encoded
    end
  end

  defp base58btc_decode(encoded) when is_binary(encoded) do
    {leading_ones, rest} = split_leading_ones(encoded)

    with {:ok, value} <- decode_base58_integer(rest) do
      decoded =
        case value do
          0 -> <<>>
          _ -> :binary.encode_unsigned(value)
        end

      {:ok, <<0::size(leading_ones * 8)>> <> decoded}
    end
  end

  defp base58btc_decode(_), do: {:error, :invalid_base58}

  defp count_leading_zeros(bin) do
    bin
    |> :binary.bin_to_list()
    |> Enum.take_while(&(&1 == 0))
    |> length()
  end

  defp split_leading_ones(encoded) do
    encoded
    |> String.graphemes()
    |> Enum.split_while(&(&1 == "1"))
    |> then(fn {ones, rest} -> {length(ones), Enum.join(rest)} end)
  end

  defp encode_base58_integer(0), do: ""

  defp encode_base58_integer(value) when is_integer(value) and value > 0 do
    encode_base58_integer(value, "")
  end

  defp encode_base58_integer(0, acc), do: acc

  defp encode_base58_integer(value, acc) do
    {quotient, remainder} = div_rem(value, 58)
    char = @base58_alphabet |> Enum.at(remainder) |> then(&<<&1>>)
    encode_base58_integer(quotient, char <> acc)
  end

  defp decode_base58_integer(""), do: {:ok, 0}

  defp decode_base58_integer(encoded) when is_binary(encoded) do
    encoded
    |> String.graphemes()
    |> Enum.reduce_while({:ok, 0}, fn char, {:ok, acc} ->
      case Map.fetch(@base58_map, String.to_charlist(char) |> List.first()) do
        {:ok, value} -> {:cont, {:ok, acc * 58 + value}}
        :error -> {:halt, {:error, :invalid_base58}}
      end
    end)
  end

  defp div_rem(value, divisor) do
    {div(value, divisor), rem(value, divisor)}
  end
end
