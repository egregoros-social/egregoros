defmodule Egregoros.MentionsTest do
  use ExUnit.Case, async: true

  alias Egregoros.Mentions

  test "extracts mentions preceded by punctuation" do
    assert Mentions.extract("hi (@alice)") == [{"alice", nil}]
  end

  test "extracts multiple mentions within a single token" do
    mentions = Mentions.extract("hi (@alice,@bob@example.com)")

    assert MapSet.new(mentions) ==
             MapSet.new([
               {"alice", nil},
               {"bob", "example.com"}
             ])
  end

  test "extracts remote mentions with non-default ports" do
    assert Mentions.extract("hi (@bob@example.com:8443)") == [{"bob", "example.com:8443"}]
  end

  test "does not extract mentions from profile URLs" do
    assert Mentions.extract("see https://example.com/@alice") == []
  end
end
