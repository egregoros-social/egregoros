defmodule Egregoros.Activities.EncryptedMessageRemovedTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.ActivityRegistry
  alias Egregoros.Pipeline
  alias Egregoros.Users

  test "EncryptedMessage is not a known activity type" do
    assert {:ok, Egregoros.Activities.Note} = ActivityRegistry.fetch("Note")
    assert {:error, :unknown_type} = ActivityRegistry.fetch("EncryptedMessage")
  end

  test "EncryptedMessage objects are not ingested" do
    {:ok, alice} = Users.create_local_user("alice")
    {:ok, bob} = Users.create_local_user("bob")

    msg = %{
      "id" => "https://example.com/objects/" <> Ecto.UUID.generate(),
      "type" => "EncryptedMessage",
      "attributedTo" => alice.ap_id,
      "to" => [bob.ap_id],
      "content" => "Encrypted message",
      "published" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "egregoros:e2ee_dm" => %{"version" => 1, "ciphertext" => "abc"}
    }

    assert {:error, :unknown_type} = Pipeline.ingest(msg, local: true)
  end
end
