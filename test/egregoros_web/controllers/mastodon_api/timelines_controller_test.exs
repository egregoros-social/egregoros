defmodule EgregorosWeb.MastodonAPI.TimelinesControllerTest do
  use EgregorosWeb.ConnCase, async: true

  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Users

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
    {:ok, _} = Publish.post_note(user, "Unlisted post", visibility: "unlisted")

    conn = get(conn, "/api/v1/timelines/public")
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["content"] == "<p>Hello public</p>"))
    refute Enum.any?(response, &(&1["content"] == "<p>Secret DM</p>"))
    refute Enum.any?(response, &(&1["content"] == "<p>Unlisted post</p>"))
  end

  test "GET /api/v1/timelines/public with local=true only includes local statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "Local post")

    remote_note = %{
      "id" => "https://remote.example/objects/" <> Ecto.UUID.generate(),
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [],
      "content" => "Remote post"
    }

    assert {:ok, _} = Pipeline.ingest(remote_note, local: false)

    conn = get(conn, "/api/v1/timelines/public", %{"local" => "true"})
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["content"] == "<p>Local post</p>"))
    refute Enum.any?(response, &(&1["content"] == "<p>Remote post</p>"))
  end

  test "GET /api/v1/timelines/public with remote=true only includes remote statuses", %{
    conn: conn
  } do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "Local post")

    remote_note = %{
      "id" => "https://remote.example/objects/" <> Ecto.UUID.generate(),
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [],
      "content" => "Remote post"
    }

    assert {:ok, _} = Pipeline.ingest(remote_note, local: false)

    conn = get(conn, "/api/v1/timelines/public", %{"remote" => "true"})
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["content"] == "<p>Remote post</p>"))
    refute Enum.any?(response, &(&1["content"] == "<p>Local post</p>"))
  end

  test "GET /api/v1/timelines/public does not include reblogs with missing objects", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "Local post")

    {:ok, announce} =
      Egregoros.Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/missing",
        type: "Announce",
        actor: "https://remote.example/users/alice",
        object: "https://remote.example/objects/missing",
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/missing",
          "type" => "Announce",
          "actor" => "https://remote.example/users/alice",
          "object" => "https://remote.example/objects/missing",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => []
        }
      })

    conn = get(conn, "/api/v1/timelines/public")
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["content"] == "<p>Local post</p>"))
    refute Enum.any?(response, &(&1["id"] == Integer.to_string(announce.id)))
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

  test "GET /api/v1/timelines/tag/:hashtag returns latest tagged statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "First #linux")
    {:ok, _} = Publish.post_note(user, "Second #linux")
    {:ok, _} = Publish.post_note(user, "Other #other")

    conn = get(conn, "/api/v1/timelines/tag/linux")
    response = json_response(conn, 200)

    assert length(response) == 2
    assert Enum.at(response, 0)["content"] =~ "#linux"
    assert Enum.at(response, 1)["content"] =~ "#linux"
  end

  test "GET /api/v1/timelines/tag/:hashtag does not include direct or unlisted statuses", %{
    conn: conn
  } do
    {:ok, user} = Users.create_local_user("local")

    {:ok, _} = Publish.post_note(user, "Hello #linux")
    {:ok, _} = Publish.post_note(user, "Secret #linux", visibility: "direct")
    {:ok, _} = Publish.post_note(user, "Unlisted #linux", visibility: "unlisted")

    conn = get(conn, "/api/v1/timelines/tag/linux")
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["content"] =~ "Hello"))
    refute Enum.any?(response, &(&1["content"] =~ "Secret"))
    refute Enum.any?(response, &(&1["content"] =~ "Unlisted"))
  end

  test "GET /api/v1/timelines/tag/:hashtag with local=true only includes local statuses", %{
    conn: conn
  } do
    {:ok, user} = Users.create_local_user("local")
    {:ok, _} = Publish.post_note(user, "Local #linux")

    remote_note = %{
      "id" => "https://remote.example/objects/" <> Ecto.UUID.generate(),
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [],
      "content" => "Remote #linux"
    }

    assert {:ok, _} = Pipeline.ingest(remote_note, local: false)

    conn = get(conn, "/api/v1/timelines/tag/linux", %{"local" => "true"})
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["content"] =~ "Local"))
    refute Enum.any?(response, &(&1["content"] =~ "Remote"))
  end

  test "GET /api/v1/timelines/home returns latest statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, _} = Publish.post_note(user, "First home post")
    {:ok, _} = Publish.post_note(user, "Second home post")

    conn = get(conn, "/api/v1/timelines/home")

    response = json_response(conn, 200)
    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "<p>Second home post</p>"
    assert Enum.at(response, 1)["content"] == "<p>First home post</p>"
  end

  test "GET /api/v1/timelines/home does not include reblogs with missing objects", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    remote_actor = "https://remote.example/users/alice"

    assert {:ok, _follow} =
             Pipeline.ingest(
               %{
                 "id" => "https://remote.example/activities/follow/1",
                 "type" => "Follow",
                 "actor" => user.ap_id,
                 "object" => remote_actor
               },
               local: true
             )

    {:ok, announce} =
      Egregoros.Objects.create_object(%{
        ap_id: "https://remote.example/activities/announce/missing-home",
        type: "Announce",
        actor: remote_actor,
        object: "https://remote.example/objects/missing-home",
        local: false,
        data: %{
          "id" => "https://remote.example/activities/announce/missing-home",
          "type" => "Announce",
          "actor" => remote_actor,
          "object" => "https://remote.example/objects/missing-home",
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => []
        }
      })

    conn = get(conn, "/api/v1/timelines/home")
    response = json_response(conn, 200)

    refute Enum.any?(response, &(&1["id"] == Integer.to_string(announce.id)))
  end

  test "GET /api/v1/timelines/home includes reblog statuses by the current user", %{conn: conn} do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    Egregoros.Auth.Mock
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

    Egregoros.Auth.Mock
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

  test "GET /api/v1/timelines/home does not include posts from muted accounts", %{conn: conn} do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    Egregoros.Auth.Mock
    |> expect(:current_user, 2, fn _conn -> {:ok, bob} end)

    {:ok, _follow} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/3",
          "type" => "Follow",
          "actor" => bob.ap_id,
          "object" => alice.ap_id
        },
        local: true
      )

    {:ok, _} = Publish.post_note(alice, "Muted post")

    conn = get(conn, "/api/v1/timelines/home")
    response = json_response(conn, 200)
    assert Enum.any?(response, &(&1["content"] == "<p>Muted post</p>"))

    {:ok, _} =
      Egregoros.Relationships.upsert_relationship(%{
        type: "Mute",
        actor: bob.ap_id,
        object: alice.ap_id,
        activity_ap_id: "https://example.com/activities/mute/2"
      })

    conn = get(conn, "/api/v1/timelines/home")
    response = json_response(conn, 200)
    refute Enum.any?(response, &(&1["content"] == "<p>Muted post</p>"))
  end

  test "GET /api/v1/timelines/home does not include direct messages from blocked accounts", %{
    conn: conn
  } do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    Egregoros.Auth.Mock
    |> expect(:current_user, 2, fn _conn -> {:ok, bob} end)

    {:ok, _} = Publish.post_note(alice, "@bob Secret DM", visibility: "direct")

    conn = get(conn, "/api/v1/timelines/home")
    response = json_response(conn, 200)

    assert Enum.any?(response, fn status ->
             status["visibility"] == "direct" and
               is_binary(status["content"]) and
               String.contains?(status["content"], "Secret DM")
           end)

    {:ok, _} =
      Egregoros.Relationships.upsert_relationship(%{
        type: "Block",
        actor: bob.ap_id,
        object: alice.ap_id,
        activity_ap_id: "https://example.com/activities/block/2"
      })

    conn = get(conn, "/api/v1/timelines/home")
    response = json_response(conn, 200)

    refute Enum.any?(response, fn status ->
             is_binary(status["content"]) and String.contains?(status["content"], "Secret DM")
           end)
  end
end
