defmodule PleromaRedux.Activities.AcceptCastAndValidateTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.Activities.Accept
  alias PleromaRedux.TestSupport.PleromaOldFixtures

  test "accepts an embedded Follow object (mastodon fixture)" do
    activity = PleromaOldFixtures.json!("mastodon-accept-activity.json")

    assert {:ok, validated} = Accept.cast_and_validate(activity)
    assert validated["actor"] == activity["actor"]
    assert is_map(validated["object"])
    assert validated["object"]["id"] == activity["object"]["id"]
  end
end

