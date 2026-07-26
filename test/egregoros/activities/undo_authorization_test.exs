defmodule Egregoros.Activities.UndoAuthorizationTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.Undo
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Publish
  alias Egregoros.Relationships
  alias Egregoros.Users
  alias Egregoros.Workers.IngestActivity

  test "does not undo state when actor does not match the target activity actor" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, eve} = Users.create_local_user("eve")

    follow = %{
      "id" => "https://example.com/activities/follow/1",
      "type" => "Follow",
      "actor" => alice.ap_id,
      "object" => bob.ap_id
    }

    assert {:ok, follow_object} = Pipeline.ingest(follow, local: true)
    assert Relationships.get_by_type_actor_object("Follow", alice.ap_id, bob.ap_id)

    undo = %{
      "id" => "https://example.com/activities/undo/1",
      "type" => "Undo",
      "actor" => eve.ap_id,
      "object" => follow_object.ap_id
    }

    assert {:ok, _undo_object} = Pipeline.ingest(undo, local: false)

    assert Relationships.get_by_type_actor_object("Follow", alice.ap_id, bob.ap_id)
    assert Objects.get_by_ap_id(follow_object.ap_id)
  end

  describe "an Undo whose target activity we do not hold" do
    setup do
      {:ok, alice} = Users.create_local_user("alice")
      {:ok, bob} = Users.create_local_user("bob")

      %{alice: alice, bob: bob}
    end

    defp like_of(object_ap_id, actor) do
      %{
        "id" => "https://remote.example/activities/like/#{Ecto.UUID.generate()}",
        "type" => "Like",
        "actor" => actor,
        "object" => object_ap_id
      }
    end

    defp undo_of(like_ap_id, actor) do
      %{
        "id" => "https://remote.example/activities/undo/#{Ecto.UUID.generate()}",
        "type" => "Undo",
        "actor" => actor,
        "object" => like_ap_id
      }
    end

    # A remote actor the local user does not follow Likes a local post, then
    # Undoes it. Mastodon's Undo of a Like carries no to/cc, so authorization
    # depends entirely on us already holding the Like. Both arrive as separate
    # jobs on a queue with concurrency 10, so the Undo can run first.
    test "is retryable rather than rejected", %{alice: alice} do
      liker = "https://remote.example/users/liker"
      {:ok, create} = Publish.post_note(alice, "a local post")

      undo = undo_of(like_of(create.object, liker)["id"], liker)

      assert {:error, :target_unknown} =
               Undo.authorize_inbox(undo, local: false, inbox_user_ap_id: alice.ap_id)

      assert {:error, :target_unknown} =
               Pipeline.ingest(undo, local: false, inbox_user_ap_id: alice.ap_id)
    end

    # {:error, _} keeps the job for another attempt. {:discard, _} would lose the
    # unlike permanently and leave a stale Like on the post forever.
    test "is retried by the ingest worker", %{alice: alice} do
      liker = "https://remote.example/users/liker"
      {:ok, create} = Publish.post_note(alice, "a local post")

      undo = undo_of(like_of(create.object, liker)["id"], liker)

      assert {:error, :target_unknown} =
               perform_job(IngestActivity, %{
                 "activity" => undo,
                 "inbox_user_ap_id" => alice.ap_id
               })
    end

    test "is authorized once the target Like has arrived", %{alice: alice} do
      liker = "https://remote.example/users/liker"
      {:ok, create} = Publish.post_note(alice, "a local post")

      like = like_of(create.object, liker)
      assert {:ok, _} = Pipeline.ingest(like, local: false, inbox_user_ap_id: alice.ap_id)

      undo = undo_of(like["id"], liker)

      assert :ok = Undo.authorize_inbox(undo, local: false, inbox_user_ap_id: alice.ap_id)
    end

    # We hold the target, so there is nothing to wait for: this Undo is simply
    # not ours, and must stay a permanent rejection.
    test "stays rejected when we hold a target that is not ours", %{alice: alice, bob: bob} do
      liker = "https://remote.example/users/liker"
      {:ok, create} = Publish.post_note(bob, "bob's post")

      like = like_of(create.object, liker)
      assert {:ok, _} = Pipeline.ingest(like, local: false, inbox_user_ap_id: bob.ap_id)

      undo = undo_of(like["id"], liker)

      assert {:error, :not_targeted} =
               Undo.authorize_inbox(undo, local: false, inbox_user_ap_id: alice.ap_id)
    end
  end
end
