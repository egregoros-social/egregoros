defmodule PleromaRedux.Activities.LikeCastAndValidateTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.Activities.Like

  test "normalizes actor and object ids from embedded maps" do
    activity = %{
      "id" => "https://example.com/activities/like/1",
      "type" => "Like",
      "actor" => %{"id" => "https://example.com/users/alice"},
      "object" => %{"id" => "https://example.com/objects/1"}
    }

    assert {:ok, validated} = Like.cast_and_validate(activity)
    assert validated["actor"] == "https://example.com/users/alice"
    assert validated["object"] == "https://example.com/objects/1"
  end
end

