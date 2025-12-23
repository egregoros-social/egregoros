defmodule PleromaReduxWeb.MastodonAPI.TimelinesControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Pipeline
  alias PleromaRedux.Publish
  alias PleromaRedux.Users

  test "GET /api/v1/timelines/public returns latest statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "First post")
    {:ok, _} = Publish.post_note(user, "Second post")

    conn = get(conn, "/api/v1/timelines/public")

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "<p>Second post</p>"
    assert Enum.at(response, 1)["content"] == "<p>First post</p>"
  end

  test "GET /api/v1/timelines/public does not include direct statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    {:ok, _} = Publish.post_note(user, "Hello public")
    {:ok, _} = Publish.post_note(user, "Secret DM", visibility: "direct")

    conn = get(conn, "/api/v1/timelines/public")
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["content"] == "<p>Hello public</p>"))
    refute Enum.any?(response, &(&1["content"] == "<p>Secret DM</p>"))
  end

  test "GET /api/v1/timelines/public includes reblog statuses", %{conn: conn} do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    {:ok, create} = Publish.post_note(alice, "Hello")

    {:ok, _announce} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/announce/1",
          "type" => "Announce",
          "actor" => bob.ap_id,
          "object" => create.object,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => []
        },
        local: true
      )

    conn = get(conn, "/api/v1/timelines/public")

    response = json_response(conn, 200)
    assert length(response) == 2

    assert Enum.at(response, 0)["account"]["username"] == "bob"
    assert Enum.at(response, 0)["content"] == ""
    assert Enum.at(response, 0)["reblog"]["content"] == "<p>Hello</p>"

    assert Enum.at(response, 1)["account"]["username"] == "alice"
    assert Enum.at(response, 1)["content"] == "<p>Hello</p>"
    assert Enum.at(response, 1)["reblog"] == nil
  end

  test "GET /api/v1/timelines/public paginates with max_id and Link header", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "First post")
    {:ok, _} = Publish.post_note(user, "Second post")
    {:ok, _} = Publish.post_note(user, "Third post")

    conn = get(conn, "/api/v1/timelines/public", %{"limit" => "2"})

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "<p>Third post</p>"
    assert Enum.at(response, 1)["content"] == "<p>Second post</p>"

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
    assert Enum.at(response, 0)["content"] == "<p>First post</p>"
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
    assert Enum.at(response, 0)["content"] == "<p>Second home post</p>"
    assert Enum.at(response, 1)["content"] == "<p>First home post</p>"
  end

  test "GET /api/v1/timelines/home includes reblog statuses by the current user", %{conn: conn} do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    PleromaRedux.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, bob} end)

    {:ok, create} = Publish.post_note(alice, "Hello")

    {:ok, _announce} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/announce/2",
          "type" => "Announce",
          "actor" => bob.ap_id,
          "object" => create.object
        },
        local: true
      )

    conn = get(conn, "/api/v1/timelines/home")
    response = json_response(conn, 200)

    assert length(response) == 1
    assert Enum.at(response, 0)["account"]["username"] == "bob"
    assert Enum.at(response, 0)["content"] == ""
    assert Enum.at(response, 0)["reblog"]["account"]["username"] == "alice"
    assert Enum.at(response, 0)["reblog"]["content"] == "<p>Hello</p>"
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
    assert Enum.at(response, 0)["content"] == "<p>Third home post</p>"
    assert Enum.at(response, 1)["content"] == "<p>Second home post</p>"

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
    assert Enum.at(response, 0)["content"] == "<p>First home post</p>"
  end
end
