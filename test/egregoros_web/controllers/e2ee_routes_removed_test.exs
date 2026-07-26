defmodule EgregorosWeb.E2EERoutesRemovedTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Users

  setup %{conn: conn} do
    {:ok, user} =
      Users.register_local_user(%{
        nickname: "alice",
        email: "alice@example.com",
        password: "very secure password"
      })

    %{conn: Plug.Test.init_test_session(conn, %{user_id: user.id}), user: user}
  end

  test "GET /settings/e2ee is gone", %{conn: conn} do
    assert %{status: 404} = get(conn, "/settings/e2ee")
  end

  test "POST /settings/e2ee/mnemonic is gone", %{conn: conn} do
    assert %{status: 404} = post(conn, "/settings/e2ee/mnemonic", %{})
  end

  test "POST /settings/e2ee/actor_key is gone", %{conn: conn} do
    assert %{status: 404} = post(conn, "/settings/e2ee/actor_key", %{})
  end

  test "the settings page has no encrypted DM section", %{conn: conn} do
    html = conn |> get("/settings") |> html_response(200)

    refute html =~ "e2ee-settings"
    refute html =~ "e2ee-enable-mnemonic"
    refute html =~ "Encrypted DMs"
  end
end
