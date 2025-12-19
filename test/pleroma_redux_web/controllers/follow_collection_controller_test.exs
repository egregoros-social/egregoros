defmodule PleromaReduxWeb.FollowCollectionControllerTest do
  use PleromaReduxWeb.ConnCase, async: true

  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  test "GET /users/:nickname/followers returns follower collection", %{conn: conn} do
    {:ok, local} = Users.create_local_user("alice-followers")

    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob-followers",
        ap_id: "https://remote.example/users/bob-followers",
        inbox: "https://remote.example/users/bob-followers/inbox",
        outbox: "https://remote.example/users/bob-followers/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        local: false
      })

    follow = %{
      "id" => "https://remote.example/activities/follow/followers-1",
      "type" => "Follow",
      "actor" => remote.ap_id,
      "object" => local.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow, local: false)

    follow_2 = %{follow | "id" => "https://remote.example/activities/follow/followers-2"}
    assert {:ok, _} = Pipeline.ingest(follow_2, local: false)

    conn = get(conn, "/users/alice-followers/followers")
    assert conn.status == 200

    decoded = Jason.decode!(conn.resp_body)
    assert decoded["type"] == "OrderedCollection"
    assert decoded["id"] == local.ap_id <> "/followers"
    assert decoded["totalItems"] == 1
    assert decoded["orderedItems"] == [remote.ap_id]
  end

  test "GET /users/:nickname/following returns following collection", %{conn: conn} do
    {:ok, local} = Users.create_local_user("alice-following")

    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob-following",
        ap_id: "https://remote.example/users/bob-following",
        inbox: "https://remote.example/users/bob-following/inbox",
        outbox: "https://remote.example/users/bob-following/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        local: false
      })

    follow = %{
      "id" => "http://localhost:4000/activities/follow/following-1",
      "type" => "Follow",
      "actor" => local.ap_id,
      "object" => remote.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow, local: true)

    follow_2 = %{follow | "id" => "http://localhost:4000/activities/follow/following-2"}
    assert {:ok, _} = Pipeline.ingest(follow_2, local: true)

    conn = get(conn, "/users/alice-following/following")
    assert conn.status == 200

    decoded = Jason.decode!(conn.resp_body)
    assert decoded["type"] == "OrderedCollection"
    assert decoded["id"] == local.ap_id <> "/following"
    assert decoded["totalItems"] == 1
    assert decoded["orderedItems"] == [remote.ap_id]
  end
end
