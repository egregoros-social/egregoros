defmodule PleromaReduxWeb.RegistrationControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users

  test "GET /register renders form", %{conn: conn} do
    conn = get(conn, "/register")
    assert html_response(conn, 200) =~ "Register"
  end

  test "POST /register creates user and sets session", %{conn: conn} do
    conn =
      post(conn, "/register", %{
        "registration" => %{
          "nickname" => "alice",
          "email" => "alice@example.com",
          "password" => "very secure password"
        }
      })

    assert redirected_to(conn) == "/"
    assert is_integer(get_session(conn, :user_id))

    assert user = Users.get_by_nickname("alice")
    assert user.email == "alice@example.com"
    assert is_binary(user.password_hash)
  end

  test "POST /register respects return_to", %{conn: conn} do
    conn =
      post(conn, "/register", %{
        "registration" => %{
          "nickname" => "alice",
          "email" => "alice@example.com",
          "password" => "very secure password",
          "return_to" => "/settings"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert is_integer(get_session(conn, :user_id))
  end
end
