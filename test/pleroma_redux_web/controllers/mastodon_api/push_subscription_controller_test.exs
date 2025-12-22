defmodule PleromaReduxWeb.MastodonAPI.PushSubscriptionControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Mox

  alias PleromaRedux.Users

  test "GET /api/v1/push/subscription returns 404 when push is unsupported", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/push/subscription")
    body = json_response(conn, 404)

    assert body["error"] == "push subscriptions are not supported"
  end
end

