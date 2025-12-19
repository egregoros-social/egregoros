defmodule PleromaReduxWeb.MastodonAPI.StatusesControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Users

  test "POST /api/v1/statuses creates a status", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/statuses", %{"status" => "Hello API"})

    response = json_response(conn, 200)
    assert response["content"] == "Hello API"
    assert response["account"]["username"] == "local"

    [object] = Objects.list_notes()
    assert object.data["content"] == "Hello API"
  end

  test "POST /api/v1/statuses rejects empty status", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/statuses", %{"status" => "  "})
    assert response(conn, 422)
  end
end
