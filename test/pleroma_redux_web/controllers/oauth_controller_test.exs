defmodule PleromaReduxWeb.OAuthControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.OAuth
  alias PleromaRedux.Users

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

    assert html_response(conn, 200) =~ "Authorize"
    assert html_response(conn, 200) =~ "Husky"
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
