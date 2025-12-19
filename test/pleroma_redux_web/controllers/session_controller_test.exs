defmodule PleromaReduxWeb.SessionControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users

  test "GET /login renders form", %{conn: conn} do
    conn = get(conn, "/login")
    assert html_response(conn, 200) =~ "Login"
  end

  test "POST /login sets session for valid credentials", %{conn: conn} do
    {:ok, user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "alice@example.com",
          password: "very secure password"
        }
      ])

    conn =
      post(conn, "/login", %{
        "session" => %{"email" => "alice@example.com", "password" => "very secure password"}
      })

    assert redirected_to(conn) == "/"
    assert get_session(conn, :user_id) == user.id
  end

  test "POST /login rejects invalid credentials", %{conn: conn} do
    {:ok, _user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "alice@example.com",
          password: "very secure password"
        }
      ])

    conn =
      post(conn, "/login", %{
        "session" => %{"email" => "alice@example.com", "password" => "wrong password"}
      })

    assert html_response(conn, 401) =~ "Invalid email or password"
    assert get_session(conn, :user_id) == nil
  end

  test "GET /logout clears the session", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: 123})
      |> get("/logout")

    assert redirected_to(conn) == "/"
    assert get_session(conn, :user_id) == nil
  end
end

