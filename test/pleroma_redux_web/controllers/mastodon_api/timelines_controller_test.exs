defmodule PleromaReduxWeb.MastodonAPI.TimelinesControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Publish
  alias PleromaRedux.Users

  test "GET /api/v1/timelines/public returns latest statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "First post")
    {:ok, _} = Publish.post_note(user, "Second post")

    conn = get(conn, "/api/v1/timelines/public")

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "Second post"
    assert Enum.at(response, 1)["content"] == "First post"
  end

  test "GET /api/v1/timelines/public paginates with max_id and Link header", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "First post")
    {:ok, _} = Publish.post_note(user, "Second post")
    {:ok, _} = Publish.post_note(user, "Third post")

    conn = get(conn, "/api/v1/timelines/public", %{"limit" => "2"})

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "Third post"
    assert Enum.at(response, 1)["content"] == "Second post"

    [link] = get_resp_header(conn, "link")
    assert String.contains?(link, "rel=\"next\"")
    assert String.contains?(link, "max_id=#{Enum.at(response, 1)["id"]}")
    assert String.contains?(link, "rel=\"prev\"")
    assert String.contains?(link, "since_id=#{Enum.at(response, 0)["id"]}")

    conn =
      get(conn, "/api/v1/timelines/public", %{
        "limit" => "2",
        "max_id" => Enum.at(response, 1)["id"]
      })

    response = json_response(conn, 200)
    assert length(response) == 1
    assert Enum.at(response, 0)["content"] == "First post"
  end

  test "GET /api/v1/timelines/home returns latest statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, _} = Publish.post_note(user, "First home post")
    {:ok, _} = Publish.post_note(user, "Second home post")

    conn = get(conn, "/api/v1/timelines/home")

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "Second home post"
    assert Enum.at(response, 1)["content"] == "First home post"
  end

  test "GET /api/v1/timelines/home paginates with max_id and Link header", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, 2, fn _conn -> {:ok, user} end)

    {:ok, _} = Publish.post_note(user, "First home post")
    {:ok, _} = Publish.post_note(user, "Second home post")
    {:ok, _} = Publish.post_note(user, "Third home post")

    conn = get(conn, "/api/v1/timelines/home", %{"limit" => "2"})
    response = json_response(conn, 200)

    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "Third home post"
    assert Enum.at(response, 1)["content"] == "Second home post"

    [link] = get_resp_header(conn, "link")
    assert String.contains?(link, "rel=\"next\"")
    assert String.contains?(link, "max_id=#{Enum.at(response, 1)["id"]}")
    assert String.contains?(link, "rel=\"prev\"")
    assert String.contains?(link, "since_id=#{Enum.at(response, 0)["id"]}")

    conn =
      get(conn, "/api/v1/timelines/home", %{
        "limit" => "2",
        "max_id" => Enum.at(response, 1)["id"]
      })

    response = json_response(conn, 200)
    assert length(response) == 1
    assert Enum.at(response, 0)["content"] == "First home post"
  end
end
