defmodule PleromaReduxWeb.MastodonAPI.InstanceControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  test "GET /api/v1/instance returns instance information", %{conn: conn} do
    conn = get(conn, "/api/v1/instance")
    response = json_response(conn, 200)

    assert is_binary(response["uri"])
    assert is_binary(response["title"])
    assert is_binary(response["version"])
    assert is_map(response["stats"])
  end
end
