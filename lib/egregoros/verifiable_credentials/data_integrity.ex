defmodule Egregoros.VerifiableCredentials.DataIntegrity do
  @moduledoc """
  Utilities for creating and verifying Data Integrity proofs for JSON-LD documents
  using the `eddsa-jcs-2022` cryptosuite.
  """

  @cryptosuite "eddsa-jcs-2022"
  @proof_type "DataIntegrityProof"
  @base58_alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @base58_map Map.new(Enum.with_index(@base58_alphabet))

  @type proof_opts :: map() | keyword()

  @spec attach_proof(map(), binary(), proof_opts()) :: {:ok, map()} | {:error, atom()}
  def attach_proof(document, private_key, opts \\ %{})

  def attach_proof(document, private_key, opts)
      when is_map(document) and is_binary(private_key) do
    with :ok <- validate_document(document),
         :ok <- ensure_unsigned(document),
         :ok <- validate_private_key(private_key),
         {:ok, proof_config} <- build_proof_options(document, opts),
         {:ok, proof} <- create_proof(document, proof_config, private_key) do
      {:ok, Map.put(document, "proof", proof)}
    end
  end

  def attach_proof(_document, _private_key, _opts), do: {:error, :invalid_document}

  @spec verify_proof(map(), binary()) :: {:ok, boolean()} | {:error, atom()}
  def verify_proof(document, public_key) when is_map(document) and is_binary(public_key) do
    with :ok <- validate_document(document),
         :ok <- validate_public_key(public_key),
         {:ok, proof} <- extract_proof(document),
         {:ok, proof_options} <- proof_options_from_proof(proof),
         {:ok, {unsecured_document, proof_options}} <-
           prepare_unsecured_document(document, proof_options),
         {:ok, proof_config} <- proof_configuration(proof_options),
         {:ok, signature} <- decode_proof_value(proof["proofValue"]),
         {:ok, canonical_proof_config} <- canonicalize(proof_config),
         {:ok, canonical_document} <- canonicalize(unsecured_document) do
      hash_data = hash_proof_data(canonical_proof_config, canonical_document)
      verified = :crypto.verify(:eddsa, :none, hash_data, signature, [public_key, :ed25519])
      {:ok, verified}
    end
  end

  def verify_proof(_document, _public_key), do: {:error, :invalid_document}

  defp validate_document(%{} = document) do
    if Map.has_key?(document, :__struct__), do: {:error, :invalid_document}, else: :ok
  end

  defp ensure_unsigned(%{"proof" => _}), do: {:error, :proof_already_present}
  defp ensure_unsigned(_document), do: :ok

  defp validate_private_key(private_key) when byte_size(private_key) == 32, do: :ok
  defp validate_private_key(_private_key), do: {:error, :invalid_private_key}

  defp validate_public_key(public_key) when byte_size(public_key) == 32, do: :ok
  defp validate_public_key(_public_key), do: {:error, :invalid_public_key}

  defp build_proof_options(document, opts) do
    opts = normalize_opts(opts)

    with {:ok, verification_method} <- fetch_required_string(opts, "verificationMethod"),
         {:ok, proof_purpose} <- fetch_required_string(opts, "proofPurpose"),
         {:ok, created} <- normalize_created(Map.get(opts, "created")) do
      proof_options =
        opts
        |> Map.drop(["type", "cryptosuite", "proofValue", "@context"])
        |> Map.put("verificationMethod", verification_method)
        |> Map.put("proofPurpose", proof_purpose)
        |> Map.put("created", created)
        |> maybe_put_context(document)

      proof_configuration(proof_options)
    end
  end

  defp maybe_put_context(opts, %{"@context" => context}), do: Map.put(opts, "@context", context)
  defp maybe_put_context(opts, _document), do: opts

  defp normalize_opts(opts) when is_list(opts) do
    opts
    |> Enum.into(%{}, fn {key, value} -> {normalize_opt_key(key), value} end)
  end

  defp normalize_opts(%{} = opts) do
    Map.new(opts, fn {key, value} -> {normalize_opt_key(key), value} end)
  end

  defp normalize_opts(_opts), do: %{}

  defp normalize_opt_key(key) when is_binary(key), do: key

  defp normalize_opt_key(key) when is_atom(key) do
    case key do
      :verification_method -> "verificationMethod"
      :proof_purpose -> "proofPurpose"
      :verificationMethod -> "verificationMethod"
      :proofPurpose -> "proofPurpose"
      :created -> "created"
      :domain -> "domain"
      :challenge -> "challenge"
      _ -> Atom.to_string(key)
    end
  end

  defp normalize_opt_key(key), do: to_string(key)

  defp fetch_required_string(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, :invalid_proof_options}, else: {:ok, value}

      _ ->
        {:error, :invalid_proof_options}
    end
  end

  defp normalize_created(nil) do
    created = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    {:ok, created}
  end

  defp normalize_created(%DateTime{} = created), do: {:ok, DateTime.to_iso8601(created)}

  defp normalize_created(created) when is_binary(created) do
    case DateTime.from_iso8601(created) do
      {:ok, _datetime, _offset} -> {:ok, created}
      _ -> {:error, :invalid_created}
    end
  end

  defp normalize_created(_created), do: {:error, :invalid_created}

  defp proof_configuration(%{} = proof_options) do
    proof_config =
      proof_options
      |> Map.put("type", @proof_type)
      |> Map.put("cryptosuite", @cryptosuite)

    with :ok <- validate_created(proof_config),
         :ok <- validate_domain(proof_config),
         :ok <- validate_challenge(proof_config),
         :ok <- validate_required_fields(proof_config) do
      {:ok, proof_config}
    end
  end

  defp validate_created(%{"created" => created}) when is_binary(created) do
    case DateTime.from_iso8601(created) do
      {:ok, _datetime, _offset} -> :ok
      _ -> {:error, :invalid_created}
    end
  end

  defp validate_created(%{"created" => _}), do: {:error, :invalid_created}
  defp validate_created(_proof_config), do: :ok

  defp validate_domain(%{"domain" => domain}) when is_binary(domain) do
    if String.trim(domain) == "", do: {:error, :invalid_domain}, else: :ok
  end

  defp validate_domain(%{"domain" => _}), do: {:error, :invalid_domain}
  defp validate_domain(_proof_config), do: :ok

  defp validate_challenge(%{"challenge" => challenge}) when is_binary(challenge) do
    if String.trim(challenge) == "", do: {:error, :invalid_challenge}, else: :ok
  end

  defp validate_challenge(%{"challenge" => _}), do: {:error, :invalid_challenge}
  defp validate_challenge(_proof_config), do: :ok

  defp validate_required_fields(proof_config) do
    with {:ok, _} <- fetch_required_string(proof_config, "verificationMethod"),
         {:ok, _} <- fetch_required_string(proof_config, "proofPurpose") do
      :ok
    else
      {:error, :invalid_proof_options} -> {:error, :invalid_proof_options}
    end
  end

  defp create_proof(document, proof_config, private_key) do
    unsecured_document = Map.delete(document, "proof")

    with {:ok, canonical_proof_config} <- canonicalize(proof_config),
         {:ok, canonical_document} <- canonicalize(unsecured_document) do
      hash_data = hash_proof_data(canonical_proof_config, canonical_document)
      signature = :crypto.sign(:eddsa, :none, hash_data, [private_key, :ed25519])
      proof_value = encode_proof_value(signature)
      {:ok, Map.put(proof_config, "proofValue", proof_value)}
    end
  end

  defp hash_proof_data(canonical_proof_config, canonical_document) do
    proof_hash = :crypto.hash(:sha256, canonical_proof_config)
    doc_hash = :crypto.hash(:sha256, canonical_document)
    proof_hash <> doc_hash
  end

  defp extract_proof(%{"proof" => %{} = proof}), do: {:ok, proof}
  defp extract_proof(%{"proof" => _}), do: {:error, :invalid_proof}
  defp extract_proof(_document), do: {:error, :missing_proof}

  defp proof_options_from_proof(%{"type" => @proof_type, "cryptosuite" => @cryptosuite} = proof) do
    case Map.fetch(proof, "proofValue") do
      {:ok, proof_value} when is_binary(proof_value) ->
        {:ok, Map.delete(proof, "proofValue")}

      _ ->
        {:error, :invalid_proof}
    end
  end

  defp proof_options_from_proof(%{"type" => _type}), do: {:error, :unsupported_cryptosuite}
  defp proof_options_from_proof(_proof), do: {:error, :invalid_proof}

  defp prepare_unsecured_document(document, proof_options) do
    unsecured_document = Map.delete(document, "proof")

    if Map.has_key?(proof_options, "@context") do
      proof_context = proof_options["@context"]

      if context_prefix?(document["@context"], proof_context) do
        {:ok, {Map.put(unsecured_document, "@context", proof_context), proof_options}}
      else
        {:error, :invalid_context}
      end
    else
      {:ok, {unsecured_document, proof_options}}
    end
  end

  defp context_prefix?(secured_context, proof_context) do
    if is_list(secured_context) do
      proof_list = List.wrap(proof_context)
      Enum.take(secured_context, length(proof_list)) == proof_list
    else
      false
    end
  end

  defp decode_proof_value("z" <> encoded) do
    with {:ok, decoded} <- base58btc_decode(encoded),
         64 <- byte_size(decoded) do
      {:ok, decoded}
    else
      _ -> {:error, :invalid_proof_value}
    end
  end

  defp decode_proof_value(_), do: {:error, :invalid_proof_value}

  defp encode_proof_value(signature) when is_binary(signature) do
    "z" <> base58btc_encode(signature)
  end

  defp canonicalize(value) do
    case encode_jcs(value) do
      {:ok, iodata} -> {:ok, IO.iodata_to_binary(iodata)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_jcs(%{} = map) do
    if Map.has_key?(map, :__struct__) do
      {:error, :invalid_json}
    else
      with {:ok, entries} <- normalize_entries(map),
           {:ok, pairs} <- encode_pairs(entries) do
        {:ok, ["{", Enum.intersperse(pairs, ","), "}"]}
      end
    end
  end

  defp encode_jcs(list) when is_list(list) do
    with {:ok, items} <- encode_list_items(list) do
      {:ok, ["[", Enum.intersperse(items, ","), "]"]}
    end
  end

  defp encode_jcs(value) when is_binary(value), do: {:ok, Jason.encode!(value)}
  defp encode_jcs(value) when is_integer(value), do: {:ok, Integer.to_string(value)}

  defp encode_jcs(value) when is_float(value) do
    if value == 0.0 do
      {:ok, "0"}
    else
      {:ok, encode_float(value)}
    end
  end

  defp encode_jcs(true), do: {:ok, "true"}
  defp encode_jcs(false), do: {:ok, "false"}
  defp encode_jcs(nil), do: {:ok, "null"}
  defp encode_jcs(_), do: {:error, :invalid_json}

  defp normalize_entries(map) do
    map
    |> Enum.reduce_while([], fn {key, value}, acc ->
      case normalize_key(key) do
        {:ok, normalized_key} -> {:cont, [{normalized_key, value} | acc]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} ->
        {:error, reason}

      entries ->
        entries
        |> Enum.reverse()
        |> Enum.sort_by(fn {key, _value} -> utf16_code_units(key) end)
        |> then(&{:ok, &1})
    end
  end

  defp normalize_key(key) when is_binary(key), do: {:ok, key}
  defp normalize_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp normalize_key(_key), do: {:error, :invalid_json_key}

  defp encode_pairs(entries) do
    entries
    |> Enum.reduce_while([], fn {key, value}, acc ->
      case encode_jcs(value) do
        {:ok, encoded_value} ->
          {:cont, [[Jason.encode!(key), ":", encoded_value] | acc]}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      pairs -> {:ok, Enum.reverse(pairs)}
    end
  end

  defp encode_list_items(list) do
    list
    |> Enum.reduce_while([], fn item, acc ->
      case encode_jcs(item) do
        {:ok, encoded_item} -> {:cont, [encoded_item | acc]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      items -> {:ok, Enum.reverse(items)}
    end
  end

  defp encode_float(value) do
    raw = :io_lib_format.fwrite_g(value) |> IO.iodata_to_binary() |> String.downcase()

    {sign, raw} =
      if String.starts_with?(raw, "-") do
        {"-", String.trim_leading(raw, "-")}
      else
        {"", raw}
      end

    case String.split(raw, "e", parts: 2) do
      [mantissa, exp_str] ->
        exp = String.to_integer(exp_str)
        mantissa = normalize_decimal(mantissa)

        if exp >= -6 and exp < 21 do
          decimal = mantissa |> expand_scientific(exp) |> normalize_decimal()
          sign <> decimal
        else
          exp_out = if exp >= 0, do: "+" <> Integer.to_string(exp), else: Integer.to_string(exp)
          sign <> mantissa <> "e" <> exp_out
        end

      [decimal] ->
        sign <> normalize_decimal(decimal)
    end
  end

  defp normalize_decimal(decimal) do
    case String.split(decimal, ".", parts: 2) do
      [int] ->
        int

      [int, frac] ->
        frac = String.trim_trailing(frac, "0")
        if frac == "", do: int, else: int <> "." <> frac
    end
  end

  defp expand_scientific(mantissa, exp) do
    {int_part, frac_part} =
      case String.split(mantissa, ".", parts: 2) do
        [int] -> {int, ""}
        [int, frac] -> {int, frac}
      end

    digits = int_part <> frac_part
    frac_len = byte_size(frac_part)
    shift = exp - frac_len

    cond do
      shift >= 0 ->
        digits <> String.duplicate("0", shift)

      true ->
        pos = byte_size(digits) + shift

        if pos > 0 do
          left = String.slice(digits, 0, pos)
          right = String.slice(digits, pos, byte_size(digits) - pos)
          left <> "." <> right
        else
          "0." <> String.duplicate("0", -pos) <> digits
        end
    end
  end

  defp utf16_code_units(string) when is_binary(string) do
    :unicode.characters_to_binary(string, :utf8, :utf16)
    |> then(fn bin -> for <<unit::16 <- bin>>, do: unit end)
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
      decoded = if value == 0, do: <<>>, else: :binary.encode_unsigned(value)
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
      case Map.fetch(@base58_map, char |> String.to_charlist() |> List.first()) do
        {:ok, value} -> {:cont, {:ok, acc * 58 + value}}
        :error -> {:halt, {:error, :invalid_base58}}
      end
    end)
  end

  defp div_rem(value, divisor), do: {div(value, divisor), rem(value, divisor)}
end
