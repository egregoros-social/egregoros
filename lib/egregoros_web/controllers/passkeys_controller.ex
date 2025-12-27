defmodule EgregorosWeb.PasskeysController do
  use EgregorosWeb, :controller

  alias Egregoros.Passkeys
  alias Egregoros.Passkeys.Credential
  alias Egregoros.Passkeys.WebAuthn
  alias Egregoros.Repo
  alias Egregoros.User
  alias Egregoros.Users

  def registration_options(conn, params) do
    nickname = params |> Map.get("nickname", "") |> to_string() |> String.trim()
    return_to = params |> Map.get("return_to", "") |> to_string()

    email =
      params
      |> Map.get("email", "")
      |> to_string()
      |> String.trim()
      |> case do
        "" -> nil
        value -> value
      end

    cond do
      nickname == "" ->
        send_resp(conn, 422, "Unprocessable Entity")

      Users.get_by_nickname(nickname) ->
        conn
        |> put_status(:conflict)
        |> json(%{"error" => "nickname_taken"})

      is_binary(email) and Users.get_by_email(email) ->
        conn
        |> put_status(:conflict)
        |> json(%{"error" => "email_taken"})

      true ->
        challenge = :crypto.strong_rand_bytes(32)
        user_handle = :crypto.strong_rand_bytes(32)
        options = WebAuthn.registration_options(nickname, challenge, user_handle)

        conn
        |> put_session(:passkey_reg_challenge, options["challenge"])
        |> put_session(:passkey_reg_nickname, nickname)
        |> put_session(:passkey_reg_email, email)
        |> put_session(:passkey_reg_return_to, return_to)
        |> json(%{"publicKey" => options})
    end
  end

  def registration_finish(conn, %{"credential" => %{} = credential}) do
    challenge = get_session(conn, :passkey_reg_challenge)
    nickname = get_session(conn, :passkey_reg_nickname)
    email = get_session(conn, :passkey_reg_email)
    return_to = get_session(conn, :passkey_reg_return_to)

    with true <- is_binary(challenge) and challenge != "",
         true <- is_binary(nickname) and nickname != "",
         {:ok, %{credential_id: credential_id, public_key: public_key, sign_count: sign_count}} <-
           WebAuthn.verify_attestation(credential, challenge),
         {:ok, %User{} = user} <-
           register_user_with_credential(%{
             nickname: nickname,
             email: email,
             credential_id: credential_id,
             public_key: public_key,
             sign_count: sign_count
           }) do
      redirect_to = safe_return_to(return_to) || "/"

      conn
      |> clear_passkey_registration_session()
      |> put_session(:user_id, user.id)
      |> put_status(:created)
      |> json(%{"redirect_to" => redirect_to})
    else
      _ ->
        conn
        |> clear_passkey_registration_session()
        |> send_resp(422, "Unprocessable Entity")
    end
  end

  def registration_finish(conn, _params), do: send_resp(conn, 422, "Unprocessable Entity")

  def authentication_options(conn, params) do
    nickname = params |> Map.get("nickname", "") |> to_string() |> String.trim()
    return_to = params |> Map.get("return_to", "") |> to_string()

    with %User{} = user <- Users.get_by_nickname(nickname),
         credentials when is_list(credentials) and credentials != [] <- Passkeys.list_credentials(user) do
      challenge = :crypto.strong_rand_bytes(32)
      options = WebAuthn.authentication_options(credentials, challenge)

      conn
      |> put_session(:passkey_auth_challenge, options["challenge"])
      |> put_session(:passkey_auth_user_id, user.id)
      |> put_session(:passkey_auth_return_to, return_to)
      |> json(%{"publicKey" => options})
    else
      _ ->
        send_resp(conn, 404, "Not Found")
    end
  end

  def authentication_finish(conn, %{"credential" => %{} = credential}) do
    challenge = get_session(conn, :passkey_auth_challenge)
    user_id = get_session(conn, :passkey_auth_user_id)
    return_to = get_session(conn, :passkey_auth_return_to)

    with true <- is_binary(challenge) and challenge != "",
         %User{} = user <- Users.get(user_id),
         {:ok, raw_id} <- decode_raw_id(credential),
         %Credential{} = stored <- Passkeys.get_credential(user, raw_id),
         {:ok, %{sign_count: sign_count}} <-
           WebAuthn.verify_assertion(credential, challenge, stored.public_key,
             require_user_verification?: true
           ),
         {:ok, _updated} <-
           Passkeys.update_credential(stored, %{
             sign_count: merged_sign_count(stored.sign_count, sign_count),
             last_used_at: DateTime.utc_now()
           }) do
      redirect_to = safe_return_to(return_to) || "/"

      conn
      |> clear_passkey_authentication_session()
      |> put_session(:user_id, user.id)
      |> json(%{"redirect_to" => redirect_to})
    else
      _ ->
        conn
        |> clear_passkey_authentication_session()
        |> send_resp(401, "Unauthorized")
    end
  end

  def authentication_finish(conn, _params), do: send_resp(conn, 401, "Unauthorized")

  defp decode_raw_id(%{} = credential) do
    case Map.get(credential, "rawId") do
      value when is_binary(value) ->
        case Base.url_decode64(value, padding: false) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, :invalid_payload}
        end

      _ ->
        {:error, :invalid_payload}
    end
  end

  defp merged_sign_count(stored, incoming)
       when is_integer(stored) and stored >= 0 and is_integer(incoming) and incoming >= 0 do
    cond do
      incoming == 0 -> stored
      stored == 0 -> incoming
      incoming > stored -> incoming
      true -> stored
    end
  end

  defp merged_sign_count(stored, _incoming) when is_integer(stored), do: stored
  defp merged_sign_count(_stored, _incoming), do: 0

  defp clear_passkey_registration_session(conn) do
    conn
    |> delete_session(:passkey_reg_challenge)
    |> delete_session(:passkey_reg_nickname)
    |> delete_session(:passkey_reg_email)
    |> delete_session(:passkey_reg_return_to)
  end

  defp clear_passkey_authentication_session(conn) do
    conn
    |> delete_session(:passkey_auth_challenge)
    |> delete_session(:passkey_auth_user_id)
    |> delete_session(:passkey_auth_return_to)
  end

  defp register_user_with_credential(%{} = attrs) do
    Repo.transaction(fn ->
      with {:ok, %User{} = user} <-
             Users.register_local_user_with_passkey(%{
               nickname: Map.get(attrs, :nickname),
               email: Map.get(attrs, :email)
             }),
           {:ok, %Credential{}} <-
             Passkeys.create_credential(user, %{
               credential_id: Map.get(attrs, :credential_id),
               public_key: Map.get(attrs, :public_key),
               sign_count: Map.get(attrs, :sign_count)
             }) do
        user
      else
        {:error, reason} -> Repo.rollback(reason)
        _ -> Repo.rollback(:invalid)
      end
    end)
    |> case do
      {:ok, %User{} = user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_return_to(return_to) when is_binary(return_to) do
    return_to = String.trim(return_to)

    cond do
      return_to == "" ->
        nil

      String.starts_with?(return_to, "/") and not String.starts_with?(return_to, "//") ->
        return_to

      true ->
        nil
    end
  end

  defp safe_return_to(_return_to), do: nil
end
