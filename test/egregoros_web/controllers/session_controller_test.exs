defmodule EgregorosWeb.SessionControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Users

  test "GET /login renders form", %{conn: conn} do
    conn = get(conn, "/login")
    html = html_response(conn, 200)
    assert html =~ "Login"
    assert html =~ ~s(data-role="app-shell")
    assert html =~ ~s(data-role="nav-login")
    assert html =~ ~s(data-role="passkey-login-button")
  end

  test "POST /login sets session for valid credentials", %{conn: conn} do
    {:ok, user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "",
          password: "very secure password"
        }
      ])

    conn =
      post(conn, "/login", %{
        "session" => %{"nickname" => "alice", "password" => "very secure password"}
      })

    assert redirected_to(conn) == "/"
    assert get_session(conn, :user_id) == user.id
  end

  test "POST /login respects return_to for valid credentials", %{conn: conn} do
    {:ok, user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "",
          password: "very secure password"
        }
      ])

    conn =
      post(conn, "/login", %{
        "session" => %{
          "nickname" => "alice",
          "password" => "very secure password",
          "return_to" => "/settings"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert get_session(conn, :user_id) == user.id
  end

  test "POST /login rejects invalid credentials", %{conn: conn} do
    {:ok, _user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "",
          password: "very secure password"
        }
      ])

    conn =
      post(conn, "/login", %{
        "session" => %{"nickname" => "alice", "password" => "wrong password"}
      })

    assert html_response(conn, 401) =~ "Invalid nickname or password"
    assert get_session(conn, :user_id) == nil
  end

  test "POST /logout clears the session", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: 123})
      |> get("/")

    csrf_token = Phoenix.Controller.get_csrf_token()

    conn =
      conn
      |> recycle()
      |> post("/logout", %{"_csrf_token" => csrf_token})

    assert redirected_to(conn) == "/"
    assert get_session(conn, :user_id) == nil
  end
end
