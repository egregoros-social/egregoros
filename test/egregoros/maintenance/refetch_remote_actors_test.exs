defmodule Egregoros.Maintenance.RefetchRemoteActorsTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Maintenance.RefetchRemoteActors
  alias Egregoros.Users

  test "refetch/1 updates remote users with missing emoji metadata" do
    {:ok, user} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false,
        name: ":linux: Bob"
      })

    expect(Egregoros.HTTP.Mock, :get, fn _url, _headers ->
      {:ok,
       %{
         status: 200,
         body: %{
           "id" => user.ap_id,
           "type" => "Person",
           "preferredUsername" => "bob",
           "name" => ":linux: Bob",
           "tag" => [
             %{
               "type" => "Emoji",
               "name" => ":linux:",
               "icon" => %{"url" => "https://remote.example/emoji/linux.png"}
             }
           ],
           "inbox" => user.inbox,
           "outbox" => user.outbox,
           "publicKey" => %{
             "id" => user.ap_id <> "#main-key",
             "owner" => user.ap_id,
             "publicKeyPem" => user.public_key
           }
         },
         headers: []
       }}
    end)

    assert %{total: 1, ok: 1, error: 0} = RefetchRemoteActors.refetch()

    user = Users.get_by_ap_id(user.ap_id)

    assert %{"shortcode" => "linux", "url" => "https://remote.example/emoji/linux.png"} in user.emojis
  end

  test "refetch/1 skips remote users that already have emojis when only_missing_emojis is true" do
    {:ok, _user} =
      Users.create_user(%{
        nickname: "bob",
        ap_id: "https://remote.example/users/bob",
        inbox: "https://remote.example/users/bob/inbox",
        outbox: "https://remote.example/users/bob/outbox",
        public_key: "PUB",
        private_key: nil,
        local: false,
        name: ":linux: Bob",
        emojis: [%{shortcode: "linux", url: "https://remote.example/emoji/linux.png"}]
      })

    expect(Egregoros.HTTP.Mock, :get, 0, fn _url, _headers ->
      :ok
    end)

    assert %{total: 0, ok: 0, error: 0} = RefetchRemoteActors.refetch(only_missing_emojis: true)
  end
end
