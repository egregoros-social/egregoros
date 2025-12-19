defmodule PleromaReduxWeb.MastodonAPI.CustomEmojisControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  test "GET /api/v1/custom_emojis returns a list", %{conn: conn} do
    conn = get(conn, "/api/v1/custom_emojis")
    response = json_response(conn, 200)

    assert is_list(response)
  end
end
