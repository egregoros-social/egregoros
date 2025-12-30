defmodule Egregoros.RelaysTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.Follow
  alias Egregoros.Federation.InternalFetchActor
  alias Egregoros.Pipeline
  alias Egregoros.Relay
  alias Egregoros.Relationships
  alias Egregoros.Relays
  alias Egregoros.Repo
  alias Egregoros.Users

  test "incoming Reject of a relay follow removes the relay subscription" do
    {:ok, internal} = InternalFetchActor.get_actor()

    {:ok, relay_user} =
      Users.create_user(%{
        nickname: "relay",
        ap_id: "https://relay.example/actor",
        inbox: "https://relay.example/inbox",
        outbox: "https://relay.example/outbox",
        public_key: "remote-key",
        private_key: nil,
        local: false
      })

    assert {:ok, follow_object} = Pipeline.ingest(Follow.build(internal, relay_user), local: true)

    assert Relationships.get_by_type_actor_object(
             "FollowRequest",
             internal.ap_id,
             relay_user.ap_id
           )

    assert {:ok, _relay} =
             %Relay{}
             |> Relay.changeset(%{ap_id: relay_user.ap_id})
             |> Repo.insert()

    assert Relays.subscribed?(relay_user.ap_id)

    reject = %{
      "id" => "https://relay.example/activities/reject/1",
      "type" => "Reject",
      "actor" => relay_user.ap_id,
      "object" => follow_object.data
    }

    assert {:ok, _} =
             Pipeline.ingest(reject,
               local: false,
               inbox_user_ap_id: internal.ap_id
             )

    assert Relationships.get_by_type_actor_object(
             "FollowRequest",
             internal.ap_id,
             relay_user.ap_id
           ) ==
             nil

    assert Relationships.get_by_type_actor_object("Follow", internal.ap_id, relay_user.ap_id) ==
             nil

    refute Relays.subscribed?(relay_user.ap_id)
  end
end
