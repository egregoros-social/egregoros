defmodule PleromaRedux.Compat.UpstreamFixturesTest do
  use PleromaRedux.DataCase, async: true

  alias PleromaRedux.Objects
  alias PleromaRedux.Pipeline
  alias PleromaRedux.Relationships
  alias PleromaRedux.TestSupport.Fixtures

  test "ingests a Follow activity with an inline actor object (hubzilla)" do
    activity = Fixtures.json!("hubzilla-follow-activity.json")

    assert {:ok, follow} = Pipeline.ingest(activity, local: false)
    assert follow.type == "Follow"
    assert follow.actor == activity["actor"]["id"]
    assert follow.object == activity["object"]

    assert Relationships.get_by_type_actor_object("Follow", follow.actor, follow.object)
  end

  test "ingests a Create activity with an inline actor object (kroeg)" do
    activity = Fixtures.json!("kroeg-post-activity.json")

    assert {:ok, create} = Pipeline.ingest(activity, local: false)
    assert create.type == "Create"
    assert create.actor == activity["actor"]["id"]

    note = Objects.get_by_ap_id(create.object)
    assert %{} = note
    assert note.type == "Note"
    assert is_binary(note.data["content"])
  end

  test "ingests an Accept activity with an embedded Follow object (mastodon)" do
    activity = Fixtures.json!("mastodon-accept-activity.json")

    assert {:ok, accept} = Pipeline.ingest(activity, local: false)
    assert accept.type == "Accept"
    assert accept.actor == activity["actor"]
    assert accept.object == activity["object"]["id"]
  end

  test "ingests an Announce activity with an embedded Note object (mastodon)" do
    activity = Fixtures.json!("bogus-mastodon-announce.json")

    assert {:ok, announce} = Pipeline.ingest(activity, local: false)
    assert announce.type == "Announce"
    assert announce.actor == activity["actor"]
    assert announce.object == activity["object"]["id"]

    note = Objects.get_by_ap_id(activity["object"]["id"])
    assert %{} = note
    assert note.type == "Note"
  end

  test "ingests an Announce activity with inline actor and embedded Note attributedTo object (kroeg)" do
    activity = Fixtures.json!("kroeg-announce-with-inline-actor.json")

    assert {:ok, announce} = Pipeline.ingest(activity, local: false)
    assert announce.type == "Announce"
    assert announce.actor == activity["actor"]["id"]
    assert announce.object == activity["object"]["id"]

    note = Objects.get_by_ap_id(activity["object"]["id"])
    assert %{} = note
    assert note.type == "Note"
    assert note.actor == activity["object"]["attributedTo"]["id"]
  end

  test "ingests an Undo activity with embedded Like object and removes relationship state (mastodon)" do
    like = Fixtures.json!("mastodon-like.json")
    undo = Fixtures.json!("mastodon-undo-like.json")

    assert {:ok, like_object} = Pipeline.ingest(like, local: false)
    assert like_object.type == "Like"

    assert Relationships.get_by_type_actor_object("Like", like_object.actor, like_object.object)

    assert {:ok, _undo_object} = Pipeline.ingest(undo, local: false)

    assert Relationships.get_by_type_actor_object("Like", like_object.actor, like_object.object) ==
             nil
  end

  test "ingests an EmojiReact activity and creates an emoji relationship state (mastodon)" do
    activity = Fixtures.json!("emoji-reaction.json")

    assert {:ok, react} = Pipeline.ingest(activity, local: false)
    assert react.type == "EmojiReact"

    assert Relationships.get_by_type_actor_object(
             "EmojiReact:" <> activity["content"],
             activity["actor"],
             activity["object"]
           )
  end
end
