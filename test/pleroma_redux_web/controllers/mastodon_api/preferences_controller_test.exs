defmodule PleromaReduxWeb.MastodonAPI.PreferencesControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Users

  test "GET /api/v1/preferences returns a map", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/preferences")
    response = json_response(conn, 200)

    assert is_map(response)
  end
end
