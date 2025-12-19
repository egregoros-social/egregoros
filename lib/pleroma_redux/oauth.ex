defmodule PleromaRedux.OAuth do
  import Ecto.Query, only: [from: 2]

  alias PleromaRedux.OAuth.Application, as: OAuthApplication
  alias PleromaRedux.OAuth.AuthorizationCode
  alias PleromaRedux.OAuth.Token
  alias PleromaRedux.Repo
  alias PleromaRedux.User

  @default_code_ttl_seconds 600

  def create_application(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    application_attrs = %{
      name: Map.get(attrs, "client_name") || Map.get(attrs, :client_name) || "App",
      website: Map.get(attrs, "website") || Map.get(attrs, :website),
      redirect_uris: parse_redirect_uris(Map.get(attrs, "redirect_uris") || Map.get(attrs, :redirect_uris)),
      scopes: Map.get(attrs, "scopes") || Map.get(attrs, :scopes) || "",
      client_id: generate_token(32),
      client_secret: generate_token(48),
      inserted_at: now,
      updated_at: now
    }

    %OAuthApplication{}
    |> OAuthApplication.changeset(application_attrs)
    |> Repo.insert()
  end

  def get_application_by_client_id(nil), do: nil

  def get_application_by_client_id(client_id) when is_binary(client_id) do
    Repo.get_by(OAuthApplication, client_id: client_id)
  end

  def redirect_uri_allowed?(%OAuthApplication{redirect_uris: redirect_uris}, redirect_uri)
      when is_binary(redirect_uri) and is_list(redirect_uris) do
    redirect_uri in redirect_uris
  end

  def redirect_uri_allowed?(_app, _redirect_uri), do: false

  def create_authorization_code(
        %OAuthApplication{} = application,
        %User{} = user,
        redirect_uri,
        scopes
      )
      when is_binary(redirect_uri) and is_binary(scopes) do
    if redirect_uri_allowed?(application, redirect_uri) do
      ttl_seconds =
        Elixir.Application.get_env(
          :pleroma_redux,
          :oauth_code_ttl_seconds,
          @default_code_ttl_seconds
        )

      expires_at = DateTime.add(DateTime.utc_now(), ttl_seconds, :second)

      %AuthorizationCode{}
      |> AuthorizationCode.changeset(%{
        code: generate_token(32),
        redirect_uri: redirect_uri,
        scopes: scopes,
        expires_at: expires_at,
        user_id: user.id,
        application_id: application.id
      })
      |> Repo.insert()
    else
      {:error, :invalid_redirect_uri}
    end
  end

  def get_authorization_code(nil), do: nil

  def get_authorization_code(code) when is_binary(code) do
    Repo.get_by(AuthorizationCode, code: code)
  end

  def exchange_code_for_token(%{
        "grant_type" => "authorization_code",
        "code" => code,
        "client_id" => client_id,
        "client_secret" => client_secret,
        "redirect_uri" => redirect_uri
      })
      when is_binary(code) and is_binary(client_id) and is_binary(client_secret) and
             is_binary(redirect_uri) do
    with %OAuthApplication{} = application <- get_application_by_client_id(client_id),
         true <- Plug.Crypto.secure_compare(application.client_secret, client_secret),
         %AuthorizationCode{} = auth_code <- get_authorization_code(code),
         true <- auth_code.application_id == application.id,
         true <- auth_code.redirect_uri == redirect_uri,
         true <- DateTime.compare(auth_code.expires_at, DateTime.utc_now()) == :gt,
         {:ok, %Token{} = token} <- create_token(application, auth_code) do
      _ = Repo.delete(auth_code)
      {:ok, token}
    else
      nil -> {:error, :invalid_client}
      false -> {:error, :invalid_grant}
      {:error, _} = error -> error
      _ -> {:error, :invalid_grant}
    end
  end

  def exchange_code_for_token(_params), do: {:error, :unsupported_grant_type}

  def get_user_by_token(nil), do: nil

  def get_user_by_token(token) when is_binary(token) do
    from(t in Token,
      where: t.token == ^token and is_nil(t.revoked_at),
      join: u in assoc(t, :user),
      preload: [user: u]
    )
    |> Repo.one()
    |> case do
      %Token{user: %User{} = user} -> user
      _ -> nil
    end
  end

  defp create_token(%OAuthApplication{} = application, %AuthorizationCode{} = auth_code) do
    %Token{}
    |> Token.changeset(%{
      token: generate_token(48),
      scopes: auth_code.scopes,
      user_id: auth_code.user_id,
      application_id: application.id
    })
    |> Repo.insert()
  end

  defp parse_redirect_uris(nil), do: []

  defp parse_redirect_uris(value) when is_binary(value) do
    value
    |> String.split(~r/[\s\n]+/, trim: true)
    |> Enum.uniq()
  end

  defp parse_redirect_uris(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_redirect_uris(_), do: []

  defp generate_token(bytes) when is_integer(bytes) and bytes > 0 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
