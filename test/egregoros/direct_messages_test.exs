defmodule Egregoros.DirectMessagesTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.DirectMessages
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Users

  test "list_for_user includes direct messages addressed via bto/bcc/audience" do
    {:ok, alice} = Users.create_local_user("alice")

    assert {:ok, %Object{} = dm_bcc} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/dm-bcc",
               type: "Note",
               actor: "https://remote.example/users/bob",
               object: nil,
               local: false,
               data: %{
                 "id" => "https://remote.example/objects/dm-bcc",
                 "type" => "Note",
                 "actor" => "https://remote.example/users/bob",
                 "to" => [],
                 "cc" => [],
                 "bcc" => [alice.ap_id],
                 "content" => "secret"
               }
             })

    assert {:ok, %Object{} = dm_audience} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/dm-audience",
               type: "Note",
               actor: "https://remote.example/users/bob",
               object: nil,
               local: false,
               data: %{
                 "id" => "https://remote.example/objects/dm-audience",
                 "type" => "Note",
                 "actor" => "https://remote.example/users/bob",
                 "to" => [],
                 "cc" => [],
                 "audience" => [alice.ap_id],
                 "content" => "secret"
               }
             })

    messages = DirectMessages.list_for_user(alice)
    assert Enum.any?(messages, &(&1.id == dm_bcc.id))
    assert Enum.any?(messages, &(&1.id == dm_audience.id))
  end
end
