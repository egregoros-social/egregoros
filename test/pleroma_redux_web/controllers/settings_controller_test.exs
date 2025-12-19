defmodule PleromaReduxWeb.SettingsControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users

  test "GET /settings redirects when not logged in", %{conn: conn} do
    conn = get(conn, "/settings")
    assert redirected_to(conn) == "/login"
  end

  test "GET /settings renders settings for logged-in user", %{conn: conn} do
    {:ok, user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "alice@example.com",
          password: "very secure password"
        }
      ])

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> get("/settings")

    assert html_response(conn, 200) =~ "Settings"
    assert html_response(conn, 200) =~ "alice@example.com"
  end

  test "POST /settings/profile updates name, bio, and avatar upload", %{conn: conn} do
    {:ok, user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "alice@example.com",
          password: "very secure password"
        }
      ])

    fixture_path = Path.expand("pleroma-old/test/fixtures/DSCN0010.png", File.cwd!())

    upload = %Plug.Upload{
      path: fixture_path,
      filename: "avatar.png",
      content_type: "image/png"
    }

    expect(PleromaRedux.AvatarStorage.Mock, :store_avatar, fn passed_user, passed_upload ->
      assert passed_user.id == user.id
      assert passed_upload.filename == "avatar.png"
      assert passed_upload.content_type == "image/png"

      {:ok, "/uploads/avatars/#{passed_user.id}/avatar.png"}
    end)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> post("/settings/profile", %{
        "profile" => %{
          "name" => "Alice Example",
          "bio" => "Hello from Redux",
          "avatar" => upload
        }
      })

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Profile updated."

    updated = Users.get(user.id)
    assert updated.name == "Alice Example"
    assert updated.bio == "Hello from Redux"
    assert updated.avatar_url == "/uploads/avatars/#{user.id}/avatar.png"
  end

  test "POST /settings/account updates email and allows logging in with the new email", %{
    conn: conn
  } do
    {:ok, user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "alice@example.com",
          password: "very secure password"
        }
      ])

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> post("/settings/account", %{"account" => %{"email" => "alice2@example.com"}})

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Email updated."

    updated = Users.get(user.id)
    assert updated.email == "alice2@example.com"

    conn =
      Phoenix.ConnTest.build_conn()
      |> post("/login", %{
        "session" => %{"email" => "alice2@example.com", "password" => "very secure password"}
      })

    assert redirected_to(conn) == "/"
    assert is_integer(get_session(conn, :user_id))
  end

  test "POST /settings/password updates the password and allows logging in again", %{conn: conn} do
    {:ok, user} =
      apply(Users, :register_local_user, [
        %{
          nickname: "alice",
          email: "alice@example.com",
          password: "very secure password"
        }
      ])

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> post("/settings/password", %{
        "password" => %{
          "current_password" => "very secure password",
          "password" => "even more secure password",
          "password_confirmation" => "even more secure password"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Password updated."

    conn =
      Phoenix.ConnTest.build_conn()
      |> post("/login", %{
        "session" => %{"email" => "alice@example.com", "password" => "even more secure password"}
      })

    assert redirected_to(conn) == "/"
    assert is_integer(get_session(conn, :user_id))
  end
end
