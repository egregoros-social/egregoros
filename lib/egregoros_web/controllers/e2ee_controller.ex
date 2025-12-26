defmodule EgregorosWeb.E2EEController do
  use EgregorosWeb, :controller

  alias Egregoros.E2EE
  alias Egregoros.User

  def show(conn, _params) do
    case conn.assigns.current_user do
      %User{} = user ->
        render_status(conn, user)

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "unauthorized"})
    end
  end

  def enable_passkey(conn, %{
        "kid" => kid,
        "public_key_jwk" => %{} = public_key_jwk,
        "wrapper" => %{
          "type" => type,
          "wrapped_private_key" => wrapped_private_key_b64,
          "params" => %{} = params
        }
      }) do
    with %User{} = user <- conn.assigns.current_user,
         {:ok, wrapped_private_key} <- decode_b64url(wrapped_private_key_b64),
         {:ok, %{key: key}} <-
           E2EE.enable_key_with_wrapper(user, %{
             kid: kid,
             public_key_jwk: public_key_jwk,
             wrapper: %{
               type: type,
               wrapped_private_key: wrapped_private_key,
               params: params
             }
           }) do
      conn
      |> put_status(:created)
      |> json(%{"kid" => key.kid, "fingerprint" => key.fingerprint})
    else
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{"error" => "unauthorized"})

      {:error, :already_enabled} ->
        conn
        |> put_status(:conflict)
        |> json(%{"error" => "already_enabled"})

      {:error, :invalid_key} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "invalid_payload"})

      {:error, :invalid_base64} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "invalid_payload"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{"error" => "invalid_payload", "details" => errors_on(changeset)})
    end
  end

  def enable_passkey(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{"error" => "invalid_payload"})
  end

  defp render_status(conn, %User{} = user) do
    case E2EE.get_active_key(user) do
      nil ->
        json(conn, %{"enabled" => false, "active_key" => nil, "wrappers" => []})

      key ->
        wrappers =
          user
          |> E2EE.list_wrappers(key.kid)
          |> Enum.map(fn wrapper ->
            %{
              "type" => wrapper.type,
              "wrapped_private_key" =>
                Base.url_encode64(wrapper.wrapped_private_key, padding: false),
              "params" => wrapper.params
            }
          end)

        json(conn, %{
          "enabled" => true,
          "active_key" => %{
            "kid" => key.kid,
            "fingerprint" => key.fingerprint,
            "public_key_jwk" => key.public_key_jwk,
            "created_at" => DateTime.to_iso8601(key.inserted_at)
          },
          "wrappers" => wrappers
        })
    end
  end

  defp decode_b64url(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode_b64url(_), do: {:error, :invalid_base64}

  defp errors_on(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
