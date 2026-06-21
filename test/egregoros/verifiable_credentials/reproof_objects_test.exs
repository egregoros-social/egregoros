defmodule Egregoros.VerifiableCredentials.ReproofObjectsTest do
  use Egregoros.DataCase, async: true

  alias Egregoros.Object
  alias Egregoros.Repo
  alias Egregoros.Users
  alias Egregoros.Federation.InstanceActor
  alias Egregoros.VerifiableCredentials.DidWeb
  alias Egregoros.VerifiableCredentials.Reproof

  @activitystreams_context "https://www.w3.org/ns/activitystreams"
  @credentials_context "https://www.w3.org/ns/credentials/v2"

  test "reproof_local_credentials/1 streams and counts updated/skipped/error results" do
    {:ok, issuer} = InstanceActor.get_actor()

    _valid =
      insert_vc_object!(
        actor: issuer.ap_id,
        data:
          base_vc_data()
          |> Map.put("issuer", issuer.ap_id)
          |> Map.put("proof", %{})
      )

    _skipped_missing_proof =
      insert_vc_object!(
        actor: issuer.ap_id,
        data: base_vc_data() |> Map.put("issuer", issuer.ap_id)
      )

    {:ok, missing_key_user} = Users.create_local_user("vc_missing_key")

    _ = Repo.update!(Ecto.Changeset.change(missing_key_user, %{ed25519_private_key: nil}))

    _skipped_missing_private_key =
      insert_vc_object!(
        actor: missing_key_user.ap_id,
        data: base_vc_data() |> Map.put("issuer", missing_key_user.ap_id) |> Map.put("proof", %{})
      )

    {:ok, invalid_key_user} = Users.create_local_user("vc_invalid_key")

    _ =
      Repo.update!(Ecto.Changeset.change(invalid_key_user, %{ed25519_private_key: <<1, 2, 3>>}))

    _errored_invalid_private_key =
      insert_vc_object!(
        actor: invalid_key_user.ap_id,
        data: base_vc_data() |> Map.put("issuer", invalid_key_user.ap_id) |> Map.put("proof", %{})
      )

    assert {:ok, %{updated: 1, skipped: 2, errors: 1}} =
             Reproof.reproof_local_credentials(dry_run: true, batch_size: 1)
  end

  test "ensure_local_credentials/1 attaches proofs for missing proof documents and can be forced" do
    {:ok, issuer} = InstanceActor.get_actor()

    _skipped_proof_present =
      insert_vc_object!(
        actor: issuer.ap_id,
        data:
          base_vc_data()
          |> Map.put("issuer", issuer.ap_id)
          |> Map.put("@context", [@credentials_context, %{"to" => %{}}])
          |> Map.put("proof", %{})
      )

    _attached =
      insert_vc_object!(
        actor: issuer.ap_id,
        data: base_vc_data() |> Map.put("issuer", issuer.ap_id)
      )

    assert {:ok, %{updated: 1, skipped: 1, errors: 0}} =
             Reproof.ensure_local_credentials(dry_run: true, batch_size: 1)

    assert {:ok, %{updated: 2, skipped: 0, errors: 0}} =
             Reproof.ensure_local_credentials(dry_run: true, batch_size: 1, force: true)
  end

  test "ensure_local_credentials/1 counts errors when the issuer private key is invalid" do
    {:ok, invalid_key_user} = Users.create_local_user("vc_invalid_key_for_ensure")

    _ =
      Repo.update!(Ecto.Changeset.change(invalid_key_user, %{ed25519_private_key: <<1, 2, 3>>}))

    _errored =
      insert_vc_object!(
        actor: invalid_key_user.ap_id,
        data: base_vc_data() |> Map.put("issuer", invalid_key_user.ap_id)
      )

    assert {:ok, %{updated: 0, skipped: 0, errors: 1}} =
             Reproof.ensure_local_credentials(dry_run: true, batch_size: 1)
  end

  test "migrate_object_to_did/2 migrates locally issued credentials to did:web issuer identifiers" do
    {:ok, issuer} = InstanceActor.get_actor()
    did = DidWeb.instance_did()
    assert is_binary(did) and did != ""

    object =
      insert_vc_object!(
        actor: issuer.ap_id,
        data:
          base_vc_data()
          |> Map.put("issuer", issuer.ap_id)
          |> Map.put("proof", %{})
      )

    assert {:ok, %{} = migrated} = Reproof.migrate_object_to_did(object, dry_run: true)
    assert migrated["issuer"] == did
    assert migrated["proof"]["verificationMethod"] == did <> "#ed25519-key"
  end

  test "migrate_local_credentials_to_did/1 streams and migrates eligible credentials" do
    {:ok, issuer} = InstanceActor.get_actor()
    did = DidWeb.instance_did()
    assert is_binary(did) and did != ""

    _migrated =
      insert_vc_object!(
        actor: issuer.ap_id,
        data: base_vc_data() |> Map.put("issuer", issuer.ap_id) |> Map.put("proof", %{})
      )

    _skipped_mismatch =
      insert_vc_object!(
        actor: issuer.ap_id,
        data:
          base_vc_data()
          |> Map.put("issuer", "https://example.com/users/someone-else")
          |> Map.put("proof", %{})
      )

    assert {:ok, %{updated: 1, skipped: 1, errors: 0}} =
             Reproof.migrate_local_credentials_to_did(dry_run: true, batch_size: 1)
  end

  test "migrate_local_credentials_to_did/1 migrates documents with activitystreams-only context" do
    {:ok, issuer} = InstanceActor.get_actor()

    _migrated =
      insert_vc_object!(
        actor: issuer.ap_id,
        data: %{
          "@context" => [@activitystreams_context],
          "issuer" => issuer.ap_id,
          "proof" => %{}
        }
      )

    assert {:ok, %{updated: 1, skipped: 0, errors: 0}} =
             Reproof.migrate_local_credentials_to_did(dry_run: true, batch_size: 1)
  end

  test "reproof_object/1 updates stored objects and resolves did:web issuers via the instance actor" do
    {:ok, issuer} = InstanceActor.get_actor()
    did = DidWeb.instance_did()

    object =
      insert_vc_object!(
        actor: issuer.ap_id,
        data:
          base_vc_data()
          |> Map.put("issuer", %{"id" => did})
          |> Map.put("proof", %{})
      )

    assert {:ok, %Object{} = updated} = Reproof.reproof_object(object)

    contexts = List.wrap(updated.data["@context"])
    refute @activitystreams_context in contexts
    assert updated.data["issuer"] == %{"id" => did}
    assert is_map(updated.data["proof"])
  end

  test "ensure_object/1 persists updated credentials when not dry_run" do
    {:ok, issuer} = InstanceActor.get_actor()

    object =
      insert_vc_object!(
        actor: issuer.ap_id,
        data: base_vc_data() |> Map.put("issuer", issuer.ap_id)
      )

    assert {:ok, %Object{} = updated} = Reproof.ensure_object(object)
    assert is_map(updated.data["proof"])
  end

  test "default option wrappers return empty summaries" do
    assert {:ok, %{updated: 0, skipped: 0, errors: 0}} = Reproof.reproof_local_credentials()
    assert {:ok, %{updated: 0, skipped: 0, errors: 0}} = Reproof.ensure_local_credentials()

    assert {:ok, %{updated: 0, skipped: 0, errors: 0}} =
             Reproof.migrate_local_credentials_to_did()

    assert {:ok, %{updated: 0, skipped: 0, errors: 0}} =
             Reproof.reproof_local_credentials(limit: 1)
  end

  test "migrate_object_to_did/1 persists updated credentials when not dry_run" do
    {:ok, issuer} = InstanceActor.get_actor()
    did = DidWeb.instance_did()

    object =
      insert_vc_object!(
        actor: issuer.ap_id,
        data: base_vc_data() |> Map.put("issuer", issuer.ap_id) |> Map.put("proof", %{})
      )

    assert {:ok, %Object{} = updated} = Reproof.migrate_object_to_did(object)
    assert updated.data["issuer"] == did
    assert updated.data["proof"]["verificationMethod"] == did <> "#ed25519-key"
  end

  defp insert_vc_object!(attrs) when is_list(attrs) do
    data =
      attrs
      |> Keyword.get(:data, %{})
      |> Map.new()

    actor = Keyword.get(attrs, :actor)

    %Object{}
    |> Object.changeset(%{
      ap_id: "https://example.com/credentials/" <> FlakeId.get(),
      type: "VerifiableCredential",
      actor: actor,
      local: true,
      data: data
    })
    |> Repo.insert!()
  end

  defp base_vc_data do
    %{
      "@context" => [@activitystreams_context, @credentials_context],
      "id" => "https://example.com/credentials/1",
      "type" => ["VerifiableCredential"],
      "credentialSubject" => %{"id" => "https://example.com/users/alice"}
    }
  end
end
