defmodule PleromaReduxWeb.MastodonAPI.TimelinesControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Timeline
  alias PleromaRedux.Users

  test "GET /api/v1/timelines/public returns latest statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Timeline.create_post(user, "First post")
    {:ok, _} = Timeline.create_post(user, "Second post")

    conn = get(conn, "/api/v1/timelines/public")

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "Second post"
    assert Enum.at(response, 1)["content"] == "First post"
  end

  test "GET /api/v1/timelines/home returns latest statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, _} = Timeline.create_post(user, "First home post")
    {:ok, _} = Timeline.create_post(user, "Second home post")

    conn = get(conn, "/api/v1/timelines/home")

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "Second home post"
    assert Enum.at(response, 1)["content"] == "First home post"
  end
end
