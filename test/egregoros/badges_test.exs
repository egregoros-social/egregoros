defmodule Egregoros.BadgesTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.BadgeDefinition
  alias Egregoros.Activities.Accept
  alias Egregoros.Badges
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.Interactions
  alias Egregoros.Notifications
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Repo
  alias Egregoros.Users
  alias Egregoros.VerifiableCredentials.DidWeb
  alias Egregoros.Workers.DeliverActivity
  alias EgregorosWeb.Endpoint

  test "issue_badge/2 issues a badge offer to a local user" do
    {:ok, recipient} = Users.create_local_user("badge_issue_local")
    {:ok, badge} = insert_badge_definition("TestDonator")
    {:ok, instance_actor} = InstanceActor.get_actor()

    assert {:ok, %{offer: offer, credential: credential}} =
             Badges.issue_badge("TestDonator", recipient.ap_id)

    assert offer.type == "Offer"
    assert offer.actor == instance_actor.ap_id
    assert offer.object == credential.ap_id

    assert credential.type == "VerifiableCredential"
    assert credential.actor == instance_actor.ap_id
    assert credential.data["issuer"] == DidWeb.instance_did()
    assert credential.data["credentialSubject"]["id"] == recipient.ap_id
    refute Map.has_key?(credential.data, "proof")

    assert credential.data["credentialSubject"]["achievement"]["id"] ==
             Endpoint.url() <> "/badges/" <> badge.id

    assert Enum.any?(
             Notifications.list_for_user(recipient, include_offers?: true),
             &(&1.ap_id == offer.ap_id)
           )

    refute_enqueued(worker: DeliverActivity)
  end

  test "issue_badge/2 returns errors for invalid inputs" do
    {:ok, recipient} = Users.create_local_user("badge_issue_invalid_inputs")
    {:ok, _badge} = insert_badge_definition("TestInvalidInputs")

    assert {:error, :unknown_badge} = Badges.issue_badge("DoesNotExist", recipient.ap_id)

    assert {:error, :invalid_badge} = Badges.issue_badge(nil, recipient.ap_id)

    assert {:error, :invalid_badge} =
             Badges.issue_badge("TestInvalidInputs", recipient.ap_id, %{})

    assert {:error, :invalid_recipient} = Badges.issue_badge("TestInvalidInputs", " ")
  end

  test "issue_badge/2 returns an error for disabled badges" do
    {:ok, recipient} = Users.create_local_user("badge_issue_disabled")

    {:ok, _badge} =
      %BadgeDefinition{}
      |> BadgeDefinition.changeset(%{
        badge_type: "TestDisabled",
        name: "TestDisabled",
        description: "Disabled badge",
        narrative: "Disabled badge",
        disabled: true
      })
      |> Repo.insert()

    assert {:error, :disabled_badge} = Badges.issue_badge("TestDisabled", recipient.ap_id)
  end

  test "accepting a badge offer publicizes the credential and emits an Update" do
    {:ok, recipient} = Users.create_local_user("badge_issue_accept")
    {:ok, _badge} = insert_badge_definition("TestPublicize")
    {:ok, instance_actor} = InstanceActor.get_actor()

    assert {:ok, %{offer: offer, credential: credential}} =
             Badges.issue_badge("TestPublicize", recipient.ap_id)

    assert credential.data["to"] == [recipient.ap_id]

    assert {:ok, _accept_object} =
             Pipeline.ingest(Accept.build(recipient, offer), local: true)

    updated_credential = Objects.get_by_ap_id(credential.ap_id)
    assert %Egregoros.Object{} = updated_credential

    assert "https://www.w3.org/ns/activitystreams#Public" in updated_credential.data["to"]

    assert %{
             "proofValue" => proof_value,
             "cryptosuite" => "eddsa-jcs-2022",
             "verificationMethod" => verification_method
           } =
             updated_credential.data["proof"]

    assert is_binary(proof_value)
    assert verification_method == DidWeb.instance_did() <> "#ed25519-key"

    assert %Egregoros.Object{} =
             Objects.get_by_type_actor_object(
               "Update",
               instance_actor.ap_id,
               credential.ap_id
             )
  end

  test "list_definitions/1 can filter out disabled badges" do
    {:ok, _enabled} = insert_badge_definition("TestEnabledList")

    {:ok, _disabled} =
      %BadgeDefinition{}
      |> BadgeDefinition.changeset(%{
        badge_type: "TestDisabledList",
        name: "TestDisabledList",
        description: "Disabled badge",
        narrative: "Disabled badge",
        disabled: true
      })
      |> Repo.insert()

    definitions = Badges.list_definitions(include_disabled?: false)
    assert Enum.any?(definitions, &(&1.badge_type == "TestEnabledList"))
    refute Enum.any?(definitions, &(&1.badge_type == "TestDisabledList"))
  end

  test "issue_badge/2 delivers offers to remote recipients" do
    {:ok, badge} = insert_badge_definition("TestVIP")
    {:ok, instance_actor} = InstanceActor.get_actor()

    remote_ap_id = "https://remote.example/users/alice"
    remote_inbox = "https://remote.example/users/alice/inbox"
    remote_outbox = "https://remote.example/users/alice/outbox"

    expect(Egregoros.HTTP.Mock, :get, fn url, _headers ->
      assert url == remote_ap_id

      {:ok,
       %{
         status: 200,
         body: %{
           "id" => remote_ap_id,
           "type" => "Person",
           "preferredUsername" => "alice",
           "inbox" => remote_inbox,
           "outbox" => remote_outbox,
           "publicKey" => %{
             "id" => remote_ap_id <> "#main-key",
             "owner" => remote_ap_id,
             "publicKeyPem" => "-----BEGIN PUBLIC KEY-----\nMIIB\n-----END PUBLIC KEY-----"
           }
         },
         headers: []
       }}
    end)

    assert {:ok, %{offer: offer, credential: credential}} =
             Badges.issue_badge("TestVIP", remote_ap_id)

    assert offer.actor == instance_actor.ap_id

    assert credential.data["credentialSubject"]["achievement"]["id"] ==
             Endpoint.url() <> "/badges/" <> badge.id

    assert_enqueued(
      worker: DeliverActivity,
      args: %{
        "user_id" => instance_actor.id,
        "inbox_url" => remote_inbox,
        "activity" => %{
          "type" => "Offer",
          "object" => %{"id" => credential.ap_id}
        }
      }
    )
  end

  test "list_offers/1 returns pending offers and reflects accepted state" do
    {:ok, recipient} = Users.create_local_user("badge_offer_list_recipient")
    {:ok, _badge} = insert_badge_definition("TestOfferList")
    {:ok, %{offer: offer}} = Badges.issue_badge("TestOfferList", recipient.ap_id)

    pending_entry =
      Badges.list_offers()
      |> Enum.find(fn entry ->
        entry.offer.ap_id == offer.ap_id and entry.recipient_ap_id == recipient.ap_id
      end)

    assert pending_entry
    assert pending_entry.status == "Pending"
    assert pending_entry.badge_name == "TestOfferList"
    assert pending_entry.badge_description == "TestOfferList badge"

    assert {:ok, _accept_object} =
             Pipeline.ingest(Accept.build(recipient, offer), local: true)

    accepted_entry =
      Badges.list_offers()
      |> Enum.find(fn entry ->
        entry.offer.ap_id == offer.ap_id and entry.recipient_ap_id == recipient.ap_id
      end)

    assert accepted_entry
    assert accepted_entry.status == "Accepted"
  end

  test "update_definition/2 handles image url normalization and upload errors" do
    {:ok, badge} = insert_badge_definition("TestUpdateDefinition")

    assert {:ok, updated} =
             Badges.update_definition(badge, %{
               "image_url" => "   "
             })

    assert is_nil(updated.image_url)

    upload = %Plug.Upload{
      path: fixture_path("DSCN0010.png"),
      filename: "badge.png",
      content_type: "image/png"
    }

    {:ok, instance_actor} = InstanceActor.get_actor()

    expect(Egregoros.MediaStorage.Mock, :store_media, fn ^instance_actor,
                                                         %Plug.Upload{filename: "badge.png"} ->
      {:error, :upload_failed}
    end)

    assert {:error, :upload_failed} = Badges.update_definition(badge, %{"image" => upload})
    assert {:error, :invalid_badge} = Badges.update_definition(nil, %{})
  end

  test "badge_share_flash_message/2 reports sharing state for verifiable credentials" do
    {:ok, user} = Users.create_local_user("badge_share_user")

    credential = %{
      "id" => "https://remote.example/credentials/" <> Ecto.UUID.generate(),
      "type" => "VerifiableCredential",
      "issuer" => "https://remote.example/users/issuer",
      "to" => [user.ap_id],
      "credentialSubject" => %{
        "id" => user.ap_id,
        "achievement" => %{
          "id" => "https://remote.example/badges/" <> Ecto.UUID.generate(),
          "type" => "Achievement",
          "name" => "Donator"
        }
      }
    }

    {:ok, credential_object} =
      Pipeline.ingest(credential, local: false, inbox_user_ap_id: user.ap_id)

    assert Badges.badge_share_flash_message(user, credential_object.id) == "Badge unshared."

    assert {:ok, _} = Interactions.toggle_repost(user, credential_object.id)
    assert Badges.badge_share_flash_message(user, credential_object.id) == "Badge shared."

    assert {:ok, _} = Interactions.toggle_repost(user, credential_object.id)
    assert Badges.badge_share_flash_message(user, credential_object.id) == "Badge unshared."
  end

  test "badge_share_flash_message/2 returns nil for non-credential objects" do
    {:ok, user} = Users.create_local_user("badge_share_non_credential")

    assert is_nil(Badges.badge_share_flash_message(user, "invalid"))
  end

  defp insert_badge_definition(badge_type) do
    %BadgeDefinition{}
    |> BadgeDefinition.changeset(%{
      badge_type: badge_type,
      name: badge_type,
      description: "#{badge_type} badge",
      narrative: "Issued for #{badge_type}",
      disabled: false
    })
    |> Repo.insert()
  end

  defp fixture_path(filename) do
    Path.expand(Path.join(["test", "fixtures", filename]), File.cwd!())
  end
end
