defmodule PleromaRedux.Activities.AnnounceCastAndValidateTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.Activities.Announce
  alias PleromaRedux.TestSupport.PleromaOldFixtures

  test "accepts an embedded Note object (mastodon fixture)" do
    activity = PleromaOldFixtures.json!("bogus-mastodon-announce.json")

    assert {:ok, validated} = Announce.cast_and_validate(activity)
    assert validated["actor"] == activity["actor"]
    assert is_map(validated["object"])
    assert validated["object"]["id"] == activity["object"]["id"]
  end

  test "normalizes an inline actor object id (kroeg fixture)" do
    activity = PleromaOldFixtures.json!("kroeg-announce-with-inline-actor.json")

    assert {:ok, validated} = Announce.cast_and_validate(activity)
    assert validated["actor"] == activity["actor"]["id"]
    assert is_map(validated["object"])
    assert validated["object"]["id"] == activity["object"]["id"]
  end
end

