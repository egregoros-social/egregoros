defmodule EgregorosWeb.OAuthControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.OAuth
  alias Egregoros.Users

  test "POST /oauth/token exchanges a code for a bearer token", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, app} =
      OAuth.create_application(%{
        "client_name" => "Husky",
        "redirect_uris" => "urn:ietf:wg:oauth:2.0:oob",
        "scopes" => "read"
      })

    {:ok, auth_code} =
      OAuth.create_authorization_code(app, user, "urn:ietf:wg:oauth:2.0:oob", "read")

    conn =
      post(conn, "/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => auth_code.code,
        "client_id" => app.client_id,
        "client_secret" => app.client_secret,
        "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob"
      })

    response = json_response(conn, 200)
    assert response["token_type"] == "Bearer"
    assert response["scope"] == "read"
    assert is_binary(response["access_token"])
    assert is_binary(response["refresh_token"])
    assert is_integer(response["expires_in"])
  end

  test "POST /oauth/token exchanges a refresh_token for a new bearer token", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, app} =
      OAuth.create_application(%{
        "client_name" => "Husky",
        "redirect_uris" => "urn:ietf:wg:oauth:2.0:oob",
        "scopes" => "read"
      })

    {:ok, auth_code} =
      OAuth.create_authorization_code(app, user, "urn:ietf:wg:oauth:2.0:oob", "read")

    conn =
      post(conn, "/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => auth_code.code,
        "client_id" => app.client_id,
        "client_secret" => app.client_secret,
        "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob"
      })

    first = json_response(conn, 200)
    assert is_binary(first["access_token"])
    assert is_binary(first["refresh_token"])

    conn =
      post(build_conn(), "/oauth/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => first["refresh_token"],
        "client_id" => app.client_id,
        "client_secret" => app.client_secret
      })

    second = json_response(conn, 200)
    assert is_binary(second["access_token"])
    assert second["access_token"] != first["access_token"]
    assert is_binary(second["refresh_token"])
    assert second["refresh_token"] != first["refresh_token"]
  end

  test "POST /oauth/revoke revokes an access token", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, app} =
      OAuth.create_application(%{
        "client_name" => "Husky",
        "redirect_uris" => "urn:ietf:wg:oauth:2.0:oob",
        "scopes" => "read"
      })

    {:ok, auth_code} =
      OAuth.create_authorization_code(app, user, "urn:ietf:wg:oauth:2.0:oob", "read")

    conn =
      post(conn, "/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => auth_code.code,
        "client_id" => app.client_id,
        "client_secret" => app.client_secret,
        "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob"
      })

    token = json_response(conn, 200)["access_token"]
    assert OAuth.get_user_by_token(token)

    conn =
      post(build_conn(), "/oauth/revoke", %{
        "token" => token,
        "client_id" => app.client_id,
        "client_secret" => app.client_secret
      })

    assert response(conn, 200)
    refute OAuth.get_user_by_token(token)
  end

  test "GET /oauth/authorize redirects to login when not signed in", %{conn: conn} do
    {:ok, app} =
      OAuth.create_application(%{
        "client_name" => "Husky",
        "redirect_uris" => "urn:ietf:wg:oauth:2.0:oob",
        "scopes" => "read"
      })

    conn =
      get(conn, "/oauth/authorize", %{
        "client_id" => app.client_id,
        "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob",
        "response_type" => "code",
        "scope" => "read"
      })

    assert redirected_to(conn) =~ "/login"
  end

  test "GET /oauth/authorize renders consent when signed in", %{conn: conn} do
    {:ok, user} =
      Users.register_local_user(%{
        nickname: "alice",
        email: "alice@example.com",
        password: "very secure password"
      })

    {:ok, app} =
      OAuth.create_application(%{
        "client_name" => "Husky",
        "redirect_uris" => "urn:ietf:wg:oauth:2.0:oob",
        "scopes" => "read"
      })

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> get("/oauth/authorize", %{
        "client_id" => app.client_id,
        "redirect_uri" => "urn:ietf:wg:oauth:2.0:oob",
        "response_type" => "code",
        "scope" => "read"
      })

    html = html_response(conn, 200)
    assert html =~ "Authorize"
    assert html =~ "Husky"
    assert html =~ ~s(data-role="app-shell")
    assert html =~ ~s(data-role="nav-settings")
  end

  test "POST /oauth/authorize approves and redirects with code", %{conn: conn} do
    {:ok, user} =
      Users.register_local_user(%{
        nickname: "alice",
        email: "alice@example.com",
        password: "very secure password"
      })

    {:ok, app} =
      OAuth.create_application(%{
        "client_name" => "Husky",
        "redirect_uris" => "https://client.example/cb",
        "scopes" => "read"
      })

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> post("/oauth/authorize", %{
        "oauth" => %{
          "client_id" => app.client_id,
          "redirect_uri" => "https://client.example/cb",
          "response_type" => "code",
          "scope" => "read"
        }
      })

    location = redirected_to(conn)
    assert String.starts_with?(location, "https://client.example/cb")
    assert location =~ "code="
  end
end
