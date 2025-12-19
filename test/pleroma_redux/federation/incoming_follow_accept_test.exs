defmodule PleromaRedux.Federation.IncomingFollowAcceptTest do
  use PleromaRedux.DataCase, async: true

  import Mox

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Users

  test "ingesting remote Follow to local user stores and sends Accept" do
    {:ok, local} = Users.create_local_user("alice")

    {:ok, remote} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        local: false
      })

    follow = %{
      "id" => "https://remote.example/activities/follow/1",
      "type" => "Follow",
      "actor" => remote.ap_id,
      "object" => local.ap_id,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    PleromaRedux.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Accept"
      assert decoded["actor"] == local.ap_id
      assert decoded["object"]["id"] == follow["id"]
      assert decoded["object"]["type"] == "Follow"

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, follow_object} = Pipeline.ingest(follow, local: false)
    assert follow_object.type == "Follow"

    assert Objects.get_by_type_actor_object("Accept", local.ap_id, follow["id"])
  end
end

