defmodule Egregoros.Federation.IncomingFollowAcceptTest do
  use Egregoros.DataCase, async: true

  import Mox

  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Users
  alias Egregoros.Workers.DeliverActivity

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

    Egregoros.HTTP.Mock
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

    args =
      all_enqueued(worker: DeliverActivity)
      |> Enum.map(& &1.args)
      |> Enum.find(fn
        %{"activity" => %{"type" => "Accept"}} -> true
        _ -> false
      end)

    assert is_map(args)
    assert :ok = perform_job(DeliverActivity, args)
  end

  test "ingesting remote Follow to a locked local user stores a follow request without sending Accept" do
    {:ok, local} = Users.create_local_user("alice")
    {:ok, _} = Users.update_profile(local, %{locked: true})

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
      "id" => "https://remote.example/activities/follow/locked-1",
      "type" => "Follow",
      "actor" => remote.ap_id,
      "object" => local.ap_id,
      "published" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    assert {:ok, follow_object} = Pipeline.ingest(follow, local: false)
    assert follow_object.type == "Follow"

    refute Objects.get_by_type_actor_object("Accept", local.ap_id, follow["id"])

    assert Egregoros.Relationships.get_by_type_actor_object(
             "FollowRequest",
             remote.ap_id,
             local.ap_id
           )

    assert Egregoros.Relationships.get_by_type_actor_object("Follow", remote.ap_id, local.ap_id) ==
             nil

    assert all_enqueued(worker: DeliverActivity) == []
  end
end
