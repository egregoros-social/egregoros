defmodule PleromaReduxWeb.MastodonAPI.AccountsControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users

  test "GET /api/v1/accounts/verify_credentials returns current user", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/accounts/verify_credentials")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "local"
  end

  test "GET /api/v1/accounts/:id returns account", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    conn = get(conn, "/api/v1/accounts/#{user.id}")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "alice"
  end
end
