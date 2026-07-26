defmodule Egregoros.DirectMessagesTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.DirectMessages
  alias Egregoros.Object
  alias Egregoros.Objects
  alias Egregoros.Users

  @as_public "https://www.w3.org/ns/activitystreams#Public"

  test "list_for_user excludes EncryptedMessage objects" do
    {:ok, alice} = Users.create_local_user("alice")

    actor = "https://remote.example/users/bob"

    assert {:ok, %Object{} = dm} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/encrypted-dm",
               type: "EncryptedMessage",
               actor: actor,
               object: nil,
               local: false,
               data: %{
                 "id" => "https://remote.example/objects/encrypted-dm",
                 "type" => "EncryptedMessage",
                 "actor" => actor,
                 "to" => [alice.ap_id],
                 "cc" => [],
                 "content" => "Encrypted message"
               }
             })

    messages = DirectMessages.list_for_user(alice)
    refute Enum.any?(messages, &(&1.id == dm.id))
  end

  test "list_for_user includes notes carrying a legacy egregoros:e2ee_dm payload" do
    {:ok, alice} = Users.create_local_user("alice")

    actor = "https://remote.example/users/bob"

    assert {:ok, %Object{} = dm} =
             Objects.create_object(%{
               ap_id: "https://remote.example/objects/legacy-e2ee-dm",
               type: "Note",
               actor: actor,
               object: nil,
               local: false,
               data: %{
                 "id" => "https://remote.example/objects/legacy-e2ee-dm",
                 "type" => "Note",
                 "actor" => actor,
                 "to" => [alice.ap_id],
                 "cc" => [],
                 "content" => "Encrypted message",
                 "egregoros:e2ee_dm" => %{
                   "version" => 1,
                   "alg" => "ECDH-P256+HKDF-SHA256+AES-256-GCM",
                   "ciphertext" => "ciphertext"
                 }
               }
             })

    messages = DirectMessages.list_for_user(alice)
    assert Enum.any?(messages, &(&1.id == dm.id))
  end

  test "list_conversation returns only messages between the user and the peer" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")
    {:ok, carol} = Users.create_local_user("carol")

    received =
      create_note!("https://remote.example/objects/dm-from-bob", bob.ap_id, %{
        "to" => [alice.ap_id],
        "content" => "hi alice"
      })

    sent =
      create_note!("https://example.com/objects/dm-to-bob", alice.ap_id, %{
        "to" => [bob.ap_id],
        "content" => "hi bob"
      })

    _other =
      create_note!("https://example.com/objects/dm-to-carol", alice.ap_id, %{
        "to" => [carol.ap_id],
        "content" => "hi carol"
      })

    assert [^sent, ^received] = DirectMessages.list_conversation(alice, bob.ap_id)
  end

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

  test "list_for_user excludes public and followers-only notes even when addressed to you" do
    {:ok, alice} = Users.create_local_user("alice")

    bob = "https://remote.example/users/bob"

    public =
      create_note!("https://remote.example/objects/public", bob, %{
        "to" => [alice.ap_id, @as_public],
        "content" => "public"
      })

    followers_only =
      create_note!("https://remote.example/objects/followers", bob, %{
        "to" => [bob <> "/followers", alice.ap_id],
        "content" => "followers"
      })

    direct =
      create_note!("https://remote.example/objects/direct", bob, %{
        "to" => [alice.ap_id],
        "content" => "dm"
      })

    messages = DirectMessages.list_for_user(alice)
    assert Enum.any?(messages, &(&1.id == direct.id))
    refute Enum.any?(messages, &(&1.id == public.id))
    refute Enum.any?(messages, &(&1.id == followers_only.id))
  end

  test "list_for_user normalizes limits" do
    {:ok, alice} = Users.create_local_user("alice")

    bob = "https://remote.example/users/bob"

    _one = create_note!("https://remote.example/objects/dm-1", bob, %{"bcc" => [alice.ap_id]})
    _two = create_note!("https://remote.example/objects/dm-2", bob, %{"bcc" => [alice.ap_id]})

    assert length(DirectMessages.list_for_user(alice, limit: 0)) == 1
    assert length(DirectMessages.list_for_user(alice, limit: "1")) == 1

    # Invalid limit strings fall back to the default and must not crash.
    assert length(DirectMessages.list_for_user(alice, limit: "not-a-number")) == 2
  end

  test "list_for_user supports max_id and since_id filters (including string ids)" do
    {:ok, alice} = Users.create_local_user("alice")

    bob = "https://remote.example/users/bob"

    oldest = create_note!("https://remote.example/objects/oldest", bob, %{"bcc" => [alice.ap_id]})
    middle = create_note!("https://remote.example/objects/middle", bob, %{"bcc" => [alice.ap_id]})
    newest = create_note!("https://remote.example/objects/newest", bob, %{"bcc" => [alice.ap_id]})

    assert [^newest, ^middle, ^oldest] = DirectMessages.list_for_user(alice)

    assert DirectMessages.list_for_user(alice, max_id: middle.id) == [oldest]
    assert DirectMessages.list_for_user(alice, max_id: "  #{middle.id}  ") == [oldest]

    assert DirectMessages.list_for_user(alice, since_id: middle.id) == [newest]
    assert DirectMessages.list_for_user(alice, since_id: "  #{middle.id}  ") == [newest]
  end

  test "direct?/1 returns true only when not public and not followers-only" do
    actor = "https://remote.example/users/bob"

    assert DirectMessages.direct?(%Object{
             actor: actor,
             data: %{"to" => ["https://example.org/users/alice"]}
           })

    refute DirectMessages.direct?(%Object{
             actor: actor,
             data: %{"to" => [@as_public]}
           })

    refute DirectMessages.direct?(%Object{
             actor: actor,
             data: %{"to" => [actor <> "/followers"]}
           })
  end

  defp create_note!(ap_id, actor, data_overrides) when is_binary(ap_id) and is_binary(actor) do
    {:ok, %Object{} = object} =
      Objects.create_object(%{
        ap_id: ap_id,
        type: "Note",
        actor: actor,
        object: nil,
        local: false,
        data:
          %{
            "id" => ap_id,
            "type" => "Note",
            "actor" => actor,
            "to" => [],
            "cc" => [],
            "content" => "secret"
          }
          |> Map.merge(data_overrides)
      })

    object
  end
end
