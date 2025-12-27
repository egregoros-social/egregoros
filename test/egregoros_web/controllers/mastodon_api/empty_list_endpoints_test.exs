defmodule EgregorosWeb.MastodonAPI.EmptyListEndpointsTest do
  use EgregorosWeb.ConnCase, async: true

  import Mox

  alias Egregoros.Users

  test "empty list endpoints return []", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    paths = [
      "/api/v1/filters",
      "/api/v1/lists",
      "/api/v1/bookmarks",
      "/api/v1/favourites",
      "/api/v1/blocks",
      "/api/v1/mutes",
      "/api/v1/follow_requests",
      "/api/v1/followed_tags"
    ]

    Egregoros.Auth.Mock
    |> expect(:current_user, length(paths), fn _conn -> {:ok, user} end)

    Enum.each(paths, fn path ->
      assert conn |> get(path) |> json_response(200) == []
    end)
  end

  test "directory returns [] without auth", %{conn: conn} do
    assert conn |> get("/api/v1/directory") |> json_response(200) == []
  end
end
