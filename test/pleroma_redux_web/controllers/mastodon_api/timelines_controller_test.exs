defmodule PleromaReduxWeb.MastodonAPI.TimelinesControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Timeline

  test "GET /api/v1/timelines/public returns latest statuses", %{conn: conn} do
    {:ok, _} = Timeline.create_post("First post")
    {:ok, _} = Timeline.create_post("Second post")

    conn = get(conn, "/api/v1/timelines/public")

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "Second post"
    assert Enum.at(response, 1)["content"] == "First post"
  end
end
