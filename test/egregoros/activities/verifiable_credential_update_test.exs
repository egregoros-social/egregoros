defmodule Egregoros.Activities.VerifiableCredentialUpdateTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Activities.Update
  alias Egregoros.BadgeDefinition
  alias Egregoros.Badges
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.Keys
  alias Egregoros.Objects
  alias Egregoros.Pipeline
  alias Egregoros.Repo
  alias Egregoros.Users
  alias Egregoros.VerifiableCredentials.AssertionMethod
  alias Egregoros.VerifiableCredentials.DataIntegrity
  alias Egregoros.VerifiableCredentials.DidWeb
  alias Egregoros.Activities.VerifiableCredential

  @public "https://www.w3.org/ns/activitystreams#Public"

  test "accepts an Update that only adds Public to the credential recipients" do
    {:ok, recipient} = Users.create_local_user("vc_update_recipient")
    {:ok, _badge} = insert_badge_definition("UpdatePublic")
    {:ok, instance_actor} = InstanceActor.get_actor()

    assert {:ok, %{credential: credential}} =
             Badges.issue_badge("UpdatePublic", recipient.ap_id)

    assert credential.data["to"] == [recipient.ap_id]

    updated_credential =
      credential.data
      |> Map.put("to", [recipient.ap_id, @public])

    update_activity = Update.build(instance_actor, updated_credential)

    assert {:ok, _update_object} = Pipeline.ingest(update_activity, local: true)

    stored_credential = Objects.get_by_ap_id(credential.ap_id)
    assert @public in stored_credential.data["to"]
  end

  test "accepts an Update that adds a cryptographic proof alongside Public" do
    {:ok, recipient} = Users.create_local_user("vc_update_proof_recipient")
    {:ok, _badge} = insert_badge_definition("UpdateWithProof")
    {:ok, instance_actor} = InstanceActor.get_actor()

    assert {:ok, %{credential: credential}} =
             Badges.issue_badge("UpdateWithProof", recipient.ap_id)

    updated_credential =
      credential.data
      |> Map.put("to", [recipient.ap_id, @public])

    verification_method = DidWeb.instance_did() <> "#ed25519-key"

    assert {:ok, signed_credential} =
             DataIntegrity.attach_proof(updated_credential, instance_actor.ed25519_private_key, %{
               "verificationMethod" => verification_method,
               "proofPurpose" => "assertionMethod"
             })

    update_activity = Update.build(instance_actor, signed_credential)

    assert {:ok, _update_object} = Pipeline.ingest(update_activity, local: true)

    stored_credential = Objects.get_by_ap_id(credential.ap_id)
    assert @public in stored_credential.data["to"]
    assert stored_credential.data["proof"] == signed_credential["proof"]
  end

  test "rejects an Update that changes credential content beyond adding Public" do
    {:ok, recipient} = Users.create_local_user("vc_update_invalid_recipient")
    {:ok, _badge} = insert_badge_definition("UpdateInvalid")
    {:ok, instance_actor} = InstanceActor.get_actor()

    assert {:ok, %{credential: credential}} =
             Badges.issue_badge("UpdateInvalid", recipient.ap_id)

    mutated_credential =
      credential.data
      |> Map.put("to", [recipient.ap_id, @public])
      |> put_in(["credentialSubject", "achievement", "description"], "Tampered")

    update_activity = Update.build(instance_actor, mutated_credential)

    assert {:error, :invalid} = Pipeline.ingest(update_activity, local: true)

    stored_credential = Objects.get_by_ap_id(credential.ap_id)
    assert stored_credential.data["credentialSubject"]["achievement"]["description"] != "Tampered"
    refute @public in stored_credential.data["to"]
  end

  test "accepts a remote Update when the embedded proof is valid" do
    {:ok, recipient} = Users.create_local_user("vc_update_remote_recipient_valid")
    {:ok, badge} = insert_badge_definition("RemoteUpdateValid")

    {public_key, private_key} = Keys.generate_ed25519_keypair()
    {:ok, remote_user} = create_remote_user("remote_issuer_valid", public_key)

    {:ok, %Egregoros.Object{} = credential} =
      insert_remote_credential(badge, remote_user.ap_id, recipient.ap_id)

    updated_credential =
      credential.data
      |> Map.put("to", [recipient.ap_id, @public])

    verification_method = remote_user.ap_id <> "#ed25519-key"

    assert {:ok, signed_credential} =
             DataIntegrity.attach_proof(updated_credential, private_key, %{
               "verificationMethod" => verification_method,
               "proofPurpose" => "assertionMethod"
             })

    update_activity =
      Update.build(remote_user.ap_id, signed_credential)
      |> Map.put("id", remote_activity_id(remote_user.ap_id))

    assert {:ok, _update_object} = Pipeline.ingest(update_activity, local: false)

    stored_credential = Objects.get_by_ap_id(credential.ap_id)
    assert @public in stored_credential.data["to"]
    assert stored_credential.data["proof"] == signed_credential["proof"]
  end

  test "accepts a remote Update when the embedded proof uses did:web verification" do
    {:ok, recipient} = Users.create_local_user("vc_update_remote_recipient_did")
    {:ok, badge} = insert_badge_definition("RemoteUpdateDid")

    did = "did:web:remote.example"

    {public_key, private_key} = Keys.generate_ed25519_keypair()

    {:ok, remote_user} = create_remote_user("did_issuer", public_key)
    actor_ap_id = remote_user.ap_id

    {:ok, %Egregoros.Object{} = credential} =
      insert_remote_credential(badge, did, recipient.ap_id)

    updated_credential =
      credential.data
      |> Map.put("to", [recipient.ap_id, @public])
      |> Map.put("issuer", did)

    verification_method = did <> "#ed25519-key"

    assert {:ok, signed_credential} =
             DataIntegrity.attach_proof(updated_credential, private_key, %{
               "verificationMethod" => verification_method,
               "proofPurpose" => "assertionMethod"
             })

    did_document = %{
      "@context" => [
        "https://www.w3.org/ns/did/v1",
        "https://w3id.org/security/data-integrity/v2"
      ],
      "id" => did,
      "alsoKnownAs" => [actor_ap_id],
      "verificationMethod" => [
        %{
          "id" => verification_method,
          "type" => "Multikey",
          "controller" => did,
          "publicKeyMultibase" => DidWeb.public_key_multibase(public_key)
        }
      ],
      "assertionMethod" => [verification_method]
    }

    expect(Egregoros.HTTP.Mock, :get, 3, fn url, _headers ->
      assert url == "https://remote.example/.well-known/did.json"

      {:ok,
       %{
         status: 200,
         body: did_document,
         headers: []
       }}
    end)

    update_activity =
      Update.build(actor_ap_id, signed_credential)
      |> Map.put("id", remote_activity_id(actor_ap_id))

    assert {:ok, _update_object} = Pipeline.ingest(update_activity, local: false)

    stored_credential = Objects.get_by_ap_id(credential.ap_id)
    assert @public in stored_credential.data["to"]
    assert stored_credential.data["proof"] == signed_credential["proof"]
  end

  test "rejects a remote Update when the embedded proof is invalid" do
    {:ok, recipient} = Users.create_local_user("vc_update_remote_recipient_invalid")
    {:ok, badge} = insert_badge_definition("RemoteUpdateInvalid")

    {public_key, _private_key} = Keys.generate_ed25519_keypair()
    {:ok, remote_user} = create_remote_user("remote_issuer_invalid", public_key)

    {:ok, %Egregoros.Object{} = credential} =
      insert_remote_credential(badge, remote_user.ap_id, recipient.ap_id)

    updated_credential =
      credential.data
      |> Map.put("to", [recipient.ap_id, @public])

    {_wrong_public, wrong_private} = Keys.generate_ed25519_keypair()
    verification_method = remote_user.ap_id <> "#ed25519-key"

    assert {:ok, signed_credential} =
             DataIntegrity.attach_proof(updated_credential, wrong_private, %{
               "verificationMethod" => verification_method,
               "proofPurpose" => "assertionMethod"
             })

    update_activity =
      Update.build(remote_user.ap_id, signed_credential)
      |> Map.put("id", remote_activity_id(remote_user.ap_id))

    assert {:error, :invalid} = Pipeline.ingest(update_activity, local: false)

    stored_credential = Objects.get_by_ap_id(credential.ap_id)
    refute @public in stored_credential.data["to"]
    refute Map.has_key?(stored_credential.data, "proof")
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

  defp create_remote_user(nickname, ed25519_public_key)
       when is_binary(nickname) and is_binary(ed25519_public_key) do
    {public_key, _private_key} = Keys.generate_rsa_keypair()
    ap_id = "https://remote.example/users/" <> nickname

    with {:ok, assertion_method} <-
           AssertionMethod.from_ed25519_public_key(ap_id, ed25519_public_key) do
      Users.create_user(%{
        nickname: nickname,
        ap_id: ap_id,
        inbox: ap_id <> "/inbox",
        outbox: ap_id <> "/outbox",
        public_key: public_key,
        local: false,
        assertion_method: assertion_method
      })
    end
  end

  defp insert_remote_credential(%BadgeDefinition{} = badge, issuer_ap_id, recipient_ap_id)
       when is_binary(issuer_ap_id) and is_binary(recipient_ap_id) do
    credential_id = "https://remote.example/objects/" <> Ecto.UUID.generate()

    credential =
      badge
      |> VerifiableCredential.build_for_badge(issuer_ap_id, recipient_ap_id)
      |> Map.put("id", credential_id)
      |> Map.put("issuer", issuer_ap_id)

    Pipeline.ingest(credential, local: false, skip_inbox_target: true)
  end

  defp remote_activity_id(actor_ap_id) when is_binary(actor_ap_id) do
    base =
      actor_ap_id
      |> String.split("/users/", parts: 2)
      |> List.first()

    base <> "/activities/update/" <> Ecto.UUID.generate()
  end
end
