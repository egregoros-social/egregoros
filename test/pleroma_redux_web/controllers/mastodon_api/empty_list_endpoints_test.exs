defmodule PleromaReduxWeb.MastodonAPI.EmptyListEndpointsTest do
  use PleromaReduxWeb.ConnCase, async: true

  import Mox

  alias PleromaRedux.Users

  test "empty list endpoints return []", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    paths = [
      "/api/v1/filters",
      "/api/v1/lists",
      "/api/v1/bookmarks",
      "/api/v1/favourites",
      "/api/v1/blocks",
      "/api/v1/mutes",
      "/api/v1/follow_requests"
    ]

    PleromaRedux.Auth.Mock
    |> expect(:current_user, length(paths), fn _conn -> {:ok, user} end)

    Enum.each(paths, fn path ->
      assert conn |> get(path) |> json_response(200) == []
    end)
  end
end

