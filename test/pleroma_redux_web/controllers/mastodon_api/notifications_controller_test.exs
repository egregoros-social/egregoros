defmodule PleromaReduxWeb.MastodonAPI.NotificationsControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users

  test "GET /api/v1/notifications returns a list", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/notifications")
    response = json_response(conn, 200)

    assert is_list(response)
  end
end
