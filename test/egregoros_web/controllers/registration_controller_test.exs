defmodule EgregorosWeb.RegistrationControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Users

  test "GET /register renders form", %{conn: conn} do
    conn = get(conn, "/register")
    html = html_response(conn, 200)
    assert html =~ "Register"
    assert html =~ ~s(data-role="app-shell")
    assert html =~ ~s(data-role="nav-register")
    assert html =~ ~s(data-role="passkey-register-button")
  end

  test "POST /register creates user and sets session", %{conn: conn} do
    conn =
      post(conn, "/register", %{
        "registration" => %{
          "nickname" => "alice",
          "email" => "",
          "password" => "very secure password"
        }
      })

    assert redirected_to(conn) == "/"
    assert is_integer(get_session(conn, :user_id))

    assert user = Users.get_by_nickname("alice")
    assert user.email == nil
    assert is_binary(user.password_hash)
  end

  test "POST /register respects return_to", %{conn: conn} do
    conn =
      post(conn, "/register", %{
        "registration" => %{
          "nickname" => "alice",
          "email" => "",
          "password" => "very secure password",
          "return_to" => "/settings"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert is_integer(get_session(conn, :user_id))
  end
end
