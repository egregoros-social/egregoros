defmodule Egregoros.OAuth do
  import Ecto.Query, only: [from: 2]

  alias Egregoros.OAuth.Application, as: OAuthApplication
  alias Egregoros.OAuth.AuthorizationCode
  alias Egregoros.OAuth.Scopes
  alias Egregoros.OAuth.Token
  alias Egregoros.Repo
  alias Egregoros.User

  @default_code_ttl_seconds 600
  @default_access_token_ttl_seconds 7_200
  @default_refresh_token_ttl_seconds 31_536_000

  def create_application(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    application_attrs = %{
      name: Map.get(attrs, "client_name") || Map.get(attrs, :client_name) || "App",
      website: Map.get(attrs, "website") || Map.get(attrs, :website),
      redirect_uris:
        parse_redirect_uris(Map.get(attrs, "redirect_uris") || Map.get(attrs, :redirect_uris)),
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
      if Scopes.subset?(scopes, application.scopes) do
        ttl_seconds =
          Elixir.Application.get_env(
            :egregoros,
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
        {:error, :invalid_scope}
      end
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
         {:ok, %Token{} = token} <- create_token(application, auth_code.user_id, auth_code.scopes) do
      _ = Repo.delete(auth_code)
      {:ok, token}
    else
      nil -> {:error, :invalid_client}
      false -> {:error, :invalid_grant}
      {:error, _} = error -> error
      _ -> {:error, :invalid_grant}
    end
  end

  def exchange_code_for_token(
        %{
          "grant_type" => "refresh_token",
          "refresh_token" => refresh_token,
          "client_id" => client_id,
          "client_secret" => client_secret
        } = params
      )
      when is_binary(refresh_token) and is_binary(client_id) and is_binary(client_secret) do
    refresh_token = String.trim(refresh_token)

    with %OAuthApplication{} = application <- get_application_by_client_id(client_id),
         true <- Plug.Crypto.secure_compare(application.client_secret, client_secret),
         %Token{} = old_token <- get_token_by_refresh_token(refresh_token),
         true <- old_token.application_id == application.id,
         true <- refresh_token_active?(old_token),
         {:ok, scopes} <- refresh_scopes(params, old_token, application),
         {:ok, %Token{} = token} <- create_token(application, old_token.user_id, scopes) do
      _ = revoke_token_record(old_token)
      {:ok, token}
    else
      nil -> {:error, :invalid_client}
      false -> {:error, :invalid_grant}
      {:error, _} = error -> error
      _ -> {:error, :invalid_grant}
    end
  end

  def exchange_code_for_token(
        %{
          "grant_type" => "client_credentials",
          "client_id" => client_id,
          "client_secret" => client_secret
        } = params
      )
      when is_binary(client_id) and is_binary(client_secret) do
    client_id = String.trim(client_id)
    client_secret = String.trim(client_secret)

    with %OAuthApplication{} = application <- get_application_by_client_id(client_id),
         true <- Plug.Crypto.secure_compare(application.client_secret, client_secret),
         :ok <- validate_redirect_uri_param(application, params),
         {:ok, scopes} <- client_credentials_scopes(params, application),
         {:ok, %Token{} = token} <- create_token(application, nil, scopes) do
      {:ok, token}
    else
      nil -> {:error, :invalid_client}
      false -> {:error, :invalid_client}
      {:error, _} = error -> error
      _ -> {:error, :invalid_request}
    end
  end

  def exchange_code_for_token(_params), do: {:error, :unsupported_grant_type}

  def get_user_by_token(nil), do: nil

  def get_user_by_token(token) when is_binary(token) do
    case get_token(token) do
      %Token{user: %User{} = user} -> user
      _ -> nil
    end
  end

  def get_token(nil), do: nil

  def get_token(token) when is_binary(token) do
    now = DateTime.utc_now()

    from(t in Token,
      where:
        t.token == ^token and is_nil(t.revoked_at) and
          (is_nil(t.expires_at) or t.expires_at > ^now),
      left_join: u in assoc(t, :user),
      preload: [user: u]
    )
    |> Repo.one()
  end

  def revoke_token(%{
        "token" => token,
        "client_id" => client_id,
        "client_secret" => client_secret
      })
      when is_binary(token) and is_binary(client_id) and is_binary(client_secret) do
    token = String.trim(token)

    with %OAuthApplication{} = application <- get_application_by_client_id(client_id),
         true <- Plug.Crypto.secure_compare(application.client_secret, client_secret) do
      _ = revoke_token_record_for_token(application.id, token)
      :ok
    else
      nil -> {:error, :invalid_client}
      false -> {:error, :invalid_client}
      _ -> {:error, :invalid_client}
    end
  end

  def revoke_token(_params), do: {:error, :invalid_request}

  defp create_token(%OAuthApplication{} = application, user_id, scopes)
       when is_integer(user_id) and user_id > 0 and is_binary(scopes) do
    now = DateTime.utc_now()
    ttl_seconds = access_token_ttl_seconds()
    refresh_ttl_seconds = refresh_token_ttl_seconds()

    expires_at =
      case ttl_seconds do
        seconds when is_integer(seconds) and seconds >= 1 -> DateTime.add(now, seconds, :second)
        _ -> nil
      end

    refresh_expires_at =
      case refresh_ttl_seconds do
        seconds when is_integer(seconds) and seconds >= 1 ->
          DateTime.add(now, seconds, :second)

        _ ->
          nil
      end

    %Token{}
    |> Token.changeset(%{
      token: generate_token(48),
      refresh_token: generate_token(48),
      scopes: scopes,
      user_id: user_id,
      application_id: application.id,
      expires_at: expires_at,
      refresh_expires_at: refresh_expires_at
    })
    |> Repo.insert()
  end

  defp create_token(%OAuthApplication{} = application, nil, scopes) when is_binary(scopes) do
    now = DateTime.utc_now()
    ttl_seconds = access_token_ttl_seconds()
    refresh_ttl_seconds = refresh_token_ttl_seconds()

    expires_at =
      case ttl_seconds do
        seconds when is_integer(seconds) and seconds >= 1 -> DateTime.add(now, seconds, :second)
        _ -> nil
      end

    refresh_expires_at =
      case refresh_ttl_seconds do
        seconds when is_integer(seconds) and seconds >= 1 ->
          DateTime.add(now, seconds, :second)

        _ ->
          nil
      end

    %Token{}
    |> Token.changeset(%{
      token: generate_token(48),
      refresh_token: generate_token(48),
      scopes: scopes,
      user_id: nil,
      application_id: application.id,
      expires_at: expires_at,
      refresh_expires_at: refresh_expires_at
    })
    |> Repo.insert()
  end

  defp get_token_by_refresh_token(refresh_token) when is_binary(refresh_token) do
    now = DateTime.utc_now()

    from(t in Token,
      where:
        t.refresh_token == ^refresh_token and is_nil(t.revoked_at) and
          (is_nil(t.refresh_expires_at) or t.refresh_expires_at > ^now)
    )
    |> Repo.one()
  end

  defp get_token_by_refresh_token(_refresh_token), do: nil

  defp refresh_token_active?(%Token{refresh_expires_at: nil}), do: true

  defp refresh_token_active?(%Token{refresh_expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  defp refresh_token_active?(_), do: false

  defp refresh_scopes(params, %Token{} = old_token, %OAuthApplication{} = application) do
    case Map.get(params, "scope") do
      scope when is_binary(scope) and scope != "" ->
        scope = String.trim(scope)

        cond do
          not Scopes.subset?(scope, old_token.scopes) ->
            {:error, :invalid_scope}

          not Scopes.subset?(scope, application.scopes) ->
            {:error, :invalid_scope}

          true ->
            {:ok, scope}
        end

      _ ->
        {:ok, old_token.scopes}
    end
  end

  defp validate_redirect_uri_param(%OAuthApplication{} = application, params) when is_map(params) do
    case Map.get(params, "redirect_uri") do
      redirect_uri when is_binary(redirect_uri) ->
        redirect_uri = String.trim(redirect_uri)

        if redirect_uri == "" or redirect_uri_allowed?(application, redirect_uri) do
          :ok
        else
          {:error, :invalid_redirect_uri}
        end

      _ ->
        :ok
    end
  end

  defp validate_redirect_uri_param(_application, _params), do: :ok

  defp client_credentials_scopes(params, %OAuthApplication{} = application) when is_map(params) do
    scope =
      case Map.get(params, "scope") do
        value when is_binary(value) -> String.trim(value)
        _ -> ""
      end

    scopes = if scope == "", do: application.scopes, else: scope

    if Scopes.subset?(scopes, application.scopes) do
      {:ok, scopes}
    else
      {:error, :invalid_scope}
    end
  end

  defp revoke_token_record(%Token{} = token) do
    Token.changeset(token, %{revoked_at: DateTime.utc_now()})
    |> Repo.update()
  end

  defp revoke_token_record(_token), do: :ok

  defp revoke_token_record_for_token(application_id, token)
       when is_integer(application_id) and application_id > 0 and is_binary(token) do
    now = DateTime.utc_now()

    from(t in Token,
      where:
        t.application_id == ^application_id and is_nil(t.revoked_at) and
          (t.token == ^token or t.refresh_token == ^token)
    )
    |> Repo.update_all(set: [revoked_at: now])
  end

  defp revoke_token_record_for_token(_application_id, _token), do: :ok

  defp access_token_ttl_seconds do
    Application.get_env(
      :egregoros,
      :oauth_access_token_ttl_seconds,
      @default_access_token_ttl_seconds
    )
  end

  defp refresh_token_ttl_seconds do
    Application.get_env(
      :egregoros,
      :oauth_refresh_token_ttl_seconds,
      @default_refresh_token_ttl_seconds
    )
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
