defmodule Egregoros.PipelineInboxAuthorizationTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.Follow
  alias Egregoros.Pipeline
  alias Egregoros.Users
  alias Egregoros.Workers.FetchActor
  alias Egregoros.Workers.IngestActivity

  @remote "https://remote.example"

  setup do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    %{alice: alice, bob: bob}
  end

  defp activity_id, do: "#{@remote}/activities/#{Ecto.UUID.generate()}"
  defp object_id, do: "#{@remote}/objects/#{Ecto.UUID.generate()}"

  describe "untargeted inbox activities enqueue no discovery work" do
    test "Follow aimed at another user", %{alice: alice, bob: bob} do
      # Delivered to alice's inbox, but the Follow targets bob.
      activity = %{
        "id" => activity_id(),
        "type" => "Follow",
        "actor" => "#{@remote}/users/unknown-follower",
        "object" => bob.ap_id
      }

      assert {:error, :not_targeted} =
               Pipeline.ingest(activity, local: false, inbox_user_ap_id: alice.ap_id)

      refute_enqueued(worker: FetchActor)
    end

    test "Create whose Note is addressed at nobody we know", %{alice: alice} do
      mention = "#{@remote}/users/unknown-mention"
      note_id = object_id()

      activity = %{
        "id" => activity_id(),
        "type" => "Create",
        "actor" => "#{@remote}/users/unknown-author",
        "to" => ["#{@remote}/users/someone-else"],
        "cc" => [],
        "object" => %{
          "id" => note_id,
          "type" => "Note",
          "attributedTo" => "#{@remote}/users/unknown-author",
          "to" => ["#{@remote}/users/someone-else"],
          "cc" => [],
          "content" => "not for you",
          "published" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "tag" => [
            %{"type" => "Mention", "href" => mention, "name" => "@unknown-mention@remote.example"}
          ]
        }
      }

      assert {:error, :not_targeted} =
               Pipeline.ingest(activity, local: false, inbox_user_ap_id: alice.ap_id)

      refute_enqueued(worker: FetchActor)
      # Explicit: the nested Note's mention must not be fetched either.
      refute_enqueued(worker: FetchActor, args: %{"ap_id" => mention})
    end

    test "Like of an object nobody local owns", %{alice: alice} do
      activity = %{
        "id" => activity_id(),
        "type" => "Like",
        "actor" => "#{@remote}/users/unknown-liker",
        "object" => object_id()
      }

      assert {:error, :not_targeted} =
               Pipeline.ingest(activity, local: false, inbox_user_ap_id: alice.ap_id)

      refute_enqueued(worker: FetchActor)
    end

    test "Accept of a Follow we hold no record of", %{alice: alice} do
      activity = %{
        "id" => activity_id(),
        "type" => "Accept",
        "actor" => "#{@remote}/users/unknown-accepter",
        "to" => ["#{@remote}/users/someone-else"],
        "object" => "#{@remote}/activities/#{Ecto.UUID.generate()}"
      }

      assert {:error, :not_targeted} =
               Pipeline.ingest(activity, local: false, inbox_user_ap_id: alice.ap_id)

      refute_enqueued(worker: FetchActor)
    end

    test "Delete from an actor the inbox owner does not follow", %{alice: alice} do
      activity = %{
        "id" => activity_id(),
        "type" => "Delete",
        "actor" => "#{@remote}/users/unknown-deleter",
        "to" => ["#{@remote}/users/someone-else"],
        "object" => object_id()
      }

      assert {:error, :not_targeted} =
               Pipeline.ingest(activity, local: false, inbox_user_ap_id: alice.ap_id)

      refute_enqueued(worker: FetchActor)
    end

    # An Undo whose target we do not hold is rejected as :target_unknown rather
    # than :not_targeted (it is retryable — see undo_authorization_test), but it
    # must still short-circuit before discovery either way.
    test "Undo of something unrelated to the inbox owner", %{alice: alice} do
      activity = %{
        "id" => activity_id(),
        "type" => "Undo",
        "actor" => "#{@remote}/users/unknown-undoer",
        "to" => ["#{@remote}/users/someone-else"],
        "object" => "#{@remote}/activities/#{Ecto.UUID.generate()}"
      }

      assert {:error, :target_unknown} =
               Pipeline.ingest(activity, local: false, inbox_user_ap_id: alice.ap_id)

      refute_enqueued(worker: FetchActor)
    end
  end

  describe "authorized activities still discover actors" do
    test "Follow aimed at the inbox owner enqueues the unknown follower", %{alice: alice} do
      follower = "#{@remote}/users/known-follower"

      activity = %{
        "id" => activity_id(),
        "type" => "Follow",
        "actor" => follower,
        "object" => alice.ap_id
      }

      assert {:ok, _} = Pipeline.ingest(activity, local: false, inbox_user_ap_id: alice.ap_id)

      assert_enqueued(worker: FetchActor, args: %{"ap_id" => follower})
    end

    # Public activities reach the shared inbox without an `inbox_user_ap_id`, so
    # targeting is permissive by design. Pinned so a future tightening of
    # InboxTargeting can't silently drop public federation traffic.
    test "an activity delivered without an inbox owner is not rejected" do
      author = "#{@remote}/users/public-author"

      activity = %{
        "id" => activity_id(),
        "type" => "Create",
        "actor" => author,
        "to" => ["https://www.w3.org/ns/activitystreams#Public"],
        "cc" => [],
        "object" => %{
          "id" => object_id(),
          "type" => "Note",
          "attributedTo" => author,
          "to" => ["https://www.w3.org/ns/activitystreams#Public"],
          "cc" => [],
          "content" => "hello world",
          "published" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      assert {:ok, _} = Pipeline.ingest(activity, local: false)

      assert_enqueued(worker: FetchActor, args: %{"ap_id" => author})
    end

    test "locally authored activities are unaffected", %{alice: alice} do
      assert {:ok, _} = Egregoros.Publish.post_note(alice, "a local post")

      # Discovery is a no-op for local activities; the new step must not change
      # that, nor reject them.
      refute_enqueued(worker: FetchActor)
    end
  end

  describe "activity modules keep their own guard" do
    # The pipeline authorizes before discovery, but each module also re-checks
    # inside ingest/2. That second check is the safety net for any path that
    # reaches a module directly, so it must not be deleted as redundant.
    test "ingest/2 rejects an untargeted activity on its own", %{alice: alice, bob: bob} do
      activity = %{
        "id" => activity_id(),
        "type" => "Follow",
        "actor" => "#{@remote}/users/unknown-follower",
        "object" => bob.ap_id
      }

      assert {:error, :not_targeted} =
               Follow.ingest(activity, local: false, inbox_user_ap_id: alice.ap_id)
    end
  end

  describe "the ingest worker discards untargeted activities" do
    test "without enqueueing discovery", %{alice: alice, bob: bob} do
      activity = %{
        "id" => activity_id(),
        "type" => "Follow",
        "actor" => "#{@remote}/users/unknown-follower",
        "object" => bob.ap_id
      }

      assert {:discard, :not_targeted} =
               perform_job(IngestActivity, %{
                 "activity" => activity,
                 "inbox_user_ap_id" => alice.ap_id
               })

      refute_enqueued(worker: FetchActor)
    end
  end
end
