defmodule PleromaRedux.Activities.EmojiReactCastAndValidateTest do
  use ExUnit.Case, async: true

  alias PleromaRedux.Activities.EmojiReact

  test "normalizes actor/object ids and trims content" do
    activity = %{
      "id" => "https://example.com/activities/react/1",
      "type" => "EmojiReact",
      "actor" => %{"id" => "https://example.com/users/alice"},
      "object" => %{"id" => "https://example.com/objects/1"},
      "content" => "  :fire:  "
    }

    assert {:ok, validated} = EmojiReact.cast_and_validate(activity)
    assert validated["actor"] == "https://example.com/users/alice"
    assert validated["object"] == "https://example.com/objects/1"
    assert validated["content"] == ":fire:"
  end

  test "rejects blank content" do
    activity = %{
      "id" => "https://example.com/activities/react/1",
      "type" => "EmojiReact",
      "actor" => "https://example.com/users/alice",
      "object" => "https://example.com/objects/1",
      "content" => "   "
    }

    assert {:error, %Ecto.Changeset{}} = EmojiReact.cast_and_validate(activity)
  end
end

