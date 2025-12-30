defmodule EgregorosWeb.MastodonAPI.TrendsControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Publish
  alias Egregoros.Users

  test "GET /api/v1/trends returns a list", %{conn: conn} do
    conn = get(conn, "/api/v1/trends")
    response = json_response(conn, 200)

    assert is_list(response)
  end

  test "GET /api/v1/trends/tags returns trending tags", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    assert {:ok, _} = Publish.post_note(user, "Hello #linux #Linux")

    conn = get(conn, "/api/v1/trends/tags")
    response = json_response(conn, 200)

    assert is_list(response)
    assert Enum.any?(response, &(&1["name"] == "linux"))
  end

  test "GET /api/v1/trends/statuses returns a list", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    assert {:ok, _} = Publish.post_note(user, "Hello trends")

    conn = get(conn, "/api/v1/trends/statuses")
    response = json_response(conn, 200)

    assert is_list(response)
    assert Enum.any?(response, &(&1["content"] == "<p>Hello trends</p>"))
  end

  test "GET /api/v1/trends/links returns a list", %{conn: conn} do
    conn = get(conn, "/api/v1/trends/links")
    response = json_response(conn, 200)

    assert is_list(response)
  end
end
