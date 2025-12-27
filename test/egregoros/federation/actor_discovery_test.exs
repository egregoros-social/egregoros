defmodule Egregoros.Federation.ActorDiscoveryTest do
  use ExUnit.Case, async: true

  alias Egregoros.Federation.ActorDiscovery

  test "actor_ids extracts actor ids from actors, recipients, and mention tags" do
    activity = %{
      "actor" => "https://remote.example/users/alice",
      "attributedTo" => "https://remote.example/users/alice",
      "to" => [
        "https://www.w3.org/ns/activitystreams#Public",
        "https://remote.example/users/carol"
      ],
      "cc" => [
        "https://remote.example/users/alice/followers",
        "https://remote.example/users/dave"
      ],
      "tag" => [
        %{
          "type" => "Mention",
          "href" => "https://remote2.example/users/bob",
          "name" => "@bob@remote2.example"
        },
        %{
          "type" => "Hashtag",
          "href" => "https://remote.example/tags/test",
          "name" => "#test"
        }
      ]
    }

    assert Enum.sort(ActorDiscovery.actor_ids(activity)) ==
             Enum.sort([
               "https://remote.example/users/alice",
               "https://remote.example/users/carol",
               "https://remote.example/users/dave",
               "https://remote2.example/users/bob"
             ])
  end
end
