defmodule PleromaRedux.Activities.DeleteCastAndValidateTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.Activities.Delete

  test "normalizes an embedded object id map" do
    activity = %{
      "id" => "https://example.com/activities/delete/1",
      "type" => "Delete",
      "actor" => %{"id" => "https://example.com/users/alice"},
      "object" => %{"id" => "https://example.com/objects/1"}
    }

    assert {:ok, validated} = Delete.cast_and_validate(activity)
    assert validated["actor"] == "https://example.com/users/alice"
    assert validated["object"] == "https://example.com/objects/1"
  end
end

