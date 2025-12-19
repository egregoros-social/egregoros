defmodule PleromaRedux.Federation.OutgoingDeliveryTest do
  use PleromaRedux.DataCase, async: true

  import Mox

  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  test "local Follow delivers to remote inbox" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    follow = %{
      "id" => "https://local.example/activities/follow/1",
      "type" => "Follow",
      "actor" => local.ap_id,
      "object" => remote.ap_id
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, headers ->
      assert url == remote.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Follow"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"] == remote.ap_id

      expected_digest = "SHA-256=" <> (:crypto.hash(:sha256, body) |> Base.encode64())
      assert {"digest", expected_digest} in headers

      assert Enum.any?(headers, fn
               {"signature", value} ->
                 is_binary(value) and String.contains?(value, "keyId=\"#{local.ap_id}#main-key\"")

               _ ->
                 false
             end)

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Pipeline.ingest(follow, local: true)
  end

  test "local Create delivers to remote followers" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote_follower} =
      Users.create_user(%{
        nickname: "carol",
        ap_id: "https://remote.example/users/carol",
        inbox: "https://remote.example/users/carol/inbox",
        outbox: "https://remote.example/users/carol/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    follow = %{
      "id" => "https://remote.example/activities/follow/1",
      "type" => "Follow",
      "actor" => remote_follower.ap_id,
      "object" => local.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow, local: false)

    follow_2 = %{follow | "id" => "https://remote.example/activities/follow/2"}
    assert {:ok, _} = Pipeline.ingest(follow_2, local: false)

    note = %{
      "id" => "https://local.example/objects/1",
      "type" => "Note",
      "attributedTo" => local.ap_id,
      "content" => "Hello followers"
    }

    create = %{
      "id" => "https://local.example/activities/create/1",
      "type" => "Create",
      "actor" => local.ap_id,
      "object" => note
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote_follower.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Create"
      assert decoded["actor"] == local.ap_id
      assert is_map(decoded["object"])

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Pipeline.ingest(create, local: true)
  end

  test "local Like delivers to remote object's actor inbox" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote_author} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    note = %{
      "id" => "https://remote.example/objects/like-target",
      "type" => "Note",
      "attributedTo" => remote_author.ap_id,
      "content" => "Like me"
    }

    assert {:ok, _} = Pipeline.ingest(note, local: false)

    like = %{
      "id" => "https://local.example/activities/like/1",
      "type" => "Like",
      "actor" => local.ap_id,
      "object" => note["id"]
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote_author.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Like"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"] == note["id"]

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Pipeline.ingest(like, local: true)
  end

  test "local EmojiReact delivers to remote object's actor inbox" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote_author} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    note = %{
      "id" => "https://remote.example/objects/react-target",
      "type" => "Note",
      "attributedTo" => remote_author.ap_id,
      "content" => "React to me"
    }

    assert {:ok, _} = Pipeline.ingest(note, local: false)

    react = %{
      "id" => "https://local.example/activities/react/1",
      "type" => "EmojiReact",
      "actor" => local.ap_id,
      "object" => note["id"],
      "content" => ":fire:"
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote_author.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "EmojiReact"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"] == note["id"]
      assert decoded["content"] == ":fire:"

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Pipeline.ingest(react, local: true)
  end

  test "local Announce delivers to remote followers" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote_follower} =
      Users.create_user(%{
        nickname: "carol",
        ap_id: "https://remote.example/users/carol",
        inbox: "https://remote.example/users/carol/inbox",
        outbox: "https://remote.example/users/carol/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    follow = %{
      "id" => "https://remote.example/activities/follow/1-announce",
      "type" => "Follow",
      "actor" => remote_follower.ap_id,
      "object" => local.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow, local: false)

    announce = %{
      "id" => "https://local.example/activities/announce/1",
      "type" => "Announce",
      "actor" => local.ap_id,
      "object" => "https://remote.example/objects/1",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [local.ap_id <> "/followers"]
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote_follower.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Announce"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"] == "https://remote.example/objects/1"

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Pipeline.ingest(announce, local: true)
  end

  test "local Undo of Follow delivers to remote inbox" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    follow = %{
      "id" => "https://local.example/activities/follow/undo-follow",
      "type" => "Follow",
      "actor" => local.ap_id,
      "object" => remote.ap_id
    }

    assert {:ok, _} =
             PleromaRedux.Objects.create_object(%{
               ap_id: follow["id"],
               type: follow["type"],
               actor: follow["actor"],
               object: follow["object"],
               data: follow,
               local: true
             })

    undo = %{
      "id" => "https://local.example/activities/undo/undo-follow",
      "type" => "Undo",
      "actor" => local.ap_id,
      "object" => follow["id"]
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Undo"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"] == follow["id"]

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Pipeline.ingest(undo, local: true)
  end

  test "local Undo of Like delivers to remote object's actor inbox" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote_author} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    note = %{
      "id" => "https://remote.example/objects/undo-like-target",
      "type" => "Note",
      "attributedTo" => remote_author.ap_id,
      "content" => "Like me"
    }

    assert {:ok, _} = Pipeline.ingest(note, local: false)

    like = %{
      "id" => "https://local.example/activities/like/undo-like",
      "type" => "Like",
      "actor" => local.ap_id,
      "object" => note["id"]
    }

    assert {:ok, _} = Pipeline.ingest(like, local: true)

    undo = %{
      "id" => "https://local.example/activities/undo/undo-like",
      "type" => "Undo",
      "actor" => local.ap_id,
      "object" => like["id"]
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote_author.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Undo"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"] == like["id"]

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Pipeline.ingest(undo, local: true)
  end

  test "local Undo of Announce delivers to remote followers" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote_follower} =
      Users.create_user(%{
        nickname: "carol",
        ap_id: "https://remote.example/users/carol",
        inbox: "https://remote.example/users/carol/inbox",
        outbox: "https://remote.example/users/carol/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false
      })

    follow = %{
      "id" => "https://remote.example/activities/follow/undo-announce",
      "type" => "Follow",
      "actor" => remote_follower.ap_id,
      "object" => local.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow, local: false)

    announce = %{
      "id" => "https://local.example/activities/announce/undo-announce",
      "type" => "Announce",
      "actor" => local.ap_id,
      "object" => "https://remote.example/objects/1"
    }

    assert {:ok, _} =
             PleromaRedux.Objects.create_object(%{
               ap_id: announce["id"],
               type: announce["type"],
               actor: announce["actor"],
               object: announce["object"],
               data: announce,
               local: true
             })

    undo = %{
      "id" => "https://local.example/activities/undo/undo-announce",
      "type" => "Undo",
      "actor" => local.ap_id,
      "object" => announce["id"]
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote_follower.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Undo"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"] == announce["id"]

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Pipeline.ingest(undo, local: true)
  end
end
