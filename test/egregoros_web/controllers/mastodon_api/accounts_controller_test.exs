defmodule EgregorosWeb.MastodonAPI.AccountsControllerTest do
  use EgregorosWeb.ConnCase, async: true

  import Mox

  alias Egregoros.Publish
  alias Egregoros.Pipeline
  alias Egregoros.Relationships
  alias Egregoros.Users

  test "GET /api/v1/accounts/verify_credentials returns current user", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/accounts/verify_credentials")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "local"
  end

  test "GET /api/v1/accounts/:id returns account", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    conn = get(conn, "/api/v1/accounts/#{user.id}")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "alice"
  end

  test "GET /api/v1/accounts/:id/statuses returns account statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, _} = Publish.post_note(user, "First post")
    {:ok, _} = Publish.post_note(user, "Second post")

    conn = get(conn, "/api/v1/accounts/#{user.id}/statuses")
    response = json_response(conn, 200)

    assert length(response) == 2
    assert Enum.at(response, 0)["content"] == "<p>Second post</p>"
    assert Enum.at(response, 1)["content"] == "<p>First post</p>"
  end

  test "GET /api/v1/accounts/:id/statuses does not include direct statuses", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, _} = Publish.post_note(user, "Hello public")
    {:ok, _} = Publish.post_note(user, "Secret DM", visibility: "direct")

    conn = get(conn, "/api/v1/accounts/#{user.id}/statuses")
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["content"] == "<p>Hello public</p>"))
    refute Enum.any?(response, &(&1["content"] == "<p>Secret DM</p>"))
  end

  test "GET /api/v1/accounts/:id/statuses with pinned=true only returns pinned statuses", %{
    conn: conn
  } do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, _} = Publish.post_note(user, "First post")

    conn = get(conn, "/api/v1/accounts/#{user.id}/statuses", %{"pinned" => "true"})
    response = json_response(conn, 200)

    assert response == []
  end

  test "GET /api/v1/accounts/:id/statuses includes reblogs", %{conn: conn} do
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

    conn = get(conn, "/api/v1/accounts/#{bob.id}/statuses")
    response = json_response(conn, 200)

    assert length(response) == 1
    assert Enum.at(response, 0)["account"]["username"] == "bob"
    assert Enum.at(response, 0)["content"] == ""
    assert Enum.at(response, 0)["reblog"]["content"] == "<p>Hello</p>"
  end

  test "GET /api/v1/accounts/:id/statuses paginates with max_id and Link header", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    {:ok, _} = Publish.post_note(user, "First post")
    {:ok, _} = Publish.post_note(user, "Second post")
    {:ok, _} = Publish.post_note(user, "Third post")

    conn = get(conn, "/api/v1/accounts/#{user.id}/statuses", %{"limit" => "2"})
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
      get(conn, "/api/v1/accounts/#{user.id}/statuses", %{
        "limit" => "2",
        "max_id" => Enum.at(response, 1)["id"]
      })

    response = json_response(conn, 200)
    assert length(response) == 1
    assert Enum.at(response, 0)["content"] == "<p>First post</p>"
  end

  test "PATCH /api/v1/accounts/update_credentials updates profile fields", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn =
      patch(conn, "/api/v1/accounts/update_credentials", %{
        "display_name" => "New Name",
        "note" => "New bio"
      })

    response = json_response(conn, 200)
    assert response["display_name"] == "New Name"
    assert response["note"] == "<p>New bio</p>"

    user = Users.get(user.id)
    assert user.name == "New Name"
    assert user.bio == "New bio"
  end

  test "PATCH /api/v1/accounts/update_credentials updates avatar upload", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    upload =
      %Plug.Upload{
        path: tmp_upload_path(),
        filename: "avatar.png",
        content_type: "image/png"
      }

    Egregoros.AvatarStorage.Mock
    |> expect(:store_avatar, fn ^user, %Plug.Upload{filename: "avatar.png"} ->
      {:ok, "/uploads/avatars/#{user.id}/avatar.png"}
    end)

    conn =
      patch(conn, "/api/v1/accounts/update_credentials", %{
        "avatar" => upload
      })

    response = json_response(conn, 200)
    assert String.ends_with?(response["avatar"], "/uploads/avatars/#{user.id}/avatar.png")

    user = Users.get(user.id)
    assert user.avatar_url == "/uploads/avatars/#{user.id}/avatar.png"
  end

  test "GET /api/v1/accounts/lookup finds a local account by acct", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    conn = get(conn, "/api/v1/accounts/lookup", %{"acct" => "alice"})
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "alice"
  end

  test "GET /api/v1/accounts/lookup treats trailing @ as a local acct", %{conn: conn} do
    {:ok, user} = Users.create_local_user("alice")

    conn = get(conn, "/api/v1/accounts/lookup", %{"acct" => "alice@"})
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "alice"
  end

  test "GET /api/v1/accounts/lookup treats a local acct with an explicit port as local", %{
    conn: conn
  } do
    {:ok, user} = Users.create_local_user("alice")

    uri = URI.parse(EgregorosWeb.Endpoint.url())
    domain = "#{uri.host}:#{uri.port}"

    conn = get(conn, "/api/v1/accounts/lookup", %{"acct" => "alice@#{domain}"})
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(user.id)
    assert response["username"] == "alice"
  end

  test "GET /api/v1/accounts/lookup resolves a remote acct via WebFinger", %{conn: conn} do
    actor_url = "https://remote.example/users/bob"

    Egregoros.HTTP.Mock
    |> expect(:get, fn url, _headers ->
      assert url ==
               "https://remote.example/.well-known/webfinger?resource=acct:bob@remote.example"

      {:ok,
       %{
         status: 200,
         body: %{
           "links" => [
             %{
               "rel" => "self",
               "type" => "application/activity+json",
               "href" => actor_url
             }
           ]
         },
         headers: []
       }}
    end)
    |> expect(:get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "bob",
           "inbox" => "https://remote.example/users/bob/inbox",
           "outbox" => "https://remote.example/users/bob/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n"
           }
         },
         headers: []
       }}
    end)

    conn = get(conn, "/api/v1/accounts/lookup", %{"acct" => "bob@remote.example"})
    response = json_response(conn, 200)

    assert response["username"] == "bob"
    assert response["acct"] == "bob@remote.example"
  end

  test "GET /api/v1/accounts/lookup ignores extra @ segments (elk compatibility)", %{conn: conn} do
    actor_url = "https://remote.example/users/bob"

    Egregoros.HTTP.Mock
    |> expect(:get, fn url, _headers ->
      assert url ==
               "https://remote.example/.well-known/webfinger?resource=acct:bob@remote.example"

      {:ok,
       %{
         status: 200,
         body: %{
           "links" => [
             %{
               "rel" => "self",
               "type" => "application/activity+json",
               "href" => actor_url
             }
           ]
         },
         headers: []
       }}
    end)
    |> expect(:get, fn url, _headers ->
      assert url == actor_url

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => actor_url,
           "type" => "Person",
           "preferredUsername" => "bob",
           "inbox" => "https://remote.example/users/bob/inbox",
           "outbox" => "https://remote.example/users/bob/outbox",
           "publicKey" => %{
             "id" => actor_url <> "#main-key",
             "owner" => actor_url,
             "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n"
           }
         },
         headers: []
       }}
    end)

    conn = get(conn, "/api/v1/accounts/lookup", %{"acct" => "bob@remote.example@localhost"})
    response = json_response(conn, 200)

    assert response["username"] == "bob"
    assert response["acct"] == "bob@remote.example"
  end

  test "POST /api/v1/accounts/:id/follow creates follow activity", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("bob")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/accounts/#{target.id}/follow")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(target.id)
    assert response["following"] == true

    assert Egregoros.Objects.get_by_type_actor_object("Follow", user.ap_id, target.ap_id)
  end

  test "POST /api/v1/accounts/:id/follow requests to follow remote accounts until accepted", %{
    conn: conn
  } do
    {:ok, user} = Users.create_local_user("local")

    {:ok, target} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/accounts/#{target.id}/follow")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(target.id)
    assert response["following"] == false
    assert response["requested"] == true

    assert Egregoros.Relationships.get_by_type_actor_object("Follow", user.ap_id, target.ap_id) == nil
    assert Egregoros.Relationships.get_by_type_actor_object("FollowRequest", user.ap_id, target.ap_id)
  end

  test "POST /api/v1/accounts/:id/unfollow creates undo activity", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("charlie")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, follow} =
      Egregoros.Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/1",
          "type" => "Follow",
          "actor" => user.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    conn = post(conn, "/api/v1/accounts/#{target.id}/unfollow")
    response = json_response(conn, 200)
    assert response["id"] == Integer.to_string(target.id)
    assert response["following"] == false

    assert Egregoros.Objects.get_by_type_actor_object("Undo", user.ap_id, follow.ap_id)
  end

  test "POST /api/v1/accounts/:id/unfollow cancels pending follow requests to remote accounts", %{
    conn: conn
  } do
    {:ok, user} = Users.create_local_user("local")

    {:ok, target} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, follow} =
      Egregoros.Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/remote",
          "type" => "Follow",
          "actor" => user.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    assert Egregoros.Relationships.get_by_type_actor_object("FollowRequest", user.ap_id, target.ap_id)

    conn = post(conn, "/api/v1/accounts/#{target.id}/unfollow")
    response = json_response(conn, 200)

    assert response["following"] == false
    assert response["requested"] == false
    assert Egregoros.Objects.get_by_type_actor_object("Undo", user.ap_id, follow.ap_id)
    assert Egregoros.Relationships.get_by_type_actor_object("FollowRequest", user.ap_id, target.ap_id) == nil
  end

  test "POST /api/v1/accounts/:id/unfollow undoes the latest follow relationship", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("dana")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, follow_1} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/old",
          "type" => "Follow",
          "actor" => user.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    {:ok, follow_2} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/new",
          "type" => "Follow",
          "actor" => user.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    assert %{} = Relationships.get_by_type_actor_object("Follow", user.ap_id, target.ap_id)

    conn = post(conn, "/api/v1/accounts/#{target.id}/unfollow")
    response = json_response(conn, 200)
    assert response["following"] == false

    assert Egregoros.Objects.get_by_type_actor_object("Undo", user.ap_id, follow_2.ap_id)
    refute Egregoros.Objects.get_by_type_actor_object("Undo", user.ap_id, follow_1.ap_id)
    assert Relationships.get_by_type_actor_object("Follow", user.ap_id, target.ap_id) == nil
  end

  test "POST /api/v1/accounts/:id/block creates a block relationship and removes follows", %{
    conn: conn
  } do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("blocked")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, _follow_1} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/1",
          "type" => "Follow",
          "actor" => user.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    {:ok, _follow_2} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/2",
          "type" => "Follow",
          "actor" => target.ap_id,
          "object" => user.ap_id
        },
        local: true
      )

    assert Relationships.get_by_type_actor_object("Follow", user.ap_id, target.ap_id)
    assert Relationships.get_by_type_actor_object("Follow", target.ap_id, user.ap_id)

    conn = post(conn, "/api/v1/accounts/#{target.id}/block")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(target.id)
    assert response["blocking"] == true
    assert Relationships.get_by_type_actor_object("Block", user.ap_id, target.ap_id)
    assert Relationships.get_by_type_actor_object("Follow", user.ap_id, target.ap_id) == nil
    assert Relationships.get_by_type_actor_object("Follow", target.ap_id, user.ap_id) == nil
  end

  test "POST /api/v1/accounts/:id/unblock removes the block relationship", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("blocked")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, _} =
      Relationships.upsert_relationship(%{
        type: "Block",
        actor: user.ap_id,
        object: target.ap_id,
        activity_ap_id: "https://example.com/activities/block/1"
      })

    assert Relationships.get_by_type_actor_object("Block", user.ap_id, target.ap_id)

    conn = post(conn, "/api/v1/accounts/#{target.id}/unblock")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(target.id)
    assert response["blocking"] == false
    assert Relationships.get_by_type_actor_object("Block", user.ap_id, target.ap_id) == nil
  end

  test "POST /api/v1/accounts/:id/mute creates a mute relationship", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("muted")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = post(conn, "/api/v1/accounts/#{target.id}/mute")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(target.id)
    assert response["muting"] == true
    assert Relationships.get_by_type_actor_object("Mute", user.ap_id, target.ap_id)
  end

  test "POST /api/v1/accounts/:id/unmute removes the mute relationship", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target} = Users.create_local_user("muted")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    {:ok, _} =
      Relationships.upsert_relationship(%{
        type: "Mute",
        actor: user.ap_id,
        object: target.ap_id,
        activity_ap_id: "https://example.com/activities/mute/1"
      })

    assert Relationships.get_by_type_actor_object("Mute", user.ap_id, target.ap_id)

    conn = post(conn, "/api/v1/accounts/#{target.id}/unmute")
    response = json_response(conn, 200)

    assert response["id"] == Integer.to_string(target.id)
    assert response["muting"] == false
    assert Relationships.get_by_type_actor_object("Mute", user.ap_id, target.ap_id) == nil
  end

  test "GET /api/v1/accounts/relationships returns relationship objects", %{conn: conn} do
    {:ok, user} = Users.create_local_user("local")
    {:ok, target_1} = Users.create_local_user("alice")
    {:ok, target_2} = Users.create_local_user("bob")

    Egregoros.Auth.Mock
    |> expect(:current_user, fn _conn -> {:ok, user} end)

    conn = get(conn, "/api/v1/accounts/relationships", %{"id" => [target_1.id, target_2.id]})
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["id"] == Integer.to_string(target_1.id)))
    assert Enum.any?(response, &(&1["id"] == Integer.to_string(target_2.id)))
  end

  test "GET /api/v1/accounts/:id/followers returns follower accounts", %{conn: conn} do
    {:ok, follower} = Users.create_local_user("alice")
    {:ok, target} = Users.create_local_user("bob")

    {:ok, _follow} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/1",
          "type" => "Follow",
          "actor" => follower.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    conn = get(conn, "/api/v1/accounts/#{target.id}/followers")
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["id"] == Integer.to_string(follower.id)))
  end

  test "GET /api/v1/accounts/:id/following returns followed accounts", %{conn: conn} do
    {:ok, follower} = Users.create_local_user("alice")
    {:ok, target} = Users.create_local_user("bob")

    {:ok, _follow} =
      Pipeline.ingest(
        %{
          "id" => "https://example.com/activities/follow/1",
          "type" => "Follow",
          "actor" => follower.ap_id,
          "object" => target.ap_id
        },
        local: true
      )

    conn = get(conn, "/api/v1/accounts/#{follower.id}/following")
    response = json_response(conn, 200)

    assert Enum.any?(response, &(&1["id"] == Integer.to_string(target.id)))
  end

  defp tmp_upload_path do
    path = Path.join(System.tmp_dir!(), "egregoros-test-upload-#{Ecto.UUID.generate()}")
    File.write!(path, <<0, 1, 2, 3>>)
    path
  end
end
