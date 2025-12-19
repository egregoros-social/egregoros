defmodule PleromaRedux.Password do
  @algorithm "pbkdf2_sha256"
  @digest :sha256
  @key_length 32
  @salt_length 16

  def hash(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(@salt_length)
    iterations = iterations()
    derived = :crypto.pbkdf2_hmac(@digest, password, salt, iterations, @key_length)

    "#{@algorithm}$#{iterations}$#{Base.encode64(salt)}$#{Base.encode64(derived)}"
  end

  def verify(password, encoded) when is_binary(password) and is_binary(encoded) do
    with {:ok, iterations, salt, expected} <- decode_hash(encoded),
         derived <- :crypto.pbkdf2_hmac(@digest, password, salt, iterations, byte_size(expected)) do
      Plug.Crypto.secure_compare(derived, expected)
    else
      _ -> false
    end
  end

  defp decode_hash(encoded) when is_binary(encoded) do
    case String.split(encoded, "$") do
      [@algorithm, iterations, salt, hash] ->
        with {iterations, ""} <- Integer.parse(iterations),
             {:ok, salt} <- Base.decode64(salt),
             {:ok, hash} <- Base.decode64(hash) do
          {:ok, iterations, salt, hash}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp iterations do
    Application.get_env(:pleroma_redux, :password_iterations, 200_000)
  end
end

