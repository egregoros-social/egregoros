defmodule PleromaRedux.TimelineTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Pipeline
  alias PleromaRedux.Timeline
  alias PleromaRedux.Users
  alias PleromaRedux.Objects

  test "ingesting a note broadcasts to the timeline" do
    Timeline.subscribe()

    note = %{
      "id" => "https://remote.example/objects/stream-1",
      "type" => "Note",
      "attributedTo" => "https://remote.example/users/alice",
      "content" => "Remote hello"
    }

    assert {:ok, object} = Pipeline.ingest(note, local: false)

    assert_receive {:post_created, ^object}
  end

  test "create_post delivers Create with addressing to remote followers" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote_follower} =
      Users.create_user(%{
        nickname: "lain",
        ap_id: "https://lain.com/users/lain",
        inbox: "https://lain.com/users/lain/inbox",
        outbox: "https://lain.com/users/lain/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        local: false
      })

    follow = %{
      "id" => "https://lain.com/activities/follow/1",
      "type" => "Follow",
      "actor" => remote_follower.ap_id,
      "object" => local.ap_id
    }

    assert {:ok, _} =
             Objects.create_object(%{
               ap_id: follow["id"],
               type: follow["type"],
               actor: follow["actor"],
               object: follow["object"],
               data: follow,
               local: false
             })

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote_follower.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Create"
      assert decoded["actor"] == local.ap_id

      assert "https://www.w3.org/ns/activitystreams#Public" in decoded["to"]
      assert local.ap_id <> "/followers" in decoded["cc"]

      assert is_map(decoded["object"])
      assert "https://www.w3.org/ns/activitystreams#Public" in decoded["object"]["to"]
      assert local.ap_id <> "/followers" in decoded["object"]["cc"]

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Timeline.create_post(local, "Hello followers")
  end
end
