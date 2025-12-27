defmodule Egregoros.PublishTest do
  use Egregoros.DataCase, async: true

  import Mox

  alias Egregoros.Pipeline
  alias Egregoros.Objects
  alias Egregoros.Publish
  alias Egregoros.Users
  alias Egregoros.Workers.DeliverActivity

  test "post_note/2 rejects content longer than 5000 characters" do
    {:ok, local} = Users.create_local_user("alice")
    assert {:error, :too_long} = Publish.post_note(local, String.duplicate("a", 5001))
  end

  test "post_note/2 delivers Create with addressing to remote followers" do
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

    assert {:ok, _} = Pipeline.ingest(follow, local: false)

    Egregoros.HTTP.Mock
    |> expect(:post, fn url, body, _headers ->
      assert url == remote_follower.inbox

      decoded = Jason.decode!(body)
      assert decoded["type"] == "Create"
      assert decoded["actor"] == local.ap_id

      assert "https://www.w3.org/ns/activitystreams#Public" in decoded["to"]
      assert (local.ap_id <> "/followers") in decoded["cc"]

      assert is_map(decoded["object"])
      assert "https://www.w3.org/ns/activitystreams#Public" in decoded["object"]["to"]
      assert (local.ap_id <> "/followers") in decoded["object"]["cc"]

      {:ok, %{status: 202, body: "", headers: []}}
    end)

    assert {:ok, _} = Publish.post_note(local, "Hello followers")

    args =
      all_enqueued(worker: DeliverActivity)
      |> Enum.map(& &1.args)
      |> Enum.find(fn
        %{"activity" => %{"type" => "Create"}} -> true
        _ -> false
      end)

    assert is_map(args)
    assert :ok = perform_job(DeliverActivity, args)
  end

  test "post_note/3 with visibility=direct addresses mentioned local users and does not deliver to followers" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

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
      "object" => alice.ap_id
    }

    assert {:ok, _} = Pipeline.ingest(follow, local: false)

    assert {:ok, create} = Publish.post_note(alice, "@bob Secret DM", visibility: "direct")

    assert %{} = note = Objects.get_by_ap_id(create.object)
    assert bob.ap_id in note.data["to"]
    assert Objects.visible_to?(note, bob)

    create_jobs =
      all_enqueued(worker: DeliverActivity)
      |> Enum.filter(fn job ->
        match?(%{"activity" => %{"type" => "Create"}}, job.args)
      end)

    refute Enum.any?(create_jobs, &(&1.args["inbox_url"] == remote_follower.inbox))
  end

  test "post_note/3 with visibility=direct delivers Create to remote recipients" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, remote_recipient} =
      Users.create_user(%{
        nickname: "toast",
        domain: "donotsta.re",
        ap_id: "https://donotsta.re/users/toast",
        inbox: "https://donotsta.re/users/toast/inbox",
        outbox: "https://donotsta.re/users/toast/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        local: false
      })

    assert {:ok, create} =
             Publish.post_note(alice, "@toast@donotsta.re hello", visibility: "direct")

    assert %{} = note = Objects.get_by_ap_id(create.object)
    assert remote_recipient.ap_id in note.data["to"]

    create_jobs =
      all_enqueued(worker: DeliverActivity)
      |> Enum.filter(fn job ->
        match?(%{"activity" => %{"type" => "Create"}}, job.args)
      end)

    assert Enum.any?(create_jobs, &(&1.args["inbox_url"] == remote_recipient.inbox))
  end

  test "post_note/2 delivers Create to mentioned remote actors" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, remote} =
      Users.create_user(%{
        nickname: "lain",
        domain: "lain.com",
        ap_id: "https://lain.com/users/lain",
        inbox: "https://lain.com/users/lain/inbox",
        outbox: "https://lain.com/users/lain/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        local: false
      })

    assert {:ok, create} = Publish.post_note(alice, "hi @lain@lain.com")

    assert %{} = note = Objects.get_by_ap_id(create.object)
    assert note.data["content"] =~ "href=\"#{remote.ap_id}\""
    assert remote.ap_id in List.wrap(note.data["cc"])

    assert Enum.any?(List.wrap(note.data["tag"]), fn
             %{"type" => "Mention", "href" => href, "name" => name} ->
               href == remote.ap_id and name == "@lain@lain.com"

             _ ->
               false
           end)

    create_jobs =
      all_enqueued(worker: DeliverActivity)
      |> Enum.filter(fn job ->
        match?(%{"activity" => %{"type" => "Create"}}, job.args)
      end)

    assert Enum.any?(create_jobs, &(&1.args["inbox_url"] == remote.inbox))
  end

  test "post_note/3 replies deliver to the inReplyTo actor even without an explicit @mention" do
    {:ok, alice} = Users.create_local_user("alice")

    {:ok, remote_author} =
      Users.create_user(%{
        nickname: "lain",
        domain: "lain.com",
        ap_id: "https://lain.com/users/lain",
        inbox: "https://lain.com/users/lain/inbox",
        outbox: "https://lain.com/users/lain/outbox",
        public_key: "-----BEGIN PUBLIC KEY-----\nMIIB...\n-----END PUBLIC KEY-----\n",
        local: false
      })

    parent_note = %{
      "id" => "https://lain.com/objects/parent",
      "type" => "Note",
      "attributedTo" => remote_author.ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [],
      "content" => "parent"
    }

    assert {:ok, _} = Pipeline.ingest(parent_note, local: false)

    assert {:ok, create} =
             Publish.post_note(alice, "a reply", in_reply_to: parent_note["id"])

    assert %{} = note = Objects.get_by_ap_id(create.object)
    assert note.data["inReplyTo"] == parent_note["id"]
    assert remote_author.ap_id in List.wrap(note.data["cc"])

    assert Enum.any?(List.wrap(note.data["tag"]), fn
             %{"type" => "Mention", "href" => href} -> href == remote_author.ap_id
             _ -> false
           end)

    create_jobs =
      all_enqueued(worker: DeliverActivity)
      |> Enum.filter(fn job ->
        match?(%{"activity" => %{"type" => "Create"}}, job.args)
      end)

    assert Enum.any?(create_jobs, &(&1.args["inbox_url"] == remote_author.inbox))
  end

  test "post_note/3 replies mention actors with non-default ports even when the actor is not stored" do
    {:ok, alice} = Users.create_local_user("alice")

    parent_note = %{
      "id" => "https://example.com:8443/objects/parent",
      "type" => "Note",
      "attributedTo" => "https://example.com:8443/users/bob",
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [],
      "content" => "parent"
    }

    assert {:ok, _} = Pipeline.ingest(parent_note, local: false)

    assert {:ok, create} =
             Publish.post_note(alice, "a reply", in_reply_to: parent_note["id"])

    assert %{} = note = Objects.get_by_ap_id(create.object)

    assert Enum.any?(List.wrap(note.data["tag"]), fn
             %{"type" => "Mention", "href" => href, "name" => name} ->
               href == parent_note["attributedTo"] and name == "@bob@example.com:8443"

             _ ->
               false
           end)
  end
end
